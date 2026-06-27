import Foundation

struct ReceiptMatchSuggestion: Identifiable {
    let receipt: ReceiptAttachment
    let expense: Expense
    let score: Int
    let reasons: [String]

    var id: String {
        "\(receipt.id.uuidString)-\(expense.id.uuidString)"
    }
}

@MainActor
enum ReceiptMatcher {
    static func suggestions(
        receipts: [ReceiptAttachment],
        expenses: [Expense],
        minimumScore: Int = 70
    ) -> [ReceiptMatchSuggestion] {
        let unmatchedReceipts = receipts.filter { $0.expenseID == nil }
        let candidateExpenses = ExpenseLedger.expensesMissingReceipts(in: expenses)

        return unmatchedReceipts.compactMap { receipt in
            bestSuggestion(
                for: receipt,
                expenses: candidateExpenses,
                minimumScore: minimumScore
            )
        }
        .sorted {
            if $0.score == $1.score {
                return $0.receipt.importedAt > $1.receipt.importedAt
            }
            return $0.score > $1.score
        }
    }

    static func bestSuggestion(
        for receipt: ReceiptAttachment,
        expenses: [Expense],
        minimumScore: Int = 70
    ) -> ReceiptMatchSuggestion? {
        expenses
            .compactMap { suggestion(for: receipt, expense: $0, minimumScore: minimumScore) }
            .sorted {
                if $0.score == $1.score {
                    return $0.expense.date > $1.expense.date
                }
                return $0.score > $1.score
            }
            .first
    }

    static func suggestion(
        for receipt: ReceiptAttachment,
        expense: Expense,
        minimumScore: Int = 70
    ) -> ReceiptMatchSuggestion? {
        guard expense.status != .ignored,
              expense.receiptAttachmentID == nil,
              ExpenseLedger.isBlank(expense.receiptFilename),
              ExpenseLedger.isBlank(expense.receiptContentHash),
              let receiptAmount = receipt.extractedAmount,
              amountsMatch(receiptAmount, expense.amount) else {
            return nil
        }

        var score = 55
        var reasons = ["amount"]

        let dateScore = scoreDate(receiptDate: receipt.extractedDate, expenseDate: expense.date)
        score += dateScore.value
        if let reason = dateScore.reason {
            reasons.append(reason)
        }

        let merchantScore = scoreMerchant(
            receiptMerchant: receipt.extractedMerchant ?? fallbackMerchant(for: receipt),
            expenseMerchant: expense.merchant
        )
        score += merchantScore.value
        if merchantScore.value > 0 {
            reasons.append("merchant")
        }

        guard score >= minimumScore else { return nil }
        return ReceiptMatchSuggestion(
            receipt: receipt,
            expense: expense,
            score: score,
            reasons: reasons
        )
    }

    private static func amountsMatch(_ lhs: Decimal, _ rhs: Decimal) -> Bool {
        cents(lhs) == cents(rhs)
    }

    private static func cents(_ value: Decimal) -> Int64 {
        let number = NSDecimalNumber(decimal: value)
        return number.multiplying(byPowerOf10: 2)
            .rounding(accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 0,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            ))
            .int64Value
    }

    private static func scoreDate(receiptDate: Date?, expenseDate: Date) -> (value: Int, reason: String?) {
        guard let receiptDate else { return (0, nil) }
        let days = abs(Calendar.current.dateComponents([.day], from: receiptDate, to: expenseDate).day ?? 0)

        switch days {
        case 0:
            return (25, "same day")
        case 1:
            return (18, "1 day")
        case 2...3:
            return (10, "\(days) days")
        default:
            return (0, nil)
        }
    }

    private static func scoreMerchant(receiptMerchant: String, expenseMerchant: String) -> (value: Int, overlap: Double) {
        let receiptTokens = merchantTokens(receiptMerchant)
        let expenseTokens = merchantTokens(expenseMerchant)
        guard !receiptTokens.isEmpty, !expenseTokens.isEmpty else { return (0, 0) }

        let overlap = receiptTokens.intersection(expenseTokens)
        guard !overlap.isEmpty else { return (0, 0) }

        let ratio = Double(overlap.count) / Double(min(receiptTokens.count, expenseTokens.count))
        return (Int((ratio * 20).rounded()), ratio)
    }

    private static func merchantTokens(_ value: String) -> Set<String> {
        let stopWords: Set<String> = ["inc", "llc", "ltd", "the", "and", "com", "receipt"]
        let normalized = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let tokens = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 && !stopWords.contains($0) }
        return Set(tokens)
    }

    private static func fallbackMerchant(for receipt: ReceiptAttachment) -> String {
        let stem = (receipt.originalFilename as NSString).deletingPathExtension
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stem.isEmpty ? "Receipt" : stem
    }
}
