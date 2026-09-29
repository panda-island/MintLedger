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

    static var parameterSummary: some ParameterSummary {
        Summary("記錄\(.$kind) \(.$amount) 元於 \(.$category)") { \.$account; \.$note }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else { throw $amount.needsValueError("請輸入大於 0 的金額") }
        try SharedLedgerStorage.append(
            kind: kind.ledgerKind,
            amountMinor: Int64((amount * 100).rounded()),
            category: category.ledgerCategory,
            accountID: account?.id,
            note: note
        )
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "完成，已記錄 \(amount) 元\(kind == .expense ? "支出" : "收入")")
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

