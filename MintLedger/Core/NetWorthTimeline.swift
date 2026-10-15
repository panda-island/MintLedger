import Foundation

enum NetWorthRange: String, CaseIterable, Identifiable {
    case month, quarter, year, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .month: "1 個月"
        case .quarter: "3 個月"
        case .year: "1 年"
        case .all: "全部"
        }
    }
    var months: Int? {
        switch self {
        case .month: 1
        case .quarter: 3
        case .year: 12
        case .all: nil
        }
    }
}

struct NetWorthPoint: Identifiable {
    let date: Date
    let amountMinor: Int64
    var currencyCode = "TWD"
    var id: Date { date }
    var amount: Double { CurrencyMath.double(amountMinor, code: currencyCode) }
}

struct NetWorthTimeline {
    let points: [NetWorthPoint]
    let openingMinor: Int64
    let usesMonthlySamples: Bool
    var changeMinor: Int64 { (points.last?.amountMinor ?? openingMinor) - openingMinor }

    init(snapshot: LedgerSnapshot, range: NetWorthRange, now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let transactions = snapshot.transactions.filter { $0.date <= now }.sorted { $0.date < $1.date }
        let start: Date
        if let months = range.months {
            start = calendar.date(byAdding: .month, value: -months, to: today) ?? today
        } else if let first = transactions.first {
            // Include the day before the first transaction to show the initial balance.
            start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: first.date)) ?? today
        } else {
            start = calendar.date(byAdding: .month, value: -1, to: today) ?? today
        }

        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        usesMonthlySamples = range == .all && days > 400
        var dates: [Date] = []
        if usesMonthlySamples {
            dates.append(start)
            let monthCount = calendar.dateComponents([.month], from: start, to: today).month ?? 0
            let stride = max(1, (monthCount + 399) / 400)
            var monthEnd = calendar.dateInterval(of: .month, for: start)?.end
            while let boundary = monthEnd,
                  let date = calendar.date(byAdding: .day, value: -1, to: boundary), date < today {
                if date > start { dates.append(date) }
                monthEnd = calendar.date(byAdding: .month, value: stride, to: boundary)
            }
            if dates.last != today { dates.append(today) }
        } else {
            var day = start
            while day <= today {
                dates.append(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }

        var balance = snapshot.accounts.reduce(Int64.zero) { $0 + $1.openingBalanceMinor }
        var index = 0
        while index < transactions.count && transactions[index].date < start {
            balance += transactions[index].signedAmountMinor
            index += 1
        }
        openingMinor = balance
        var result: [NetWorthPoint] = []
        for date in dates {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            while index < transactions.count && transactions[index].date < nextDay {
                balance += transactions[index].signedAmountMinor
                index += 1
            }
            result.append(NetWorthPoint(date: date, amountMinor: balance, currencyCode: snapshot.currencyCode))
        }
        points = result
    }
}
