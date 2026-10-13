import XCTest
@testable import MintLedger

final class NetWorthTimelineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func transaction(_ kind: TransactionKind, _ amount: Int64, _ date: Date, account: UUID) -> LedgerTransaction {
        LedgerTransaction(kind: kind, amountMinor: amount, category: .other, accountID: account, note: "", date: date)
    }

    func testRangeIncludesPriorBalanceAndFirstDayTransactionsButExcludesFuture() {
        let cash = LedgerAccount(name: "現金", symbol: "banknote", openingBalanceMinor: 100_000)
        let debt = LedgerAccount(name: "信用卡", symbol: "creditcard", openingBalanceMinor: -30_000)
        let snapshot = LedgerSnapshot(transactions: [
            transaction(.income, 3_000, date(2026, 3, 15, hour: 10), account: cash.id),
            transaction(.expense, 1_000, date(2026, 2, 15), account: cash.id),
            transaction(.income, 5_000, date(2026, 1, 1), account: cash.id),
            transaction(.expense, 2_000, date(2026, 2, 14), account: cash.id),
            transaction(.expense, 99_000, date(2026, 3, 16), account: cash.id),
            transaction(.income, 88_000, date(2026, 3, 15, hour: 18), account: cash.id)
        ], accounts: [cash, debt])
        let timeline = NetWorthTimeline(snapshot: snapshot, range: .month, now: date(2026, 3, 15), calendar: calendar)
        XCTAssertEqual(timeline.openingMinor, 73_000)
        XCTAssertEqual(timeline.points.first?.amountMinor, 72_000)
        XCTAssertEqual(timeline.points.last?.amountMinor, 75_000)
        XCTAssertEqual(timeline.changeMinor, 2_000)
        XCTAssertEqual(timeline.points.first?.date, date(2026, 2, 15, hour: 0))
        XCTAssertEqual(timeline.points.count, 29)
    }

    func testAllHistoryStartsBeforeFirstTransactionAndCarriesBalanceAcrossQuietDays() {
        let account = LedgerAccount(name: "負餘額", symbol: "creditcard", openingBalanceMinor: -10_000)
        let snapshot = LedgerSnapshot(transactions: [
            transaction(.expense, 2_000, date(2026, 3, 11), account: account.id),
            transaction(.income, 5_000, date(2026, 3, 11), account: account.id)
        ], accounts: [account])
        let timeline = NetWorthTimeline(snapshot: snapshot, range: .all, now: date(2026, 3, 15), calendar: calendar)
        XCTAssertEqual(timeline.points.first?.date, date(2026, 3, 10, hour: 0))
        XCTAssertEqual(timeline.points.first?.amountMinor, -10_000)
        XCTAssertTrue(timeline.points.dropFirst().allSatisfy { $0.amountMinor == -7_000 })
        XCTAssertEqual(timeline.changeMinor, 3_000)
    }

    func testEmptyLedgerStillShowsInitialBalanceAndZeroChange() {
        let account = LedgerAccount(name: "起始", symbol: "banknote", openingBalanceMinor: 12_345)
        for range in NetWorthRange.allCases {
            let timeline = NetWorthTimeline(snapshot: LedgerSnapshot(accounts: [account]), range: range, now: date(2026, 3, 15), calendar: calendar)
            XCTAssertGreaterThan(timeline.points.count, 1)
            XCTAssertTrue(timeline.points.allSatisfy { $0.amountMinor == 12_345 })
            XCTAssertEqual(timeline.changeMinor, 0)
        }
    }

    func testLongHistoryIsSampledWithoutLosingIntermediateTransactionsOrLastBalance() {
        let account = LedgerAccount(name: "長期", symbol: "banknote", openingBalanceMinor: 10_000)
        let snapshot = LedgerSnapshot(transactions: [
            transaction(.income, 5_000, date(2000, 1, 15), account: account.id),
            transaction(.expense, 2_000, date(2000, 1, 25), account: account.id),
            transaction(.income, 7_000, date(2026, 3, 10), account: account.id)
        ], accounts: [account])
        let timeline = NetWorthTimeline(snapshot: snapshot, range: .all, now: date(2026, 3, 15), calendar: calendar)
        XCTAssertTrue(timeline.usesMonthlySamples)
        XCTAssertLessThan(timeline.points.count, 402)
        XCTAssertEqual(timeline.points.first?.amountMinor, 10_000)
        XCTAssertEqual(timeline.points.first { $0.date == date(2000, 1, 31, hour: 0) }?.amountMinor, 13_000)
        XCTAssertEqual(timeline.points.last?.amountMinor, 20_000)
        XCTAssertEqual(timeline.points.last?.date, date(2026, 3, 15, hour: 0))
        XCTAssertEqual(timeline.changeMinor, 10_000)
    }

    func testEditingAndDeletingHistoricalTransactionsRebuildsTimeline() {
        let account = LedgerAccount(name: "歷史", symbol: "banknote", openingBalanceMinor: 5_000)
        var snapshot = LedgerSnapshot(transactions: [transaction(.expense, 1_000, date(2026, 3, 1), account: account.id)], accounts: [account])
        func latest() -> Int64? {
            NetWorthTimeline(snapshot: snapshot, range: .quarter, now: date(2026, 3, 15), calendar: calendar).points.last?.amountMinor
        }
        XCTAssertEqual(latest(), 4_000)
        snapshot.transactions[0].amountMinor = 2_000
        XCTAssertEqual(latest(), 3_000)
        snapshot.transactions.removeAll()
        XCTAssertEqual(latest(), 5_000)
        snapshot.accounts[0].openingBalanceMinor = 8_000
        XCTAssertEqual(latest(), 8_000)
    }

    func testDailySamplesUseCalendarDaysAcrossDaylightSavingTime() {
        var localCalendar = calendar
        localCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = localCalendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12))!
        let timeline = NetWorthTimeline(snapshot: .empty, range: .month, now: now, calendar: localCalendar)
        XCTAssertEqual(Set(timeline.points.map(\.date)).count, timeline.points.count)
        XCTAssertEqual(timeline.points.last?.date, localCalendar.startOfDay(for: now))
        let gaps = zip(timeline.points, timeline.points.dropFirst()).map { pair in pair.1.date.timeIntervalSince(pair.0.date) }
        XCTAssertTrue(gaps.contains(23 * 3_600))
    }
}
