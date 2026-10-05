import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(ICloudBackupService.self) private var cloudBackup
    @Environment(\.openURL) private var openURL
    @State private var exportDocument = BackupDocument()
    @State private var csvDocument = CSVDocument(data: Data())
    @State private var exportingBackup = false
    @State private var exportingCSV = false
    @State private var importing = false
    @State private var statusMessage: String?
    @State private var newAccountName = ""

    var body: some View {
        Form {
            privacySection
            cloudBackupSection
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
                if SharedLedgerStorage.isUsingAppGroup {
                    Label("小工具與 App 正在共用同一份資料", systemImage: "checkmark.icloud.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("目前簽章未授權共享資料；小工具無法與 App 同步", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Section("支援與法律") {
                Link(destination: URL(string: "https://panda-island.github.io/MintLedger-Site/support/")!) {
                    Label("使用支援", systemImage: "questionmark.circle")
                }
                Link(destination: URL(string: "https://panda-island.github.io/MintLedger-Site/privacy/")!) {
                    Label("隱私權政策", systemImage: "hand.raised")
                }
                Link(destination: URL(string: "https://panda-island.github.io/MintLedger-Site/eula/")!) {
                    Label("最終使用者授權協議", systemImage: "doc.text")
                }
            }
            Section("關於") {
                LabeledContent("版本", value: appVersion)
                LabeledContent("資料格式", value: "MintLedger v1 JSON")
            }
        }
        .navigationTitle("設定")
        .task {
            await cloudBackup.prepare()
        }
        .fileExporter(isPresented: $exportingBackup, document: exportDocument, contentType: .mintLedgerBackup, defaultFilename: "MintLedger-Backup") { result in report(result, success: "備份已匯出") }
        .fileExporter(isPresented: $exportingCSV, document: csvDocument, contentType: .commaSeparatedText, defaultFilename: "MintLedger-Transactions") { result in report(result, success: "CSV 已匯出") }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in importBackup(result) }
        .alert("MintLedger", isPresented: Binding(get: { statusMessage != nil }, set: { if !$0 { statusMessage = nil } })) {
            Button("好") { statusMessage = nil }
        } message: { Text(statusMessage ?? "") }
    }

    private var privacySection: some View {
        Section("隱私") {
            if cloudBackup.isAvailable {
                Label("帳本只備份到你自己的 iCloud 私人資料庫", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            } else {
                Label("資料預設只保存在本機", systemImage: "hand.raised.fill")
                    .foregroundStyle(.secondary)
            }
            Text("開發者與其他 MintLedger 使用者都無法查看你的 iCloud 私人備份。備份會占用你自己的 iCloud 儲存空間。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var cloudBackupSection: some View {
        Section("iCloud 雲端備份") {
            Label("所有雲端備份功能皆免費", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
            LabeledContent("iCloud", value: cloudBackup.accountStatusText)

            if cloudBackup.isAvailable {
                if let date = cloudBackup.lastBackupDate {
                    LabeledContent("最近備份") {
                        Text(date, format: .dateTime.year().month().day().hour().minute())
                    }
                } else {
                    LabeledContent("最近備份", value: "尚未備份")
                }

                Button { backupToICloud() } label: {
                    Label("立即備份", systemImage: "arrow.triangle.2.circlepath.icloud.fill")
                }
                .disabled(cloudBackup.isWorking)

                NavigationLink {
                    ICloudBackupsView()
                } label: {
                    Label("查看與還原雲端備份", systemImage: "clock.arrow.circlepath")
                }
            } else {
                Button {
                    openURL(URL(string: UIApplication.openSettingsURLString)!)
                } label: {
                    Label("開啟 iPhone 設定", systemImage: "gear")
                }
                Text("請在 iPhone 登入 iCloud 並開啟 iCloud Drive，回到 App 後會自動重新檢查。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if cloudBackup.isWorking {
                HStack {
                    ProgressView()
                    Text("正在連接 iCloud…")
                        .foregroundStyle(.secondary)
                }
            }
            if let error = cloudBackup.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func exportBackup() {
        do { exportDocument = BackupDocument(data: try store.encodedBackup()); exportingBackup = true }
        catch { statusMessage = error.localizedDescription }
    }

    private func backupToICloud() {
        Task {
            do {
                await cloudBackup.backupNow(data: try store.encodedBackup())
                if cloudBackup.lastError == nil { statusMessage = "iCloud 備份完成" }
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            try store.importBackup(BackupFileReader.read(from: url))
            statusMessage = "還原完成，共匯入 \(store.snapshot.transactions.count) 筆明細"
        } catch {
            statusMessage = "還原失敗：請確認選取的是 MintLedger 匯出的 .mintledger 備份檔。\n\(error.localizedDescription)"
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func report(_ result: Result<URL, Error>, success: String) {
        switch result { case .success: statusMessage = success; case .failure(let error): statusMessage = error.localizedDescription }
    }

    private func addAccount() {
        store.addAccount(name: newAccountName.trimmingCharacters(in: .whitespacesAndNewlines))
        newAccountName = ""
    }
}

private struct ICloudBackupsView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(ICloudBackupService.self) private var cloudBackup
    @State private var pendingRestore: ICloudBackupFile?
    @State private var statusMessage: String?

    var body: some View {
        Group {
            if cloudBackup.backups.isEmpty, !cloudBackup.isWorking {
                ContentUnavailableView(
                    "尚無 iCloud 備份",
                    systemImage: "externaldrive.badge.icloud",
                    description: Text("按設定頁的「立即備份」建立第一份備份。")
                )
            } else {
                List {
                    ForEach(cloudBackup.backups) { backup in
                        Button { pendingRestore = backup } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(backup.modifiedAt, format: .dateTime.year().month().day().weekday().hour().minute())
                                    .foregroundStyle(.primary)
                                Text(ByteCountFormatter.string(fromByteCount: backup.size, countStyle: .file))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .swipeActions {
                            Button("刪除", role: .destructive) {
                                Task { await cloudBackup.delete(backup) }
                            }
                        }
                    }
                }
                .refreshable { await cloudBackup.refreshBackups() }
            }
        }
        .navigationTitle("iCloud 備份")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if cloudBackup.isWorking { ProgressView().controlSize(.large) }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await cloudBackup.refreshBackups() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(cloudBackup.isWorking)
            }
        }
        .task { await cloudBackup.refreshBackups() }
        .confirmationDialog(
            "要還原這份 iCloud 備份嗎？",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("還原並取代目前資料", role: .destructive) {
                guard let backup = pendingRestore else { return }
                pendingRestore = nil
                restore(backup)
            }
            Button("取消", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("目前 App 內的資料會被選取的備份取代；系統會先留下本機輪替備份。")
        }
        .alert("MintLedger", isPresented: Binding(
            get: { statusMessage != nil },
            set: { if !$0 { statusMessage = nil } }
        )) {
            Button("好") { statusMessage = nil }
        } message: {
            Text(statusMessage ?? "")
        }
    }

    private func restore(_ backup: ICloudBackupFile) {
        Task {
            do {
                let data = try await cloudBackup.download(backup)
                try store.importBackup(data)
                statusMessage = "iCloud 備份還原完成，共有 \(store.snapshot.transactions.count) 筆明細"
            } catch {
                statusMessage = "還原失敗：\(error.localizedDescription)"
            }
        }
    }
}
