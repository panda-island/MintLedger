import SwiftUI

struct TransactionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LedgerStore.self) private var store
    private let original: LedgerTransaction

    @State private var kind: TransactionKind
    @State private var money: CurrencyEntryModel
    @State private var category: LedgerCategory
    @State private var accountID: UUID
    @State private var note: String
    @FocusState private var amountFocused: Bool

    init(transaction: LedgerTransaction) {
        original = transaction
        _kind = State(initialValue: transaction.kind)
        _money = State(initialValue: CurrencyEntryModel(transaction: transaction))
        _category = State(initialValue: transaction.category)
        _accountID = State(initialValue: transaction.accountID)
        _note = State(initialValue: transaction.note)
    }

    var body: some View {
        @Bindable var money = money
        Form {
            Section {
                Picker("類型", selection: $kind) {
                    ForEach(TransactionKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack(alignment: .firstTextBaseline) {
                    Text(money.currencyCode).font(.headline).foregroundStyle(.secondary)
                    TextField("0", text: $money.amountText)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                }
                .padding(.vertical, 8)
                CurrencyConversionFields(draft: money, baseCode: store.snapshot.currencyCode)
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
                DatePicker("日期", selection: $money.date)
                    .environment(\.locale, Locale(identifier: "zh_TW"))
                TextField("備註（選填）", text: $note)
            }

            Section("記錄資訊") {
                LabeledContent("建立時間", value: original.createdAt.ledgerDateTimeText)
                if let conversion = original.conversion {
                    LabeledContent("原始金額", value: "\(conversion.originalCurrencyCode) \(conversion.originalAmount)")
                    LabeledContent("原入帳幣別", value: conversion.booked.currencyCode)
                    LabeledContent("原入帳金額", value: conversion.booked.amountMinor.currency(code: conversion.booked.currencyCode))
                    LabeledContent("原入帳匯率", value: conversion.bookingRate ?? conversion.rate)
                }
                LabeledContent("識別碼", value: original.id.uuidString)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if amountFocused {
                AmountKeyboardAccessory(expression: $money.amountText, finishCalculation: finishCalculation)
            }
        }
        .navigationTitle("編輯明細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("儲存") { save() }.disabled((try? money.booking(base: store.snapshot.currencyCode)) == nil) }
        }
        .onAppear { money.prepare(base: store.snapshot.currencyCode) }
        .task(id: money.requestKey(base: store.snapshot.currencyCode)) { await money.loadRate(base: store.snapshot.currencyCode) }
    }

    private func save() {
        guard let booking = try? money.booking(base: store.snapshot.currencyCode) else { return }
        var updated = original
        updated.kind = kind
        updated.amountMinor = booking.amountMinor
        updated.conversion = booking.conversion
        updated.category = category
        updated.accountID = accountID
        updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.date = money.date
        store.updateTransaction(updated)
        if let error = store.lastError { money.error = error } else { dismiss() }
    }

    private func finishCalculation() {
        if let value = AmountExpression.evaluate(money.amountText) { money.amountText = CurrencyMath.string(CurrencyMath.decimal(String(value)) ?? 0) }
        amountFocused = false
    }
}
