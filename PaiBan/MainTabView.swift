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

            // 工资 Tab：只有有工资权限的人才显示（1.2.7.001，第 23 条）。
            // 没权限的人只有排班 / 设置两个 Tab；年休假跟着工资走，也一并隐藏。
            if store.payAccess {
                NavigationStack {
                    PayView()
                        .navigationTitle("预估工资")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .tabItem {
                    Label("工资", systemImage: "yensign.circle")
                }
                .tag(1)
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
            .tag(2)
        }
        .tint(Color.accentColor)
        // 1.2.8.002：Tab 选中态走自适应强调色（浅色深 navy、深色亮蓝），
        // 别让系统默认去猜；未选中态在 PaiBanApp.init 里用 UITabBar 外观定。
        // 没登录时点小组件进来的深链：登录后进主界面再跳（store.handleDeepLink 先记下来）。
        .task {
            if let tab = store.pendingDeepLinkTab {
                store.pendingDeepLinkTab = nil
                store.selectedTab = tab
            }
        }
        // 工资权限没了（管理员关了）而当前正停在工资 Tab：切回排班。
        .onChange(of: store.payAccess) { newValue in
            if !newValue && store.selectedTab == 1 {
                store.selectedTab = 0
            }
        }
    }
}
