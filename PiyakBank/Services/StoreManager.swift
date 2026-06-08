import Foundation
import StoreKit
import Combine

/// StoreKit 2. IAP 상품 = 결제 전용 아이템 (예: 졸업 가운)
@MainActor
final class StoreManager: ObservableObject {

    /// 상품 ID ↔ 카탈로그 ID 매핑
    static let productMap: [String: String] = [
        "com.minseo.piyakbank.graduation_gown": "bodyFront.graduation_gown"
    ]

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedIds: Set<String> = []

    private var updates: Task<Void, Never>?
    /// 결제 성공 시 보유 지급 콜백 (EconomyStore.grantIAP)
    var onPurchased: ((String) -> Void)?

    init() {
        updates = observeTransactions()
    }

    deinit { updates?.cancel() }

    func loadProducts() async {
        let ids = Array(Self.productMap.keys)
        products = (try? await Product.products(for: ids)) ?? []
        await refreshEntitlements()
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            grant(productId: transaction.productID)
            await transaction.finish()
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    private func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if let t = try? checkVerified(result) {
                grant(productId: t.productID)
            }
        }
    }

    private func observeTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { continue }
                if let t = try? await self.checkVerified(result) {
                    await self.grant(productId: t.productID)
                    await t.finish()
                }
            }
        }
    }

    private func grant(productId: String) {
        purchasedIds.insert(productId)
        if let catalogId = Self.productMap[productId] {
            onPurchased?(catalogId)
        }
    }

    enum StoreError: Error { case failedVerification }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified: throw StoreError.failedVerification
        }
    }
}
