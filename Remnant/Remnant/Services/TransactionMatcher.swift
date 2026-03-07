import Foundation

@MainActor
final class TransactionMatcher {

    /// Matches imported transactions against existing bills, returning updated transactions with match info.
    func match(transactions: [ImportedTransaction], against bills: [Bill]) -> [ImportedTransaction] {
        transactions.map { transaction in
            var best: (bill: Bill, confidence: Double)?

            for bill in bills {
                let confidence = matchConfidence(transaction: transaction, bill: bill)
                if confidence > (best?.confidence ?? 0) {
                    best = (bill, confidence)
                }
            }

            var matched = transaction
            if let best, best.confidence >= 0.5 {
                matched.matchedBill = best.bill
                matched.matchConfidence = best.confidence
            }
            return matched
        }
    }

    private func matchConfidence(transaction: ImportedTransaction, bill: Bill) -> Double {
        var score: Double = 0

        // Name matching (0-0.7)
        let txName = transaction.name.lowercased()
        let billName = bill.name.lowercased()

        if txName == billName || billName == txName {
            score += 0.7
        } else if txName.localizedStandardContains(billName) || billName.localizedStandardContains(txName) {
            score += 0.5
        } else {
            // Check individual words
            let billWords = billName.split(separator: " ").map(String.init)
            let matchedWords = billWords.filter { txName.contains($0) }
            if !billWords.isEmpty {
                score += 0.3 * (Double(matchedWords.count) / Double(billWords.count))
            }
        }

        // Amount matching (0-0.3)
        if let expected = bill.expectedAmount, expected > 0 {
            let diff = abs(transaction.amount - expected)
            let ratio = diff / expected
            if ratio == 0 {
                score += 0.3
            } else if ratio < Decimal(string: "0.05")! {
                score += 0.2
            } else if ratio < Decimal(string: "0.1")! {
                score += 0.1
            }
        }

        return min(score, 1.0)
    }
}
