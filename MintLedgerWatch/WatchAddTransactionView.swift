import SwiftUI

struct WatchAddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchLedgerStore.self) private var store
    @State private var kind: TransactionKind = .expense
    @State private var money = CurrencyEntryModel()
    @State private var category: LedgerCategory = .food
    @State private var accountID: UUID?
    @State private var note = ""

    var body: some View {
        @Bindable var money = money
        Form {
            Picker("類型", selection: $kind) {
                ForEach(TransactionKind.allCases) { item in
                    Text(item.title).tag(item)
                }
            }

            TextField("原幣金額", text: $money.amountText)
                .accessibilityLabel("原幣金額")
            CurrencyConversionFields(draft: money, baseCode: store.snapshot.currencyCode)

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
            .disabled((try? money.booking(base: store.snapshot.currencyCode)) == nil || accountID == nil)
        }
        .navigationTitle(kind == .expense ? "新增支出" : "新增收入")
        .onAppear {
            accountID = accountID ?? store.snapshot.accounts.first?.id
            money.prepare(base: store.snapshot.currencyCode)
        }
        .task(id: money.requestKey(base: store.snapshot.currencyCode)) { await money.loadRate(base: store.snapshot.currencyCode) }
    }

    private func save() {
        guard let booking = try? money.booking(base: store.snapshot.currencyCode), let accountID else { return }
        store.addTransaction(
            kind: kind,
            amountMinor: booking.amountMinor,
            category: category,
            accountID: accountID,
            note: note,
            date: money.date,
            conversion: booking.conversion
        )
        dismiss()
    }
}
