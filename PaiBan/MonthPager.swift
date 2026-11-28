import SwiftUI
import Observation

/// 月份切换与标题栏·重做（老爷 2026-11-28 14:30 亲口令「直接重做」）：
/// 旧的 jumpToMonth（20pt 轻移 + 交叉淡入）、标题视差（PageGeom / PageOffsetKey）、
/// monthShift / monthOpacity、自定义手势，整段删掉，不留痕迹、不留兼容层。
/// 这里是唯一一份月份切换代码：排班页与工资页共用同一套分页容器 + 同一个月标题栏。
///
/// 两条铁律（录屏验出来的毛病）：
/// 1. 标题跟过半页走（2026-11-28 改，取代落定才变）——拖过一半标题就换；
///    数据只跟落定页走：分页器内部用 scrollOffset 跟踪拖拽位置，只在滚动落定
///    （scrollPhase == .idle）时才把 selectedOffset 提交给数据；箭头点按 /
///    点“今天”是程序切页，selectedOffset 立刻换，标题立刻淡入过去
///    （1.3.2.010 曾全改淡入；1.3.2.011 改回 Gemini 的做法：滑动中/连变禁动画、
///    慢速单次点按保留数字滚动，标题只在 MonthTitleState 里变，不带动整页重算）。
///    拖一半松手弹回时标题跟着回来，可以接受。
/// 2. 标题与网格绝不同步错位——网格就是分页器当前页，标题就是过半页/落定页，
///    两者同一个状态源；快速猛滑跳过一个月是系统原生分页行为，可以接受。
///
/// 月份索引：固定数组相对基准月的偏移（-120..<120，共 240 个月，覆盖 10 年窗口
/// 2016-11～2036-10），数组本身永远不变；基准月只在视图第一次创建时定一次（当月），
/// 之后不再动——动态改数组 / 改基准都会让 scrollPosition 的 id 错位、跳月。

// MARK: - 标题状态隔离（过半切月只重绘标题，不带动整页重算）

/// 标题状态隔离（Gemini 1.3.2.011）：月份索引 + 滑动状态只活在这里，
/// 过半回调 / 落定 / 按钮切月统一走 update(to:)；滑动中或 0.28s 内连续变月
/// 直接禁动画，避免 numericText 数字叠糊；慢速单次点按箭头保留数字滚动。
@Observable
final class MonthTitleState {
    var monthIndex: Int
    var isScrolling: Bool = false
    var countsDown: Bool = false
    var suppressAnimation: Bool = false

    @ObservationIgnored private var lastChangeTime: CFAbsoluteTime = 0

    init(monthIndex: Int) {
        self.monthIndex = monthIndex
    }

    /// 过半回调 / 落定 / 按钮切月统一走这里：滑动中或 0.28s 内连续变月直接禁动画，避免数字叠糊。
    func update(to newIndex: Int) {
        guard newIndex != monthIndex else { return }
        let now = CFAbsoluteTimeGetCurrent()
        countsDown = newIndex < monthIndex
        suppressAnimation = isScrolling || (now - lastChangeTime) < 0.28
        lastChangeTime = now
        monthIndex = newIndex
    }

    func setScrolling(_ scrolling: Bool) {
        guard isScrolling != scrolling else { return }
        isScrolling = scrolling
        if scrolling {
            suppressAnimation = true
        } else {
            // 滚动停稳后恢复单次点按动画能力；monthIndex 未变不会触发多余动画。
            suppressAnimation = false
        }
    }
}

/// 隔离观察 MonthTitleState 的标题栏包装：滑动中标题高频变化只在这一小块内重绘。
struct ObservedMonthHeaderView: View {
    let state: MonthTitleState
    let onPrevious: () -> Void
    let onNext: () -> Void
    /// 点月份标题弹出年月快选（1.3.2.013）。
    var onTitleTap: (() -> Void)? = nil

    var body: some View {
        let idx = state.monthIndex
        MonthHeaderView(
            year: idx / 12,
            month: idx % 12 + 1,
            onPrevious: onPrevious,
            onNext: onNext,
            isScrolling: state.isScrolling,
            countsDown: state.countsDown,
            suppressAnimation: state.suppressAnimation,
            onTitleTap: onTitleTap
        )
    }
}

// MARK: - 月份标题栏

/// 月份标题栏（老爷给的 MonthHeaderView 代码为准，只按 App 的规矩补了两处：
/// 48pt 热区（.touchTarget）与减弱动态效果分支；其余结构、字号、间距一字不动）。
/// ZStack 两层：左右箭头固定两侧；标题绝对居中。
/// “今天”按钮不在这里（2026-11-28 老爷亲口令：改成排班页/工资页右下角悬浮按钮，
/// 标题行只剩 < 标题 >，标题真正居中；悬浮按钮只在非当月出现，点按走原来的 goToToday）。
/// 标题跟左右按钮都没关系，再也不会被挤偏、也不会跟今天按钮撞车
///（录屏 00:10「20: 今天 2月」重叠的根）。
/// 1.3.2.011（Gemini）：快滑/连点时切无动画纯文本，杜绝 numericText 叠成乱码；
/// 慢速单次点按箭头或「今天」时保留克制的数字过渡。
struct MonthHeaderView: View {
    let year: Int
    let month: Int
    let onPrevious: () -> Void
    let onNext: () -> Void
    var isScrolling: Bool = false
    var countsDown: Bool = false
    var suppressAnimation: Bool = false
    /// 点月份标题弹出年月快选（1.3.2.013）。
    var onTitleTap: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

            // 2. 绝对居中的月份标题：快滑/连点时切无动画纯文本，杜绝 numericText 叠成乱码；
            //    慢速单次点按箭头或「今天」时保留克制的数字过渡。
            //    1.3.2.013：标题可点，弹出年月快选（不用连点箭头翻去年/明年）。
            let title = DateUtil.yearMonthTitle(year: year, month: month)
            Button(action: { onTitleTap?() }) {
                if isScrolling || suppressAnimation {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .monospacedDigit()
                        .id("plain-month-title")
                        .transaction { $0.animation = nil }
                } else {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: countsDown))
                        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.2), value: monthIndex)
                        .id("animated-month-title")
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }
}

// MARK: - 年月快选

/// 年月快选（1.3.2.013）：点月份标题弹出，选年月直接跳过去，不用连点箭头翻去年/明年。
/// 年份步进 + 12 个月网格；当前月深炭黑高亮；超出 10 年窗口（2016-11～2036-10）
/// 的月份置灰不可点（goToMonth 本来也会 clamp，这里先拦住）。
struct MonthJumpSheet: View {
    let currentIndex: Int
    let range: Range<Int>
    var onJump: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var year: Int

    init(currentIndex: Int, range: Range<Int>, onJump: @escaping (Int) -> Void) {
        self.currentIndex = currentIndex
        self.range = range
        self.onJump = onJump
        _year = State(initialValue: currentIndex / 12)
    }

    private var minYear: Int { range.lowerBound / 12 }
    private var maxYear: Int { (range.upperBound - 1) / 12 }
    private func index(year: Int, month: Int) -> Int { year * 12 + (month - 1) }
    private func inRange(year: Int, month: Int) -> Bool { range.contains(index(year: year, month: month)) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 年份步进。
                HStack(spacing: 24) {
                    Button { year -= 1 } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(AppStyle.surface1, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(year <= minYear)
                    .opacity(year <= minYear ? 0.4 : 1)
                    Text("\(year)年")
                        .font(.system(size: 18, weight: .bold))
                        .monospacedDigit()
                        .frame(minWidth: 90)
                    Button { year += 1 } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(AppStyle.surface1, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(year >= maxYear)
                    .opacity(year >= maxYear ? 0.4 : 1)
                }
                // 12 个月网格。
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(1...12, id: \.self) { m in
                        let selected = (year == currentIndex / 12 && m == currentIndex % 12 + 1)
                        let enabled = inRange(year: year, month: m)
                        Button {
                            onJump(index(year: year, month: m))
                            dismiss()
                        } label: {
                            Text("\(m)月")
                                .font(.system(size: 16, weight: selected ? .bold : .regular))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(selected ? AppStyle.navyAdaptive : AppStyle.surface1, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundColor(selected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        .disabled(!enabled)
                        .opacity(enabled ? 1 : 0.35)
                    }
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("选择年月")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - 月份分页容器

/// 原生分页月份容器（老爷给的 SmoothMonthPager 代码为准，只加了一个落定提交和一个过半标题回调：
/// 滚动位置（scrollOffset）与已落定的月份（selectedOffset）分开管——拖拽中数据
/// 用的 selectedOffset 不动，数据就不会在手指还没松开时提前跳变；滚动停稳（idle）
/// 时才提交，数据与网格严格同步。拖一半松手弹回去时，scrollOffset 自己回到原页，等于没提交过。
/// 标题另外走过半回调（onMidpointPageChange）：拖过一半标题就换（2026-11-28 改，
/// 取代上一轮故意选的落定才变；拖一半松手弹回时标题跟着回来，可以接受）。
/// 不用 DragGesture 手拼 offset / transition，不用自定义 Transition；
/// 手势物理曲线、回弹与打断全交给系统（.scrollTargetBehavior(.paging)）。
/// 每页留白（pagePadding）画在容器宽度里面（先 padding 再 containerRelativeFrame），
/// 每页正好一个容器宽——之前 padding 在容器外面，每页宽了 2*pagePadding，
/// 落点整体右移 pagePadding、右边缘被切掉 pagePadding（2026-11-28 实测 +16pt）。
/// 1.3.2.011（Gemini）：fillHeight 时绝不用 .containerRelativeFrame(.vertical)——
/// 横向 ScrollView 不定义纵向容器轴，.vertical 会越级取到 NavigationStack 全高，
/// 导致页面上下溢出、顶部黑卡被硬切；改用 GeometryReader 拿精确可视宽高。
struct SmoothMonthPager<Content: View>: View {
    /// 固定月份偏移数组（相对基准月，-120..<120，共 240 个月）。数组本身永远不变。
    let monthOffsets: [Int]
    /// 已落定的月份偏移（数据跟它走）。拖拽中不动，只在落定时提交。
    @Binding var selectedOffset: Int
    /// 每页左右留白（默认 16：两页内容之间自然有 32pt 间距，不再粘连）。
    /// 工资页的卡片自带 16pt 横向留白，传 0 即可，同样是 32pt 间距。
    /// 留白画在容器宽度里面，不改变每页宽度（见上面）。
    var pagePadding: CGFloat = 16
    /// 页内容是否撑满分页器高度（工资页：每页是一个竖滚 ScrollView，必须撑满）。
    var fillHeight: Bool = false
    /// 拖过一半时报一次（月份偏移）：标题跟它走，数据不跟（数据只跟落定页）。
    /// 不传就不报（标题仍跟落定页，旧行为）。
    var onMidpointPageChange: ((Int) -> Void)? = nil
    /// 用户手势滑动状态回调（true = 拖拽/惯性滑动中，false = 已停稳）。
    var onScrollingChange: ((Bool) -> Void)? = nil
    @ViewBuilder let content: (Int) -> Content

    /// 滚动位置（拖拽中跟着手指走；程序切页时由 selectedOffset 同步过来）。
    @State private var scrollOffset: Int
    /// 上一次报过的过半页（去重：滚动几何每帧都变，只在页码真变了才回调）。
    @State private var lastReportedMidpoint: Int?
    /// 减弱动态效果：落定提交只做 0.15s 淡入，不做位移（App 的统一规矩）。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        monthOffsets: [Int],
        selectedOffset: Binding<Int>,
        pagePadding: CGFloat = 16,
        fillHeight: Bool = false,
        onMidpointPageChange: ((Int) -> Void)? = nil,
        onScrollingChange: ((Bool) -> Void)? = nil,
        @ViewBuilder content: @escaping (Int) -> Content
    ) {
        self.monthOffsets = monthOffsets
        self._selectedOffset = selectedOffset
        self.pagePadding = pagePadding
        self.fillHeight = fillHeight
        self.onMidpointPageChange = onMidpointPageChange
        self.onScrollingChange = onScrollingChange
        self.content = content
        // 初始就停在已选中的那一页，不先闪到数组头再跳回来。
        self._scrollOffset = State(initialValue: selectedOffset.wrappedValue)
    }

    /// 滚动几何（过半标题用）：x 偏移 + 容器宽。自定义 Equatable 结构（不用元组——
    /// 元组不能当泛型 Equatable 约束传给 onScrollGeometryChange；本文件已有 ScrollGeo 同款先例）。
    private struct PagerScrollGeo: Equatable {
        var offsetX: CGFloat = 0
        var width: CGFloat = 0
    }

    /// 过半页换了就报给标题（去重 + 夹在偏移数组里）。
    private func reportMidpoint(_ offset: Int) {
        guard let onMidpointPageChange else { return }
        let clamped = min(max(offset, monthOffsets.min() ?? offset), monthOffsets.max() ?? offset)
        guard lastReportedMidpoint != clamped else { return }
        lastReportedMidpoint = clamped
        onMidpointPageChange(clamped)
    }

    var body: some View {
        // fillHeight == true（工资页）：绝不用 .containerRelativeFrame(.vertical)——
        // 横向 ScrollView 不定义纵向容器轴，.vertical 会越级取到 NavigationStack 全高，
        // 导致页面上下溢出、顶部黑卡被硬切；改用 GeometryReader 拿精确可视宽高。
        if fillHeight {
            GeometryReader { geo in
                if geo.size.width > 0, geo.size.height > 0 {
                    pagerContainer(pageSize: geo.size)
                }
            }
        } else {
            pagerContainer(pageSize: nil)
        }
    }

    @ViewBuilder
    private func pagerContainer(pageSize: CGSize?) -> some View {
        // onScrollPhaseChange 只要 iOS 18+（部署目标 17.0，不能升到 18）：
        // 18 走系统原生的落定信号，17 走等效的防抖落定判断，两边数据都只跟落定页走；
        // 标题另外走过半回调（拖过一半就换，2026-11-28 改，取代落定才变）。
        if #available(iOS 18.0, *) {
            pagerView(pageSize: pageSize)
                // 标题过半就换：滚动几何每帧都来，按 contentOffset.x / 页宽四舍五入，
                // 拖过一半标题立刻跟过去；拖一半松手弹回时几何值跟着回来，标题也回来。
                // 只在页码真变了才回调（reportMidpoint 去重），不每帧都写父视图状态。
                .onScrollGeometryChange(for: PagerScrollGeo.self, of: { g in
                    PagerScrollGeo(offsetX: g.contentOffset.x, width: g.containerSize.width)
                }) { _, new in
                    guard new.width > 0 else { return }
                    let idx = Int((new.offsetX / new.width).rounded())
                    let clampedIdx = min(max(idx, 0), monthOffsets.count - 1)
                    reportMidpoint(monthOffsets[clampedIdx])
                }
                // 落定才提交：滚动停稳（idle）时，才把当前页写回 selectedOffset，数据
                // 一起换。拖一半松手弹回去时，scrollOffset 自己回到原页，等于没提交过。
                // 快速猛滑一次滑过两页是系统原生分页行为，可以接受；数据跟落定页严格一致。
                .onScrollPhaseChange { _, newPhase in
                    let userScrolling = (newPhase == .tracking || newPhase == .interacting || newPhase == .decelerating)
                    onScrollingChange?(userScrolling)
                    if newPhase == .idle, scrollOffset != selectedOffset {
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25)) {
                            selectedOffset = scrollOffset
                        }
                    }
                }
        } else {
            pagerView(pageSize: pageSize)
                // iOS 17 标题过半就换：scrollPosition 的 scrollOffset 拖拽中跟着手指变，
                // 过半就翻到下一页的偏移，标题立刻跟过去；松手弹回时 scrollOffset 回到原页，
                // 标题也回来。程序切页（箭头 / 今天）时 scrollOffset 同步变，标题一样立刻跟。
                .onChange(of: scrollOffset) { newValue in
                    if newValue != selectedOffset {
                        onScrollingChange?(true)
                    }
                    reportMidpoint(newValue)
                }
                // iOS 17 等效落定判断（.task(id:) 防抖）：scrollOffset 一变，旧任务取消、
                // 新任务重算 0.3 秒；位置停稳 0.3 秒才提交，中途再变（继续拖、松手弹回）
                // 就作废重算，数据不动。0.3 秒约等于分页落定的弹回时长：正常轻滑落定后
                // 数据正好跟上；拖一半松手弹回去时 scrollOffset 回到原页，等于没提交过。
                // 手指按住中途停顿超过 0.3 秒的极端情况数据会提前跟到拖向的那一页，
                // 松手/拖回后立刻纠正——17 上没有系统落定信号，这是能做到的最近似做法，
                // 数据最终永远跟落定页一致。
                .task(id: scrollOffset) {
                    let captured = scrollOffset
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    onScrollingChange?(false)
                    if scrollOffset == captured, scrollOffset != selectedOffset {
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25)) {
                            selectedOffset = scrollOffset
                        }
                    }
                }
        }
    }

    /// 分页器本体（两条分支共用）：原生分页 ScrollView + scrollPosition 跟踪 +
    /// 程序切页同步。落定提交不在这里，两条分支各用各的落定信号。
    private func pagerView(pageSize: CGSize?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(monthOffsets, id: \.self) { offset in
                    if let size = pageSize {
                        content(offset)
                            .padding(.horizontal, pagePadding)
                            .frame(width: size.width, height: size.height, alignment: .top)
                            .clipped()
                    } else {
                        content(offset)
                            .padding(.horizontal, pagePadding)
                            .containerRelativeFrame(.horizontal)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        // 滚动位置只跟 scrollOffset 走：拖拽中它跟着手指变，数据用的 selectedOffset 不动，
        // 数据就不会在手指还没松开时提前跳变（录屏 00:29 / 00:31 工资页的毛病）；
        // 标题另外走过半回调（见 body），拖过一半就换。
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
    }
}

/// 金额一键隐藏开关（1.3.2.013）：黑卡右上角的眼睛，点一下排班黑卡与工资页的
/// 全部金额脱敏为 ¥****，再点恢复；状态存在 Store.hideAmounts（UserDefaults），
/// 下次进 App 还在。极轻量：白字 0.85 透明度、无底块，只一个小眼睛。
/// 放这里不用放 DesignSystem.swift——DesignSystem 同时编进小组件扩展，
/// 那边没有 AppStore，写 @Environment(AppStore.self) 编不过。
/// 金额一键隐藏的眼睛按钮（1.3.2.013 建，1.3.2.014 改色）：顶卡从黑底改成
/// 白框（跟随浅深色）后，眼睛不能再是纯白，改成自适应的 secondary——浅色深灰、
/// 深色浅灰，在白卡和深卡上都看得清。只用在排班/工资两张顶卡上。
struct HideAmountsEyeButton: View {
    @Environment(AppStore.self) private var store: AppStore

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            store.hideAmounts.toggle()
        } label: {
            Image(systemName: store.hideAmounts ? "eye.slash" : "eye")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.hideAmounts ? "显示金额" : "隐藏金额")
    }
}
