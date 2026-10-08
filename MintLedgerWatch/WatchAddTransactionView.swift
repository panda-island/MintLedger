import SwiftUI

struct WatchAddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchLedgerStore.self) private var store
    @State private var kind: TransactionKind = .expense
    @State private var amountText = ""
    @State private var category: LedgerCategory = .food
    @State private var accountID: UUID?
    @State private var note = ""

    private var amountMinor: Int64? {
        guard let amount = Int64(amountText), amount > 0, amount <= Int64.max / 100 else { return nil }
        return amount * 100
    }

    var body: some View {
        Form {
            Picker("類型", selection: $kind) {
                ForEach(TransactionKind.allCases) { item in
                    Text(item.title).tag(item)
                }
            }

            TextField("金額（元）", text: $amountText)
                .accessibilityLabel("金額，單位為元")

            Picker("分類", selection: $category) {
                ForEach(LedgerCategory.allCases) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
            }

            Picker("帳戶", selection: $accountID) {
                ForEach(store.snapshot.accounts) { account in
                    Label(account.name, systemImage: account.symbol).tag(Optional(account.id))
                }
            }

            TextField("備註（選填）", text: $note)

            Button("儲存", systemImage: "checkmark") {
                save()
            }
            .disabled(amountMinor == nil || accountID == nil)
        }
        .navigationTitle(kind == .expense ? "新增支出" : "新增收入")
        .onAppear {
            accountID = accountID ?? store.snapshot.accounts.first?.id
        }
    }

    private func save() {
        guard let amountMinor, let accountID else { return }
        store.addTransaction(
            kind: kind,
            amountMinor: amountMinor,
            category: category,
            accountID: accountID,
            note: note
        )
        dismiss()
    }
}
