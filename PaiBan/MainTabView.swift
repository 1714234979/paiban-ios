import SwiftUI
import UIKit

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

    var body: some View {
        TabView(selection: $store.selectedTab) {
            NavigationStack {
                CalendarView()
                    .navigationTitle("排班")
                    .navigationBarTitleDisplayMode(.inline)
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
                .tag(1)
            }

            NavigationStack {
                SettingsView()
            }
            .tag(2)
        }
        // 原生 Tab 栏藏掉，底下放悬浮胶囊玻璃栏。栏本身左右留边、底部留空隙，
        // 不贴底、不满宽，浮在内容上面；safeAreaInset 照样占位，内容不会被栏挡住。
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            GlassTabBar(
                items: tabItems,
                selectedTab: $store.selectedTab,
                onSwipeLeft: { switchTab(step: 1) },
                onSwipeRight: { switchTab(step: -1) }
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
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
        Haptics.tabSwitch()
        withAnimation(.easeInOut(duration: 0.2)) {
            store.selectedTab = next
        }
    }
}

/// 震动（1.3.0.001，第 46 条）：滑动切 Tab 时震一下。
/// iOS 16 部署目标，用 UIKit 的 UIImpactFeedbackGenerator（sensoryFeedback 要 iOS 17）。
private enum Haptics {
    static func tabSwitch() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
}

/// 悬浮胶囊切换栏（1.3.0.002，第 46 条修订）：圆角胶囊 + 系统玻璃底，浮在内容上面。
/// 不贴底、不满宽、没有顶部分隔线；点按钮切换；在栏上左右滑动也能切换（来回都行），滑动时震一下。
/// 选中态走 AccentColor 资产（浅色深 navy、深色亮蓝，1.2.8.002 已改好）；
/// 未选中态用 secondary，跟着深浅色走。
private struct GlassTabBar: View {
    let items: [(tag: Int, title: String, icon: String)]
    @Binding var selectedTab: Int
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tag) { item in
                Button {
                    guard item.tag != selectedTab else { return }
                    Haptics.tabSwitch()
                    withAnimation(.easeInOut(duration: 0.2)) {
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
                    .foregroundColor(item.tag == selectedTab ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .glassBarBackground()
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        .gesture(
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

/// 玻璃底（1.3.0.002）：iOS 26+ 用系统 Liquid Glass（.glassEffect()，
/// 默认 regular，透明度跟系统走，深浅色系统自己适配）；iOS 26 以下
/// fallback 回 ultraThinMaterial（老样子，不崩）。
/// 部署目标 iOS 16，.glassEffect() 是 iOS 26 SDK 的 API，必须包在
/// if #available 里——而且构建机必须用 Xcode 26 才能编过
/// （macos-15 镜像默认是 Xcode 16.4，工作流里要显式选 Xcode_26.3.app）。
private struct GlassBarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

private extension View {
    func glassBarBackground() -> some View {
        modifier(GlassBarBackground())
    }
}
