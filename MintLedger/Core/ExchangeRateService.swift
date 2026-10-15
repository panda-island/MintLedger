import Foundation

struct ExchangeQuote: Codable, Sendable {
    let date: String
    let base: String
    let quote: String
    let rate: Decimal
}

actor ExchangeRateService {
    static let shared = ExchangeRateService()
    private let session: URLSession
    private let defaults: UserDefaults
    private var cache: [String: ExchangeQuote]

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
        cache = defaults.data(forKey: "mintledger.exchange-quotes.v2")
            .flatMap { try? JSONDecoder().decode([String: ExchangeQuote].self, from: $0) } ?? [:]
    }

    func quote(from: String, to: String, day: String) async throws -> ExchangeQuote {
        guard CurrencyMath.codes.contains(from), CurrencyMath.codes.contains(to) else { throw CurrencyError.invalidCurrency }
        guard day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { throw CurrencyError.unavailableRate }
        if from == to { return ExchangeQuote(date: day, base: from, quote: to, rate: 1) }
        guard day <= CurrencyMath.day(.now) else { throw CurrencyError.futureDate }
        let key = "\(from)/\(to)/\(day)"
        if let cached = cache[key] { return cached }
        var components = URLComponents(string: "https://api.frankfurter.dev/v2/rate/\(from)/\(to)")!
        components.queryItems = [URLQueryItem(name: "date", value: day)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CurrencyError.unavailableRate }
        let result = try Self.decodeQuote(data, from: from, to: to, requestedDay: day)
        cache[key] = result
        if cache.count > 2_000 { cache = [key: result] }
        if let encoded = try? JSONEncoder().encode(cache) { defaults.set(encoded, forKey: "mintledger.exchange-quotes.v2") }
        return result
    }

    static func decodeQuote(_ data: Data, from: String, to: String, requestedDay: String) throws -> ExchangeQuote {
        let result = try JSONDecoder().decode(ExchangeQuote.self, from: data)
        guard result.base.uppercased() == from, result.quote.uppercased() == to,
              !result.rate.isNaN, result.rate > 0, result.date <= requestedDay,
              result.date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { throw CurrencyError.unavailableRate }
        return result
    }

    func booking(amount: Decimal, from: String, to: String, date: Date, manualRate: Decimal? = nil) async throws -> CurrencyBooking {
        let day = CurrencyMath.day(date)
        let rate: Decimal
        let rateDate: String
        let source: String
        if let manualRate, from != to {
            rate = manualRate
            rateDate = day
            source = "自訂匯率"
        } else {
            let result = try await quote(from: from, to: to, day: day)
            rate = result.rate
            rateDate = result.date
            source = from == to ? "相同幣別" : "Frankfurter 每日參考匯率"
        }
        return try Self.booking(amount: amount, from: from, to: to, day: day, rate: rate, rateDate: rateDate, source: source)
    }

    static func booking(amount: Decimal, from: String, to: String, day: String, rate: Decimal, rateDate: String, source: String) throws -> CurrencyBooking {
        guard CurrencyMath.codes.contains(from), CurrencyMath.codes.contains(to) else { throw CurrencyError.invalidCurrency }
        guard amount > 0, !rate.isNaN, rate > 0 else { throw CurrencyError.invalidAmount }
        let originalMinor = try CurrencyMath.minor(amount, code: from)
        guard originalMinor > 0, from != to || rate == 1 else { throw CurrencyError.invalidAmount }
        let normalizedAmount = CurrencyMath.major(originalMinor, code: from)
        let converted = try CurrencyMath.minor(normalizedAmount * rate, code: to)
        guard converted >= 0 else { throw CurrencyError.invalidAmount }
        let conversion = CurrencyConversion(
            originalCurrencyCode: from, originalAmount: CurrencyMath.string(normalizedAmount), baseCurrencyCode: to,
            rate: CurrencyMath.string(rate), rateDate: rateDate, rateSource: source, requestedDate: day,
            booked: CurrencyReference(currencyCode: to, amountMinor: converted, date: day),
            bookingRate: CurrencyMath.string(rate), bookingRateDate: rateDate, bookingRateSource: source
        )
        return CurrencyBooking(amountMinor: converted, conversion: conversion)
    }
}

enum CurrencyRebaser {
    struct Request: Hashable, Sendable {
        let from: String
        let to: String
        let day: String
    }

    static func legacyConversion(_ transaction: LedgerTransaction, code: String) -> CurrencyConversion {
        CurrencyConversion(originalCurrencyCode: code, originalAmount: CurrencyMath.string(transaction.amountMinor, code: code),
                           baseCurrencyCode: code, rate: "1", rateDate: CurrencyMath.day(transaction.date), rateSource: "相同幣別",
                           requestedDate: CurrencyMath.day(transaction.date),
                           booked: CurrencyReference(currencyCode: code, amountMinor: transaction.amountMinor, date: CurrencyMath.day(transaction.date)),
                           bookingRate: "1", bookingRateDate: CurrencyMath.day(transaction.date), bookingRateSource: "相同幣別")
    }

    static func rebase(
        _ snapshot: LedgerSnapshot, to code: String, day: String = CurrencyMath.day(.now),
        lookup: @escaping @Sendable (String, String, String) async throws -> ExchangeQuote = { from, to, day in
            try await ExchangeRateService.shared.quote(from: from, to: to, day: day)
        }
    ) async throws -> LedgerSnapshot {
        guard code != snapshot.currencyCode else { return snapshot }
        guard CurrencyMath.codes.contains(code) else { throw CurrencyError.invalidCurrency }
        let conversions = snapshot.transactions.map { $0.conversion ?? legacyConversion($0, code: snapshot.currencyCode) }
        let openings = snapshot.accounts.map { $0.openingReference ?? CurrencyReference(currencyCode: snapshot.currencyCode, amountMinor: $0.openingBalanceMinor, date: day) }
        let budgets = snapshot.budgets.map { $0.currencyReference ?? CurrencyReference(currencyCode: snapshot.currencyCode, amountMinor: $0.limitMinor, date: day) }
        let recurring = snapshot.recurringEntries.map { $0.currencyReference ?? CurrencyReference(currencyCode: snapshot.currencyCode, amountMinor: $0.amountMinor, date: day) }
        var requests = Set<Request>()
        let bookingReferences = conversions.filter { $0.originalCurrencyCode != code }.map(\.booked)
        for reference in bookingReferences + openings + budgets + recurring where reference.amountMinor != 0 && reference.currencyCode != code {
            requests.insert(Request(from: reference.currencyCode, to: code, day: reference.date))
        }
        var quotes: [Request: ExchangeQuote] = [:]
        let list = Array(requests)
        // Bound concurrent requests and reuse a single daily quote across all matching entries.
        for offset in stride(from: 0, to: list.count, by: 6) {
            let batch = Array(list[offset..<min(offset + 6, list.count)])
            let results = try await withThrowingTaskGroup(of: (Request, ExchangeQuote).self) { group in
                for request in batch {
                    group.addTask { (request, try await lookup(request.from, request.to, request.day)) }
                }
                var results: [(Request, ExchangeQuote)] = []
                for try await result in group { results.append(result) }
                return results
            }
            for (request, quote) in results {
                guard quote.base.uppercased() == request.from, quote.quote.uppercased() == code,
                      quote.rate > 0, !quote.rate.isNaN, quote.date <= request.day else { throw CurrencyError.unavailableRate }
                quotes[request] = quote
            }
        }
        func converted(_ reference: CurrencyReference) throws -> Int64 {
            if reference.amountMinor == 0 { return 0 }
            if reference.currencyCode == code { return reference.amountMinor }
            guard let quote = quotes[Request(from: reference.currencyCode, to: code, day: reference.date)] else { throw CurrencyError.unavailableRate }
            return try CurrencyMath.minor(CurrencyMath.major(reference.amountMinor, code: reference.currencyCode) * quote.rate, code: code)
        }
        var output = snapshot
        output.currencyCode = code
        output.schemaVersion = 2
        for index in output.transactions.indices {
            var conversion = conversions[index]
            guard let originalAmount = CurrencyMath.decimal(conversion.originalAmount), originalAmount >= 0,
                  conversion.booked.amountMinor >= 0 else { throw CurrencyError.invalidAmount }
            let isOriginalCurrency = conversion.originalCurrencyCode == code
            let amount: Int64
            if isOriginalCurrency { amount = try CurrencyMath.minor(originalAmount, code: code) }
            else { amount = try converted(conversion.booked) }
            let quote = quotes[Request(from: conversion.booked.currencyCode, to: code, day: conversion.booked.date)]
            conversion.baseCurrencyCode = code
            conversion.rateDate = quote?.date ?? conversion.bookingRateDate ?? conversion.booked.date
            conversion.rateSource = quote == nil ? (conversion.bookingRateSource ?? "原入帳金額") : "Frankfurter（由原入帳金額換算）"
            if isOriginalCurrency {
                conversion.rate = "1"
                conversion.rateDate = conversion.requestedDate
                conversion.rateSource = "相同幣別"
            } else if conversion.booked.currencyCode == code {
                conversion.rate = conversion.bookingRate ?? "1"
            } else if let original = CurrencyMath.decimal(conversion.originalAmount), original > 0 {
                conversion.rate = CurrencyMath.string(CurrencyMath.major(amount, code: code) / original)
            } else { conversion.rate = "1" }
            output.transactions[index].amountMinor = amount
            output.transactions[index].conversion = conversion
        }
        for index in output.accounts.indices {
            output.accounts[index].openingBalanceMinor = try converted(openings[index])
            output.accounts[index].openingReference = openings[index]
        }
        for index in output.budgets.indices {
            output.budgets[index].limitMinor = try converted(budgets[index])
            output.budgets[index].currencyReference = budgets[index]
        }
        for index in output.recurringEntries.indices {
            output.recurringEntries[index].amountMinor = try converted(recurring[index])
            output.recurringEntries[index].currencyReference = recurring[index]
        }
        return output
    }
}
