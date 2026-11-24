import SwiftUI

/// 主界面：三个 Tab（排班 / 工资 / 设置），各带自己的 NavigationStack。
/// 今日 Tab 已删；工资页标题叫「预估工资」。
struct MainTabView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        TabView(selection: $store.selectedTab) {
            NavigationStack {
                CalendarView()
                    .navigationTitle("排班")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("排班", systemImage: "calendar")
            }
            .tag(0)

            NavigationStack {
                PayView()
                    .navigationTitle("预估工资")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("工资", systemImage: "yensign.circle")
            }
            .tag(1)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
            .tag(2)
        }
        // 没登录时点小组件进来的深链：登录后进主界面再跳（store.handleDeepLink 先记下来）。
        .task {
            if let tab = store.pendingDeepLinkTab {
                store.pendingDeepLinkTab = nil
                store.selectedTab = tab
            }
        }
    }
}
