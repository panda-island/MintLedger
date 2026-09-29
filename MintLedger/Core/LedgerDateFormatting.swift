import Foundation

extension Date {
    private static let ledgerDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy年M月d日 a h點mm分"
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
        Self.ledgerDateTimeFormatter.string(from: self)
    }

    var ledgerMonthText: String {
        Self.ledgerMonthFormatter.string(from: self)
    }
}
