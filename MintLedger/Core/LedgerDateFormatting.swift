import Foundation

extension Date {
    private static let ledgerTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "a h點mm分"
        return formatter
    }()

    private static let ledgerMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()

    var ledgerDateTimeText: String {
        "\(ledgerDateText) \(Self.ledgerTimeFormatter.string(from: self))"
    }

    var ledgerMonthText: String {
        Self.ledgerMonthFormatter.string(from: self)
    }

    /// 日期本身會在跨年度時保留年份，避免最近帳目被不必要的年份資訊淹沒。
    var ledgerDateText: String {
        let calendar = Calendar.current
        let hasDifferentYear = calendar.component(.year, from: self) != calendar.component(.year, from: .now)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = hasDifferentYear ? "yyyy年M月d日" : "M月d日"
        return formatter.string(from: self)
    }

    /// 「今天／昨天」旁使用的短日期；其他日期則直接使用完整日期標題。
    var ledgerShortDateText: String {
        let calendar = Calendar.current
        let hasDifferentYear = calendar.component(.year, from: self) != calendar.component(.year, from: .now)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = hasDifferentYear ? "yyyy年M月d日" : "M月d日"
        return formatter.string(from: self)
    }

    var ledgerDayTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "今天" }
        if calendar.isDateInYesterday(self) { return "昨天" }
        return "\(ledgerDateText) \(ledgerWeekdayText)"
    }

    var ledgerShowsShortDateAlongsideDayTitle: Bool {
        let calendar = Calendar.current
        return calendar.isDateInToday(self) || calendar.isDateInYesterday(self)
    }

    private var ledgerWeekdayText: String {
        let weekday = Calendar.current.component(.weekday, from: self)
        return ["週日", "週一", "週二", "週三", "週四", "週五", "週六"][weekday - 1]
    }
}
