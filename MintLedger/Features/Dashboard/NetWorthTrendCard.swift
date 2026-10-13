import Charts
import SwiftUI

struct NetWorthTrendCard: View {
    let snapshot: LedgerSnapshot
    @State private var range: NetWorthRange = .month

    var body: some View {
        // Selection lives in the plot, so dragging doesn't recalculate the ledger history.
        let timeline = NetWorthTimeline(snapshot: snapshot, range: range)
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("淨資產時間軸", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Picker("時間範圍", selection: $range) {
                    ForEach(NetWorthRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                NetWorthTrendPlot(timeline: timeline, currency: snapshot.currencyCode)
                    .id(range)

                HStack {
                    Text("區間增減").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(timeline.changeMinor > 0 ? "+" : "")\(timeline.changeMinor.currency(code: snapshot.currencyCode))")
                        .monospacedDigit()
                        .foregroundStyle(timeline.changeMinor < 0 ? Color.red : Color.green)
                }
                .font(.subheadline)

                Text(timeline.usesMonthlySamples ? "長期區間以月底餘額取樣，末點為今天。" : "點選或拖動圖表，查看當天淨資產。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("帳戶初始餘額＋累計收支；未來日期帳目不計入。修改歷史帳目或初始餘額會重算趨勢。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct NetWorthTrendPlot: View {
    let timeline: NetWorthTimeline
    let currency: String
    @State private var selectedDate: Date?

    private var highlightedPoint: NetWorthPoint? {
        guard let selectedDate else { return timeline.points.last }
        return timeline.points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    private var valueDomain: ClosedRange<Double> {
        let values = timeline.points.map(\.amount)
        let lower = values.min() ?? 0
        let upper = values.max() ?? 0
        let padding = max(max((upper - lower) * 0.15, max(abs(upper), abs(lower)) * 0.02), 1)
        return (lower - padding)...(upper + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let point = highlightedPoint {
                Text(selectedDate == nil ? "截至今天" : point.date.ledgerShortDateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(point.amountMinor.currency(code: currency))
                    .font(.title2.bold())
                    .monospacedDigit()
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
            }

            Chart {
                ForEach(timeline.points) { point in
                    LineMark(x: .value("日期", point.date), y: .value("淨資產", point.amount))
                        .foregroundStyle(Color.mintLedger)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.stepEnd)
                }
                if let point = highlightedPoint {
                    if selectedDate != nil {
                        RuleMark(x: .value("選取日期", point.date))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(dash: [3, 3]))
                    }
                    PointMark(x: .value("日期", point.date), y: .value("淨資產", point.amount))
                        .foregroundStyle(Color.mintLedger)
                        .symbolSize(45)
                }
            }
            .frame(height: 190)
            .chartYScale(domain: valueDomain)
            .chartXSelection(value: $selectedDate)
            .chartGesture { proxy in
                DragGesture(minimumDistance: 0)
                    .onChanged { value in proxy.selectXValue(at: value.location.x) }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(axisLabel(date)).font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(amount.formatted(.number.notation(.compactName).locale(Locale(identifier: "zh_TW"))))
                                .font(.caption2)
                        }
                    }
                }
            }
            .accessibilityLabel("\(currency) 淨資產時間軸趨勢")
        }
    }

    private func axisLabel(_ date: Date) -> String {
        guard let first = timeline.points.first, let last = timeline.points.last,
              last.date.timeIntervalSince(first.date) > 100 * 86_400 else { return date.ledgerShortDateText }
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return year == calendar.component(.year, from: .now) ? "\(month)月" : "\(year)年\(month)月"
    }
}
