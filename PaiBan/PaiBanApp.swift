import SwiftUI
import QuartzCore // CADisplayLink（1.3.0.006 刷新率适配）

/// 刷新率适配（1.3.0.006，第 34 条）：显式让 App 跟着系统自适应刷新走，最高 120Hz。
/// 硬件事实：iPhone ProMotion 自适应刷新封顶就是 120Hz（老爷那台 iPhone 17 Pro Max
/// 也是），140Hz 在 iOS 硬件上做不到——不是代码问题，是屏幕就到 120Hz。
/// 根因：代码里没有任何帧率设置（没 CADisplayLink、没 preferredFrameRateRange、
/// 没 Timer），SwiftUI 默认跟 ProMotion 走，但没有显式声明帧率范围，系统在部分
/// 场景下只给 60Hz。改法：App 启动时建一个 CADisplayLink，preferredFrameRateRange
/// 设成 10–120Hz（preferred 120），显式告诉系统这 App 要用满自适应刷新；静止时
/// 系统自己会降频省电（minimum 10Hz），不用管。这个 link 空转、只声明帧率范围、
/// 不干活（tick 里什么都不做），开销就是每帧一次空调用；帧率范围是声明，系统按
/// 内容自适应升降，不会一直锁 120Hz 耗电。
private final class RefreshRateBoost: NSObject {
    static let shared = RefreshRateBoost()
    private var link: CADisplayLink?
    private override init() { super.init() }

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 120, preferred: 120)
        }
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick() {
        // 空转：只声明帧率范围，不干活。
    }
}

@main
struct PaiBanApp: App {
    @State private var store = AppStore()

    init() {
        // 1.3.0.006：刷新率适配（第 34 条）——显式声明 10–120Hz 自适应刷新，最高 120Hz。
        RefreshRateBoost.shared.start()
        // 底栏重做（老爷 2026-11-28 14:36 亲口令：改回原生 TabView，改 appearance 的全删掉）：
        // 这里原来用 UITabBar.appearance() 全局改未选中态颜色（1.2.8.002，深色 0.65 白 /
        // 浅色系统灰），已删掉——未选中态改回系统默认，选中态仍走 AccentColor 资产。
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
                    .environment(store)
                    // 1.2.8.001：外观跟设置走（跟随系统传 nil；改完立刻生效，不用重启）。
                    .preferredColorScheme(store.appearance.colorScheme)
                    // 1.2.7：小组件深链（paiban://schedule 进排班页、paiban://pay 进工资页）。
                    .onOpenURL { store.handleDeepLink($0) }
            }
            #else
            ContentView()
                .environment(store)
                // 1.2.8.001：外观跟设置走（跟随系统传 nil；改完立刻生效，不用重启）。
                .preferredColorScheme(store.appearance.colorScheme)
                // 1.2.7：小组件深链（paiban://schedule 进排班页、paiban://pay 进工资页）。
                .onOpenURL { store.handleDeepLink($0) }
            #endif
        }
    }
}
