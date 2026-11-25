import SwiftUI

@main
struct PaiBanApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // 调试图：模拟器启动参数 --widget-preview <kind> 时直接进小组件截图画廊（不走登录/启动流程）。
            // Release 包里没有画廊，这段不编进。
            if let kind = WidgetPreviewLaunch.kind {
                WidgetPreviewGallery(kind: kind)
            } else {
                ContentView()
                    .environmentObject(store)
                    // 1.2.8.001：外观跟设置走（跟随系统传 nil；改完立刻生效，不用重启）。
                    .preferredColorScheme(store.appearance.colorScheme)
                    // 1.2.7：小组件深链（paiban://schedule 进排班页、paiban://pay 进工资页）。
                    .onOpenURL { store.handleDeepLink($0) }
            }
            #else
            ContentView()
                .environmentObject(store)
                // 1.2.8.001：外观跟设置走（跟随系统传 nil；改完立刻生效，不用重启）。
                .preferredColorScheme(store.appearance.colorScheme)
                // 1.2.7：小组件深链（paiban://schedule 进排班页、paiban://pay 进工资页）。
                .onOpenURL { store.handleDeepLink($0) }
            #endif
        }
    }
}
