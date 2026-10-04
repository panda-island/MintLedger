import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let mintLedgerBackup = UTType(exportedAs: "com.pandaisland.mintledger.backup", conformingTo: .json)
}

enum BackupFileReader {
    static func read(from url: URL) throws -> Data {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
        }

        var coordinationError: NSError?
        var readResult: Result<Data, Error>?
        NSFileCoordinator().coordinate(
            readingItemAt: url,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            readResult = Result {
                try Data(contentsOf: coordinatedURL, options: .mappedIfSafe)
            }
        }

        if let coordinationError { throw coordinationError }
        guard let readResult else { throw CocoaError(.fileReadUnknown) }
        return try readResult.get()
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.mintLedgerBackup, .json] }
    var data: Data

    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
