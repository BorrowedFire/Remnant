import Foundation

enum VendorRuleMatcher {
    static func categoryName(for merchant: String, rules: [VendorRule]) -> String? {
        bestRule(for: merchant, rules: rules)?.defaultCategoryName
    }

    static func bestRule(for merchant: String, rules: [VendorRule]) -> VendorRule? {
        let normalizedMerchant = normalize(merchant)
        guard !normalizedMerchant.isEmpty else { return nil }

        return rules
            .filter { rule in
                let pattern = normalize(rule.merchantPattern)
                return !pattern.isEmpty && normalizedMerchant.contains(pattern)
            }
            .sorted { lhs, rhs in
                let lhsPattern = normalize(lhs.merchantPattern)
                let rhsPattern = normalize(rhs.merchantPattern)
                if lhsPattern.count != rhsPattern.count {
                    return lhsPattern.count > rhsPattern.count
                }
                return lhs.createdAt < rhs.createdAt
            }
            .first
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}
