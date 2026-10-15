import AppIntents
import Foundation
import WidgetKit

enum IntentTransactionKind: String, AppEnum {
    case expense, income
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "交易類型"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.expense: "支出", .income: "收入"]
    var ledgerKind: TransactionKind { self == .expense ? .expense : .income }
}

struct AccountEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "帳戶"
    static let defaultQuery = AccountQuery()
    let id: UUID
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", image: .init(systemName: "wallet.pass")) }
}

struct AccountQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [AccountEntity] {
        try SharedLedgerStorage.load().accounts.filter { identifiers.contains($0.id) }.map { AccountEntity(id: $0.id, name: $0.name) }
    }
    func suggestedEntities() async throws -> [AccountEntity] {
        try SharedLedgerStorage.load().accounts.map { AccountEntity(id: $0.id, name: $0.name) }
    }
    func defaultResult() async -> AccountEntity? {
        try? SharedLedgerStorage.load().accounts.first.map { AccountEntity(id: $0.id, name: $0.name) }
    }
}

struct RecordTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "記一筆帳"
    static let description = IntentDescription("在裝置鎖定時也能快速記錄收入或支出。")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "類型", default: .expense) var kind: IntentTransactionKind
    @Parameter(title: "金額") var amount: Double
    @Parameter(title: "分類", default: .food) var category: IntentCategory
    @Parameter(title: "帳戶") var account: AccountEntity?
    @Parameter(title: "備註", default: "") var note: String
    @Parameter(title: "原始幣別（留空使用主要幣別）") var currencyCode: String?
    @Parameter(title: "自訂匯率（選填）") var exchangeRate: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("記錄 \(\.$kind) \(\.$amount) 於 \(\.$category)") { \.$account; \.$note; \.$currencyCode; \.$exchangeRate }
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
            kind: kind.ledgerKind,
            amountMinor: booking.amountMinor,
            category: category.ledgerCategory,
            accountID: account?.id,
            note: note,
            date: date,
            conversion: booking.conversion
        )
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "完成，已記錄 \(source) \(amount) \(kind == .expense ? "支出" : "收入")，換算為 \(base) 入帳")
    }
}

struct MintLedgerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordTransactionIntent(),
            phrases: ["用 \(.applicationName) 記一筆", "在 \(.applicationName) 新增交易", "\(.applicationName) 快速記帳"],
            shortTitle: "記一筆帳",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: QuickExpenseIntent(),
            phrases: ["用 \(.applicationName) 記支出"],
            shortTitle: "快速支出",
            systemImageName: "minus.circle.fill"
        )
    }
}
