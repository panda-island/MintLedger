import AppIntents
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
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(900))))
    }
}

struct LedgerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LedgerEntry

    private var monthExpenses: Int64 {
        entry.snapshot.transactions.filter { $0.kind == .expense && Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }.reduce(0) { $0 + $1.amountMinor }
    }
    private var balance: Int64 {
        entry.snapshot.accounts.reduce(0) { $0 + $1.openingBalanceMinor } + entry.snapshot.transactions.reduce(0) { $0 + $1.signedAmountMinor }
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 1) { Image(systemName: "wallet.pass.fill"); Text(compact(monthExpenses)).font(.caption2).monospacedDigit() }
                .accessibilityLabel("本月支出 \(monthExpenses.currency(code: entry.snapshot.currencyCode))")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("本月支出", systemImage: "chart.line.downtrend.xyaxis")
                Text(monthExpenses.currency(code: entry.snapshot.currencyCode)).font(.headline).monospacedDigit()
                Text("餘額 \(balance.currency(code: entry.snapshot.currencyCode))").font(.caption2)
            }
        default:
            VStack(alignment: .leading, spacing: 10) {
                HStack { Label("MintLedger", systemImage: "wallet.pass.fill").font(.headline); Spacer(); Text(entry.date, style: .time).font(.caption2).foregroundStyle(.secondary) }
                Text("本月支出").font(.caption).foregroundStyle(.secondary)
                Text(monthExpenses.currency(code: entry.snapshot.currencyCode)).font(.title2.bold()).monospacedDigit()
                HStack(spacing: 8) {
                    quickButton(50)
                    quickButton(100)
                    quickButton(200)
                }
            }
        }
    }

    private func quickButton(_ amount: Double) -> some View {
        Button(intent: QuickExpenseIntent(amount: amount)) {
            Text("+\(Int(amount))").font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 5)
        }.buttonStyle(.bordered)
    }

    private func compact(_ value: Int64) -> String {
        let whole = Double(value) / 100
        if whole >= 10_000 { return String(format: "%.0f萬", whole / 10_000) }
        return String(format: "%.0f", whole)
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
        .configurationDisplayName("MintLedger 摘要")
        .description("查看支出與餘額，或直接快速記帳。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct MintLedgerWidgetBundle: WidgetBundle {
    var body: some Widget { MintLedgerSummaryWidget() }
}

