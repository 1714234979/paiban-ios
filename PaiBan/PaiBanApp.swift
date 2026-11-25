import SwiftUI
import UIKit // Tab 栏未选中态用动态 UIColor（1.2.8.002）

@main
struct PaiBanApp: App {
    @StateObject private var store = AppStore()

    init() {
        // 1.2.8.002：Tab 栏深色下未选中态也要认得出来。选中态走 AccentColor 资产
        //（深色已提亮成亮蓝）；未选中默认灰在黑底上太暗，深色改 0.65 白，浅色沿用系统灰。
        // 动态 UIColor 跟着 trait 走，设置页切外观（跟随系统/浅色/深色）时跟着变。
        UITabBar.appearance().unselectedItemTintColor = UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 0.65, alpha: 1)
                : UIColor.systemGray
        }
    }

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
