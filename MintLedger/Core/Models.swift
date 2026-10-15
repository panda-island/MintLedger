import Foundation

enum TransactionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case expense
    case income

    var id: String { rawValue }
    var title: String { self == .expense ? "支出" : "收入" }
    var symbol: String { self == .expense ? "arrow.up.right" : "arrow.down.left" }
}

enum LedgerCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case food, transport, shopping, housing, entertainment, health, education, salary, allowance, investment, travel, other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .food: "餐飲"
        case .transport: "交通"
        case .shopping: "購物"
        case .housing: "居家"
        case .entertainment: "娛樂"
        case .health: "醫療"
        case .education: "學習"
        case .salary: "薪資"
        case .allowance: "零用錢"
        case .investment: "投資"
        case .travel: "旅遊"
        case .other: "其他"
        }
    }

    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .transport: "car.fill"
        case .shopping: "bag.fill"
        case .housing: "house.fill"
        case .entertainment: "gamecontroller.fill"
        case .health: "cross.case.fill"
        case .education: "book.fill"
        case .salary: "banknote.fill"
        case .allowance: "giftcard.fill"
        case .investment: "chart.line.uptrend.xyaxis"
        case .travel: "airplane"
        case .other: "ellipsis.circle.fill"
        }
    }
}

struct LedgerAccount: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var symbol: String
    var openingBalanceMinor: Int64 = 0
    var openingReference: CurrencyReference? = nil

    static let defaults = [
        LedgerAccount(name: "現金", symbol: "banknote"),
        LedgerAccount(name: "銀行", symbol: "building.columns"),
        LedgerAccount(name: "信用卡", symbol: "creditcard")
    ]
}

struct LedgerTransaction: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var kind: TransactionKind
    var amountMinor: Int64
    var category: LedgerCategory
    var accountID: UUID
    var note: String
    var date: Date
    var createdAt: Date = .now
    var conversion: CurrencyConversion? = nil

    var signedAmountMinor: Int64 { kind == .income ? amountMinor : -amountMinor }
}

struct Budget: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var category: LedgerCategory
    var limitMinor: Int64
    var currencyReference: CurrencyReference? = nil
}

struct RecurringEntry: Codable, Hashable, Identifiable, Sendable {
    enum Cadence: String, Codable, CaseIterable, Identifiable, Sendable {
        case weekly, monthly, yearly
        var id: String { rawValue }
        var title: String { switch self { case .weekly: "每週"; case .monthly: "每月"; case .yearly: "每年" } }
    }

    var id: UUID = UUID()
    var title: String
    var kind: TransactionKind
    var amountMinor: Int64
    var category: LedgerCategory
    var accountID: UUID
    var cadence: Cadence
    var nextDate: Date
    var isEnabled = true
    var currencyReference: CurrencyReference? = nil
}

struct LedgerSnapshot: Codable, Hashable, Sendable {
    var schemaVersion = 2
    var transactions: [LedgerTransaction] = []
    var accounts: [LedgerAccount] = LedgerAccount.defaults
    var budgets: [Budget] = []
    var recurringEntries: [RecurringEntry] = []
    var currencyCode = "TWD"
    var updatedAt: Date = .now

    static var empty: LedgerSnapshot { LedgerSnapshot() }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, transactions, accounts, budgets, recurringEntries, currencyCode, updatedAt
    }
}

extension LedgerSnapshot {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        transactions = try values.decode([LedgerTransaction].self, forKey: .transactions)
        accounts = try values.decode([LedgerAccount].self, forKey: .accounts)
        budgets = try values.decodeIfPresent([Budget].self, forKey: .budgets) ?? []
        recurringEntries = try values.decodeIfPresent([RecurringEntry].self, forKey: .recurringEntries) ?? []
        currencyCode = try values.decode(String.self, forKey: .currencyCode)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        if schemaVersion < 2 {
            // V1 stored hundredths for every currency. V2 uses each ISO currency's
            // own minor unit (JPY 0, USD/TWD 2, KWD 3), preserving old backup values.
            for index in transactions.indices { transactions[index].amountMinor = try CurrencyMath.minor(Decimal(transactions[index].amountMinor) / 100, code: currencyCode) }
            for index in accounts.indices { accounts[index].openingBalanceMinor = try CurrencyMath.minor(Decimal(accounts[index].openingBalanceMinor) / 100, code: currencyCode) }
            for index in budgets.indices { budgets[index].limitMinor = try CurrencyMath.minor(Decimal(budgets[index].limitMinor) / 100, code: currencyCode) }
            for index in recurringEntries.indices { recurringEntries[index].amountMinor = try CurrencyMath.minor(Decimal(recurringEntries[index].amountMinor) / 100, code: currencyCode) }
            schemaVersion = 2
        }
    }
}

extension Int64 {
    func currency(code: String) -> String {
        CurrencyMath.display(CurrencyMath.major(self, code: code), code: code)
    }
}
