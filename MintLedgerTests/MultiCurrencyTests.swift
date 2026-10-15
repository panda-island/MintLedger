import XCTest
@testable import MintLedger

final class MultiCurrencyTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_760_400_000)

    private func value(_ text: String) -> Decimal { Decimal(string: text)! }

    func testCurrencyMinorUnitsAndDecimalRounding() throws {
        XCTAssertEqual(try CurrencyMath.minor(value("12.345"), code: "USD"), 1_235)
        XCTAssertEqual(try CurrencyMath.minor(value("123.5"), code: "JPY"), 124)
        XCTAssertEqual(try CurrencyMath.minor(value("1.234"), code: "KWD"), 1_234)
        XCTAssertEqual(try CurrencyMath.minor(value("-12.345"), code: "TWD"), -1_235)
        XCTAssertEqual(CurrencyMath.major(1_234, code: "KWD"), value("1.234"))
        XCTAssertEqual(Set(CurrencyMath.codes).count, CurrencyMath.codes.count)
        XCTAssertTrue(CurrencyMath.codes.contains("TWD"))
        XCTAssertNil(CurrencyMath.decimal("31.5junk"))
        XCTAssertThrowsError(try CurrencyMath.minor(value("99999999999999999999999999"), code: "TWD"))
    }

    func testBookingRetainsOriginalCurrencyAndLockedRate() throws {
        let result = try ExchangeRateService.booking(amount: value("12.34"), from: "USD", to: "TWD", day: "2025-10-14", rate: value("31.57"), rateDate: "2025-10-14", source: "自訂匯率")
        XCTAssertEqual(result.amountMinor, 38_957)
        XCTAssertEqual(result.conversion.originalAmount, "12.34")
        XCTAssertEqual(result.conversion.originalCurrencyCode, "USD")
        XCTAssertEqual(result.conversion.rate, "31.57")
        XCTAssertEqual(result.conversion.booked.amountMinor, result.amountMinor)
        XCTAssertEqual(result.conversion.bookingRateSource, "自訂匯率")
        let jpy = try ExchangeRateService.booking(amount: 1_500, from: "JPY", to: "USD", day: "2025-10-14", rate: value("0.0067"), rateDate: "2025-10-14", source: "test")
        XCTAssertEqual(jpy.amountMinor, 1_005)
        XCTAssertThrowsError(try ExchangeRateService.booking(amount: 10, from: "USD", to: "TWD", day: "2025-10-14", rate: -1, rateDate: "2025-10-14", source: "test"))
        XCTAssertThrowsError(try ExchangeRateService.booking(amount: 10, from: "USD", to: "USD", day: "2025-10-14", rate: 2, rateDate: "2025-10-14", source: "test"))
    }

    func testHistoricalQuoteResponseRejectsWrongPairAndFutureObservation() throws {
        let fixture = Data(#"{"date":"2025-10-14","base":"USD","quote":"TWD","rate":30.72}"#.utf8)
        let quote = try ExchangeRateService.decodeQuote(fixture, from: "USD", to: "TWD", requestedDay: "2025-10-14")
        XCTAssertEqual(quote.rate, value("30.72"))
        XCTAssertThrowsError(try ExchangeRateService.decodeQuote(fixture, from: "JPY", to: "TWD", requestedDay: "2025-10-14"))
        XCTAssertThrowsError(try ExchangeRateService.decodeQuote(fixture, from: "USD", to: "TWD", requestedDay: "2025-10-13"))
    }

    func testV1BackupMigrationPreservesTWDAndConvertsOldJPYUnits() throws {
        let account = LedgerAccount(name: "測試", symbol: "banknote", openingBalanceMinor: -5_000)
        let transaction = LedgerTransaction(kind: .expense, amountMinor: 12_300, category: .food, accountID: account.id, note: "", date: date, createdAt: date)
        for code in ["TWD", "JPY", "KWD"] {
            let snapshot = LedgerSnapshot(schemaVersion: 1, transactions: [transaction], accounts: [account], currencyCode: code, updatedAt: date)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let result = try decoder.decode(LedgerSnapshot.self, from: encoder.encode(snapshot))
            XCTAssertEqual(result.schemaVersion, 2)
            XCTAssertEqual(CurrencyMath.major(result.transactions[0].amountMinor, code: code), 123)
            XCTAssertEqual(CurrencyMath.major(result.accounts[0].openingBalanceMinor, code: code), -50)
            XCTAssertNil(result.transactions[0].conversion)
        }
    }

    func testForeignCurrencyBackupAndWatchPayloadRoundTrip() throws {
        let account = LedgerAccount(name: "銀行", symbol: "building.columns")
        let booking = try ExchangeRateService.booking(amount: value("1.234"), from: "KWD", to: "USD", day: "2025-10-14", rate: value("3.25"), rateDate: "2025-10-14", source: "test")
        let transaction = LedgerTransaction(kind: .income, amountMinor: booking.amountMinor, category: .other, accountID: account.id, note: "原幣保留", date: date, createdAt: date, conversion: booking.conversion)
        let snapshot = LedgerSnapshot(transactions: [transaction], accounts: [account], currencyCode: "USD", updatedAt: date)
        let data = try WatchSyncPayload.encode(snapshot)
        let decoded = try WatchSyncPayload.decode(LedgerSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.transactions[0].conversion?.originalAmount, "1.234")
    }

    func testBaseCurrencyChangeUsesHistoricalDaysAndKeepsStableBookingAnchors() async throws {
        let account = LedgerAccount(name: "測試", symbol: "banknote", openingBalanceMinor: -1_000)
        let transaction = LedgerTransaction(kind: .income, amountMinor: 12_345, category: .salary, accountID: account.id, note: "", date: date, createdAt: date)
        let original = LedgerSnapshot(transactions: [transaction], accounts: [account], currencyCode: "TWD", updatedAt: date)
        let recorder = QuoteRecorder()
        let jpy = try await CurrencyRebaser.rebase(original, to: "JPY", day: "2025-10-15") { from, to, day in
            await recorder.record(day)
            return ExchangeQuote(date: day, base: from, quote: to, rate: 5)
        }
        XCTAssertEqual(jpy.transactions[0].amountMinor, 617)
        XCTAssertEqual(jpy.accounts[0].openingBalanceMinor, -50)
        XCTAssertEqual(jpy.transactions[0].id, transaction.id)
        XCTAssertEqual(jpy.transactions[0].conversion?.originalAmount, "123.45")
        let requestedDays = await recorder.days
        XCTAssertTrue(requestedDays.contains(CurrencyMath.day(date)))
        XCTAssertTrue(requestedDays.contains("2025-10-15"))
        let back = try await CurrencyRebaser.rebase(jpy, to: "TWD") { _, _, _ in
            XCTFail("Returning to the original booking currency must not fetch or round again")
            throw CurrencyError.unavailableRate
        }
        XCTAssertEqual(back.transactions[0].amountMinor, original.transactions[0].amountMinor)
        XCTAssertEqual(back.accounts[0].openingBalanceMinor, original.accounts[0].openingBalanceMinor)
    }

    func testReturningToOriginalForeignCurrencyPreservesTheActualOriginalAmount() async throws {
        let booking = try ExchangeRateService.booking(amount: value("12.34"), from: "USD", to: "TWD", day: "2025-10-14", rate: value("31.57"), rateDate: "2025-10-14", source: "自訂匯率")
        let transaction = LedgerTransaction(kind: .expense, amountMinor: booking.amountMinor, category: .food, accountID: UUID(), note: "", date: date, createdAt: date, conversion: booking.conversion)
        let snapshot = LedgerSnapshot(transactions: [transaction], accounts: [], currencyCode: "TWD", updatedAt: date)
        let usd = try await CurrencyRebaser.rebase(snapshot, to: "USD") { _, _, _ in
            XCTFail("Original foreign amount is already known")
            throw CurrencyError.unavailableRate
        }
        XCTAssertEqual(usd.transactions[0].amountMinor, 1_234)
        XCTAssertEqual(usd.transactions[0].conversion?.bookingRate, "31.57")
        let back = try await CurrencyRebaser.rebase(usd, to: "TWD") { _, _, _ in throw CurrencyError.unavailableRate }
        XCTAssertEqual(back.transactions[0].amountMinor, booking.amountMinor)
        XCTAssertEqual(back.transactions[0].conversion?.rateSource, "自訂匯率")
    }

    func testMissingRatesAbortBaseCurrencyChange() async throws {
        let transaction = LedgerTransaction(kind: .expense, amountMinor: 100, category: .food, accountID: UUID(), note: "", date: date, createdAt: date)
        let snapshot = LedgerSnapshot(transactions: [transaction], accounts: [], currencyCode: "TWD", updatedAt: date)
        do {
            _ = try await CurrencyRebaser.rebase(snapshot, to: "USD") { _, _, _ in throw CurrencyError.unavailableRate }
            XCTFail("Missing quotes must not produce a partially converted ledger")
        } catch { XCTAssertTrue(error is CurrencyError) }
        XCTAssertEqual(snapshot.currencyCode, "TWD")
        XCTAssertEqual(snapshot.transactions[0].amountMinor, 100)
    }

    @MainActor
    func testEditingNotesKeepsSavedRateAndChangingCurrencyClearsManualRate() async throws {
        let booking = try ExchangeRateService.booking(amount: 10, from: "USD", to: "TWD", day: CurrencyMath.day(date), rate: value("31.57"), rateDate: CurrencyMath.day(date), source: "自訂匯率")
        let transaction = LedgerTransaction(kind: .expense, amountMinor: booking.amountMinor, category: .food, accountID: UUID(), note: "", date: date, createdAt: date, conversion: booking.conversion)
        let draft = CurrencyEntryModel(transaction: transaction)
        draft.prepare(base: "TWD")
        await draft.loadRate(base: "TWD")
        let saved = try draft.booking(base: "TWD")
        XCTAssertEqual(saved.conversion, booking.conversion)
        draft.currencyCode = "JPY"
        XCTAssertFalse(draft.manualRate)
        XCTAssertEqual(draft.rateText, "")
        XCTAssertThrowsError(try draft.booking(base: "TWD"))
        draft.manualRate = true
        draft.rateText = "0.21"
        draft.amountText = "100"
        await draft.loadRate(base: "TWD")
        XCTAssertEqual(try draft.booking(base: "TWD").amountMinor, 2_100)
    }

    @MainActor
    func testUnchangedTransactionUsesSavedCalendarDayInsteadOfDeviceTimeZone() async throws {
        // The saved day can differ from today's local rendering of its UTC timestamp.
        let day = "2025-10-13"
        let booking = try ExchangeRateService.booking(amount: 10, from: "USD", to: "TWD", day: day, rate: value("31.57"), rateDate: day, source: "Frankfurter 每日參考匯率")
        let transaction = LedgerTransaction(kind: .expense, amountMinor: booking.amountMinor, category: .food, accountID: UUID(), note: "", date: date, createdAt: date, conversion: booking.conversion)
        let draft = CurrencyEntryModel(transaction: transaction)
        draft.prepare(base: "TWD")
        await draft.loadRate(base: "TWD")
        XCTAssertNil(draft.error)
        XCTAssertEqual(draft.rateDate, day)
        XCTAssertEqual(try draft.booking(base: "TWD").conversion, booking.conversion)
    }

    @MainActor
    func testArithmeticInputDoesNotCreateBinaryFloatingPointRoundingErrors() async throws {
        let draft = CurrencyEntryModel()
        draft.prepare(base: "USD")
        draft.amountText = "0.1+0.2"
        await draft.loadRate(base: "USD")
        let booking = try draft.booking(base: "USD")
        XCTAssertEqual(booking.amountMinor, 30)
        XCTAssertEqual(booking.conversion.originalAmount, "0.3")
    }
}

private actor QuoteRecorder {
    private(set) var days: [String] = []
    func record(_ day: String) { days.append(day) }
}
