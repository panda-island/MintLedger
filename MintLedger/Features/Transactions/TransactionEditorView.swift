import SwiftUI

struct TransactionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LedgerStore.self) private var store
    private let original: LedgerTransaction

    @State private var kind: TransactionKind
    @State private var amountText: String
    @State private var category: LedgerCategory
    @State private var accountID: UUID
    @State private var note: String
    @State private var date: Date
    @FocusState private var amountFocused: Bool

    init(transaction: LedgerTransaction) {
        original = transaction
        _kind = State(initialValue: transaction.kind)
        _amountText = State(initialValue: AmountExpression.formatted(Double(transaction.amountMinor) / 100))
        _category = State(initialValue: transaction.category)
        _accountID = State(initialValue: transaction.accountID)
        _note = State(initialValue: transaction.note)
        _date = State(initialValue: transaction.date)
    }

    private var amountMinor: Int64? {
        guard let value = AmountExpression.evaluate(amountText), value > 0 else { return nil }
        return Int64((value * 100).rounded())
    }

    var body: some View {
        Form {
            Section {
                Picker("類型", selection: $kind) {
                    ForEach(TransactionKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack(alignment: .firstTextBaseline) {
                    Text(store.snapshot.currencyCode).font(.headline).foregroundStyle(.secondary)
                    TextField("0", text: $amountText)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                }
                .padding(.vertical, 8)
            }

            Section("分類") {
                Picker("分類", selection: $category) {
                    ForEach(LedgerCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
            }

            Section("詳細資料") {
                Picker("帳戶", selection: $accountID) {
                    ForEach(store.snapshot.accounts) { Label($0.name, systemImage: $0.symbol).tag($0.id) }
                }
                DatePicker("日期", selection: $date)
                TextField("備註（選填）", text: $note)
            }

            Section("記錄資訊") {
                LabeledContent("建立時間", value: original.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("識別碼", value: original.id.uuidString)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if amountFocused {
                AmountKeyboardAccessory(expression: $amountText, finishCalculation: finishCalculation)
            }
        }
        .navigationTitle("編輯明細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("儲存") { save() }.disabled(amountMinor == nil) }
        }
    }

    private func save() {
        guard let amountMinor else { return }
        var updated = original
        updated.kind = kind
        updated.amountMinor = amountMinor
        updated.category = category
        updated.accountID = accountID
        updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.date = date
        store.updateTransaction(updated)
        dismiss()
    }

    private func finishCalculation() {
        if let value = AmountExpression.evaluate(amountText) { amountText = AmountExpression.formatted(value) }
        amountFocused = false
    }
}
