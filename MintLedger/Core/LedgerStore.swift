import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class LedgerStore {
    private(set) var snapshot: LedgerSnapshot = .empty
    private(set) var lastError: String?
    private(set) var savePulse = 0

    init() {
        reload()
    }

    var transactions: [LedgerTransaction] {
        snapshot.transactions.sorted { $0.date > $1.date }
    }

    var currentMonthTransactions: [LedgerTransaction] {
        let calendar = Calendar.current
        return transactions.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .month) }
    }

    var monthIncomeMinor: Int64 {
        currentMonthTransactions.filter { $0.kind == .income }.reduce(0) { $0 + $1.amountMinor }
    }

    var monthExpenseMinor: Int64 {
        currentMonthTransactions.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountMinor }
    }

    var balanceMinor: Int64 {
        snapshot.accounts.reduce(0) { $0 + $1.openingBalanceMinor }
            + snapshot.transactions.reduce(0) { $0 + $1.signedAmountMinor }
    }

    func reload() {
        do {
            snapshot = try SharedLedgerStorage.load()
            lastError = nil
        } catch {
            lastError = "無法讀取資料：\(error.localizedDescription)"
        }
    }

    func addTransaction(
        kind: TransactionKind,
        amountMinor: Int64,
        category: LedgerCategory,
        accountID: UUID,
        note: String,
        date: Date
    ) {
        snapshot.transactions.append(LedgerTransaction(
            kind: kind,
            amountMinor: amountMinor,
            category: category,
            accountID: accountID,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date
        ))
        persist()
    }

    func deleteTransactions(ids: Set<UUID>) {
        snapshot.transactions.removeAll { ids.contains($0.id) }
        persist()
    }

    func upsertBudget(category: LedgerCategory, limitMinor: Int64) {
        if let index = snapshot.budgets.firstIndex(where: { $0.category == category }) {
            snapshot.budgets[index].limitMinor = limitMinor
        } else {
            snapshot.budgets.append(Budget(category: category, limitMinor: limitMinor))
        }
        persist()
    }

    func addAccount(name: String, symbol: String = "wallet.pass") {
        snapshot.accounts.append(LedgerAccount(name: name, symbol: symbol))
        persist()
    }

    func replace(with imported: LedgerSnapshot) {
        snapshot = imported
        persist()
    }

    func createRecurring(_ entry: RecurringEntry) {
        snapshot.recurringEntries.append(entry)
        persist()
    }

    func runDueRecurringEntries(now: Date = .now) {
        var changed = false
        for index in snapshot.recurringEntries.indices where snapshot.recurringEntries[index].isEnabled {
            while snapshot.recurringEntries[index].nextDate <= now {
                let item = snapshot.recurringEntries[index]
                snapshot.transactions.append(LedgerTransaction(
                    kind: item.kind,
                    amountMinor: item.amountMinor,
                    category: item.category,
                    accountID: item.accountID,
                    note: item.title,
                    date: item.nextDate
                ))
                snapshot.recurringEntries[index].nextDate = nextDate(after: item.nextDate, cadence: item.cadence)
                changed = true
            }
        }
        if changed { persist() }
    }

    func encodedBackup() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    func importBackup(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        replace(with: try decoder.decode(LedgerSnapshot.self, from: data))
    }

    func csvData() -> Data {
        var lines = ["date,type,amount,category,account,note"]
        let formatter = ISO8601DateFormatter()
        let accounts = Dictionary(uniqueKeysWithValues: snapshot.accounts.map { ($0.id, $0.name) })
        for item in transactions {
            let fields = [
                formatter.string(from: item.date), item.kind.rawValue,
                String(format: "%.2f", Double(item.amountMinor) / 100), item.category.title,
                accounts[item.accountID] ?? "", item.note
            ].map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n").data(using: .utf8) ?? Data()
    }

    private func persist() {
        snapshot.updatedAt = .now
        do {
            try SharedLedgerStorage.save(snapshot)
            try LocalBackupService.rotate(snapshot: snapshot)
            lastError = nil
            savePulse += 1
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            lastError = "儲存失敗：\(error.localizedDescription)"
        }
    }

    private func nextDate(after date: Date, cadence: RecurringEntry.Cadence) -> Date {
        let component: Calendar.Component = cadence == .weekly ? .weekOfYear : (cadence == .monthly ? .month : .year)
        return Calendar.current.date(byAdding: component, value: 1, to: date) ?? date.addingTimeInterval(86_400)
    }
}

