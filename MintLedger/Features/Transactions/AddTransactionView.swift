import SwiftUI

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LedgerStore.self) private var store
    @State private var kind: TransactionKind = .expense
    @State private var amountText = ""
    @State private var category: LedgerCategory = .food
    @State private var accountID: UUID?
    @State private var note = ""
    @State private var date = Date()
    @FocusState private var amountFocused: Bool

    private var amountMinor: Int64? {
        guard let value = AmountExpression.evaluate(amountText) else { return nil }
        return Int64((value * 100).rounded())
    }

    var body: some View {
        Form {
            Section {
                Picker("類型", selection: $kind) {
                    ForEach(TransactionKind.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                HStack(alignment: .firstTextBaseline) {
                    Text(currencySymbol).font(.title2).foregroundStyle(.secondary)
                    TextField("0", text: $amountText)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .keyboardType(.decimalPad).focused($amountFocused)
                        .accessibilityLabel("金額")
                }.padding(.vertical, 8)
            }
            Section("分類") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                    ForEach(LedgerCategory.allCases) { item in
                        Button {
                            category = item
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: item.symbol).font(.title3)
                                Text(item.title).font(.caption)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(category == item ? Color.mintLedger.opacity(0.22) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain).accessibilityAddTraits(category == item ? .isSelected : [])
                    }
                }.padding(.vertical, 4)
            }
            Section("詳細資料") {
                Picker("帳戶", selection: Binding(get: { accountID ?? store.snapshot.accounts.first?.id }, set: { accountID = $0 })) {
                    ForEach(store.snapshot.accounts) { Label($0.name, systemImage: $0.symbol).tag(Optional($0.id)) }
                }
                DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .environment(\.locale, Locale(identifier: "zh_TW"))
                    .environment(\.calendar, Calendar(identifier: .gregorian))
                TextField("備註（選填）", text: $note)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if amountFocused {
                AmountKeyboardAccessory(expression: $amountText, finishCalculation: finishCalculation)
            }
        }
        .navigationTitle(kind == .expense ? "新增支出" : "新增收入")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("儲存") { save() }.disabled(amountMinor == nil || store.snapshot.accounts.isEmpty) }
        }
        .onAppear { accountID = accountID ?? store.snapshot.accounts.first?.id; amountFocused = true }
    }

    private var currencySymbol: String {
        Locale.current.localizedString(forCurrencyCode: store.snapshot.currencyCode) == nil ? store.snapshot.currencyCode : (Locale.current.currencySymbol ?? "$")
    }

    private func save() {
        guard let amountMinor, let accountID else { return }
        store.addTransaction(kind: kind, amountMinor: amountMinor, category: category, accountID: accountID, note: note, date: date)
        dismiss()
    }

    private func finishCalculation() {
        if let value = AmountExpression.evaluate(amountText) { amountText = AmountExpression.formatted(value) }
        amountFocused = false
    }
}

struct AmountKeyboardAccessory: View {
    @Binding var expression: String
    let finishCalculation: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(["+", "−", "×", "÷"], id: \.self) { operation in
                Button(operation) {
                    expression = AmountExpression.appending(operation, to: expression)
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 36)
                .buttonStyle(.bordered)
                .accessibilityLabel("加入 \(operation) 運算")
            }
            Button(action: finishCalculation) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .frame(minWidth: 38, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("計算並收起鍵盤")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }
}
