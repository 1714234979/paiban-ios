import SwiftUI

/// 月份切换与标题栏·重做（老爷 2026-11-28 14:30 亲口令「直接重做」）：
/// 旧的 jumpToMonth（20pt 轻移 + 交叉淡入）、标题视差（PageGeom / PageOffsetKey）、
/// monthShift / monthOpacity、自定义手势，整段删掉，不留痕迹、不留兼容层。
/// 这里是唯一一份月份切换代码：排班页与工资页共用同一套分页容器 + 同一个月标题栏。
///
/// 两条铁律（录屏验出来的毛病）：
/// 1. 标题只跟落定页走——拖拽过程中标题绝不提前跳变。分页器内部用 scrollOffset 跟踪
///    拖拽位置，只在滚动落定（scrollPhase == .idle）时才把 selectedOffset 提交给
///    标题与数据；箭头点按 / 点“今天”是程序切页，selectedOffset 立刻换，标题立刻
///    用 numericText 滚动过去。
/// 2. 标题与网格绝不同步错位——网格就是分页器当前页，标题就是 selectedOffset 那一页，
///    两者同一个状态源；快速猛滑跳过一个月是系统原生分页行为，可以接受。
///
/// 月份索引：固定数组相对基准月的偏移（-120..<120，共 240 个月，覆盖 10 年窗口
/// 2016-11～2036-10），数组本身永远不变；基准月只在视图第一次创建时定一次（当月），
/// 之后不再动——动态改数组 / 改基准都会让 scrollPosition 的 id 错位、跳月。

// MARK: - 月份标题栏

/// 月份标题栏（老爷给的 MonthHeaderView 代码为准，只按 App 的规矩补了两处：
/// 48pt 热区（.touchTarget）与减弱动态效果分支；其余结构、字号、间距一字不动）。
/// ZStack 三层：左右箭头固定两侧；标题绝对居中；“今天”按钮独立定位、仅非当月出现。
/// 标题跟左右按钮、“今天” pill 都没关系，再也不会被挤偏、也不会跟今天按钮撞车
///（录屏 00:10「20: 今天 2月」重叠的根）。
struct MonthHeaderView: View {
    let year: Int
    let month: Int
    let isCurrentMonth: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onBackToToday: () -> Void

    /// 减弱动态效果：标题只做 0.15s 淡入，不做数字滚动与位移（App 的统一规矩）。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 标题动画跟的月份绝对序号（年*12 + 月-1），换月就变，触发 numericText 滚动。
    private var monthIndex: Int { year * 12 + (month - 1) }

    var body: some View {
        ZStack {
            // 1. 左右切换按钮（固定在两侧）
            HStack {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(AppStyle.surface1, in: Circle())
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                        // 36pt 圆按钮，透明留白扩到 48pt，视觉不变（App 的 48pt 热区规矩）。
                        .touchTarget(vertical: 6, horizontal: 6)
                }
                .buttonStyle(PressableButtonStyle())

                Spacer()

                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(AppStyle.surface1, in: Circle())
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                        .touchTarget(vertical: 6, horizontal: 6)
                }
                .buttonStyle(PressableButtonStyle())
            }

            // 2. 绝对居中的月份标题（等宽数字 + numericText，避免宽度跳动与裁切）。
            Text(DateUtil.yearMonthTitle(year: year, month: month))
                .font(.system(size: 18, weight: .bold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .opacity : .numericText())
                .animation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25), value: monthIndex)

            // 3. “今天”按钮独立定位，仅在非当月时平滑淡入，绝不与标题碰撞。
            HStack {
                Spacer()
                if !isCurrentMonth {
                    Button("今天", action: onBackToToday)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                        .padding(.trailing, 44) // 固定在右箭头左侧，留足安全间距
                        // 小 pill 只有约 31pt 高，透明留白扩到 48pt（App 的 48pt 热区规矩）。
                        .touchTarget(vertical: 9)
                        .buttonStyle(PressableButtonStyle())
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.8), value: isCurrentMonth)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }
}

// MARK: - 月份分页容器

/// 原生分页月份容器（老爷给的 SmoothMonthPager 代码为准，只加了一个落定提交：
/// 滚动位置（scrollOffset）与已落定月份（selectedOffset）分开管——拖拽中标题
/// 用的 selectedOffset 不动，标题就不会在手指还没松开时提前跳变；
/// 滚动停稳（idle）时才提交，标题与网格严格同步。
/// 不用 DragGesture 手拼 offset / transition，不用自定义 Transition；
/// 手势物理曲线、回弹与打断全交给系统（.scrollTargetBehavior(.paging)）。
struct SmoothMonthPager<Content: View>: View {
    /// 固定月份偏移数组（相对基准月，-120..<120，共 240 个月）。数组本身永远不变。
    let monthOffsets: [Int]
    /// 已落定的月份偏移（标题 + 数据跟它走）。拖拽中不动，只在落定时提交。
    @Binding var selectedOffset: Int
    /// 每页左右留白（默认 16：两页内容之间自然有 32pt 间距，不再粘连）。
    /// 工资页的卡片自带 16pt 横向留白，传 0 即可，同样是 32pt 间距。
    var pagePadding: CGFloat = 16
    /// 页内容是否撑满分页器高度（工资页：每页是一个竖滚 ScrollView，必须撑满）。
    var fillHeight: Bool = false
    @ViewBuilder let content: (Int) -> Content

    /// 滚动位置（拖拽中跟着手指走；程序切页时由 selectedOffset 同步过来）。
    @State private var scrollOffset: Int
    /// 减弱动态效果：落定提交只做 0.15s 淡入，不做位移（App 的统一规矩）。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        monthOffsets: [Int],
        selectedOffset: Binding<Int>,
        pagePadding: CGFloat = 16,
        fillHeight: Bool = false,
        @ViewBuilder content: @escaping (Int) -> Content
    ) {
        self.monthOffsets = monthOffsets
        self._selectedOffset = selectedOffset
        self.pagePadding = pagePadding
        self.fillHeight = fillHeight
        self.content = content
        // 初始就停在已选中的那一页，不先闪到数组头再跳回来。
        self._scrollOffset = State(initialValue: selectedOffset.wrappedValue)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(monthOffsets, id: \.self) { offset in
                    content(offset)
                        .containerRelativeFrame(fillHeight ? [.horizontal, .vertical] : .horizontal)
                        .padding(.horizontal, pagePadding)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        // 滚动位置只跟 scrollOffset 走：拖拽中它跟着手指变，标题用的 selectedOffset 不动，
        // 标题就不会在手指还没松开时提前跳变（录屏 00:29 / 00:31 工资页的毛病）。
        .scrollPosition(id: Binding<Int?>(
            get: { scrollOffset },
            set: { if let v = $0 { scrollOffset = v } }
        ))
        // 程序切页（箭头 / 今天）：selectedOffset 变了，把滚动位置同步过去，分页器滑过去。
        // withAnimation 的事务从调用方传进来，滑动跟着走。
        .onChange(of: selectedOffset) { newValue in
            if scrollOffset != newValue {
                scrollOffset = newValue
            }
        }
        // 落定才提交：滚动停稳（idle）时，才把当前页写回 selectedOffset，标题与数据
        // 一起换。拖一半松手弹回去时，scrollOffset 自己回到原页，等于没提交过。
        // 快速猛滑一次滑过两页是系统原生分页行为，可以接受；标题跟落定页严格一致。
        .onScrollPhaseChange { _, newPhase in
            if newPhase == .idle, scrollOffset != selectedOffset {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25)) {
                    selectedOffset = scrollOffset
                }
            }
        }
    }
}
