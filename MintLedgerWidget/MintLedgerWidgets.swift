import SwiftUI
import WidgetKit

struct LedgerEntry: TimelineEntry {
    let date: Date
    let snapshot: LedgerSnapshot
}

struct LedgerProvider: TimelineProvider {
    func placeholder(in context: Context) -> LedgerEntry { LedgerEntry(date: .now, snapshot: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (LedgerEntry) -> Void) {
        completion(LedgerEntry(date: .now, snapshot: (try? SharedLedgerStorage.load()) ?? .empty))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LedgerEntry>) -> Void) {
        let entry = LedgerEntry(date: .now, snapshot: (try? SharedLedgerStorage.load()) ?? .empty)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(300))))
    }
}

struct LedgerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LedgerEntry

    private var balance: Int64 {
        entry.snapshot.accounts.reduce(0) { $0 + $1.openingBalanceMinor } + entry.snapshot.transactions.reduce(0) { $0 + $1.signedAmountMinor }
    }
    private var recentTransactions: [LedgerTransaction] {
        Array(entry.snapshot.transactions.sorted { $0.date > $1.date }.prefix(3))
    }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                Label("總資產", systemImage: "wallet.pass.fill")
                    .font(.caption.weight(.semibold))
                Text(balance.currency(code: entry.snapshot.currencyCode))
                    .font(.headline)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        default:
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("總資產", systemImage: "wallet.pass.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(balance.currency(code: entry.snapshot.currencyCode))
                        .font(.title2.bold())
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .monospacedDigit()
                    Spacer()
                    Text("MintLedger")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 7) {
                    Text("近期明細").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if recentTransactions.isEmpty {
                        Spacer()
                        Text("尚無交易").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    } else {
                        ForEach(recentTransactions) { transaction in
                            HStack(spacing: 6) {
                                Image(systemName: transaction.category.symbol)
                                    .frame(width: 16)
                                Text(transaction.note.isEmpty ? transaction.category.title : transaction.note)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                Text(transaction.amountMinor.currency(code: entry.snapshot.currencyCode))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(transaction.kind == .income ? .green : .red)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

struct MintLedgerSummaryWidget: Widget {
    let kind = "MintLedgerSummaryWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LedgerProvider()) { entry in
            LedgerWidgetView(entry: entry)
                .containerBackground(for: .widget) { LinearGradient(colors: [Color(red: 0.03, green: 0.12, blue: 0.22), Color(red: 0.05, green: 0.28, blue: 0.27)], startPoint: .topLeading, endPoint: .bottomTrailing) }
                .foregroundStyle(.white)
        }
        .configurationDisplayName("MintLedger 資產")
        .description("與 App 共用帳本資料；在鎖定畫面查看總資產，或在桌面查看近期明細。")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

@main
struct MintLedgerWidgetBundle: WidgetBundle {
    var body: some Widget { MintLedgerSummaryWidget() }
}
