import Charts
import SwiftUI

struct ReportsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var range: ReportRange = .month

    enum ReportRange: String, CaseIterable, Identifiable {
        case month = "本月", threeMonths = "近三月", year = "今年"
        var id: String { rawValue }
    }

    private var expenses: [LedgerTransaction] {
        let calendar = Calendar.current
        let start: Date = switch range {
        case .month: calendar.dateInterval(of: .month, for: .now)?.start ?? .distantPast
        case .threeMonths: calendar.date(byAdding: .month, value: -3, to: .now) ?? .distantPast
        case .year: calendar.dateInterval(of: .year, for: .now)?.start ?? .distantPast
        }
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
                Picker("期間", selection: $range) { ForEach(ReportRange.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
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
                        VStack(spacing: 12) {
                            ForEach(breakdown, id: \.category) { item in
                                HStack {
                                    Label(item.category.title, systemImage: item.category.symbol)
                                    Spacer()
                                    AmountText(amountMinor: item.amount, currencyCode: store.snapshot.currencyCode, kind: .expense).fontWeight(.semibold)
                                }
                                if item.category != breakdown.last?.category { Divider() }
                            }
                        }
                    }
                }
            }.padding()
        }
        .navigationTitle("分析")
    }
}

