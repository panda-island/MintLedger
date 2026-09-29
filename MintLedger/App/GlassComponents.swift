import SwiftUI

extension Color {
    static let mintLedger = Color(red: 0.16, green: 0.85, blue: 0.60)
    static let midnight = Color(red: 0.02, green: 0.08, blue: 0.17)
}

struct GlassCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        if #available(iOS 26.0, *) {
            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

struct GlassAddButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Image(systemName: "plus")
                    .font(.title2.bold())
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.glassProminent)
            .tint(.mintLedger)
        } else {
            Button(action: action) {
                Image(systemName: "plus")
                    .font(.title2.bold())
                    .foregroundStyle(.midnight)
                    .frame(width: 56, height: 56)
                    .background(Color.mintLedger, in: Circle())
                    .shadow(radius: 10, y: 5)
            }
            .buttonStyle(.plain)
        }
    }
}

struct AmountText: View {
    let amountMinor: Int64
    let currencyCode: String
    var kind: TransactionKind?

    var body: some View {
        Text(amountMinor.currency(code: currencyCode))
            .monospacedDigit()
            .foregroundStyle(kind == .expense ? .red : (kind == .income ? .green : .primary))
            .contentTransition(.numericText())
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
    }
}

