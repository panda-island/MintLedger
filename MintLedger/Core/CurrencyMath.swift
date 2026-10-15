import Foundation

enum CurrencyMath {
    static let locale = Locale(identifier: "en_US_POSIX")
    static let codes: [String] = {
        let popular = ["TWD", "USD", "JPY", "EUR", "HKD", "CNY", "KRW", "GBP", "SGD", "THB", "VND", "AUD", "CAD"]
        return popular + Locale.Currency.isoCurrencies.map(\.identifier).filter { !popular.contains($0) }.sorted()
    }()

    static func title(_ code: String) -> String {
        "\(code) · \(Locale(identifier: "zh_TW").localizedString(forCurrencyCode: code) ?? code)"
    }

    static func digits(_ code: String) -> Int {
        if ["BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF"].contains(code) { return 0 }
        if ["BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"].contains(code) { return 3 }
        if ["CLF", "UYW"].contains(code) { return 4 }
        return 2
    }

    static func scale(_ code: String) -> Int64 {
        (0..<digits(code)).reduce(Int64(1)) { result, _ in result * 10 }
    }

    static func major(_ minor: Int64, code: String) -> Decimal {
        Decimal(minor) / Decimal(scale(code))
    }

    static func minor(_ major: Decimal, code: String) throws -> Int64 {
        guard !major.isNaN else { throw CurrencyError.invalidAmount }
        var value = major * Decimal(scale(code))
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        guard !rounded.isNaN, rounded <= Decimal(Int64.max), rounded >= Decimal(Int64.min) else { throw CurrencyError.invalidAmount }
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    static func decimal(_ text: String) -> Decimal? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.range(of: #"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: normalized, locale: locale), !value.isNaN else { return nil }
        return value
    }

    static func string(_ amount: Decimal) -> String { NSDecimalNumber(decimal: amount).stringValue }
    static func string(_ minor: Int64, code: String) -> String { string(major(minor, code: code)) }
    static func double(_ minor: Int64, code: String) -> Double { NSDecimalNumber(decimal: major(minor, code: code)).doubleValue }

    static func display(_ amount: Decimal, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = digits(code)
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(code) \(string(amount))"
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

enum CurrencyError: LocalizedError {
    case invalidAmount, unavailableRate, invalidCurrency, futureDate, currencyChanged, dataChanged
    var errorDescription: String? {
        switch self {
        case .invalidAmount: "金額或匯率無效，請檢查數值與小數位。"
        case .unavailableRate: "無法取得此日期的參考匯率，請重試或輸入自訂匯率。"
        case .invalidCurrency: "請選擇有效的 ISO 幣別代碼，例如 TWD、USD、JPY。"
        case .futureDate: "尚未公布未來日期匯率，請選擇已發生的日期或輸入自訂匯率。"
        case .currencyChanged: "主要幣別已變更，請重新開啟此帳目後再儲存。"
        case .dataChanged: "換算期間帳本有更新，未套用任何變更，請再試一次。"
        }
    }
}

struct CurrencyReference: Codable, Hashable, Sendable {
    var currencyCode: String
    var amountMinor: Int64
    var date: String
}

struct CurrencyConversion: Codable, Hashable, Sendable {
    var originalCurrencyCode: String
    var originalAmount: String
    var baseCurrencyCode: String
    var rate: String
    var rateDate: String
    var rateSource: String
    var requestedDate: String
    // Immutable first-booked values avoid rounding drift when changing base repeatedly.
    var booked: CurrencyReference
    var bookingRate: String? = nil
    var bookingRateDate: String? = nil
    var bookingRateSource: String? = nil

    var originalDisplay: String {
        CurrencyMath.display(CurrencyMath.decimal(originalAmount) ?? 0, code: originalCurrencyCode)
    }
}

struct CurrencyBooking: Sendable {
    let amountMinor: Int64
    let conversion: CurrencyConversion
}
