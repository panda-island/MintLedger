import SwiftUI

struct BudgetsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var editingCategory: LedgerCategory?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(LedgerCategory.allCases.filter { $0 != .salary && $0 != .investment }) { category in
                    BudgetRow(
                        category: category,
                        spent: spent(for: category),
                        budget: store.snapshot.budgets.first { $0.category == category }?.limitMinor
                    ) { editingCategory = category }
                }
            }.padding()
        }
        .navigationTitle("每月預算")
        .sheet(item: $editingCategory) { category in BudgetEditor(category: category) }
    }

    private func spent(for category: LedgerCategory) -> Int64 {
        store.currentMonthTransactions.filter { $0.kind == .expense && $0.category == category }.reduce(0) { $0 + $1.amountMinor }
    }
}

private struct BudgetRow: View {
    @Environment(LedgerStore.self) private var store
    let category: LedgerCategory
    let spent: Int64
    let budget: Int64?
    let edit: () -> Void

    private var progress: Double { guard let budget, budget > 0 else { return 0 }; return min(Double(spent) / Double(budget), 1) }

    var body: some View {
        Button(action: edit) {
            GlassCard {
                VStack(spacing: 11) {
                    HStack {
                        Label(category.title, systemImage: category.symbol).font(.headline)
                        Spacer()
                        Text(budget.map { "\(spent.currency(code: store.snapshot.currencyCode)) / \($0.currency(code: store.snapshot.currencyCode))" } ?? "設定預算")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: progress)
                        .tint(progress > 0.9 ? .red : .mintLedger)
                }
            }
        }.buttonStyle(.plain)
    }
}

private struct BudgetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LedgerStore.self) private var store
    let category: LedgerCategory
    @State private var amount = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("\(category.title)每月上限") {
                    TextField("金額", text: $amount).keyboardType(.decimalPad)
                }
                Section { Text("預算會在每個月自動重新計算使用進度，不會刪除舊交易。") }.foregroundStyle(.secondary)
            }
            .navigationTitle("設定預算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("儲存") { save() } }
            }
            .onAppear {
                if let current = store.snapshot.budgets.first(where: { $0.category == category })?.limitMinor { amount = String(format: "%.0f", Double(current) / 100) }
            }
        }
    }

    private func save() {
        guard let value = Decimal(string: amount), value >= 0 else { return }
        store.upsertBudget(category: category, limitMinor: NSDecimalNumber(decimal: value * 100).int64Value)
        dismiss()
    }
}
