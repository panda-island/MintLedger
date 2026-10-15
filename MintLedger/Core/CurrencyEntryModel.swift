import Foundation
import Observation

@MainActor
@Observable
final class CurrencyEntryModel {
    var amountText = ""
    var currencyCode = "" {
        didSet {
            if !oldValue.isEmpty && oldValue != currencyCode {
                manualRate = false
                rateText = ""
                loadedKey = nil
                error = nil
            }
        }
    }
    var date: Date
    var rateText = ""
    var manualRate = false
    private(set) var isLoading = false
    var error: String?
    private(set) var rateDate = ""
    private(set) var rateSource = ""
    @ObservationIgnored private let original: LedgerTransaction?
    @ObservationIgnored private var preparedBase: String?
    @ObservationIgnored private var loadedKey: String?

    init(transaction: LedgerTransaction? = nil) {
        original = transaction
        date = transaction?.date ?? .now
    }

    func prepare(base: String) {
        guard preparedBase == nil else { return }
        preparedBase = base
        currencyCode = original?.conversion?.originalCurrencyCode ?? base
        amountText = original?.conversion?.originalAmount ?? original.map { CurrencyMath.string($0.amountMinor, code: base) } ?? ""
        manualRate = original?.conversion?.rateSource == "自訂匯率"
        rateText = original?.conversion?.rate ?? ""
    }

    func requestKey(base: String) -> String {
        "\(currencyCode)|\(base)|\(CurrencyMath.day(date))|\(manualRate)"
    }

    func loadRate(base: String) async {
        guard !currencyCode.isEmpty else { return }
        let key = requestKey(base: base)
        error = nil
        isLoading = false
        loadedKey = nil
        if currencyCode == base {
            rateText = "1"
            rateDate = CurrencyMath.day(date)
            rateSource = "相同幣別"
            loadedKey = key
            return
        }
        if manualRate {
            rateDate = CurrencyMath.day(date)
            rateSource = "自訂匯率"
            loadedKey = key
            return
        }
        if let saved = original?.conversion, saved.originalCurrencyCode == currencyCode,
           saved.baseCurrencyCode == base, saved.requestedDate == CurrencyMath.day(date) {
            rateText = saved.rate
            rateDate = saved.rateDate
            rateSource = saved.rateSource
            loadedKey = key
            return
        }
        isLoading = true
        defer { if requestKey(base: base) == key { isLoading = false } }
        do {
            let result = try await ExchangeRateService.shared.quote(from: currencyCode, to: base, day: CurrencyMath.day(date))
            guard !Task.isCancelled, requestKey(base: base) == key else { return }
            rateText = CurrencyMath.string(result.rate)
            rateDate = result.date
            rateSource = "Frankfurter 每日參考匯率"
            loadedKey = key
        } catch {
            guard !Task.isCancelled, requestKey(base: base) == key else { return }
            self.error = (error as? CurrencyError)?.localizedDescription ?? CurrencyError.unavailableRate.localizedDescription
        }
    }

    func booking(base: String) throws -> CurrencyBooking {
        guard preparedBase == base else { throw CurrencyError.currencyChanged }
        guard let amount = AmountExpression.evaluate(amountText),
              let parsed = CurrencyMath.decimal(String(amount)), parsed > 0 else { throw CurrencyError.invalidAmount }
        let originalAmount = CurrencyMath.major(try CurrencyMath.minor(parsed, code: currencyCode), code: currencyCode)
        let rate: Decimal
        if currencyCode == base { rate = 1 }
        else {
            guard !isLoading, manualRate || loadedKey == requestKey(base: base),
                  let value = CurrencyMath.decimal(rateText), value > 0 else { throw CurrencyError.unavailableRate }
            rate = value
        }
        if let original, original.date == date,
           currencyCode == (original.conversion?.originalCurrencyCode ?? base),
           originalAmount == CurrencyMath.decimal(original.conversion?.originalAmount ?? CurrencyMath.string(original.amountMinor, code: base)),
           rate == CurrencyMath.decimal(original.conversion?.rate ?? "1") {
            return CurrencyBooking(amountMinor: original.amountMinor, conversion: original.conversion ?? CurrencyRebaser.legacyConversion(original, code: base))
        }
        return try ExchangeRateService.booking(amount: originalAmount, from: currencyCode, to: base,
                                              day: CurrencyMath.day(date), rate: rate,
                                              rateDate: rateDate.isEmpty ? CurrencyMath.day(date) : rateDate,
                                              source: currencyCode == base ? "相同幣別" : manualRate ? "自訂匯率" : rateSource)
    }
}
