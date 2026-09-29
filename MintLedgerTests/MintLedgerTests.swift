import XCTest
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
}
