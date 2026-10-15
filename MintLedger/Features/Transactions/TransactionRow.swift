import SwiftUI

struct TransactionRow: View {
    @Environment(LedgerStore.self) private var store
    let transaction: LedgerTransaction

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: transaction.category.symbol)
                .font(.headline)
                .foregroundStyle(Color.mintLedger)
                .frame(width: 42, height: 42)
                .background(Color.mintLedger.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.note.isEmpty ? transaction.category.title : transaction.note).font(.body.weight(.medium)).lineLimit(1)
                Text("\(transaction.category.title) · \(transaction.date.ledgerDateTimeText)")
                    .font(.caption).foregroundStyle(.secondary)
                if let conversion = transaction.conversion, conversion.originalCurrencyCode != store.snapshot.currencyCode {
                    Text("原幣 \(conversion.originalCurrencyCode) \(conversion.originalAmount)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            AmountText(amountMinor: transaction.amountMinor, currencyCode: store.snapshot.currencyCode, kind: transaction.kind)
                .font(.subheadline.weight(.semibold))
        }
        .padding(12)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
