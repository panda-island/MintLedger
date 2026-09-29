import SwiftUI

struct TransactionsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var searchText = ""
    @State private var filter: TransactionKind?

    private var filtered: [LedgerTransaction] {
        store.transactions.filter { item in
            (filter == nil || item.kind == filter) &&
            (searchText.isEmpty || item.note.localizedCaseInsensitiveContains(searchText) || item.category.title.contains(searchText))
        }
    }

    var body: some View {
        Group {
            if filtered.isEmpty {
                EmptyStateView(symbol: "magnifyingglass", title: "找不到交易", message: searchText.isEmpty ? "新增一筆收入或支出" : "試試其他搜尋字詞")
            } else {
                List {
                    ForEach(groupedDates, id: \.date) { group in
                        Section(group.date.formatted(date: .complete, time: .omitted)) {
                            ForEach(group.items) { TransactionRow(transaction: $0).listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16)).listRowSeparator(.hidden) }
                            .onDelete { offsets in
                                store.deleteTransactions(ids: Set(offsets.map { group.items[$0].id }))
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("交易明細")
        .searchable(text: $searchText, prompt: "搜尋備註或分類")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("全部") { filter = nil }
                    ForEach(TransactionKind.allCases) { kind in Button(kind.title) { filter = kind } }
                } label: { Label("篩選", systemImage: filter == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") }
            }
        }
    }

    private var groupedDates: [(date: Date, items: [LedgerTransaction])] {
        Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.date) }
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }.sorted { $0.date > $1.date }
    }
}

