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
              let snapshot = store?.snapshot,
              let data = try? WatchSyncPayload.encode(snapshot) else { return }

        try? session.updateApplicationContext([WatchSyncPayload.snapshotKey: data])
        if session.isReachable {
            session.sendMessage([WatchSyncPayload.snapshotKey: data], replyHandler: nil, errorHandler: nil)
        }
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
        if payload[WatchSyncPayload.snapshotRequestKey] as? Bool == true {
            Task { @MainActor [weak self] in
                guard let self else { return }
                sendSnapshot()
                replyHandler?(snapshotReply())
            }
            return
        }

        guard let data = payload[WatchSyncPayload.transactionKey] as? Data,
              let transaction = try? WatchSyncPayload.decode(LedgerTransaction.self, from: data) else {
            replyHandler?(["accepted": false])
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            store?.addTransactionIfNeeded(transaction)
            sendSnapshot()
            replyHandler?(snapshotReply(accepted: true))
        }
    }

    private func snapshotReply(accepted: Bool? = nil) -> [String: Any] {
        var reply: [String: Any] = [:]
        if let accepted { reply["accepted"] = accepted }
        if let snapshot = store?.snapshot,
           let data = try? WatchSyncPayload.encode(snapshot) {
            reply[WatchSyncPayload.snapshotKey] = data
        }
        return reply
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor [weak self] in self?.sendSnapshot() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
