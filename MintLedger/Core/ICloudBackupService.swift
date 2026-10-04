import CloudKit
import Foundation
import Observation

struct ICloudBackupFile: Identifiable, Equatable, Sendable {
    let id: String
    let modifiedAt: Date
    let size: Int64
}

@MainActor
@Observable
final class ICloudBackupService {
    static let containerIdentifier = "iCloud.app.mulberry1261.emerald6299"

    private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    private(set) var isWorking = false
    private(set) var backups: [ICloudBackupFile] = []
    private(set) var lastBackupDate: Date?
    private(set) var lastError: String?

    @ObservationIgnored
    private lazy var container = CKContainer(identifier: ICloudBackupService.containerIdentifier)
    private var pendingAutomaticBackup: Task<Void, Never>?

    var isAvailable: Bool { accountStatus == .available }

    var accountStatusText: String {
        switch accountStatus {
        case .available: "已連接 iCloud"
        case .noAccount: "尚未登入 iCloud"
        case .restricted: "此裝置限制使用 iCloud"
        case .temporarilyUnavailable: "iCloud 暫時無法使用"
        case .couldNotDetermine: "正在確認 iCloud 狀態"
        @unknown default: "無法確認 iCloud 狀態"
        }
    }

    func prepare() async {
        await refreshAccountStatus()
        if isAvailable { await refreshBackups() }
    }

    func refreshAccountStatus() async {
        do {
            accountStatus = try await container.accountStatus()
            if accountStatus != .available {
                backups = []
                lastBackupDate = nil
            }
        } catch {
            accountStatus = .couldNotDetermine
            lastError = readableMessage(for: error)
        }
    }

    func scheduleAutomaticBackup(data: Data) {
        guard isAvailable else { return }
        pendingAutomaticBackup?.cancel()
        pendingAutomaticBackup = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.uploadBackup(data: data, reportsErrors: false)
        }
    }

    func backupNow(data: Data) async {
        pendingAutomaticBackup?.cancel()
        await uploadBackup(data: data, reportsErrors: true)
    }

    func refreshBackups() async {
        guard isAvailable else { return }
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        do {
            let entries = try await fetchIndex()
            backups = entries.map { ICloudBackupFile(id: $0.id, modifiedAt: $0.modifiedAt, size: $0.size) }
            lastBackupDate = backups.first?.modifiedAt
        } catch let error as CKError where error.code == .unknownItem {
            backups = []
            lastBackupDate = nil
        } catch {
            lastError = readableMessage(for: error)
        }
    }

    func download(_ backup: ICloudBackupFile) async throws -> Data {
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        do {
            let record = try await database.record(for: CKRecord.ID(recordName: backup.id))
            guard let asset = record[Field.payload] as? CKAsset,
                  let fileURL = asset.fileURL else {
                throw ICloudBackupError.missingBackupData
            }
            return try Data(contentsOf: fileURL)
        } catch {
            lastError = readableMessage(for: error)
            throw error
        }
    }

    func delete(_ backup: ICloudBackupFile) async {
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        do {
            _ = try await database.deleteRecord(withID: CKRecord.ID(recordName: backup.id))
            let remaining = backups.filter { $0.id != backup.id }
            try await saveIndex(remaining.map(IndexEntry.init))
            backups = remaining
            lastBackupDate = backups.first?.modifiedAt
        } catch {
            lastError = readableMessage(for: error)
        }
    }

    private var database: CKDatabase { container.privateCloudDatabase }

    private func uploadBackup(data: Data, reportsErrors: Bool) async {
        guard isAvailable else { return }
        isWorking = true
        if reportsErrors { lastError = nil }
        defer { isWorking = false }

        let recordID = CKRecord.ID(recordName: Self.dailyRecordName())
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MintLedger-\(UUID().uuidString).mintledger")

        do {
            try data.write(to: temporaryURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }

            let record: CKRecord
            do {
                record = try await database.record(for: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: Record.backup, recordID: recordID)
            }
            let now = Date.now
            record[Field.payload] = CKAsset(fileURL: temporaryURL)
            record[Field.modifiedAt] = now as CKRecordValue
            record[Field.size] = Int64(data.count) as CKRecordValue
            _ = try await database.save(record)

            var entries = (try? await fetchIndex()) ?? []
            entries.removeAll { $0.id == recordID.recordName }
            entries.insert(IndexEntry(id: recordID.recordName, modifiedAt: now, size: Int64(data.count)), at: 0)

            let expired = Array(entries.dropFirst(30))
            entries = Array(entries.prefix(30))
            try await saveIndex(entries)
            for entry in expired {
                _ = try? await database.deleteRecord(withID: CKRecord.ID(recordName: entry.id))
            }

            backups = entries.map { ICloudBackupFile(id: $0.id, modifiedAt: $0.modifiedAt, size: $0.size) }
            lastBackupDate = now
        } catch {
            if reportsErrors { lastError = readableMessage(for: error) }
        }
    }

    private func fetchIndex() async throws -> [IndexEntry] {
        let record = try await database.record(for: CKRecord.ID(recordName: Record.indexID))
        guard let data = record[Field.entries] as? Data else { return [] }
        return try JSONDecoder().decode([IndexEntry].self, from: data)
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func saveIndex(_ entries: [IndexEntry]) async throws {
        let recordID = CKRecord.ID(recordName: Record.indexID)
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Record.index, recordID: recordID)
        }
        record[Field.entries] = try JSONEncoder().encode(entries) as CKRecordValue
        record[Field.modifiedAt] = Date.now as CKRecordValue
        _ = try await database.save(record)
    }

    private func readableMessage(for error: Error) -> String {
        if let cloudError = error as? ICloudBackupError {
            return cloudError.localizedDescription
        }
        guard let ckError = error as? CKError else {
            return "iCloud 備份失敗：\(error.localizedDescription)"
        }
        return switch ckError.code {
        case .notAuthenticated: "請先在 iPhone「設定」登入 iCloud，並開啟 iCloud Drive。"
        case .networkFailure, .networkUnavailable: "目前無法連上 iCloud，請檢查網路後再試。"
        case .quotaExceeded: "iCloud 儲存空間不足，請先釋出空間。"
        case .serverRejectedRequest: "iCloud 尚未完成設定，請稍後再試。"
        default: "iCloud 備份失敗：\(ckError.localizedDescription)"
        }
    }

    private static func dailyRecordName() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return "backup-\(formatter.string(from: .now))"
    }
}

private extension ICloudBackupService {
    enum Record {
        static let backup = "LedgerBackup"
        static let index = "LedgerBackupIndex"
        static let indexID = "backup-index-v1"
    }

    enum Field {
        static let payload = "payload"
        static let modifiedAt = "modifiedAt"
        static let size = "size"
        static let entries = "entries"
    }

    struct IndexEntry: Codable {
        let id: String
        let modifiedAt: Date
        let size: Int64

        init(id: String, modifiedAt: Date, size: Int64) {
            self.id = id
            self.modifiedAt = modifiedAt
            self.size = size
        }

        init(_ backup: ICloudBackupFile) {
            self.init(id: backup.id, modifiedAt: backup.modifiedAt, size: backup.size)
        }
    }
}

private enum ICloudBackupError: LocalizedError {
    case missingBackupData

    var errorDescription: String? {
        switch self {
        case .missingBackupData: "這份 iCloud 備份缺少資料，無法還原。"
        }
    }
}
