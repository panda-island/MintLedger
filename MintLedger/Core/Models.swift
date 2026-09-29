import Foundation

enum TransactionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case expense
    case income

    var id: String { rawValue }
    var title: String { self == .expense ? "支出" : "收入" }
    var symbol: String { self == .expense ? "arrow.up.right" : "arrow.down.left" }
}

enum LedgerCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case food, transport, shopping, housing, entertainment, health, education, salary, investment, travel, other

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

    var signedAmountMinor: Int64 { kind == .income ? amountMinor : -amountMinor }
}

struct Budget: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var category: LedgerCategory
    var limitMinor: Int64
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
}

struct LedgerSnapshot: Codable, Hashable, Sendable {
    var schemaVersion = 1
    var transactions: [LedgerTransaction] = []
    var accounts: [LedgerAccount] = LedgerAccount.defaults
    var budgets: [Budget] = []
    var recurringEntries: [RecurringEntry] = []
    var currencyCode = "TWD"
    var updatedAt: Date = .now

    static var empty: LedgerSnapshot { LedgerSnapshot() }
}

extension Int64 {
    func currency(code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: Double(self) / 100)) ?? "\(self / 100)"
    }
}

