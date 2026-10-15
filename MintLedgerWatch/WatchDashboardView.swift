import SwiftUI

struct WatchDashboardView: View {
    @Environment(WatchLedgerStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                BalanceCard(
                    amount: store.balanceMinor.currency(code: store.snapshot.currencyCode),
                    syncDate: store.lastSyncDate
                )

                NavigationLink {
                    WatchAddTransactionView()
                } label: {
                    Label("新增帳目", systemImage: "plus.circle.fill")
                        .foregroundStyle(.mint)
                }

                NavigationLink {
                    WatchSettingsView()
                } label: {
                    Label("設定", systemImage: "gearshape")
                }

                Section("近期明細") {
                    if !store.pendingTransactions.isEmpty {
                        Text("\(store.pendingTransactions.count) 筆待手機確認；其他主要幣別的未確認帳目暫不列入總資產。")
                            .font(.caption2).foregroundStyle(.secondary)
                        Button("重試同步") { store.retrySync() }
                    }
                    if let error = store.lastError {
                        Text(error).font(.caption2).foregroundStyle(.orange)
                    }
                    if store.recentTransactions.isEmpty {
                        Text("尚無帳目")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.recentTransactions) { transaction in
                            VStack(alignment: .leading, spacing: 2) {
                                WatchTransactionRow(
                                    title: transaction.note.isEmpty ? transaction.category.title : transaction.note,
                                    category: transaction.category.title,
                                    symbol: transaction.category.symbol,
                                    amount: transaction.amountMinor.currency(code: transaction.conversion?.baseCurrencyCode ?? store.snapshot.currencyCode),
                                    isIncome: transaction.kind == .income,
                                    date: transaction.date
                                )
                                if let conversion = transaction.conversion, conversion.originalCurrencyCode != store.snapshot.currencyCode {
                                    Text("原幣 \(conversion.originalCurrencyCode) \(conversion.originalAmount)").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("MintLedger")
        }
    }
}

private struct BalanceCard: View {
    let amount: String
    let syncDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("總資產", systemImage: "wallet.pass.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(amount)
                .font(.title3.weight(.bold))
                .minimumScaleFactor(0.7)
            if let syncDate {
                Text("同步於 \(syncDate, format: .dateTime.hour().minute())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WatchTransactionRow: View {
    let title: String
    let category: String
    let symbol: String
    let amount: String
    let isIncome: Bool
    let date: Date

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(isIncome ? Color.green : Color.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                Text("\(category)・\(date, format: .dateTime.month().day())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 3)
            Text("\(isIncome ? "+" : "−")\(amount)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isIncome ? Color.green : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(category)，\(isIncome ? "收入" : "支出") \(amount)")
    }
}
