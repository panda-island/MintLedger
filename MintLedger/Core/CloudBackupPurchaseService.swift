import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class CloudBackupPurchaseService {
    static let productID = "app.mulberry1261.emerald6299.cloudbackup.lifetime"

    private(set) var product: Product?
    private(set) var isUnlocked = false
    private(set) var isWorking = false
    private(set) var lastError: String?
    private var transactionUpdates: Task<Void, Never>?

    var displayPrice: String {
        product?.displayPrice ?? "NT$60"
    }

    init() {
        transactionUpdates = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self.refreshEntitlement()
                }
            }
        }
    }

    func prepare() async {
        await refreshEntitlement()
        await loadProduct()
    }

    func purchase() async -> Bool {
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        do {
            if product == nil { await loadProduct() }
            guard let product else {
                throw CloudBackupPurchaseError.productUnavailable
            }

            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refreshEntitlement()
                return isUnlocked
            case .success(.unverified):
                throw CloudBackupPurchaseError.unverifiedTransaction
            case .pending:
                lastError = "購買正在等待核准；核准後會自動開啟雲端備份。"
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = readableMessage(for: error)
            return false
        }
    }

    func restorePurchases() async -> Bool {
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if !isUnlocked {
                lastError = "這個 App Store 帳號找不到已購買的 iCloud 備份功能。"
            }
            return isUnlocked
        } catch {
            lastError = readableMessage(for: error)
            return false
        }
    }

    func refreshEntitlement() async {
        var ownsProduct = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                ownsProduct = true
                break
            }
        }
        isUnlocked = ownsProduct
    }

    private func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            if !isUnlocked { lastError = readableMessage(for: error) }
        }
    }

    private func readableMessage(for error: Error) -> String {
        if let purchaseError = error as? CloudBackupPurchaseError {
            return purchaseError.localizedDescription
        }
        return "無法連接 App Store：\(error.localizedDescription)"
    }
}

private enum CloudBackupPurchaseError: LocalizedError {
    case productUnavailable
    case unverifiedTransaction

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            "目前無法取得雲端備份商品，請稍後再試。"
        case .unverifiedTransaction:
            "App Store 無法驗證這筆購買，功能尚未解鎖。"
        }
    }
}
