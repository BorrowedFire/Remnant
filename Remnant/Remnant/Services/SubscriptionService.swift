import Foundation
import StoreKit
import Observation

@MainActor
@Observable
final class SubscriptionService {
    private(set) var isPremium = false
    private(set) var products: [Product] = []
    private(set) var purchaseError: String?

    private let productIDs = [
        "com.borrowedfire.remnant.plus.monthly",
        "com.borrowedfire.remnant.plus.annual"
    ]

    @ObservationIgnored
    private nonisolated(unsafe) var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        do {
            products = try await Product.products(for: productIDs)
                .sorted { $0.price < $1.price }
        } catch {
            purchaseError = "Failed to load subscription options."
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            purchaseError = "Purchase failed. Please try again."
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    // MARK: - Entitlements

    func refreshEntitlements() async {
        var hasEntitlement = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                if productIDs.contains(transaction.productID) {
                    hasEntitlement = true
                }
            }
        }
        isPremium = hasEntitlement
    }

    // MARK: - Limits (Free Tier)

    static let freeBillLimit = 15
    static let freeAccountLimit = 1

    func canAddBill(currentCount: Int) -> Bool {
        isPremium || currentCount < Self.freeBillLimit
    }

    func canAddAccount(currentCount: Int) -> Bool {
        isPremium || currentCount < Self.freeAccountLimit
    }

    // MARK: - Private

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let transaction = try? self?.checkVerified(result) {
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
    }

    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw StoreError.verificationFailed
        }
    }

    enum StoreError: Error {
        case verificationFailed
    }
}
