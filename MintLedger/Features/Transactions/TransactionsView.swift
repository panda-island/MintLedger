import Charts
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

    private var displayedMonthGroup: TransactionMonthGroup? {
        monthGroups.first { $0.id == selectedMonth } ?? monthGroups.first
    }

    var body: some View {
        Group {
            if filtered.isEmpty {
                EmptyStateView(symbol: "magnifyingglass", title: "找不到交易", message: searchText.isEmpty ? "新增一筆收入或支出" : "試試其他搜尋字詞")
            } else if let group = displayedMonthGroup {
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
                        MonthSummaryHeader(
                            group: group,
                            currencyCode: store.snapshot.currencyCode,
                            canShowNewerMonth: canMoveMonth(by: -1),
                            canShowOlderMonth: canMoveMonth(by: 1),
                            showNewerMonth: { moveMonth(by: -1) },
                            showOlderMonth: { moveMonth(by: 1) }
                        )
                        .textCase(nil)
                        // 只讓月份標題處理水平滑動，交易列保留系統的左滑刪除手勢。
                        .gesture(
                            DragGesture(minimumDistance: 20)
                                .onEnded { value in
                                    guard abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) > 48 else { return }
                                    moveMonth(by: value.translation.width < 0 ? 1 : -1)
                                }
                        )
                    }
                }
                .listStyle(.plain)
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

    private func canMoveMonth(by offset: Int) -> Bool {
        guard let index = monthGroups.firstIndex(where: { $0.id == selectedMonth }) else { return false }
        return monthGroups.indices.contains(index + offset)
    }

    private func moveMonth(by offset: Int) {
        guard let index = monthGroups.firstIndex(where: { $0.id == selectedMonth }),
              monthGroups.indices.contains(index + offset) else { return }
        withAnimation(.snappy) {
            selectedMonth = monthGroups[index + offset].id
        }
    }
}

private struct MonthSummaryHeader: View {
    let group: TransactionMonthGroup
    let currencyCode: String
    let canShowNewerMonth: Bool
    let canShowOlderMonth: Bool
    let showNewerMonth: () -> Void
    let showOlderMonth: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Button(action: showNewerMonth) { Image(systemName: "chevron.left") }
                    .disabled(!canShowNewerMonth)
                    .accessibilityLabel("查看較新的月份")
                Spacer()
                Text(group.month.ledgerMonthText)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button(action: showOlderMonth) { Image(systemName: "chevron.right") }
                    .disabled(!canShowOlderMonth)
                    .accessibilityLabel("查看較舊的月份")
            }
            HStack(spacing: 12) {
                Text("收入 \(group.incomeMinor.currency(code: currencyCode))").foregroundStyle(.green)
                Text("支出 \(group.expenseMinor.currency(code: currencyCode))").foregroundStyle(.red)
                Spacer()
                Text("淨額 \((group.incomeMinor - group.expenseMinor).currency(code: currencyCode))")
            }
            .font(.caption)
            MonthSummaryChart(group: group)
                .frame(height: 115)
                .accessibilityLabel("\(group.month.ledgerMonthText) 收入、支出與淨額圖表")
            Text("在此月份標題左右滑動，可切換月份")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct MonthSummaryChart: View {
    let group: TransactionMonthGroup

    private var values: [(title: String, amount: Int64)] {
        [("收入", group.incomeMinor), ("支出", group.expenseMinor), ("淨額", group.incomeMinor - group.expenseMinor)]
    }

    var body: some View {
        Chart(values, id: \.title) { value in
            BarMark(x: .value("項目", value.title), y: .value("金額", value.amount))
                .foregroundStyle(color(for: value.title))
                .cornerRadius(4)
        }
        .chartLegend(.hidden)
        .chartYAxis { AxisMarks(position: .leading) }
    }

    private func color(for title: String) -> Color {
        switch title {
        case "收入": .green
        case "支出": .red
        default: .mint
        }
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
