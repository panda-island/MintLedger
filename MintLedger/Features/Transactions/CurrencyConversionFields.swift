import SwiftUI

struct CurrencyConversionFields: View {
    @Bindable var draft: CurrencyEntryModel
    let baseCode: String

    var body: some View {
        Picker("原始幣別", selection: $draft.currencyCode) {
            ForEach(CurrencyMath.codes, id: \.self) { code in
                Text(CurrencyMath.title(code)).tag(code)
            }
        }
        if draft.currencyCode != baseCode {
            Toggle("自訂匯率", isOn: $draft.manualRate)
            if draft.manualRate {
                #if os(iOS)
                TextField("1 \(draft.currencyCode) 換多少 \(baseCode)", text: $draft.rateText)
                    .keyboardType(.decimalPad)
                #else
                TextField("1 \(draft.currencyCode) 換多少 \(baseCode)", text: $draft.rateText)
                #endif
            }
            if draft.isLoading {
                HStack { ProgressView(); Text("取得交易日匯率…") }
            } else if !draft.rateText.isEmpty {
                Text("1 \(draft.currencyCode) = \(draft.rateText) \(baseCode)")
                    .font(.footnote)
                if !draft.rateDate.isEmpty {
                    Text("\(draft.rateDate) · \(draft.manualRate ? "自訂匯率" : draft.rateSource)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let booking = try? draft.booking(base: baseCode) {
                LabeledContent("換算入帳", value: booking.amountMinor.currency(code: baseCode))
            }
            Text("每日參考匯率可能與銀行成交價不同；已入帳匯率會保存，不隨行情變動。")
                .font(.caption).foregroundStyle(.secondary)
        }
        if let error = draft.error {
            Text(error).font(.footnote).foregroundStyle(.orange)
            if !draft.manualRate {
                Button("重新取得匯率") { Task { await draft.loadRate(base: baseCode) } }
            }
        }
    }
}
