import Foundation
import Observation
import WatchConnectivity

@MainActor
@Observable
final class PhoneWatchSyncService: NSObject, WCSessionDelegate {
    @ObservationIgnored private weak var store: LedgerStore?
    @ObservationIgnored private var session: WCSession?

    func start(store: LedgerStore) {
        self.store = store
        guard WCSession.isSupported(), session == nil else {
            sendSnapshot()
            return
        }

        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
    }

    func sendSnapshot() {
        guard let session, session.activationState == .activated,
              session.isWatchAppInstalled,
              let snapshot = store?.snapshot,
              let data = try? WatchSyncPayload.encode(snapshot) else { return }

        try? session.updateApplicationContext([WatchSyncPayload.snapshotKey: data])
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated, error == nil else { return }
        Task { @MainActor [weak self] in self?.sendSnapshot() }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        receiveTransaction(from: userInfo, replyHandler: nil)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        receiveTransaction(from: message, replyHandler: replyHandler)
    }

    nonisolated private func receiveTransaction(
        from payload: [String: Any],
        replyHandler: (([String: Any]) -> Void)?
    ) {
        guard let data = payload[WatchSyncPayload.transactionKey] as? Data,
              let transaction = try? WatchSyncPayload.decode(LedgerTransaction.self, from: data) else {
            replyHandler?(["accepted": false])
            return
        }

        Task { @MainActor [weak self] in
            self?.store?.addTransactionIfNeeded(transaction)
            self?.sendSnapshot()
            replyHandler?(["accepted": true])
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
