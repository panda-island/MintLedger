import Foundation

enum SharedLedgerStorage {
    static let appGroupID = "group.com.a0973.MintLedger"
    static let filename = "ledger-v1.json"

    static func dataURL(fileManager: FileManager = .default) throws -> URL {
        if let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            let folder = group.appendingPathComponent("Data", isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder.appendingPathComponent(filename)
        }

        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = base.appendingPathComponent("MintLedger", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(filename)
    }

    static func load() throws -> LedgerSnapshot {
        let url = try dataURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LedgerSnapshot.self, from: data)
    }

    static func save(_ snapshot: LedgerSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let url = try dataURL()
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    static func append(
        kind: TransactionKind,
        amountMinor: Int64,
        category: LedgerCategory,
        accountID: UUID?,
        note: String,
        date: Date = .now
    ) throws {
        var snapshot = try load()
        let resolvedAccount = accountID ?? snapshot.accounts.first?.id ?? LedgerAccount.defaults[0].id
        if snapshot.accounts.isEmpty { snapshot.accounts = LedgerAccount.defaults }
        snapshot.transactions.append(LedgerTransaction(
            kind: kind,
            amountMinor: amountMinor,
            category: category,
            accountID: resolvedAccount,
            note: note,
            date: date
        ))
        snapshot.updatedAt = .now
        try save(snapshot)
    }
}
