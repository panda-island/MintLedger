import SwiftUI

struct CurrencySettingsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var selection = "TWD"
    @State private var isWorking = false
    @State private var confirming = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("主要預設幣別") {
                Picker("幣別", selection: $selection) {
                    ForEach(CurrencyMath.codes, id: \.self) { code in
                        Text(CurrencyMath.title(code)).tag(code)
                    }
                }
                .disabled(isWorking)
                Button("套用主要幣別") { confirming = true }
                    .disabled(isWorking || selection == store.snapshot.currencyCode)
                if isWorking {
                    HStack { ProgressView(); Text("換算歷史帳目中，請稍候…") }
                }
                Text("新帳目預設使用主要幣別；選擇其他原始幣別時，會依交易日期取得每日參考匯率，並保存原幣金額及匯率。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("更改主要幣別") {
                Text("既有帳目會依各筆原入帳金額及交易日匯率換算，原始幣別、金額及首次入帳資訊會保留。期初餘額與定期交易設定，採首次切換主幣當日的匯率作為換算基準。")
                Text("換算完成前不會變更帳本；完成時會先留存本機備份。")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            Section("參考匯率") {
                Link("Frankfurter 免費每日參考匯率", destination: URL(string: "https://frankfurter.dev/")!)
                Text("查詢僅傳送幣別及日期，不傳送金額、備註或帳戶內容。參考匯率不是銀行即時成交價；無網路或無歷史報價時，可在新增帳目選擇自訂匯率。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("幣別與匯率")
        .onAppear { selection = store.snapshot.currencyCode }
        .confirmationDialog("將主要幣別改為 \(selection) 並換算現有帳本？", isPresented: $confirming, titleVisibility: .visible) {
            Button("換算並套用") { changeCurrency() }
        } message: {
            Text("原幣資訊會保留；匯率查詢失敗時不會套用任何變更。")
        }
        .alert("幣別設定", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func changeCurrency() {
        guard !isWorking else { return }
        isWorking = true
        let code = selection
        Task {
            defer { isWorking = false }
            do {
                try await store.changeBaseCurrency(to: code)
                message = "主要幣別已設為 \(code)，現有帳目已換算。"
            } catch {
                message = "未變更帳本：\(error.localizedDescription)"
            }
        }
    }
}
