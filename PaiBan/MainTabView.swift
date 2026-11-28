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
struct MainTabView: View {
    @EnvironmentObject private var store: AppStore

    /// Tab 切换交叉淡入（1.3.2.006，滑动与切换动效整改方案）：原生 TabView 自带的
    /// 左右滑切换不掉，内容层自己淡——切 Tab 时先瞬时降到 0.3 / 下移 8pt，
    /// 再 0.2s ease-out 淡回原位。底栏是 TabView 的一部分，切换时也会跟着轻微
    /// 淡一下，可以接受。1.3.2.004 的 .animation(value:) 已删掉（它换不掉原生滑切）。
    @State private var contentOpacity: Double = 1
    @State private var contentOffsetY: CGFloat = 0

    var body: some View {
        ZStack {
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
        .opacity(contentOpacity)
        .offset(y: contentOffsetY)
        .onChange(of: store.selectedTab) { _ in
            // 先瞬时设（不要包在 withAnimation 里），再淡入。
            contentOpacity = 0.3
            contentOffsetY = 8
            withAnimation(.easeOut(duration: 0.2)) {
                contentOpacity = 1
                contentOffsetY = 0
            }
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
