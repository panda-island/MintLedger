import SwiftUI

private struct TransactionMonthGroup: Identifiable {
    let month: Date
    let items: [LedgerTransaction]
    var id: Date { month }
    var incomeMinor: Int64 { items.filter { $0.kind == .income }.reduce(0) { $0 + $1.amountMinor } }
    var expenseMinor: Int64 { items.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountMinor } }

    var dayGroups: [TransactionDayGroup] {
        let calendar = Calendar.current
        return Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
            .map { TransactionDayGroup(day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }
}

private struct TransactionDayGroup: Identifiable {
    let day: Date
    let items: [LedgerTransaction]
    var id: Date { day }
    var incomeMinor: Int64 { items.filter { $0.kind == .income }.reduce(0) { $0 + $1.amountMinor } }
    var expenseMinor: Int64 { items.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountMinor } }
}

struct TransactionsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var searchText = ""
    @State private var filter: TransactionKind?
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var editingTransaction: LedgerTransaction?
    @State private var confirmsDeletion = false
    @State private var selectedMonth = Date.now

    private var filtered: [LedgerTransaction] {
        store.transactions.filter { item in
            (filter == nil || item.kind == filter) &&
            (searchText.isEmpty || item.note.localizedCaseInsensitiveContains(searchText) || item.category.title.contains(searchText))
        }
    }

    private var monthGroups: [TransactionMonthGroup] {
        let calendar = Calendar.current
        return Dictionary(grouping: filtered) { item in
            calendar.date(from: calendar.dateComponents([.year, .month], from: item.date)) ?? calendar.startOfDay(for: item.date)
        }
        .map { TransactionMonthGroup(month: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
        .sorted { $0.month > $1.month }
    }

    var body: some View {
        Group {
            if filtered.isEmpty {
                EmptyStateView(symbol: "magnifyingglass", title: "找不到交易", message: searchText.isEmpty ? "新增一筆收入或支出" : "試試其他搜尋字詞")
            } else {
                TabView(selection: $selectedMonth) {
                    ForEach(monthGroups) { group in
                        List {
                            Section {
                                ForEach(group.dayGroups) { dayGroup in
                                    Section {
                                        ForEach(dayGroup.items) { transaction in
                                            transactionButton(transaction)
                                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                                .listRowSeparator(.hidden)
                                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                                    if !isSelecting {
                                                        Button(role: .destructive) { store.deleteTransactions(ids: Set([transaction.id])) } label: {
                                                            Label("刪除", systemImage: "trash")
                                                        }
                                                    }
                                                }
                                        }
                                    } header: {
                                        DaySummaryHeader(group: dayGroup, currencyCode: store.snapshot.currencyCode)
                                            .textCase(nil)
                                    }
                                }
                            } header: {
                                MonthSummaryHeader(group: group, currencyCode: store.snapshot.currencyCode)
                                    .textCase(nil)
                            }
                        }
                        .listStyle(.plain)
                        .tag(group.id)
                        .accessibilityHint("左右滑動可查看其他月份")
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .onAppear { selectNewestAvailableMonthIfNeeded() }
                .onChange(of: monthGroups.map(\.id)) { _, months in
                    guard !months.contains(selectedMonth) else { return }
                    selectedMonth = months.first ?? .now
                }
            }
        }
        .navigationTitle(isSelecting ? "已選 \(selection.count) 筆" : "交易明細")
        .searchable(text: $searchText, prompt: "搜尋備註或分類")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(isSelecting ? "完成" : "選取") { toggleSelectionMode() }
                    .disabled(filtered.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("全部") { filter = nil }
                    ForEach(TransactionKind.allCases) { kind in Button(kind.title) { filter = kind } }
                } label: {
                    Label("篩選", systemImage: filter == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting { selectionBar }
        }
        .sheet(item: $editingTransaction) { transaction in
            NavigationStack { TransactionEditorView(transaction: transaction) }
        }
        .confirmationDialog("刪除選取的 \(selection.count) 筆明細？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("刪除", role: .destructive) {
                store.deleteTransactions(ids: selection)
                toggleSelectionMode()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func transactionButton(_ transaction: LedgerTransaction) -> some View {
        Button {
            if isSelecting {
                if selection.contains(transaction.id) { selection.remove(transaction.id) }
                else { selection.insert(transaction.id) }
            } else {
                editingTransaction = transaction
            }
        } label: {
            HStack(spacing: 10) {
                if isSelecting {
                    Image(systemName: selection.contains(transaction.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selection.contains(transaction.id) ? Color.mintLedger : .secondary)
                }
                TransactionRow(transaction: transaction)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var selectionBar: some View {
        HStack(spacing: 18) {
            Button(selection.count == filtered.count ? "取消全選" : "全選") {
                selection = selection.count == filtered.count ? [] : Set(filtered.map(\.id))
            }
            Spacer()
            Menu {
                ForEach(LedgerCategory.allCases) { category in
                    Button { changeSelectedCategory(to: category) } label: {
                        Label(category.title, systemImage: category.symbol)
                    }
                }
            } label: {
                Label("更改類別", systemImage: "tag")
            }
            .disabled(selection.isEmpty)
            Button(role: .destructive) { confirmsDeletion = true } label: {
                Label("刪除", systemImage: "trash")
            }
            .disabled(selection.isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private func toggleSelectionMode() {
        isSelecting.toggle()
        if !isSelecting { selection.removeAll() }
    }

    private func changeSelectedCategory(to category: LedgerCategory) {
        store.changeCategory(for: selection, to: category)
        toggleSelectionMode()
    }

    private func selectNewestAvailableMonthIfNeeded() {
        guard !monthGroups.contains(where: { $0.id == selectedMonth }) else { return }
        selectedMonth = monthGroups.first?.id ?? .now
    }
}

private struct MonthSummaryHeader: View {
    let group: TransactionMonthGroup
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(group.month.ledgerMonthText)
                .font(.headline)
                .foregroundStyle(.primary)
            HStack(spacing: 12) {
                Text("收入 \(group.incomeMinor.currency(code: currencyCode))").foregroundStyle(.green)
                Text("支出 \(group.expenseMinor.currency(code: currencyCode))").foregroundStyle(.red)
                Spacer()
                Text("淨額 \((group.incomeMinor - group.expenseMinor).currency(code: currencyCode))")
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

private struct DaySummaryHeader: View {
    let group: TransactionDayGroup
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(group.day.ledgerDayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if group.day.ledgerShowsShortDateAlongsideDayTitle {
                    Text(group.day.ledgerShortDateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Text("收入 \(group.incomeMinor.currency(code: currencyCode))").foregroundStyle(.green)
                Text("支出 \(group.expenseMinor.currency(code: currencyCode))").foregroundStyle(.red)
                Text("淨額 \((group.incomeMinor - group.expenseMinor).currency(code: currencyCode))")
                    .foregroundStyle(.secondary)
            }
            .font(.caption2)
        }
        .padding(.top, 9)
        .padding(.bottom, 2)
    }
}
