import Charts
import SwiftUI

private enum ReportRange: String, CaseIterable, Identifiable {
    case month = "本月", threeMonths = "近三月", year = "今年"

    var id: String { rawValue }

    func startDate(calendar: Calendar = .current) -> Date {
        switch self {
        case .month:
            calendar.dateInterval(of: .month, for: .now)?.start ?? .distantPast
        case .threeMonths:
            calendar.date(byAdding: .month, value: -3, to: .now) ?? .distantPast
        case .year:
            calendar.dateInterval(of: .year, for: .now)?.start ?? .distantPast
        }
    }
}

struct ReportsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var range: ReportRange = .month

    private var expenses: [LedgerTransaction] {
        let start = range.startDate()
        return store.transactions.filter { $0.kind == .expense && $0.date >= start }
    }

    private var breakdown: [(category: LedgerCategory, amount: Int64)] {
        Dictionary(grouping: expenses, by: \.category)
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.amountMinor }) }
            .sorted { $0.amount > $1.amount }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("期間", selection: $range) {
                    ForEach(ReportRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if breakdown.isEmpty {
                    EmptyStateView(symbol: "chart.pie", title: "尚無分析資料", message: "記錄支出後會自動產生分類統計")
                } else {
                    GlassCard {
                        Chart(breakdown, id: \.category) { item in
                            SectorMark(angle: .value("金額", item.amount), innerRadius: .ratio(0.58), angularInset: 2)
                                .foregroundStyle(by: .value("分類", item.category.title))
                                .cornerRadius(5)
                        }
                        .frame(height: 250)
                        .chartLegend(position: .bottom, alignment: .center, spacing: 10)
                        .accessibilityLabel("支出分類圓餅圖")
                    }
                    GlassCard {
                        VStack(spacing: 0) {
                            ForEach(breakdown, id: \.category) { item in
                                NavigationLink {
                                    CategoryTransactionsView(category: item.category, range: range)
                                } label: {
                                    HStack {
                                        Label(item.category.title, systemImage: item.category.symbol)
                                        Spacer()
                                        AmountText(amountMinor: item.amount, currencyCode: store.snapshot.currencyCode, kind: .expense)
                                            .fontWeight(.semibold)
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.plain)

                                if item.category != breakdown.last?.category { Divider() }
                            }
                        }
                    }
                    Text("點選分類可查看該分類的帳目")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("分析")
    }
}

private struct CategoryTransactionsView: View {
    @Environment(LedgerStore.self) private var store
    let category: LedgerCategory
    let range: ReportRange
    @State private var editingTransaction: LedgerTransaction?

    private var transactions: [LedgerTransaction] {
        let start = range.startDate()
        return store.transactions
            .filter { $0.kind == .expense && $0.category == category && $0.date >= start }
            .sorted { $0.date > $1.date }
    }

    private var total: Int64 {
        transactions.reduce(0) { $0 + $1.amountMinor }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("期間", value: range.rawValue)
                LabeledContent("支出合計", value: total.currency(code: store.snapshot.currencyCode))
                    .foregroundStyle(.red)
            }

            Section("帳目") {
                ForEach(transactions) { transaction in
                    Button { editingTransaction = transaction } label: {
                        TransactionRow(transaction: transaction)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.deleteTransactions(ids: Set([transaction.id]))
                        } label: {
                            Label("刪除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingTransaction) { transaction in
            NavigationStack { TransactionEditorView(transaction: transaction) }
        }
    }
}
