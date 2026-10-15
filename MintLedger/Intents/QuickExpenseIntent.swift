import AppIntents
import Foundation
import WidgetKit

enum IntentCategory: String, AppEnum {
    case food, transport, shopping, housing, entertainment, health, education, salary, allowance, investment, travel, other

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "分類"
    static let caseDisplayRepresentations: [IntentCategory: DisplayRepresentation] = [
        .food: "餐飲", .transport: "交通", .shopping: "購物", .housing: "居家",
        .entertainment: "娛樂", .health: "醫療", .education: "學習", .salary: "薪資", .allowance: "零用錢",
        .investment: "投資", .travel: "旅遊", .other: "其他"
    ]

    var ledgerCategory: LedgerCategory { LedgerCategory(rawValue: rawValue) ?? .other }
}

struct QuickExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "快速記支出"
    static let description = IntentDescription("不用開啟 App，從捷徑或小工具直接記錄支出。")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "金額") var amount: Double
    @Parameter(title: "分類", default: .food) var category: IntentCategory
    @Parameter(title: "備註", default: "快速記帳") var note: String
    @Parameter(title: "原始幣別（留空使用主要幣別）") var currencyCode: String?
    @Parameter(title: "自訂匯率（選填）") var exchangeRate: Double?

    init() { amount = 100; category = .food; note = "快速記帳" }
    init(amount: Double, category: IntentCategory = .food, note: String = "快速記帳") {
        self.amount = amount
        self.category = category
        self.note = note
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount.isFinite, amount > 0, let decimalAmount = CurrencyMath.decimal(String(amount)) else { throw $amount.needsValueError("請輸入有效且大於 0 的金額") }
        let base = try SharedLedgerStorage.load().currencyCode
        let code = currencyCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let source = (code?.isEmpty == false ? code : nil) ?? base
        let date = Date.now
        let manual = exchangeRate.flatMap { CurrencyMath.decimal(String($0)) }
        if let exchangeRate, (!exchangeRate.isFinite || exchangeRate <= 0) { throw CurrencyError.invalidAmount }
        let booking = try await ExchangeRateService.shared.booking(amount: decimalAmount, from: source, to: base, date: date, manualRate: manual)
        try SharedLedgerStorage.append(
            kind: .expense,
            amountMinor: booking.amountMinor,
            category: category.ledgerCategory,
            accountID: nil,
            note: note,
            date: date,
            conversion: booking.conversion
        )
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "已記錄 \(source) \(amount) 支出，換算為 \(base) 入帳")
    }
}
