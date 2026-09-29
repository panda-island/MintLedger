import SwiftUI

enum AppTab: Hashable {
    case dashboard, transactions, budgets, reports, settings
}

struct RootView: View {
    @Environment(LedgerStore.self) private var store
    @State private var selectedTab: AppTab = .dashboard
    @State private var presentedSheet: SheetDestination?

    enum SheetDestination: Identifiable {
        case addTransaction
        var id: String { "add-transaction" }
    }

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                modernTabs
            } else {
                legacyTabs
            }
        }
        .tint(Color.mintLedger)
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .addTransaction:
                NavigationStack { AddTransactionView() }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            GlassAddButton { presentedSheet = .addTransaction }
                .padding(.trailing, 20)
                .padding(.bottom, 82)
                .accessibilityLabel("新增交易")
        }
        .alert("資料錯誤", isPresented: Binding(
            get: { store.lastError != nil },
            set: { _ in }
        )) { Button("好") {} } message: { Text(store.lastError ?? "") }
        .sensoryFeedback(.success, trigger: store.savePulse)
    }

    @available(iOS 18.0, *)
    private var modernTabs: some View {
        TabView(selection: $selectedTab) {
            Tab("總覽", systemImage: "rectangle.3.group.fill", value: .dashboard) { NavigationStack { DashboardView() } }
            Tab("明細", systemImage: "list.bullet.rectangle", value: .transactions) { NavigationStack { TransactionsView() } }
            Tab("預算", systemImage: "gauge.with.dots.needle.50percent", value: .budgets) { NavigationStack { BudgetsView() } }
            Tab("分析", systemImage: "chart.bar.xaxis", value: .reports) { NavigationStack { ReportsView() } }
            Tab("設定", systemImage: "gearshape.fill", value: .settings) { NavigationStack { SettingsView() } }
        }
    }

    private var legacyTabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { DashboardView() }.tabItem { Label("總覽", systemImage: "rectangle.3.group.fill") }.tag(AppTab.dashboard)
            NavigationStack { TransactionsView() }.tabItem { Label("明細", systemImage: "list.bullet.rectangle") }.tag(AppTab.transactions)
            NavigationStack { BudgetsView() }.tabItem { Label("預算", systemImage: "gauge.with.dots.needle.50percent") }.tag(AppTab.budgets)
            NavigationStack { ReportsView() }.tabItem { Label("分析", systemImage: "chart.bar.xaxis") }.tag(AppTab.reports)
            NavigationStack { SettingsView() }.tabItem { Label("設定", systemImage: "gearshape.fill") }.tag(AppTab.settings)
        }
    }
}

