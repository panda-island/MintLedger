import Foundation

enum LocalBackupService {
    static func rotate(snapshot: LedgerSnapshot, keep: Int = 10) throws {
        let folder = try backupDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        try encoder.encode(snapshot).write(
            to: folder.appendingPathComponent("backup-\(stamp).mintledger"),
            options: [.atomic, .completeFileProtection]
        )

        let backups = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in backups.dropFirst(keep) { try? FileManager.default.removeItem(at: old) }
    }

    static func latestBackups() -> [URL] {
        guard let folder = try? backupDirectory() else { return [] }
        return (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
    }

    private static func backupDirectory() throws -> URL {
        let data = try SharedLedgerStorage.dataURL().deletingLastPathComponent()
        let folder = data.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

