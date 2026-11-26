import SwiftUI

/// 主界面：三个 Tab（排班 / 工资 / 设置），各带自己的 NavigationStack。
/// 今日 Tab 已删；工资页标题叫「预估工资」。
///
/// 1.3.0.001（第 46 条）：底部切换栏改成自定义玻璃栏——原生 Tab 栏藏掉，
/// 底下放一条毛玻璃栏（ultraThinMaterial，透出底下内容）；点栏上的按钮切换，
/// 在栏上左右滑动也能切换（来回都行），滑动时震一下（和钉钉一样）。
/// 滑动只认栏上这一块，不动内容区，所以不跟排班页切月那套左右滑页打架。
///
/// 1.3.0.002（第 46 条修订，老爷 2026-11-26 亲口纠）：毛玻璃不是他要的玻璃，
/// 改成悬浮胶囊 + 系统 Liquid Glass——栏不贴底、不满宽、没有顶部分隔线，
/// 圆角胶囊浮在内容上面，离底边和左右都留一截空隙（像钉钉那个）。
/// 玻璃用 iOS 26+ 的 .glassEffect()（系统最新的 Liquid Glass，透明度跟系统走，
/// iOS 27 上就是它）；部署目标 iOS 16，26 以下 fallback 回 ultraThinMaterial。
///
/// 1.3.0.003（第 46 条再修，老爷 2026-11-26 亲口纠）：002 的旧底栏没藏住，
/// 底下还露着原来那条（.toolbar(.hidden, for: .tabBar) 在 iOS 27 上不生效），
/// 点旧栏会震、点胶囊不震，滑动也没震动。改法：不用 TabView 了，改手动切 Tab，
/// 三个 NavigationStack 都活着（各页导航状态不丢），只显示选中的那一个，
/// 底下只留悬浮胶囊这一条栏。震动改共享一个震动器，点按和滑动都要震。
/// 胶囊尺寸：左右留边再收窄（栏做长一点）、底部空隙再加大（往上靠一点点）。
///
/// 1.3.0.004（第 46 条再修，老爷 2026-11-26 发音乐 App 视频亲口纠）：
/// 003 的胶囊还是太宽、太高，看着像回到了以前那条。照视频（Apple Music 的
/// 悬浮胶囊底栏）改：底栏位置跟视频里一样，浮在底边上面那个高度——胶囊底离
/// 屏幕底边约 23pt（003 是 50pt，往下挪约 27pt）；三个标签，胶囊按三个标签
/// 的宽度做，适当做短一点（限宽 300pt 居中），不照视频四个标签的宽度做。
/// 震动不要了，点按和滑动都不震（003 的共享震动器整段删掉）。
///
/// 1.3.0.005（第 46 条再修，老爷 2026-11-26 发文件 App 视频 + 工资页截图亲口纠，
/// 「还不对，按照视频里的那个弄，别糊弄我了」）：004 还是不对——工资页奖金那几行
/// 透过玻璃胶囊露出来、重在一起；屏幕最底边（胶囊下面到屏幕底边那块）也被划了红线。
/// 根子是胶囊是半透明 Liquid Glass，内容滚到下面会透出来。照视频（iOS 文件 App 的
/// 悬浮胶囊底栏：最近项目/共享/浏览）重做：胶囊改成**不透明**实色（systemBackground，
/// 深浅色系统自己适配），内容滚到下面直接被挡住、不会透出来；选中那个有浅色圆角底块
/// （systemGray5 圆角矩形，matchedGeometryEffect 平滑滑动）+ 蓝色图标文字，未选中
/// 是 secondary。位置、宽度、滑动切页都不变（底离屏幕底边约 23pt，限宽 300pt 居中，
/// 栏上左右滑切换，不震动）。底部留白 100 → 120pt，三页滑到底最底下的内容离胶囊更远。
/// 底边那块再修：overlay 悬浮时滚起来内容还是会进到胶囊下面那条（屏幕最底边被截断），
/// 改成 VStack 底部固定——三页内容区在胶囊上面结束，内容永远滑不到胶囊下面，
/// 胶囊下面到屏幕底边那块只剩干净的页面底色；胶囊样子不变，还是悬浮胶囊。
/// 同版再修底栏盖内容：safeAreaInset 在 NavigationStack 里传不进去，三页
/// 滑到底最底下的内容都被胶囊盖住（排班统计卡、设置「关于」）。改成 overlay
/// 纯悬浮 + 各页自己留 100pt 底部留白，胶囊顶离内容底边约 41pt，够露出来。
///
/// 1.3.0.006（第 46 条再修，老爷 2026-11-26 在真机上试了 005 亲口纠：
/// 「ui 还是有问题，而且不能滑动，不是透明玻璃效果」；同版又加刷新率适配，第 34 条）：
/// ① 不能滑动：005 里底栏上左右滑切页在真机上滑不动。根子是手势挂法：DragGesture
/// 用普通 .gesture() 挂在装了三个 Button 的 HStack 上，Button 的点按手势会先抢
/// 住触摸、父级的拖动手势拿不到事件（SwiftUI 里子视图手势优先于父级普通手势）。
/// 改法：改成 .highPriorityGesture()，让拖动手势优先于 Button 的点按——点按
/// （没位移）时拖动认不出来、Button 照样能点；左右滑（位移超 12pt）时拖动先认
/// 出来、切页。手势阈值不变（横滑 >40pt 且大于纵向）。
/// ② 不是透明玻璃：005 的不透明实色胶囊他不要，要透明玻璃效果（像音乐 / 文件 App
/// 视频里那种 Liquid Glass，磨砂、半透明、透出底下内容的模糊影子）。但 004 被否
/// 是因为玻璃太透、工资页的字透过胶囊清清楚楚能读出来。所以这次玻璃要透、但透出
/// 来的是糊的、字读不出来：胶囊底先铺一层 .regularMaterial（中度磨砂，把底下
/// 内容糊成色块、字认不出来；.thickMaterial 太实、看着像 005 的不透明实色），
/// 上面再罩 iOS 26+ 的 .glassEffect(.regular)（Liquid Glass 的折射和亮边，
/// （.glassEffect 是 26+ API，#available 包着）。其余不动：选中底块+蓝色、未选中
/// 灰色、底离屏幕底边约 23pt、限宽 300pt 居中、不震动。底栏改回 overlay 悬浮：
/// 画廊里两种磨砂看着没区别——VStack 底部固定时内容到不了胶囊下面、底下只有一色
/// 底色，玻璃糊一色底色就跟实色一个样；overlay 时内容竖滚会从胶囊底下经过，
/// 玻璃才看得见。底边干净靠三页各自的 120pt 底部留白（滑到底时内容完整露在
/// 胶囊上面、不到屏幕最底边）。
/// ③ 刷新率适配（第 34 条，老爷说刷新率太低、要 140Hz）：先说硬件事实——iPhone
/// ProMotion 自适应刷新封顶就是 120Hz（他那台 iPhone 17 Pro Max 也是），140Hz
/// 在 iOS 硬件上做不到。根因：代码里没有任何帧率设置（没 CADisplayLink、没
/// preferredFrameRateRange、没 Timer），SwiftUI 默认跟 ProMotion 走，但没有显式
/// 声明帧率范围，系统在部分场景下只给 60Hz。改法：App 启动时建一个 CADisplayLink，
/// preferredFrameRateRange 设成 10–120Hz（preferred 120），显式告诉系统这 App
/// 要用满自适应刷新；静止时系统自己会降频省电（minimum 10Hz），不用管。
/// （实现在 PaiBanApp.swift 的 RefreshRateBoost，空转、只声明范围、不干活。）
struct MainTabView: View {
    @EnvironmentObject private var store: AppStore

    /// 能切到的 Tab：工资 Tab 只有有工资权限的人才有（1.2.7.001，第 23 条），
    /// 没权限的人只有排班 / 设置两个 Tab。tag 和原来一样：排班 0、工资 1、设置 2。
    private var availableTabs: [Int] {
        store.payAccess ? [0, 1, 2] : [0, 2]
    }

    private var tabItems: [(tag: Int, title: String, icon: String)] {
        [
            (0, "排班", "calendar"),
            (1, "工资", "yensign.circle"),
            (2, "设置", "gearshape"),
        ].filter { availableTabs.contains($0.tag) }
    }

    /// 每页的 NavigationStack。手动切 Tab 时三页都留在层级里（导航状态不丢），
    /// 只显示选中的那一页。
    @ViewBuilder
    private func tabPage(tag: Int) -> some View {
        switch tag {
        case 0:
            NavigationStack {
                CalendarView()
                    .navigationTitle("排班")
                    .navigationBarTitleDisplayMode(.inline)
            }
        case 1:
            // 工资 Tab：只有有工资权限的人才显示（1.2.7.001，第 23 条）。
            // 没权限的人只有排班 / 设置两个 Tab；年休假跟着工资走，也一并隐藏。
            NavigationStack {
                PayView()
                    .navigationTitle("预估工资")
                    .navigationBarTitleDisplayMode(.inline)
            }
        default:
            NavigationStack {
                SettingsView()
            }
        }
    }

    var body: some View {
        // 不用 TabView：原生 Tab 栏在 iOS 27 上藏不掉，底下会多露一条旧底栏，
        // 还会抢点按和震动。手动切 Tab：三页都活着，只显示选中的那一页。
        // 1.3.0.006：底栏改回 overlay 悬浮——玻璃要看得见，底下必须有内容
        // 滑过去：VStack 底部固定时内容永远到不了胶囊下面，胶囊底下只有
        // 一色的页面底色，磨砂+玻璃糊一色底色就跟不透明实色一个样（画廊
        // 里 thick/regular 两种磨砂看着没区别）。overlay 时内容竖滚会从
        // 胶囊底下经过，玻璃把字糊成色块、看不清字，同时看上去是玻璃。
        // 底边干净靠三页各自的 120pt 底部留白：滑到底时最后的内容完整露
        // 在胶囊上面、不到屏幕最底边（老爷划了红线那块）。
        ZStack(alignment: .bottom) {
            ZStack {
                tabPage(tag: 0)
                    .opacity(store.selectedTab == 0 ? 1 : 0)
                    .allowsHitTesting(store.selectedTab == 0)
                if store.payAccess {
                    tabPage(tag: 1)
                        .opacity(store.selectedTab == 1 ? 1 : 0)
                        .allowsHitTesting(store.selectedTab == 1)
                }
                tabPage(tag: 2)
                    .opacity(store.selectedTab == 2 ? 1 : 0)
                    .allowsHitTesting(store.selectedTab == 2)
            }
            FilesTabBar(
                items: tabItems,
                selectedTab: $store.selectedTab,
                onSwipeLeft: { switchTab(step: 1) },
                onSwipeRight: { switchTab(step: -1) }
            )
            .frame(maxWidth: 300)
            .padding(.bottom, 23)
        }
        .background(Color(.systemGroupedBackground))
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

    /// 滑动切 Tab：左滑 → 下一个，右滑 → 上一个；到头绕回另一边（来回都能滑）。
    private func switchTab(step: Int) {
        let tabs = availableTabs
        guard tabs.count > 1,
              let index = tabs.firstIndex(of: store.selectedTab) else { return }
        let next = tabs[(index + step + tabs.count) % tabs.count]
        guard next != store.selectedTab else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            store.selectedTab = next
        }
    }
}

/// 悬浮胶囊切换栏（1.3.0.006，照 iOS 文件 App 视频重做，第 46 条）：
/// 透明玻璃胶囊：底铺 .regularMaterial（中度磨砂，把底下内容糊成色块、字认不出来），
/// 上面再罩 iOS 26+ 的 .glassEffect(.regular)（Liquid Glass 的折射和亮边，
/// 看上去还是玻璃、不是 005 那种实色死板）；26 以下只有磨砂底。浮在内容上面；
/// 不贴底、不满宽、没有顶部分隔线。选中那个有浅色圆角底块（systemGray5 圆角矩形，
/// matchedGeometryEffect 平滑滑动）+ 蓝色图标文字；未选中是 secondary，没有底块。
/// 点按钮切换；在栏上左右滑动也能切换（来回都行）。滑动手势用 .highPriorityGesture()
/// （005 的普通 .gesture() 会被 Button 的点按手势抢走、真机上滑不动）。
/// 不震动（老爷亲口定：震动不要），点按和滑动都只切页、不震。
private struct FilesTabBar: View {
    let items: [(tag: Int, title: String, icon: String)]
    @Binding var selectedTab: Int
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void
    @Namespace private var pillNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tag) { item in
                Button {
                    guard item.tag != selectedTab else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedTab = item.tag
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 21))
                        Text(item.title)
                            .font(.system(size: 10))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .background {
                        // 选中底块：浅色圆角矩形，跟着选中的那个走（平滑滑动）。
                        if item.tag == selectedTab {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.systemGray5))
                                .matchedGeometryEffect(id: "selectedPill", in: pillNamespace)
                        }
                    }
                    .foregroundColor(item.tag == selectedTab ? .blue : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        // 1.3.0.006：透明玻璃——底铺 .regularMaterial（中度磨砂，底下内容糊成色块、
        // 字认不出来；.thickMaterial 太实、画廊里看着像 005 的不透明实色胶囊），
        // 上面罩 iOS 26+ 的 .glassEffect(.regular)（Liquid Glass 的折射和亮边）。
        // 26 以下只有磨砂底（capsuleGlass 里 #available 包着）。
        .background(.regularMaterial, in: Capsule())
        .capsuleGlass()
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        // 1.3.0.006：滑动手势改成 .highPriorityGesture()。005 的普通 .gesture()
        // 会被三个 Button 的点按手势抢走触摸，真机上左右滑切页滑不动。高优先手势
        // 让拖动先于 Button 点按被认出来：点按（没位移）时拖动认不出来、Button 照样
        // 能点；左右滑（位移超 12pt）时拖动先认出来、切页。阈值不变。
        .highPriorityGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    // 只认横滑（横向位移够大、且比纵向大）；竖滑不管。
                    guard abs(value.translation.width) > 40,
                          abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < 0 {
                        onSwipeLeft()
                    } else {
                        onSwipeRight()
                    }
                }
        )
    }
}

/// 胶囊玻璃（1.3.0.006，第 46 条）：iOS 26+ 才罩 .glassEffect(.regular)
/// （Liquid Glass，26+ API）；26 以下什么都不加，只留底下的 .regularMaterial
/// 磨砂底（磨砂本身 iOS 15+ 就有，部署目标 iOS 16 能用）。
private extension View {
    @ViewBuilder
    func capsuleGlass() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self
        }
    }
}
