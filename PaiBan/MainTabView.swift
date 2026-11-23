import SwiftUI

/// 主界面：三个 Tab（排班 / 工资 / 设置），各带自己的 NavigationStack。
/// 今日 Tab 已删；工资页标题叫「预估工资」。
struct MainTabView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        TabView {
            NavigationStack {
                CalendarView()
                    .navigationTitle("排班")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("排班", systemImage: "calendar")
            }

            NavigationStack {
                PayView()
                    .navigationTitle("预估工资")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("工资", systemImage: "yensign.circle")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
        }
    }
}
