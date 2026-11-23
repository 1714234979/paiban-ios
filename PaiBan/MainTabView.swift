import SwiftUI

/// 主界面：四个 Tab（排班 / 工资 / 今日 / 设置），各带自己的 NavigationStack。
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
                    .navigationTitle("工资")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("工资", systemImage: "yensign.circle")
            }

            NavigationStack {
                TodayView()
                    .navigationTitle("今日")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("今日", systemImage: "sun.max")
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
