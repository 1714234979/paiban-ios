import SwiftUI
import UIKit

/// 日历格固定高 64pt；网格外框总高固定 414pt（6 行 × 64 + 5 × 6），行距恒定 6pt。
/// 固定 6 行（1.3.2.006，老爷 2026-11-28 12:53 亲口令「行距不一样，你改改我看看吧」）：
/// 所有月都补满 42 格，5 行的月多一行下月开头的暗色日期，行距、行位置全月一致，
/// 慢拖时两页的行严丝合缝，不再错位。
private let calendarCellHeight: CGFloat = 64
private let calendarGridHeight: CGFloat = 6 * 64 + 5 * 6
private func calendarRowSpacing(weeks: Int) -> CGFloat {
    // 固定 6 行：行距恒定 6pt（1.3.2.006）。以前按行数自适应（5 行 23.5pt、6 行 6pt），
    // 慢拖时两页行错位；现在 weeks 恒为 6，行距、行位置全月一致。总高 414pt、格高 64pt 不变。
    6
}

/// 标题视差的页位置上报（1.3.2.007，整改提示词 §3.3）：每页用 GeometryReader 把
/// 自己在 monthPager 坐标系里的 minX + 页宽报上来，父视图按当前页的位移算标题的
/// 0.5 倍视差。原生 TabView 不直接暴露拖拽进度，这是取进度的办法。
private struct PageGeom: Equatable {
    var minX: CGFloat
    var width: CGFloat
}

private struct PageOffsetKey: PreferenceKey {
    static var defaultValue: [Int: PageGeom] = [:]
    static func reduce(value: inout [Int: PageGeom], nextValue: () -> [Int: PageGeom]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// 排班页：原生月历。每个日期格里的班次 pill 都是同一固定高度（28pt、通栏圆角），
/// 修掉网页版“日班绿块占满整格、别的班只是短 pill”的 bug。
struct CalendarView: View {
    @EnvironmentObject private var store: AppStore

    @State private var selectedDay: DaySchedule?
    @State private var showDayDetail = false
    /// 1.1.4：滑页刷新防抖任务（见 .onChange(of: pageIndex)）。
    @State private var refreshTask: Task<Void, Never>?
    /// 调班/请假卡骨架延迟 150ms 的在途任务（1.3.2.006）：加载开始后 150ms 再现骨架，
    /// 数据快回来就不闪；加载结束或视图消失时取消。
    @State private var recordsSkeletonTask: Task<Void, Never>?
    /// 调班/请假卡的骨架是否显示（同上，150ms 延迟后才置 true）。
    @State private var showRecordsSkeleton = false
    /// 箭头点按切月过渡（1.3.2.007，iOS.docx §3.1）：TabView 瞬间跳页，网格本身只做
    /// 20pt 轻微位移 + 短促交叉淡入，0.25s easeInOut；拖拽滑月走原生 TabView 分页（1:1 linear），不动。
    @State private var monthShift: CGFloat = 0
    @State private var monthOpacity: Double = 1
    /// 标题视差（1.3.2.007，整改提示词 §3.3）：拖拽时年月标题以当前页位移的 0.5 倍
    /// 同向移动，opacity 随进度 1→0.5；落定后 0.25s easeInOut 回位、新标题淡入恢复。
    @State private var titleParallaxOffset: CGFloat = 0
    @State private var titleParallaxOpacity: Double = 1
    /// 标题箭头淡入（跳页时标题 0.5→1 淡入恢复）。
    @State private var titleDim: Double = 1
    /// 标题落定回位动画进行中：期间不接新的拖拽进度，免得打断回位。
    @State private var titleReturning = false
    @State private var titleReturnTask: Task<Void, Never>? = nil
    /// 今天格轻高亮（1.3.2.007，iOS.docx §3.2）：点“今天”后目标格一次微闪（边框/底色，不放大）。
    @State private var todayFlashDate: String? = nil
    @State private var todayFlashTask: Task<Void, Never>? = nil
    /// 班组胶囊滑动（1.3.2.007，iOS.docx §3.2）：选中底色用 matchedGeometryEffect 在四个 pill 间滑动。
    @Namespace private var teamCapsuleNamespace
    /// 减弱动态效果（1.3.2.007，iOS.docx §3.4）：取消横向位移与弹簧过冲，改 0.15s 交叉淡入；跟手位移保留。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // 滑页的页码 = 月份绝对序号（年*12 + 月-1），2026年11月 = 24322。
    // 用原生 TabView 分页滑，切月跟着手指走、左右月预渲染，不再整格闪白重画。
    @State private var pageIndex: Int = CalendarView.monthIndex(year: DateUtil.yearMonth(of: Date()).year, month: DateUtil.yearMonth(of: Date()).month)
    // 滑页范围：一次生成 20 年（240 个月），当前月居中（前后各 120 个月）。
    // 现在是 2026 年 11 月，窗口就是 2016-11 ~ 2036-10，滑到边就停。
    // 240 页只渲染附近页（TabView 懒加载），滑页不再为全量页做布局，卡顿的根也去了。
    @State private var windowStartIndex: Int = {
        let now = DateUtil.yearMonth(of: Date())
        return CalendarView.monthIndex(year: now.year, month: now.month) - 120
    }()
    private var pageRange: Range<Int> { windowStartIndex..<(windowStartIndex + 240) }

    /// 预加载窗口（1.3.2.004，老爷 2026-11-28 11:32 亲口定）：
    /// 当前页前后各 10 个月，共 21 页——“我每翻一页就加载 21 页”。
    /// 每页的格子在父视图提前算好存在这里，页滑过来时直接用，
    /// 不在滑动中现算、现拍快照（慢拖卡顿的根：下一页/上一页原来是现加载的）。
    private static let preloadRadius = 10
    @State private var preloadedGrids: [Int: [(day: DaySchedule, kind: MonthPageView.GridDayKind)]] = [:]

    /// 共享班表页（1.2.7.001，第 24 条）。
    @State private var showShareSchedule = false
    /// 手动排班页（1.2.7.002）：手动模式时从排班页进。
    @State private var showManualSchedule = false

    static func monthIndex(year: Int, month: Int) -> Int { year * 12 + (month - 1) }
    private func yearMonth(from index: Int) -> (year: Int, month: Int) { (index / 12, index % 12 + 1) }

    /// 以 center 为中心预加载 21 页的格子（只算本地数据：monthFor 走缓存/本地 8 天一轮；
    /// 网络预取由 monthFor 里已有的 prefetchMonth 顺带做，调班/请假一起回来）。
    /// 窗口外的旧页直接丢掉，只留 21 页；数据变了（日历数据/换班组/显示设置）
    /// 就整窗重算，已缓存的页直接复用、不重复算。
    private func preloadAround(_ center: Int) {
        let lo = max(pageRange.lowerBound, center - Self.preloadRadius)
        let hi = min(pageRange.upperBound - 1, center + Self.preloadRadius)
        var next: [Int: [(day: DaySchedule, kind: MonthPageView.GridDayKind)]] = [:]
        next.reserveCapacity(hi - lo + 1)
        for idx in lo...hi {
            if let cached = preloadedGrids[idx] {
                next[idx] = cached
            } else {
                let ym = yearMonth(from: idx)
                next[idx] = MonthPageView.buildGridDays(year: ym.year, month: ym.month, store: store)
            }
        }
        preloadedGrids = next
    }

    /// 箭头/今天/邻月点按切月（1.3.2.007，iOS.docx §3.1）：不用大跨度横甩——
    /// TabView 瞬间跳到新月（pageIndex 不包动画），网格本身只做 20pt 轻微位移 +
    /// 短促交叉淡入，0.25s easeInOut；标题同时 0.5→1 淡入恢复。
    /// 减弱动态效果时不位移，只做 0.15s 淡入。direction：+1 下月（内容从右进），-1 上月。
    private func jumpToMonth(_ index: Int, direction: Int) {
        let target = min(max(index, pageRange.lowerBound), pageRange.upperBound - 1)
        monthShift = reduceMotion ? 0 : CGFloat(direction) * 20
        monthOpacity = 0.6
        titleDim = 0.5
        pageIndex = target
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.25)) {
            monthShift = 0
            monthOpacity = 1
            titleDim = 1
        }
    }

    /// 点“今天”（1.3.2.007，iOS.docx §3.2）：不在当月时平滑切回当月；目标日期格一次
    /// 极克制的轻高亮（微闪，不放大）；轻冲击触感与动画起点同一帧触发。
    /// 已在当月时只闪格子，不跳页。减弱动态效果时不闪（当天已有绿边框标识）。
    private func goToToday() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let target = Self.monthIndex(year: DateUtil.yearMonth(of: Date()).year, month: DateUtil.yearMonth(of: Date()).month)
        if target == pageIndex {
            flashTodayCell()
        } else {
            jumpToMonth(target, direction: target > pageIndex ? 1 : -1)
            if !reduceMotion {
                // 页落定（0.25s）后再闪格子，免得格子还没滑到位就闪完了。
                flashTodayCell(after: 300_000_000)
            }
        }
    }

    /// 今天格轻高亮：把 todayFlashDate 置上今天的日期，650ms 后清掉；
    /// 格子收到后做一次 0.55s 的底色微闪。delay 用在跳页后，等页落定再闪。
    private func flashTodayCell(after delayNanoseconds: UInt64 = 0) {
        todayFlashTask?.cancel()
        todayFlashTask = Task { @MainActor in
            if delayNanoseconds > 0 { try? await Task.sleep(nanoseconds: delayNanoseconds) }
            guard !Task.isCancelled else { return }
            todayFlashDate = DateUtil.string(from: Date())
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            todayFlashDate = nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                teamSwitcher
                monthNavigator
                // 1.2.7.002：日历只留月视图（周视图已删）。
                monthPager
                summaryLine
                recordsSection
                syncTimeFooter
            }
            .padding(.horizontal, 16)
            // 底部留白 88pt（1.3.2.006）：iOS 26/27 上原生底栏是悬浮胶囊样式（约 64pt），
            // ScrollView 底部不留够白，最底下一行（“当月应出勤”）会被底栏压住一半。
            .padding(.bottom, 88)
        }
        // 1.3.0.013：滚动指示条常显（老爷 19:24 说「没有滑动框」）——.visible 没用，
        // 画廊实拍证明它根本不画出来，改走自绘滑块 AlwaysVisibleScrollIndicator。
        .modifier(AlwaysVisibleScrollIndicator())
        .background(AppStyle.pageBackground)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showShareSchedule = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("共享班表")
            }
            if store.rotation.isManual {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("手动排班") { showManualSchedule = true }
                }
            }
        }
        .navigationDestination(isPresented: $showShareSchedule) {
            ShareScheduleView()
        }
        .navigationDestination(isPresented: $showManualSchedule) {
            ManualScheduleView()
        }
        .task {
            // 1.2.6 冷启动回当天：进页对齐到今天所在的月（不再跟 Store 恢复的月份走）。
            // .task 只在视图第一次创建时跑（冷启动、登录后进主界面），从后台切回来不重跑、
            // 不强制回当天，保持原地。
            let now = DateUtil.yearMonth(of: Date())
            pageIndex = min(max(Self.monthIndex(year: now.year, month: now.month), pageRange.lowerBound), pageRange.upperBound - 1)
            store.setCurrentMonth(year: now.year, month: now.month)
            if store.month == nil {
                await store.refreshMonth()
            }
            // 进页就把前后月也预取好，第一次左右滑就不等网络。
            let next = yearMonth(from: pageIndex + 1)
            let prev = yearMonth(from: pageIndex - 1)
            store.prefetchMonth(year: next.year, month: next.month)
            store.prefetchMonth(year: prev.year, month: prev.month)
            // 1.3.2.004：进页就把前后 10 个月共 21 页的格子算好，第一次滑就不用现算。
            preloadAround(pageIndex)
            // 1.1.3：阴历缓存预热 + 工资输入补齐（日历的三薪标与底部统计要用）。
            // 阴历按月分批算（主线程，DateFormatter 不线程安全），每批之间让出主线程，
            // 避免一次算 240 个月堵住界面；滑到新月时阴历已是缓存，不再现算。
            // 工资输入（全年天数 + 配置）后台补，到了 payInputsVersion +1 触发重画。
            Task {
                for idx in pageRange {
                    let ym = yearMonth(from: idx)
                    ChineseCalendar.warmMonth(year: ym.year, month: ym.month)
                    await Task.yield()
                }
            }
            Task {
                let years = Set(pageRange.map { yearMonth(from: $0).year })
                await store.ensureYearDays(years: Array(years).sorted())
            }
        }
        // 滑到哪页，汇总、调班/请假记录跟着走（但要等落定）。
        // 1.1.5（重叠根因之二）：原来这里立刻调 setCurrentMonth，写一串 @Published，
        // 正好落在 TabView 的 settle 动画里，整页重绘打断动画，两页错位重叠。
        // 现在滑页那一刻只记页码，什么数据都不换；等 0.4 秒没再滑页（落定了）
        // 再换月 + 预取前后月 + 刷新。标题和底部统计直接跟 pageIndex 走（见 pagerTitle /
        // displayedMonth），不经过 store.currentYearMonth，所以落定前也不错位。
        .onChange(of: pageIndex) { newIndex in
            // 1.3.2.004：落到哪页就以那页为中心重算 21 页——下一页还没滑到就已经算好了。
            preloadAround(newIndex)
            refreshTask?.cancel()
            refreshTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                let ym = yearMonth(from: newIndex)
                store.setCurrentMonth(year: ym.year, month: ym.month)
                let next = yearMonth(from: newIndex + 1)
                let prev = yearMonth(from: newIndex - 1)
                store.prefetchMonth(year: next.year, month: next.month)
                store.prefetchMonth(year: prev.year, month: prev.month)
                await store.refreshMonth()
            }
            // 标题视差落定回位（1.3.2.007）：拖拽松手、页落定后，标题从 0.5× 偏移 /
            // 0.5 透明度 0.25s easeInOut 回到原位，新月份标题淡入恢复；回位期间
            // 不接新的拖拽进度（titleReturning），免得打断回位。
            // 没拖拽（箭头点按）时视差本来就是 0/1，这里什么都不做。
            if titleParallaxOffset != 0 || titleParallaxOpacity != 1 {
                titleReturning = true
                withAnimation(.easeInOut(duration: 0.25)) {
                    titleParallaxOffset = 0
                    titleParallaxOpacity = 1
                }
                titleReturnTask?.cancel()
                titleReturnTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 260_000_000)
                    titleReturning = false
                }
            }
        }
        .onChange(of: store.viewTeam) { _ in
            // 1.3.2.004：换班组立刻按新班组重算 21 页（monthFor 按新班组算），再后台刷新。
            preloadAround(pageIndex)
            Task { await store.refreshMonth() }
        }
        // 1.3.2.004：日历真数据到了 / 显示设置（周一首日、显示上下月）改了，
        // 预加载的 21 页整窗重算，已缓存的页直接复用。
        .onChange(of: store.calendarVersion) { _ in preloadAround(pageIndex) }
        .onChange(of: store.calendarDisplay) { _ in preloadAround(pageIndex) }
        .sheet(isPresented: $showDayDetail) {
            if let selectedDay {
                DayDetailView(day: selectedDay)
            }
        }
    }

    // MARK: 头部

    /// 顶栏黑框：今天的年月日、周几、什么班（切到别的月份也照样显示今天）。
    /// 1.2.7：下面再加两行实时行——倒计时 + 已挣/预估（只那一小块每秒刷新，不带动整页）。
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(todayDateLine)
                .appFont(size: AppFont.titleLarge, weight: 700)
                .fadeIn()
                .foregroundColor(.white)
            Text(todayShiftLine)
                .appFont(size: AppFont.bodySmall)
                .fadeIn()
                .foregroundColor(AppStyle.whiteText(opacity: 0.75))
            if let day = store.todaySchedule {
                let inputs = store.todayEstimateInputs
                TodayLiveRow(day: day, earlyRate: inputs.earlyRate, midRate: inputs.midRate, inputs: inputs.inputs, showMoney: store.payAccess)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppStyle.navyAdaptive)
        .cornerRadius(16)
        // 1.3.2.004（老爷 2026-11-28 11:39 亲口定）：休息的班没有预计工资，黑卡只有两行、
        // 上班的班有四行——切班时黑卡高度是慢慢变的，不再一下子跳（下面的日历跟着顺滑地挪）。
        // 1.3.2.007：曲线改成 0.25s ease-in-out（iOS.docx §3.2/§4.1），行为不变。
        .animation(.easeInOut(duration: 0.25), value: store.viewTeam)
    }

    /// 今天的年月日 + 周几，如“2026年11月24日 星期二”。
    private var todayDateLine: String {
        let today = Date()
        let ym = DateUtil.yearMonth(of: today)
        let day = DateUtil.calendar.component(.day, from: today)
        return "\(DateUtil.yearMonthTitle(year: ym.year, month: ym.month))\(day)日 \(DateUtil.weekdayCN(of: today))"
    }

    /// 今天什么班，如“中班 16:00–24:00”；双班写“早班 + 中班 …”；休息写“休息”；请假写“请假（年假）”。
    private var todayShiftLine: String {
        guard let day = store.todaySchedule else { return "—" }
        if day.onLeave == true {
            let t = day.leaveType ?? ""
            return t.isEmpty ? "请假" : "请假（\(t)）"
        }
        if day.isRest { return "休息" }
        let parts = ShiftStyle.parts(of: day.shift)
        if parts.count > 1 {
            return parts.joined(separator: " + ") + " " + day.displayTime
        }
        return "\(day.shift) \(day.displayTime)"
    }

    private var teamSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(TeamInfo.allTeams, id: \.self) { team in
                Button {
                    // 1.3.2.007（iOS.docx §3.2/P7）：轻冲击触感与动画起点同一帧触发。
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.viewTeam = team
                } label: {
                    Text("\(team)班")
                        .appFont(size: AppFont.headline, weight: store.viewTeam == team ? 700 : 400)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if store.viewTeam == team {
                                    // 选中胶囊底色平滑滑动（1.3.2.007，iOS.docx §3.2）：
                                    // matchedGeometryEffect 让底色在四个 pill 间滑过去，
                                    // 不是整块日历横移；减弱动态效果时不滑动。
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(AppStyle.navyAdaptive)
                                        .matchedGeometryEffect(id: "teamCapsule", in: teamCapsuleNamespace)
                                } else {
                                    AppStyle.surface1
                                }
                            }
                        )
                        .foregroundColor(store.viewTeam == team ? .white : .primary)
                        .cornerRadius(20)
                        // 1.3.2.005（方案 §3.3）：班组 pill 只有约 37pt 高，透明留白扩到 48pt；
                        // 只加竖向留白，不动四个 pill 之间的横向间距。
                        .touchTarget(vertical: 6)
                }
                // 1.3.2.007：按压反馈是新版 PressableButtonStyle（0.97 + opacity 0.85）；
                // 热区不动（.005 已做 48pt）。
                .buttonStyle(PressableButtonStyle())
            }
        }
        // 胶囊滑动只绑在 viewTeam 这个状态上（iOS.docx §4.1：动画绑具体状态，不绑父容器）；
        // 减弱动态效果时 animation 传 nil，胶囊直接跳过去、不滑动。
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: store.viewTeam)
    }

    private var monthNavigator: some View {
        HStack {
            Button {
                // 1.3.2.007：箭头点按不用大跨度横甩，跳页 + 20pt 轻移 + 交叉淡入（见 jumpToMonth）。
                jumpToMonth(max(pageRange.lowerBound, pageIndex - 1), direction: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
                    .background(AppStyle.surface1)
                    .clipShape(Circle())
                    // 1.3.2.005（方案 §3.3）：36pt 圆按钮，透明留白扩到 48pt，视觉不变。
                    .touchTarget(vertical: 6, horizontal: 6)
            }
            // 1.3.2.007：按压反馈是新版 PressableButtonStyle（0.97 + opacity 0.85）；
            // 热区不动（.005 已做 48pt）。
            .buttonStyle(PressableButtonStyle())
            Spacer()
            Text(pagerTitle)
                .appFont(size: 20, weight: 700).monospacedDigit()
                // 标题视差（1.3.2.007，整改提示词 §3.3）：拖拽时以网格位移 0.5 倍同向移动、
                // opacity 随进度 1→0.5；跳页时 titleDim 让它 0.5→1 淡入恢复。
                .offset(x: titleParallaxOffset)
                .opacity(titleParallaxOpacity * titleDim)
            Button {
                goToToday()
            } label: {
                Text("今天")
                    .appFont(size: AppFont.bodySmall)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppStyle.surface1)
                    .cornerRadius(14)
                    // 1.3.2.005（方案 §3.3）：小 pill 只有约 31pt 高，透明留白扩到 48pt。
                    .touchTarget(vertical: 9)
            }
            // 1.3.2.007：按压反馈是新版 PressableButtonStyle（0.97 + opacity 0.85）；
            // 热区不动（.005 已做 48pt）。
            .buttonStyle(PressableButtonStyle())
            Spacer()
            Button {
                // 1.3.2.007：箭头点按不用大跨度横甩，跳页 + 20pt 轻移 + 交叉淡入（见 jumpToMonth）。
                jumpToMonth(min(pageRange.upperBound - 1, pageIndex + 1), direction: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
                    .background(AppStyle.surface1)
                    .clipShape(Circle())
                    // 1.3.2.005（方案 §3.3）：36pt 圆按钮，透明留白扩到 48pt，视觉不变。
                    .touchTarget(vertical: 6, horizontal: 6)
            }
            // 1.3.2.007：按压反馈是新版 PressableButtonStyle（0.97 + opacity 0.85）；
            // 热区不动（.005 已做 48pt）。
            .buttonStyle(PressableButtonStyle())
        }
    }

    /// 当前页的标题，如“2027年2月”（跟着滑页走，不用等网络；年份纯数字不带逗号）。
    private var pagerTitle: String {
        let ym = yearMonth(from: pageIndex)
        return DateUtil.yearMonthTitle(year: ym.year, month: ym.month)
    }

    // MARK: 日历滑页（原生分页，跟着手指走）

    /// 周几行（固定在日历上方，不跟月份滑动）：日、六绿色，其余深色，与参考图一致。
    /// 周一为每周首日时，顺序从周一开始（1.2.7.001）。
    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(Array(weekdayTitles.enumerated()), id: \.offset) { i, title in
                Text(title)
                    .appFont(size: AppFont.caption, weight: 400)
                    .foregroundColor(weekdayTitles[i] == "日" || weekdayTitles[i] == "六" ? .green : .primary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    /// 周几标题：默认日开头；周一首日时从周一开始。
    private var weekdayTitles: [String] {
        store.calendarDisplay.mondayFirst
            ? ["一", "二", "三", "四", "五", "六", "日"]
            : ["日", "一", "二", "三", "四", "五", "六"]
    }

    private var monthPager: some View {
        VStack(spacing: 4) {
            // 周几固定在最上面，不跟月份一起滑（原来在每页里，滑走就没了）。
            weekdayHeader
            // 240 页 TabView：每页固定高（外框总高不变），行距按行数自适应。
            // 滑页时不再重新布局、不再因周数不同伸缩，根治掉帧与页边忽大忽小。
            // 月份数据走 store.monthFor：有缓存直接取，没缓存本地 8 天一轮算好缓存起来，
            // 滑页时不再现算、不再发网络请求。
            TabView(selection: $pageIndex) {
                ForEach(pageRange, id: \.self) { idx in
                    let ym = yearMonth(from: idx)
                    MonthPageView(
                        year: ym.year, month: ym.month,
                        preloadedDays: preloadedGrids[idx],
                        isSelected: { selectedDay?.date == $0 },
                        onSelectDay: { day in
                            selectedDay = day
                            showDayDetail = true
                        },
                        onSelectAdjacentMonth: { y, m in
                            // 1.3.2.007：邻月格点按也是跳页，走同一个轻移 + 淡入（见 jumpToMonth）。
                            let target = Self.monthIndex(year: y, month: m)
                            jumpToMonth(target, direction: target > pageIndex ? 1 : -1)
                        },
                        flashDate: todayFlashDate
                    )
                    .tag(idx)
                    // 标题视差取进度（1.3.2.007）：每页把自己在 monthPager 坐标系里的
                    // minX + 页宽报上来，父视图按当前页位移算标题的 0.5 倍视差。
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: PageOffsetKey.self,
                                value: [idx: PageGeom(minX: geo.frame(in: .named("monthPager")).minX, width: geo.size.width)]
                            )
                        }
                    )
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: calendarGridHeight)
            // 1.1.5：裁剪——每页内容绝不漏到邻页上（重叠的最后一道保险）。
            .clipped()
            // 标题视差的坐标系：页的 minX 在这个坐标系里静止时是 0，拖拽时就是位移。
            .coordinateSpace(name: "monthPager")
            // 箭头点按切月过渡（1.3.2.007，iOS.docx §3.1）：跳页 + 20pt 轻移 + 交叉淡入；
            // 拖拽滑月时这里是 0/1，不动，原生 TabView 自己跟手。
            .offset(x: monthShift)
            .opacity(monthOpacity)
            // 标题视差（1.3.2.007，整改提示词 §3.3）：拖拽时标题以当前页位移的 0.5 倍
            // 同向移动，opacity 随进度 1→0.5；直接写状态、不包动画，1:1 linear 跟手。
            // 减弱动态效果时不做视差；落定回位动画期间（titleReturning）不接新进度。
            .onPreferenceChange(PageOffsetKey.self) { offsets in
                guard !reduceMotion, !titleReturning else { return }
                guard let geom = offsets[pageIndex], geom.width > 0 else {
                    titleParallaxOffset = 0
                    titleParallaxOpacity = 1
                    return
                }
                let progress = min(abs(geom.minX) / geom.width, 1)
                titleParallaxOffset = geom.minX * 0.5
                titleParallaxOpacity = 1 - 0.5 * progress
            }
            if store.isLoadingMonth {
                ProgressView("正在加载…")
                    .padding(.top, 8)
            } else if store.viewTeam != store.myTeam {
                Text("看的是 \(store.viewTeam)班的排班（基础 8 天一轮；我和这个班调过、顶过岗的日子按调班后显示）。调班/请假只能改自己班的日历。")
                    .appFont(size: AppFont.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(12)
        .background(AppStyle.surface1)
        .cornerRadius(16)
    }

    /// 汇总与记录看的月份：直接取当前页那份（缓存或本地算，秒出，不等网络）。
    /// 1.1.5：跟 pageIndex 走，不跟 store.currentYearMonth——setCurrentMonth 现在是
    /// 落定 0.4 秒后才跑，跟 store 走汇总会比网格慢半拍。
    private var displayedMonth: MonthSchedule? {
        let ym = yearMonth(from: pageIndex)
        return store.monthFor(year: ym.year, month: ym.month)
    }

    // MARK: 月度汇总

    /// 1.1.3：删掉「双班 X 天」，改成「三薪 X 天」「加班 X 天」，
    /// 取当月工资算法里的 tripleDays / overtimeDays（12 月是三薪 0 天、加班 1 天）；
    /// 只在看自己班且算得出时显示数字，算不出（输入没到齐）先显示“—”，输入到了重画。
    /// 其他几项（应出勤、实际出勤、请假、休息）不动。
    /// 第 41 条（2026-11-26）：应出勤后面加「基本天数 N 天」（取当月 BASIC_DAYS，11 月 21 天），随月份变。
    private var summaryLine: some View {
        Group {
            if let stats = displayedMonth?.stats {
                Text(summaryText(stats: stats))
                    .appFont(size: AppFont.bodySmall).monospacedDigit()
                    .multilineTextAlignment(.center)
                    .padding(AppStyle.cardPadding)
                    .frame(maxWidth: .infinity)
                    .background(AppStyle.surface1)
                    .cornerRadius(AppStyle.cardRadius)
            }
        }
    }

    private func summaryText(stats: MonthStats) -> String {
        // 1.1.5：跟当前页走（见 displayedMonth），不跟 store.currentYearMonth。
        let ym = yearMonth(from: pageIndex)
        var triple = "—"
        var overtime = "—"
        if let info = store.triplePayInfo(year: ym.year, month: ym.month) {
            triple = formatDays(info.tripleDays)
            overtime = formatDays(info.overtimeDays)
        }
        // 第 44 条（2026-11-26）：应出勤是排班算的出勤（基础轮班天数，
        // PayCalc.countBaseWork：数 baseShift 不是休息的天数，调班请假不影响），
        // 基本天数是法定口径（PayCalc.basicDays，与工资页同表），两个数不一样。
        // 之前应出勤那格误用了 stats.basicDays（那是法定基本天数），10 月/11 月
        // 和基本天数撞成两个一样的数（18/18、21/21）。
        let baseWorkDays = PayCalc.countBaseWork(yearDays: displayedMonth?.days ?? [], year: ym.year, month: ym.month)
        let statutoryBasicDays = PayCalc.basicDays(year: ym.year, month: ym.month)
        return "当月应出勤 \(baseWorkDays) 天 · 基本天数 \(statutoryBasicDays) 天 · 实际出勤 \(MoneyUtil.int(stats.actualShifts)) 个班 · 三薪 \(triple) 天 · 加班 \(overtime) 天 · 请假 \(MoneyUtil.int(stats.leaveDays)) 天 · 休息 \(MoneyUtil.int(stats.restDays)) 天"
    }

    /// 天数显示：整数不带小数（如 0、1），小数保留 1 位。
    private func formatDays(_ value: Double) -> String {
        if value == value.rounded() { return "\(Int(value))" }
        return String(format: "%.1f", value)
    }

    // MARK: 调班 / 请假记录

    /// 当前页那年那月（跟滑页走，不等网络）。
    private var displayedYearMonth: (year: Int, month: Int) { yearMonth(from: pageIndex) }

    /// 当前页那月的调班记录（月缓存里读）：到了就是数组，没到是 nil（显示“正在加载…”）；
    /// 看别的班时没有自己的记录，直接给 []（对方的调班不动，见 overlayPartnerRecords）。
    /// 订阅 recordsVersion：预取回来新数据就重画，不用等整月刷新。
    private var displayedSwaps: [SwapRecord]? {
        let _ = store.recordsVersion
        guard store.viewTeam == store.myTeam else { return [] }
        let ym = displayedYearMonth
        return store.swapsFor(year: ym.year, month: ym.month)
    }
    /// 当前页那月的请假记录（同上）。
    private var displayedLeaves: [LeaveRecord]? {
        let _ = store.recordsVersion
        guard store.viewTeam == store.myTeam else { return [] }
        let ym = displayedYearMonth
        return store.leavesFor(year: ym.year, month: ym.month)
    }
    /// 当前页那月的调班记录并成“替班日 + 还班日”一条（跟原来 mergedSwapRows 同算法，
    /// 只改数据源：原来读 store.swaps（落定刷新才换月），现在读当前页的月缓存）。
    private var displayedSwapRows: [SwapRow] { mergedRows(for: displayedSwaps ?? []) }

    /// 调班/请假数据是否还在等（月缓存没到）：骨架延迟 150ms 的触发条件。
    private var isRecordsLoading: Bool { displayedSwaps == nil || displayedLeaves == nil }

    /// 骨架延迟 150ms（1.3.2.006）：加载开始后 150ms 再现骨架，数据快回来就不闪；
    /// 加载结束立刻消失；视图消失时取消任务。Task 注明 @MainActor，置 @State 安全。
    private func scheduleRecordsSkeleton() {
        recordsSkeletonTask?.cancel()
        recordsSkeletonTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            showRecordsSkeleton = true
        }
    }
    private func hideRecordsSkeleton() {
        recordsSkeletonTask?.cancel()
        recordsSkeletonTask = nil
        showRecordsSkeleton = false
    }

    private var recordsSection: some View {
        // 1.3.2.004（老爷 2026-11-28 11:33 亲口定）：这张卡一直存在，不再没记录就藏掉——
        // 本月没有调班请假就显示“本月没有调班请假”，数据没到先显示“正在加载…”。
        // 卡的高度不再忽有忽无，滑页时页面不再往上跳。数据跟当前页走（月缓存，预加载 21 页）。
        VStack(alignment: .leading, spacing: 8) {
            Text("本月调班 / 请假")
                .appFont(size: AppFont.headline, weight: 600)
            if isRecordsLoading {
                // 骨架屏（1.3.2.005，方案 §4.4/§5.4）：两行灰条，按记录行的样子排
                //（日期 + 内容），不转圈、不闪烁；数据到了直接换真内容。
                // 1.3.2.006：加载开始 150ms 后才出现，数据快回来时不闪骨架；
                // 150ms 内数据到了，这两行就不出现，卡里只剩标题。
                if showRecordsSkeleton {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            SkeletonBar(width: 86, height: 14)
                            SkeletonBar(width: 150, height: 14)
                        }
                        HStack(spacing: 8) {
                            SkeletonBar(width: 86, height: 14)
                            SkeletonBar(width: 110, height: 14)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else if displayedSwapRows.isEmpty && (displayedLeaves ?? []).isEmpty {
                Text("本月没有调班请假")
                    .appFont(size: AppFont.bodySmall)
                    .foregroundColor(.secondary)
            } else {
                ForEach(displayedSwapRows, id: \.key) { row in
                    swapRow(row)
                }
                ForEach(displayedLeaves ?? [], id: \.date) { leave in
                    HStack(alignment: .top) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text(leave.date)
                            .appFont(size: AppFont.bodySmall)
                        Text(leave.type ?? "请假")
                            .appFont(size: AppFont.bodySmall)
                            .foregroundColor(.red)
                        Spacer()
                        if let note = leave.note, !note.isEmpty {
                            Text(note)
                                .appFont(size: AppFont.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(AppStyle.cardPadding)
        .background(AppStyle.surface1)
        .cornerRadius(AppStyle.cardRadius)
        // 骨架延迟 150ms（1.3.2.006）：加载开始计时、结束立刻消失、消失时取消任务。
        .onChange(of: isRecordsLoading) { loading in
            if loading { scheduleRecordsSkeleton() } else { hideRecordsSkeleton() }
        }
        .onAppear {
            if isRecordsLoading { scheduleRecordsSkeleton() }
        }
        .onDisappear {
            hideRecordsSkeleton()
        }
    }

    /// 数据更新时间（1.3.2.005，方案 §9 第四条）：本地缓存最后一次成功取数的时间；
    /// 冷启动读磁盘缓存时是缓存的写入时间。没取到过就不显示。
    private var syncTimeFooter: some View {
        Group {
            if let at = store.lastSyncAt {
                Text("数据更新于 \(Self.syncTimeFormatter.string(from: at))")
                    .appFont(size: AppFont.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private static let syncTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// 调班记录按“替班日 + 还班日”并成一条：coverDate / paybackDate 互相指向的算一对。
    private struct SwapRow: Identifiable {
        let key: String
        let records: [SwapRecord]
        var id: String { key }
    }

    private func mergedRows(for swaps: [SwapRecord]) -> [SwapRow] {
        let sorted = swaps.sorted { $0.date < $1.date }
        var byDate: [String: SwapRecord] = [:]
        for s in sorted { byDate[s.date] = s }
        var visited = Set<String>()
        var rows: [SwapRow] = []
        for s in sorted {
            if visited.contains(s.date) { continue }
            visited.insert(s.date)
            var group = [s]
            for linkedDate in [s.coverDate, s.paybackDate].compactMap({ $0 }) {
                if let other = byDate[linkedDate], !visited.contains(linkedDate) {
                    visited.insert(linkedDate)
                    group.append(other)
                }
            }
            // 反向指向：别人的 coverDate/paybackDate 指向我，也并进来。
            for other in sorted where !visited.contains(other.date) {
                if other.coverDate == s.date || other.paybackDate == s.date {
                    visited.insert(other.date)
                    group.append(other)
                }
            }
            group.sort { $0.date < $1.date }
            rows.append(SwapRow(key: group.map(\.date).joined(separator: "+"), records: group))
        }
        return rows
    }

    private func swapRow(_ row: SwapRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(row.records, id: \.date) { record in
                HStack(alignment: .top) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                    Text(record.date)
                        .appFont(size: AppFont.bodySmall)
                    Text("调成 \(record.shift ?? "")")
                        .appFont(size: AppFont.bodySmall)
                    if let partner = record.partner, !partner.isEmpty {
                        Text("与 \(partner)班对调")
                            .appFont(size: AppFont.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if let note = record.note, !note.isEmpty {
                        Text(note)
                            .appFont(size: AppFont.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            if row.records.count > 1,
               let payback = row.records.compactMap({ $0.paybackDate ?? $0.coverDate }).first {
                Text("还班日：\(payback)")
                    .appFont(size: AppFont.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 16)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 一页月历

/// 滑页里的一页：只画某年某月的网格。数据走 store.monthFor——有缓存用缓存，
/// 没缓存先按本地 8 天一轮算顶上（秒出、不闪白）；1.1.5 起取到的数据先存快照，
/// 滑动中只读快照，真数据到了也不在滑动中换页（等落定刷新或数据变更时才重拍）。
struct MonthPageView: View {
    @EnvironmentObject private var store: AppStore
    let year: Int
    let month: Int
    /// 父视图预加载好的本页格子（前后 10 个月共 21 页）：有就直接用，不拍快照、
    /// 不等出现时现算；没有（窗口外、刚翻过来的新页）才走原来的快照兜底。
    /// 1.3.2.004（老爷 2026-11-28 11:32 亲口定预加载 21 页）。
    let preloadedDays: [(day: DaySchedule, kind: GridDayKind)]?
    let isSelected: (String) -> Bool
    let onSelectDay: (DaySchedule) -> Void
    /// 点到上月/下月补的日期时跳到对应月。
    let onSelectAdjacentMonth: (Int, Int) -> Void
    /// 点“今天”后要微闪的日期（1.3.2.007，iOS.docx §3.2）：等于今天的格子闪一次，平时是 nil。
    /// 注意：let 常量带默认值时不能在 init 里再赋值（会报“只能初始化一次”），
    /// 所以这里不写默认值，默认值放在下面显式 init 的参数上（flashDate: String? = nil）。
    let flashDate: String?

    /// 显式初始化（1.3.2.007：合成的 memberwise init 在这台工具链上不认新加的
    /// flashDate 参数——疑似 @EnvironmentObject store 干扰了合成；显式写死最稳妥）。
    init(
        year: Int,
        month: Int,
        preloadedDays: [(day: DaySchedule, kind: GridDayKind)]?,
        isSelected: @escaping (String) -> Bool,
        onSelectDay: @escaping (DaySchedule) -> Void,
        onSelectAdjacentMonth: @escaping (Int, Int) -> Void,
        flashDate: String? = nil
    ) {
        self.year = year
        self.month = month
        self.preloadedDays = preloadedDays
        self.isSelected = isSelected
        self.onSelectDay = onSelectDay
        self.onSelectAdjacentMonth = onSelectAdjacentMonth
        self.flashDate = flashDate
    }

    /// 一格的身份：上月补的 / 本月 / 下月补的（点上月/下月补的跳到对应月）。
    enum GridDayKind { case leading, current, trailing }

    /// 1.1.5：本页的数据快照——出现时从 store 取一次存在 @State 里，滑动中只读快照，
    /// store 再怎么写（prefetch 回来、setCurrentMonth、refresh）都动不了正在滑的这一页。
    /// 只在三处重拍：刚出现（.task）、日历数据真变了（store.calendarVersion +1：
    /// 调班/请假保存、刷新成功）、换了班组（viewTeam 变了）。
    /// 快照没拍好之前的第一帧先用 live 的 gridDays 顶上（只此一帧，不在滑动中）。
    @State private var snapDays: [(day: DaySchedule, kind: GridDayKind)] = []
    @State private var snapLoaded = false

    private func takeSnapshot() {
        snapDays = gridDays
        snapLoaded = true
    }

    /// 整页的格子（上月补 + 本月 + 下月补，拼满整周再补满 42 格）：数据走 store.monthFor
    ///（缓存，只算一次）。格子总数恒为 42（6 周 × 7），行数恒为 6。
    /// 1.1.4：原来是 LazyVGrid，滑页中预取回来写 @Published、视图重算，
    /// LazyVGrid 懒加载重排、格子错位。改成固定 VStack + HStack：
    /// 每格固定 64pt、7 列写死，格子永远在固定位置。
    /// 1.3.2.004：格子算法抽成静态纯函数——父视图预加载 21 页时调这一份，
    /// 本页兜底也调这一份，不另写一份算法（两份算法迟早对不上）。
    /// 1.3.2.006（老爷 2026-11-28 12:53 亲口令「行距不一样，你改改我看看吧」）：
    /// 固定 6 行——补满整周后不到 42 格，再从下月开头多补整周，kind 仍是 .trailing
    ///（暗色、点按跳到下月，跟现有尾随格一致）。5 行的月多出一行下月开头的暗色日期，
    /// 这是固定 6 行的正常样子，先让老爷看效果，不要藏起来。
    static func buildGridDays(year: Int, month: Int, store: AppStore) -> [(day: DaySchedule, kind: GridDayKind)] {
        let prev = month == 1 ? (year - 1, 12) : (year, month - 1)
        let next = month == 12 ? (year + 1, 1) : (year, month + 1)
        let mondayFirst = store.calendarDisplay.mondayFirst
        let firstWeekday = DateUtil.firstWeekday(year: year, month: month)
        // 每月第一周前面补上月末尾几天（周一为首日时，前导数按周一偏移）。
        let leading = mondayFirst ? (firstWeekday + 6) % 7 : firstWeekday
        var result: [(day: DaySchedule, kind: GridDayKind)] = []
        if leading > 0 {
            let prevMonth = store.monthFor(year: prev.0, month: prev.1)
            result += (prevMonth.days ?? []).suffix(leading).map { ($0, GridDayKind.leading) }
        }
        let current = store.monthFor(year: year, month: month)
        result += (current.days ?? []).map { ($0, GridDayKind.current) }
        // 每月最后一周后面补下月开头几天，补满整周。
        let days = DateUtil.daysInMonth(year: year, month: month)
        let remainder = (leading + days) % 7
        let trailing = remainder == 0 ? 0 : 7 - remainder
        let nextMonth = store.monthFor(year: next.0, month: next.1)
        var usedTrailing = 0
        if trailing > 0 {
            result += (nextMonth.days ?? []).prefix(trailing).map { ($0, GridDayKind.trailing) }
            usedTrailing = trailing
        }
        // 补满 42 格（6 周）：每次多补一周，跳过已用掉的尾随天数。
        // 常见是 35 格补一周；28 格的月（周一为首日的平年 2 月，如 2027-02）补两周。
        // 下月至少 28 天，已用最多 6 + 7，取 7 格一定够；guard 是防万一的兜底。
        while result.count < 42 {
            let extra = (nextMonth.days ?? []).dropFirst(usedTrailing).prefix(7)
            guard extra.count == 7 else { break }
            result += extra.map { ($0, GridDayKind.trailing) }
            usedTrailing += 7
        }
        return result
    }

    private var gridDays: [(day: DaySchedule, kind: GridDayKind)] {
        Self.buildGridDays(year: year, month: month, store: store)
    }

    var body: some View {
        // 1.3.2.006（老爷 2026-11-28 12:53 亲口令「行距不一样，你改改我看看吧」）：
        // 固定 6 行、行距恒定 6pt——以前 5 行月行距 23.5pt、6 行月 6pt，慢拖时两页
        // 行错位；现在所有月都是 42 格、同一行距，行位置严丝合缝。5 行的月底部多一
        // 行下月开头的暗色日期（.trailing，跟现有尾随格一样），先让老爷看效果。
        // 关键：行数从快照 snapDays 里算（days.count / 7，恒为 6），快照在滑动中一动不动，
        // 所以行距在动画中途绝不变；快照 + 防抖换月 + 裁剪三件不变。
        // 周几行已抽到 TabView 外面固定不动，这里只画日期网格。
        // 订阅 payInputsVersion：工资输入到齐时底部统计（三薪 X 天 / 加班 X 天）要重算，
        // 日历得重画（之前没订阅，输入到了也不重画，统计要等别的状态变了才冒出来）。
        // 三薪标本身（第 33 条）只按法定表，不依赖工资输入；网格本身（snapDays）是快照，滑动中不动。
        let _ = store.payInputsVersion
        // 1.3.2.004：父视图预加载好的格子直接用（21 页窗口内）；窗口外才走快照兜底。
        let days = preloadedDays ?? (snapLoaded ? snapDays : gridDays)
        // 格子恒为 42 格，行数恒为 6（days.count / 7）；行数从快照算，滑动中不动。
        let weeks = max(1, days.count / 7)
        VStack(spacing: calendarRowSpacing(weeks: weeks)) {
            ForEach(0..<weeks, id: \.self) { w in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { c in
                        let idx = w * 7 + c
                        if idx < days.count {
                            gridCell(day: days[idx].day, kind: days[idx].kind)
                        } else {
                            Color.clear.frame(height: calendarCellHeight)
                        }
                    }
                }
            }
        }
        // 1.1.5：裁剪 + 快照——内容不出本页；出现时拍一次快照，数据真变了
        //（calendarVersion / 换班组）才重拍，滑动中快照一动不动。
        // 2026-11-28 慢滑卡顿修：整格 42 个 DayCell（每格十几个子视图）拼成一层
        //（.drawingGroup），慢拖时合成器每帧只挪一层、不再逐个拼 400 多个子视图；
        // 快滑本来就跟手，慢拖才看得出差别。点按不受影响（drawingGroup 只管渲染，
        // 不动命中测试），选中态变了整格重栅格化一次即可。
        .clipped()
        .drawingGroup()
        // 1.3.2.004：有预加载的格子就不用拍快照（父视图算好直接给，不再出现时现算、
        // 再重画一遍）；只有窗口外的页才走原来的快照兜底。
        .task { if preloadedDays == nil { takeSnapshot() } }
        .onChange(of: store.calendarVersion) { _ in if preloadedDays == nil { takeSnapshot() } }
        .onChange(of: store.viewTeam) { _ in if preloadedDays == nil { takeSnapshot() } }
    }

    /// 一格：按身份给不同的点按行为（本月点开详情，上月/下月补的跳到对应月）。
    /// 「当月显示上下月」关了：上月/下月补的格子留空（占位不变，布局不抖），点不了。
    /// maxWidth 让格子在 HStack 里均分 7 列（原来 LazyVGrid 的 .flexible() 就是这个作用）。
    /// 1.3.2.007：格子用 Button + DayCellPressStyle（按下压暗至 0.75，0.08s；抬起 0.18s 恢复）——
    /// 以前只有 onTapGesture、没有任何按压反馈。Button 的按压态与 TabView 滑页共存（系统在
    /// 拖动开始时取消按压），不会抢滑页手势。
    @ViewBuilder
    private func gridCell(day: DaySchedule, kind: GridDayKind) -> some View {
        if (kind == .leading || kind == .trailing) && !store.calendarDisplay.showAdjacentMonths {
            Color.clear.frame(height: calendarCellHeight)
                .frame(maxWidth: .infinity)
        } else {
            switch kind {
            case .leading:
                Button { onSelectAdjacentMonth(prevYearMonth.year, prevYearMonth.month) } label: {
                    DayCell(day: day, isToday: false, isSelected: false, isAdjacent: true)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DayCellPressStyle())
            case .current:
                Button { onSelectDay(day) } label: {
                    DayCell(day: day, isToday: day.date == DateUtil.string(from: Date()), isSelected: isSelected(day.date), isTriplePay: tripleDates.contains(day.date), isFlashing: flashDate == day.date)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DayCellPressStyle())
            case .trailing:
                Button { onSelectAdjacentMonth(nextYearMonth.year, nextYearMonth.month) } label: {
                    DayCell(day: day, isToday: false, isSelected: false, isAdjacent: true)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DayCellPressStyle())
            }
        }
    }

    /// 本月三薪日（第 33 条，2026-11-26）：只按法定节假日表标，不管本班上班还是休息——
    /// 2027-01-01 元旦 B班休息也要标「三薪」。不走工资算法的 tripleDates
    ///（那份只含实际上班的法定日，是工资口径，底部「三薪 X 天」仍用它，不动）。
    /// 法定表是全队的事实，看哪个班都标；也不依赖工资输入，输入没到齐也照常标。
    private var tripleDates: Set<String> {
        Set((monthData.days ?? []).map(\.date).filter { PayCalc.isStatutoryDay($0) })
    }

    private var monthData: MonthSchedule {
        store.monthFor(year: year, month: month)
    }

    /// 上月年月 / 下月年月。
    private var prevYearMonth: (year: Int, month: Int) {
        month == 1 ? (year - 1, 12) : (year, month - 1)
    }
    private var nextYearMonth: (year: Int, month: Int) {
        month == 12 ? (year + 1, 1) : (year, month + 1)
    }
}

// MARK: - 日期格

/// 日期格（参考图样式）：阳历大数字 + 阴历/节气/节日小字 + 班次色块；
/// 法定节假日左上角绿“假”、调休上班日红“班”；当天描绿边。
/// 关键：所有班次的 pill 都是同一固定高度 28pt、通栏、圆角；
/// 双班时在同一个 28pt 高度里上下叠两个 13pt 小 pill，不撑高格子。
/// 整格固定 64pt（日期行 26 + 间距 2 + pill 28 + 上下边距 8），行距自适应靠网格间距调。
/// 1.1.3：阳历数字 18→16pt（收一收、别太高）；日期与色块间距 4→2pt；
/// 1.2.2：窄屏（<400pt，如 iPhone 15 的 393pt）阳历数字 16→15pt + 缩放兜底，
/// 左右两列 12/9→11/8——之前两位数的号在窄屏上被截成「…」。
/// 请假「假」标从号数旁边移到左列、和法定「假/班」上下叠放（之前号数+红标太宽、压着右边阴历字）；
/// 三薪日：同一个 28pt 色块里上下两行——上面班次名、下面半透明白字「三薪」，
/// 和色块重叠、不另起一行；法定「假/班」保持原样，两套标法不混。
struct DayCell: View {
    @EnvironmentObject private var store: AppStore
    /// 1.2.8.001：上下月补的日期在深色下 0.5 透明太暗、看着发虚，深色放宽到 0.65。
    @Environment(\.colorScheme) private var colorScheme

    let day: DaySchedule
    let isToday: Bool
    let isSelected: Bool
    /// 上月/下月补进来的日期：灰色显示，点后跳到对应月。
    var isAdjacent: Bool = false
    /// 三薪日（工资算法里 tripleDays 的那几天）：色块里加一行半透明「三薪」。
    var isTriplePay: Bool = false
    /// 点“今天”后的微闪（1.3.2.007，iOS.docx §3.2）：目标格一次底色微闪，不放大。
    var isFlashing: Bool = false
    /// 微闪的不透明度（1 → 0，0.55s easeOut）。
    @State private var flashOpacity: Double = 0
    /// 减弱动态效果：班次标签变化只做 0.15s 淡入、不缩放；微闪也取消。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pillHeight: CGFloat = 28

    /// 班次标签的身份（1.3.2.007）：换班组时 pill 内容变了就换身份，触发 0.2s 缩放 + 交叉淡入。
    private var pillKey: String { "\(day.shift)|\(day.isRest)|\(isTriplePay)" }

    /// 微闪：不透明度从 1 起、0.55s easeOut 淡到 0；减弱动态效果时不闪。
    private func startFlash() {
        guard !reduceMotion else { return }
        flashOpacity = 1
        withAnimation(.easeOut(duration: 0.55)) {
            flashOpacity = 0
        }
    }

    /// 日历显示设置（1.2.7.001）：法定节假日/农历显隐走这里。
    private var display: CalendarDisplaySettings { store.calendarDisplay }

    /// 当天的法定/调休标：服务端节假日数据优先（已按官方通知修正），
    /// 没有服务端数据时用内置 ChineseCalendar 的标。
    /// kind：legal → 假（放假），rest → 假（放假），workday → 班（调休上班）。
    private var holidayMark: String? {
        if let h = store.holiday(for: day.date) {
            switch h.kind {
            case "legal", "rest": return "假"
            case "workday": return "班"
            default: return nil
            }
        }
        if let mark = extra.mark {
            return mark == .holiday ? "假" : "班"
        }
        return nil
    }

    /// 1.2.2：阳历数字字号按屏宽自适应——iPhone 15 标准版屏宽只有 393pt，
    /// 日期行里左 11pt 假/班列 + 右 8pt 阴历列是写死的，中间只剩约 24pt，
    /// 两位数的号在 16pt 下会被截成「…」；窄屏（<400pt）用 15pt，
    /// 宽屏保持 16pt；再加 lineLimit(1) + minimumScaleFactor(0.75) 兜底，绝不截断。
    /// 屏宽只读一次（窄屏 <400pt 用 15pt，否则 16pt）；原来每格每次 body 都读一次 UIScreen.main.bounds。
    private static let isNarrowScreen = UIScreen.main.bounds.width < 400
    private var dayNumberFontSize: CGFloat {
        Self.isNarrowScreen ? 15 : 16
    }

    /// 当天的阴历/节气/节日/假班信息（查表 + 中国日历算，带缓存，渲染时不重算）。
    private var extra: ChineseCalendar.DayInfo {
        ChineseCalendar.info(for: day.date)
    }

    /// 日历格里显示的阴历/节日小字（1.1.5）：带「节」的节日名去掉「节」只留两个字
    ///（劳动节→劳动、儿童节→儿童、妇女节→妇女、教师节→教师、国庆节→国庆、
    /// 圣诞节→圣诞、情人节→情人、愚人节→愚人、万圣节→万圣、元宵节→元宵、
    /// 中元节→中元）。本来就两个字的（元旦、清明、端午、中秋、春节、除夕）不动；
    /// 节气名（冬至、小寒等）没有「节」字，也不动。只改这里的显示，
    /// 不动 ChineseCalendar 的原始数据（当天详情等别处不受影响）。
    private var displayLunarText: String {
        let t = extra.lunarText
        if t.count == 3 && t.hasSuffix("节") { return String(t.dropLast()) }
        return t
    }

    var body: some View {
        VStack(spacing: 2) {
            // 日期行（三栏，互不重叠）：左 法定假/班 + 请假标上下叠（11pt，没有留空）
            // + 中 阳历大数字（居中） + 右 阴历/节气/节日小字（竖排两字，节气/节日红字、阴历灰字）。
            // 请假标放左列：之前跟在号数后面，号数+红标比中间栏宽、压着右边阴历字（11-02、11-03 就是这么叠上的）。
            // 1.2.2：左列 12→11、右列 9→8，给中间阳历数字多腾 2pt（窄屏两位数的号不再截成「…」）。
            HStack(alignment: .top, spacing: 1) {
                VStack(alignment: .leading, spacing: 1) {
                    // 法定假/班标（1.2.7.001）：显示开关关了就不显示；服务端节假日数据优先。
                    if display.showHolidays, let mark = holidayMark, !isAdjacent {
                        if mark == "假" {
                            // 1.1.5：放假的「假」用白色字体——白字得配绿底 pill 才看得见
                            //（原来是绿字无底；只改字色会白底白字看不见，所以底色跟着换成绿，
                            // 位置/大小/布局不动）。请假的「假」见下面，用红色字体。
                            Text("假")
                                .appFont(size: 9, weight: 700)
                                .foregroundColor(.white)
                                .padding(.horizontal, 1)
                                .padding(.vertical, 1)
                                .background(Color.green)
                                .cornerRadius(3)
                        } else {
                            Text("班")
                                .appFont(size: 9, weight: 700)
                                .foregroundColor(.red)
                        }
                    } else {
                        Color.clear.frame(width: 11, height: 9)
                    }
                    if day.onLeave == true && !isAdjacent {
                        // 1.1.5：请假的「假」用红色字体——红字配红底看不见，底色去掉变透明
                        //（位置/大小/布局不动，只换字色和底色，和放假的白字绿底区分开）。
                        Text("假")
                            .appFont(size: 8, weight: 700)
                            .foregroundColor(.red)
                            .padding(.horizontal, 2)
                            .padding(.vertical, 1)
                    }
                }
                .frame(width: 11, alignment: .leading)
                Text("\(day.dayNumber)")
                    .appFont(size: dayNumberFontSize, weight: isToday ? 700 : 600).monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundColor(isAdjacent ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .center)
                // 阴历/节气/节日小字（1.2.7.001）：显示农历关了就留空（占位不变，布局不抖）。
                VStack(spacing: 0) {
                    if display.showLunar {
                        ForEach(Array(displayLunarText.enumerated()), id: \.offset) { _, ch in
                            Text(String(ch))
                                .appFont(size: 9, weight: 400)
                                .foregroundColor(extra.isRedText ? .red : AppStyle.tinySecondary)
                        }
                    }
                }
                .frame(width: 8, alignment: .leading)
                .padding(.top, 1)
            }
            .frame(height: 26)

            // 班次 pill：固定 28pt；补的日期用班次色但半透明（班次色不变，只是淡一点）。
            // 三薪日：色块里上下两行——上面班次名、下面半透明白字「三薪」，和色块重叠，
            // 不另起一行、不占格子外的地方；双班三薪日上行两个班次并排、下行「三薪」。
            Group {
                if day.isDouble == true {
                    if isTriplePay && !isAdjacent {
                        VStack(spacing: 0) {
                            HStack(spacing: 2) {
                                ForEach(ShiftStyle.parts(of: day.shift), id: \.self) { part in
                                    Text(TeamInfo.shortName(part))
                                        .appFont(size: 10, weight: 700)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 15)
                                        .background(ShiftStyle.color(for: part))
                                        .cornerRadius(4)
                                }
                            }
                            Text("三薪")
                                .appFont(size: 9, weight: 700)
                                .foregroundColor(AppStyle.whiteText(opacity: 0.9))
                                .frame(maxWidth: .infinity)
                                .frame(height: 13)
                                .background(AppStyle.tripleScrim)
                        }
                        .frame(height: pillHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    } else {
                        VStack(spacing: 2) {
                            ForEach(ShiftStyle.parts(of: day.shift), id: \.self) { part in
                                Text(TeamInfo.shortName(part))
                                    .appFont(size: 10, weight: 700)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 13)
                                    .background(ShiftStyle.color(for: part))
                                    .cornerRadius(4)
                            }
                        }
                        .frame(height: pillHeight)
                    }
                } else if isTriplePay && !isAdjacent {
                    VStack(spacing: 0) {
                        Text(day.isRest ? "休" : TeamInfo.shortName(day.shift))
                            .appFont(size: 12, weight: 700)
                            .foregroundColor(day.isRest ? ShiftStyle.color(for: "休息") : .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 15)
                        Text("三薪")
                            .appFont(size: 9, weight: 700)
                            .foregroundColor(AppStyle.whiteText(opacity: 0.85))
                            .frame(maxWidth: .infinity)
                            .frame(height: 13)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: pillHeight)
                    .background(day.isRest ? ShiftStyle.background(for: "休息") : ShiftStyle.color(for: day.shift))
                    .cornerRadius(7)
                } else {
                    Text(day.isRest ? "休" : TeamInfo.shortName(day.shift))
                        .appFont(size: 12, weight: 700)
                        .foregroundColor(day.isRest ? ShiftStyle.color(for: "休息") : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: pillHeight)
                        .background(day.isRest ? ShiftStyle.background(for: "休息") : ShiftStyle.color(for: day.shift))
                        .cornerRadius(7)
                }
            }
            // 班次标签变化（1.3.2.007，iOS.docx §3.2）：换班组时标签快速轻微缩放加交叉淡入，
            // 0.2s easeInOut，不整块日历横移；减弱动态效果时只做 0.15s 淡入、不缩放。
            .id(pillKey)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
            .animation(reduceMotion ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.2), value: pillKey)
            .opacity(isAdjacent ? (colorScheme == .dark ? 0.65 : 0.5) : 1.0)
        }
        .padding(2)
        .frame(height: calendarCellHeight)
        .background(isSelected ? Color.blue.opacity(0.12) : Color.clear)
        .cornerRadius(8)
        // 今天格微闪（1.3.2.007，iOS.docx §3.2）：底色微闪一次，0.55s 淡出，不放大；
        // 描边那层在上面，不会被闪盖住。
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.22))
                .opacity(flashOpacity)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isToday ? Color.green : (isSelected ? Color.blue : Color.clear), lineWidth: isToday ? 2 : 1.5)
        )
        // 选中框切换（1.3.2.007，iOS.docx §3.3）：克制的高阻尼弹簧，禁止过冲。
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isSelected)
        .onChange(of: isFlashing) { flashing in
            if flashing { startFlash() }
        }
        .onAppear {
            if isFlashing { startFlash() }
        }
    }
}

/// 今日倒计时 + 实时工资（1.2.7）：只这个小视图每秒刷新（TimelineView 1 秒一格），不带动整页。
/// 上班前：距上班 + 已挣 ¥0.00 · 预估 ¥XXX；上班中：距下班 + 已挣实时涨 · 预估 ¥XXX；
/// 下班后：今日已下班 + 今日已挣 ¥XXX；休息/请假：今日休息/今日请假（钱那行不显示）。
private struct TodayLiveRow: View {
    let day: DaySchedule
    let earlyRate: Double
    let midRate: Double
    let inputs: PayCalc.DayEstimateInputs
    /// 钱显隐（第 29 条补充规矩）：只有开了工资权限才显示「已挣 · 预估」那行；倒计时不是钱，一直显示。
    let showMoney: Bool

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            let now = context.date
            let today = DateUtil.calendar.startOfDay(for: now)
            let state = PayCalc.todayLiveState(
                shift: day.shift, onLeave: day.onLeave == true, day: today, now: now,
                earlyRate: earlyRate, midRate: midRate, inputs: inputs
            )
            VStack(alignment: .leading, spacing: 2) {
                // 2026-11-28 慢滑卡顿修：倒计时每秒重画一次，上面挂 .fadeIn 等于每秒
                // 多走一次离屏模糊；字本来就是等宽、宽度不动，模糊入场效果在每秒刷新的
                // 文字上根本看不出来，直接去掉，只留等宽数字。
                Text(countdownText(state: state, now: now))
                    .appFont(size: AppFont.bodySmall).monospacedDigit()
                    .foregroundColor(.white)
                if let money = moneyText(state: state) {
                    Text(money)
                        .appFont(size: AppFont.bodySmall).monospacedDigit()
                        .foregroundColor(AppStyle.whiteText(opacity: 0.75))
                }
            }
        }
    }

    /// 倒计时文案：距上班/下班 HH:MM:SS（秒数跟着走）。
    private func countdownText(state: PayCalc.TodayLiveState, now: Date) -> String {
        switch state {
        case .rest:
            return day.onLeave == true ? "今日请假" : "今日休息"
        case .before(let start, _):
            return "距上班 " + durationText(from: now, to: start)
        case .working(let end, _, _):
            return "距下班 " + durationText(from: now, to: end)
        case .between(let nextStart, _, _):
            return "距下一班 " + durationText(from: now, to: nextStart)
        case .done:
            return "今日已下班"
        }
    }

    /// 时长 HH:MM:SS（不足 1 小时也写 00:MM:SS，保持位数不动、不跳行）。
    private func durationText(from: Date, to: Date) -> String {
        let total = max(0, Int(to.timeIntervalSince(from)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    /// 钱那行：上班中/上班前显示已挣 + 预估；下班后显示今日已挣；休息/请假不显示。
    /// 三薪那天末尾带「（三薪）」，加班那天带「（加班）」。
    /// 没工资权限不显示这行（第 29 条补充规矩）。
    private func moneyText(state: PayCalc.TodayLiveState) -> String? {
        guard showMoney else { return nil }
        // 第 40 条：三薪/加班以后缀看当日种类（不是法定日就一定是三薪——超额的法定日转加班）。
        let suffix = inputs.isTriple ? "（三薪）" : (inputs.isOvertime ? "（加班）" : "")
        switch state {
        case .rest:
            return nil
        case .before(_, let total):
            return "已挣 ¥0.00 · 预估 \(MoneyUtil.money(total))\(suffix)"
        case .working(_, let earned, let total):
            return "已挣 \(MoneyUtil.money(earned)) · 预估 \(MoneyUtil.money(total))\(suffix)"
        case .between(_, let earned, let total):
            return "已挣 \(MoneyUtil.money(earned)) · 预估 \(MoneyUtil.money(total))\(suffix)"
        case .done(let total):
            return "今日已挣 \(MoneyUtil.money(total))\(suffix)"
        }
    }
}
