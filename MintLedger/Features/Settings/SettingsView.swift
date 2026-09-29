import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var exportDocument = BackupDocument()
    @State private var csvDocument = CSVDocument(data: Data())
    @State private var exportingBackup = false
    @State private var exportingCSV = false
    @State private var importing = false
    @State private var statusMessage: String?
    @State private var newAccountName = ""

    var body: some View {
        Form {
            Section("隱私") {
                Label("完全離線，沒有帳號也不會上傳雲端", systemImage: "hand.raised.fill").foregroundStyle(.secondary)
            }
            Section("本機備份") {
                Button { exportBackup() } label: { Label("匯出完整備份", systemImage: "square.and.arrow.up") }
                Button { importing = true } label: { Label("從備份還原", systemImage: "square.and.arrow.down") }
                Button { csvDocument = CSVDocument(data: store.csvData()); exportingCSV = true } label: { Label("匯出 CSV", systemImage: "tablecells") }
                LabeledContent("自動輪替備份", value: "保留最近 10 份")
                LabeledContent("目前備份數", value: "\(LocalBackupService.latestBackups().count)")
            }
            Section("帳戶") {
                ForEach(store.snapshot.accounts) { account in Label(account.name, systemImage: account.symbol) }
                HStack {
                    TextField("新增帳戶", text: $newAccountName)
                    Button("加入") { addAccount() }.disabled(newAccountName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section("系統整合") {
                Label("捷徑／Siri：說「用 MintLedger 記一筆」", systemImage: "wand.and.stars")
                Label("桌面與鎖定畫面小工具", systemImage: "square.grid.2x2")
            }
            Section("關於") {
                LabeledContent("版本", value: "1.1.0")
                LabeledContent("資料格式", value: "MintLedger v1 JSON")
            }
        }
        .navigationTitle("設定")
        .fileExporter(isPresented: $exportingBackup, document: exportDocument, contentType: .mintLedgerBackup, defaultFilename: "MintLedger-Backup") { result in report(result, success: "備份已匯出") }
        .fileExporter(isPresented: $exportingCSV, document: csvDocument, contentType: .commaSeparatedText, defaultFilename: "MintLedger-Transactions") { result in report(result, success: "CSV 已匯出") }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.mintLedgerBackup, .json]) { result in importBackup(result) }
        .alert("MintLedger", isPresented: Binding(get: { statusMessage != nil }, set: { if !$0 { statusMessage = nil } })) {
            Button("好") { statusMessage = nil }
        } message: { Text(statusMessage ?? "") }
    }

    private func exportBackup() {
        do { exportDocument = BackupDocument(data: try store.encodedBackup()); exportingBackup = true }
        catch { statusMessage = error.localizedDescription }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            try store.importBackup(Data(contentsOf: url))
            statusMessage = "還原完成"
        } catch { statusMessage = "還原失敗：\(error.localizedDescription)" }
    }

    private func report(_ result: Result<URL, Error>, success: String) {
        switch result { case .success: statusMessage = success; case .failure(let error): statusMessage = error.localizedDescription }
    }

    private func addAccount() {
        store.addAccount(name: newAccountName.trimmingCharacters(in: .whitespacesAndNewlines))
        newAccountName = ""
    }
}
