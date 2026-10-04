import XCTest
import UniformTypeIdentifiers
@testable import MintLedger

final class MintLedgerTests: XCTestCase {
    func testSignedAmounts() {
        let account = UUID()
        let expense = LedgerTransaction(kind: .expense, amountMinor: 12_500, category: .food, accountID: account, note: "午餐", date: .now)
        let income = LedgerTransaction(kind: .income, amountMinor: 50_000, category: .salary, accountID: account, note: "薪資", date: .now)
        XCTAssertEqual(expense.signedAmountMinor, -12_500)
        XCTAssertEqual(income.signedAmountMinor, 50_000)
    }

    func testBackupRoundTrip() throws {
        let account = LedgerAccount(name: "測試", symbol: "wallet.pass")
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let original = LedgerSnapshot(
            transactions: [LedgerTransaction(kind: .expense, amountMinor: 9_900, category: .shopping, accountID: account.id, note: "測試交易", date: fixedDate, createdAt: fixedDate)],
            accounts: [account],
            budgets: [Budget(category: .shopping, limitMinor: 100_000)],
            currencyCode: "TWD",
            updatedAt: fixedDate
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(LedgerSnapshot.self, from: encoder.encode(original)), original)
    }

    func testAllCategoriesHavePresentation() {
        for category in LedgerCategory.allCases {
            XCTAssertFalse(category.title.isEmpty)
            XCTAssertFalse(category.symbol.isEmpty)
        }
    }

    func testAmountExpressionUsesOperatorPrecedence() {
        XCTAssertEqual(AmountExpression.evaluate("100+20×3"), 160)
        XCTAssertEqual(AmountExpression.evaluate("100÷4−5"), 20)
    }

    func testAmountExpressionRejectsIncompleteOrInvalidMath() {
        XCTAssertNil(AmountExpression.evaluate("100+"))
        XCTAssertNil(AmountExpression.evaluate("100÷0"))
        XCTAssertNil(AmountExpression.evaluate("-1"))
    }

    func testBackupFileTypeIsJSONWithExpectedExtension() {
        XCTAssertTrue(UTType.mintLedgerBackup.conforms(to: .json))
        XCTAssertEqual(UTType.mintLedgerBackup.preferredFilenameExtension, "mintledger")
        XCTAssertTrue(UTType.mintLedgerBackup.conforms(to: .item))
    }

    func testWidgetUsesTheSameSharedLedgerLocation() throws {
        XCTAssertEqual(SharedLedgerStorage.widgetKind, "MintLedgerSummaryWidget")
        XCTAssertEqual(try SharedLedgerStorage.dataURL().lastPathComponent, "ledger-v1.json")
    }

    func testWidgetUsesTheSameAppGroupAsTheMainApp() {
        XCTAssertEqual(SharedLedgerStorage.appGroupID, "group.com.pandaisland.mintledger")
    }

    func testCloudBackupUsesAppSpecificIdentifiers() {
        XCTAssertEqual(ICloudBackupService.containerIdentifier, "iCloud.com.pandaisland.mintledger")
        XCTAssertEqual(CloudBackupPurchaseService.productID, "com.pandaisland.mintledger.cloudbackup.lifetime")
    }

    func testAppendingAnOperatorReplacesThePreviousOperator() {
        XCTAssertEqual(AmountExpression.appending("×", to: "100+"), "100×")
    }

    func testLedgerDateFormattingUsesChineseMonthsAndTimePeriods() {
        let priorYear = Date(timeIntervalSince1970: 1_600_000_000)
        XCTAssertTrue(priorYear.ledgerMonthText.contains("月"))
        XCTAssertTrue(priorYear.ledgerDateTimeText.contains("年"))
        XCTAssertTrue(priorYear.ledgerDateTimeText.contains("月"))
        XCTAssertTrue(priorYear.ledgerDateTimeText.contains("日"))
        XCTAssertTrue(priorYear.ledgerDateTimeText.contains("點"))
        XCTAssertFalse(priorYear.ledgerDateTimeText.localizedCaseInsensitiveContains("AM"))
        XCTAssertFalse(priorYear.ledgerDateTimeText.localizedCaseInsensitiveContains("PM"))
    }

    func testCurrentYearDateDoesNotRepeatItsYearAndUsesChineseDayTitles() {
        let current = Date.now
        XCTAssertFalse(current.ledgerDateTimeText.contains("年"))
        XCTAssertEqual(current.ledgerDayTitle, "今天")
        XCTAssertTrue(current.ledgerShowsShortDateAlongsideDayTitle)
        XCTAssertTrue(current.ledgerShortDateText.contains("月"))
    }
}
