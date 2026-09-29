import Charts
import SwiftUI

struct DashboardView: View {
    @Environment(LedgerStore.self) private var store

    private var dailyExpenses: [(date: Date, amount: Double)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.currentMonthTransactions.filter { $0.kind == .expense }) {
            calendar.startOfDay(for: $0.date)
        }
        return grouped.map { ($0.key, Double($0.value.reduce(0) { $0 + $1.amountMinor }) / 100) }.sorted { $0.date < $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                BalanceHero(balance: store.balanceMinor, currency: store.snapshot.currencyCode)
                monthCards
                expenseChart
                recentSection
            }
            .padding()
        }
        .background {
            LinearGradient(colors: [Color.mintLedger.opacity(0.14), .clear], startPoint: .topTrailing, endPoint: .center)
                .ignoresSafeArea()
        }
        .navigationTitle("MintLedger")
    }

    @ViewBuilder
    private var monthCards: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    MetricCard(title: "本月收入", amount: store.monthIncomeMinor, kind: .income, currency: store.snapshot.currencyCode)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    MetricCard(title: "本月支出", amount: store.monthExpenseMinor, kind: .expense, currency: store.snapshot.currencyCode)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                }
            }
        } else {
            HStack(spacing: 12) {
                GlassCard { MetricCard(title: "本月收入", amount: store.monthIncomeMinor, kind: .income, currency: store.snapshot.currencyCode) }
                GlassCard { MetricCard(title: "本月支出", amount: store.monthExpenseMinor, kind: .expense, currency: store.snapshot.currencyCode) }
            }
        }
    }

    private var expenseChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("本月支出趨勢").font(.headline)
                if dailyExpenses.isEmpty {
                    Text("新增支出後會顯示趨勢").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 130)
                } else {
                    Chart(dailyExpenses, id: \.date) { item in
                        AreaMark(x: .value("日期", item.date), y: .value("支出", item.amount))
                            .foregroundStyle(LinearGradient(colors: [Color.mintLedger.opacity(0.7), Color.mintLedger.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("日期", item.date), y: .value("支出", item.amount))
                            .foregroundStyle(Color.mintLedger).interpolationMethod(.catmullRom)
                    }
                    .frame(height: 150)
                    .chartXAxis(.hidden)
                    .accessibilityLabel("本月每日支出趨勢")
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近交易").font(.title3.bold()).padding(.horizontal, 4)
            if store.transactions.isEmpty {
                EmptyStateView(symbol: "tray", title: "還沒有交易", message: "點右下角新增第一筆記錄")
            } else {
                ForEach(store.transactions.prefix(5)) { transaction in
                    TransactionRow(transaction: transaction)
                }
            }
        }
    }
}

private struct BalanceHero: View {
    let balance: Int64
    let currency: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [Color.midnight, Color(red: 0.03, green: 0.24, blue: 0.30)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(Color.mintLedger.opacity(0.22)).frame(width: 150).offset(x: 40, y: 55)
            VStack(alignment: .leading, spacing: 8) {
                Label("總資產", systemImage: "wallet.pass.fill").foregroundStyle(.white.opacity(0.72))
                Text(balance.currency(code: currency)).font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(.white).monospacedDigit()
                Text("資料只保存在你的裝置上").font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(24)
        }
        .frame(minHeight: 170)
        .clipped()
        .accessibilityElement(children: .combine)
    }
}

private struct MetricCard: View {
    let title: String
    let amount: Int64
    let kind: TransactionKind
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: kind.symbol).foregroundStyle(kind == .income ? Color.green : Color.red)
            Text(title).font(.caption).foregroundStyle(.secondary)
            AmountText(amountMinor: amount, currencyCode: currency, kind: kind).font(.headline)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
    }
}
