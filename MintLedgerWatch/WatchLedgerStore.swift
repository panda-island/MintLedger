import Foundation
import Observation
import WatchConnectivity

@MainActor
@Observable
final class WatchLedgerStore: NSObject, WCSessionDelegate {
    private(set) var snapshot: LedgerSnapshot
    private(set) var lastSyncDate: Date?
    private(set) var lastError: String?

    @ObservationIgnored private var session: WCSession?
    private static let cacheKey = "MintLedger.watch.snapshot"

    override init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? WatchSyncPayload.decode(LedgerSnapshot.self, from: data) {
            snapshot = cached
        } else {
            snapshot = .empty
        }
        super.init()
        activateSession()
    }

    var balanceMinor: Int64 {
        snapshot.accounts.reduce(0) { $0 + $1.openingBalanceMinor }
            + snapshot.transactions.reduce(0) { $0 + $1.signedAmountMinor }
    }

    var recentTransactions: [LedgerTransaction] {
        Array(snapshot.transactions.sorted { $0.date > $1.date }.prefix(10))
    }

    func addTransaction(
        kind: TransactionKind,
        amountMinor: Int64,
        category: LedgerCategory,
        accountID: UUID,
        note: String
    ) {
        let transaction = LedgerTransaction(
            kind: kind,
            amountMinor: amountMinor,
            category: category,
            accountID: accountID,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            date: .now
        )
        snapshot.transactions.append(transaction)
        snapshot.updatedAt = .now
        saveCache()
        send(transaction)
    }

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
        apply(snapshotFrom: session.receivedApplicationContext)
    }

    private func send(_ transaction: LedgerTransaction) {
        guard let session,
              let data = try? WatchSyncPayload.encode(transaction) else {
            lastError = "無法準備同步資料"
            return
        }

        let payload: [String: Any] = [WatchSyncPayload.transactionKey: data]
        if session.isReachable {
            session.sendMessage(payload) { [weak self] reply in
                Task { @MainActor in
                    self?.apply(snapshotFrom: reply)
                    self?.lastError = nil
                }
            } errorHandler: { [weak session] _ in
                session?.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func requestSnapshot() {
        guard let session, session.activationState == .activated else { return }
        let payload: [String: Any] = [WatchSyncPayload.snapshotRequestKey: true]
        if session.isReachable {
            session.sendMessage(payload) { [weak self] reply in
                Task { @MainActor in self?.apply(snapshotFrom: reply) }
            } errorHandler: { [weak session] _ in
                session?.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func apply(snapshotFrom payload: [String: Any]) {
        guard let data = payload[WatchSyncPayload.snapshotKey] as? Data,
              let received = try? WatchSyncPayload.decode(LedgerSnapshot.self, from: data) else { return }
        snapshot = received
        lastSyncDate = .now
        lastError = nil
        saveCache()
    }

    private func saveCache() {
        guard let data = try? WatchSyncPayload.encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else {
            Task { @MainActor [weak self] in self?.lastError = error?.localizedDescription ?? "無法連接 iPhone" }
            return
        }
        let context = session.receivedApplicationContext
        Task { @MainActor [weak self] in
            self?.apply(snapshotFrom: context)
            self?.requestSnapshot()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor [weak self] in self?.apply(snapshotFrom: applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor [weak self] in self?.apply(snapshotFrom: message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor [weak self] in self?.apply(snapshotFrom: userInfo) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor [weak self] in self?.requestSnapshot() }
    }
}
