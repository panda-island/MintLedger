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

    init() { amount = 100; category = .food; note = "快速記帳" }
    init(amount: Double, category: IntentCategory = .food, note: String = "快速記帳") {
        self.amount = amount
        self.category = category
        self.note = note
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else { throw $amount.needsValueError("請輸入大於 0 的金額") }
        try SharedLedgerStorage.append(
            kind: .expense,
            amountMinor: Int64((amount * 100).rounded()),
            category: category.ledgerCategory,
            accountID: nil,
            note: note
        )
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "已記錄 \(amount) 元支出")
    }
}
