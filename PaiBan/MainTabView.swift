import SwiftUI

/// 1.3.0.015（第 46 条终点，老爷 2026-11-26 20:36 亲口定：「回归最开始的样子吧，
/// 别做液态玻璃了」；20:38 又补：「直接用液态玻璃之前的那个版本吧」+「除了液态玻璃，
/// 新功能全都加上」）。
///
/// 底栏直接用液态玻璃之前的那个版本——1.3.0 正式版（build 34）那套原生 TabView：
/// 系统自带的底栏，图标 + 文字就是系统默认那套，不再做任何自定义底栏。
/// 001–014 的自定义底栏（悬浮胶囊、满宽毛玻璃栏、.glassEffect、BlurView）全部撤掉，
/// 液态玻璃测试页也一起删掉。底栏左右滑切页接不上原生 TabView——不硬接、不为它
/// 再造一个自定义栏（老爷亲口允的）。
///
/// 留着的新功能（001 之后加的、跟玻璃没关系的，一个不落）：
/// 更新弹窗修法（012 内测线读公开 beta.ios + 014 双保险：查之前现解析服务器、
/// 主界面稳 2 秒后再查一次）、013 自绘滚动指示条（AlwaysVisibleScrollIndicator，
/// 在本文件最下面）、006 刷新率适配（PaiBanApp.swift 的 RefreshRateBoost，10–120Hz）、
/// 公积金自填（第 47 条，1.3.0.001 加的，Models / PayCalc / 弹窗都在）。
/// 三页底部留白改回原生底栏对应的值——原生栏自己占位，不用再留 24pt / 120pt。
///

/// 主界面：三个 Tab（排班 / 工资 / 设置），各带自己的 NavigationStack。
/// 今日 Tab 已删；工资页标题叫「预估工资」。
/// 底栏重做（老爷 2026-11-28 14:36 亲口令：改回 SwiftUI 原生 TabView）：
/// 本来就是原生 TabView（1.3.0.015 已撤掉全部自定义底栏），这次只做三件事——
/// ① 删掉 PaiBanApp.init 里 UITabBar.appearance() 的全局改色（改 appearance 的全删掉，
/// 未选中态改回系统默认）；② 删掉两页为躲底栏垫的 88pt 大额留白（见 CalendarView /
/// PayView），安全区交由原生底栏自动处理；③ iOS 26+ 加上往下滚自动收起底栏
///（.tabBarMinimizeBehavior(.onScrollDown)，见下面 iOS26TabBarEnhancement）。
/// 只有三个 Tab，不加第四个“统计”Tab（示例代码里的第四个只是模板）。
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
        // 选中态走 AccentColor 资产（浅色深 navy、深色亮蓝）；未选中态改回系统默认
        //（PaiBanApp.init 里的 UITabBar.appearance() 改色已按老爷令删掉）。
        .tint(Color.accentColor)
        // iOS 26+ 底栏往下滚自动收起（老爷 2026-11-28 14:36 亲口令）：滑到底看统计栏、
        // 奖金卡时底栏自己让开，不挡内容；往回滚就恢复。iOS 17–25 没有这个 API，原样显示。
        .modifier(iOS26TabBarEnhancement())
        // 没登录时点小组件进来的深链：登录后进主界面再跳（store.handleDeepLink 先记下来）。
        .task {
            if let tab = store.pendingDeepLinkTab {
                store.pendingDeepLinkTab = nil
                store.selectedTab = tab
            }
            // 1.3.2.004：启动时就把工资算好——不然第一次点工资 Tab 才现算现取，
                // 切换过去要等一下，快不起来。没权限 / 设定没填完时 refreshPay 自己会停。
                if store.payAccess && store.pay == nil {
                    await store.refreshPay()
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

/// iOS 26 底栏增强（老爷 2026-11-28 14:36 亲口令）：原生 TabView 在 iOS 26+ 上
/// 自动渲染液态玻璃；往下滚动时底栏自动收起（.onScrollDown），滑到底看统计栏、
/// 奖金卡时不挡内容；往回滚就恢复。iOS 17–25 没有这个 API，直接原样显示。
/// 注意：.tabBarMinimizeBehavior 是 iOS 26 SDK 的 API，必须包在 #available 里，
/// 不然部署目标 iOS 17 的包编不过。
private struct iOS26TabBarEnhancement: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

/// 常显滚动指示条（1.3.0.013，第 46 条；老爷 19:24 说「没有滑动框」）。
/// 教训：.scrollIndicators(.visible) 在这个工程里没用——画廊实拍（run 45811123307）
/// 三页右边缘全高都是均匀底色，指示条根本没画出来（List 和 ScrollView 静止时都不显）。
/// 所以自己画一条：iOS 18+ 用 onScrollGeometryChange 读滚动几何（contentOffset /
/// contentSize / containerSize），按比例算滑块位置和长度，叠在右边缘、一直看得见；
/// 原生指示条同时藏掉（.scrollIndicators(.hidden)），免得两条重影。iOS 17 及以下没有
/// onScrollGeometryChange，退回 .scrollIndicators(.visible) 尽力而为。
/// 滑块：宽 4pt、圆角 2、Color.primary 35%（深浅模式自适应），离右边缘 2pt；
/// 长度 = 视口² / 内容高（最短 44pt）；位置 = 滚动进度 ×（视口高 − 滑块长）。
/// 内容不够一屏（不用滚）时不显示。只跟竖滚，不管横滑。
private struct ScrollGeo: Equatable {
    var offsetY: CGFloat = 0
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0
}

struct AlwaysVisibleScrollIndicator: ViewModifier {
    @State private var geo = ScrollGeo()

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: ScrollGeo.self) { g in
                    ScrollGeo(offsetY: g.contentOffset.y,
                              contentHeight: g.contentSize.height,
                              viewportHeight: g.containerSize.height)
                } action: { _, new in geo = new }
                .overlay(alignment: .topTrailing) { thumb }
        } else {
            content.scrollIndicators(.visible)
        }
    }

    /// 右边缘的滑块。内容不够滚时不画；长度和位置都按滚动几何实时算。
    @ViewBuilder
    private var thumb: some View {
        if geo.contentHeight > geo.viewportHeight + 1, geo.viewportHeight > 0 {
            let thumbH = max(44, geo.viewportHeight * geo.viewportHeight / geo.contentHeight)
            let clampedH = min(thumbH, geo.viewportHeight)
            let maxOffset = max(1, geo.contentHeight - geo.viewportHeight)
            let progress = min(1, max(0, geo.offsetY / maxOffset))
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(0.35))
                .frame(width: 4, height: clampedH)
                .padding(.trailing, 2)
                .offset(y: progress * max(0, geo.viewportHeight - clampedH))
        }
    }
}
