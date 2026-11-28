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

/// 排班页：原生月历。每个日期格里的班次 pill 都是同一固定高度（24pt、通栏圆角），
/// 修掉网页版“日班绿块占满整格、别的班只是短 pill”的 bug。
struct CalendarView: View {
    @Environment(AppStore.self) private var store: AppStore

    @State private var selectedDay: DaySchedule?
    @State private var showDayDetail = false
    /// 1.1.4：滑页刷新防抖任务（见 .onChange(of: pageIndex)）。
    @State private var refreshTask: Task<Void, Never>?
    /// 调班/请假卡骨架延迟 150ms 的在途任务（1.3.2.006）：加载开始后 150ms 再现骨架，
    /// 数据快回来就不闪；加载结束或视图消失时取消。
    @State private var recordsSkeletonTask: Task<Void, Never>?
    /// 调班/请假卡的骨架是否显示（同上，150ms 延迟后才置 true）。
    @State private var showRecordsSkeleton = false
    /// 今天格轻高亮（1.3.2.007，iOS.docx §3.2）：点“今天”后目标格一次微闪（边框/底色，不放大）。
    @State private var todayFlashDate: String? = nil
    @State private var todayFlashTask: Task<Void, Never>? = nil
    /// 年月快选弹窗（1.3.2.013）：点月份标题弹出，选年月直接跳过去。
    @State private var showMonthJump = false
    /// 减弱动态效果（重做，1.3.2.008）：月份切换只做 0.15s 淡入，不做位移、不做数字滚动。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // 滑页的页码 = 月份绝对序号（年*12 + 月-1），2026年11月 = 24322。
    // 月份切换重做（老爷 2026-11-28 14:30 亲口令「直接重做」）：分页走 SmoothMonthPager
    //（原生分页 ScrollView），月份索引是相对基准月的固定偏移数组（-120..<120，共 240 个月，
    // 覆盖 10 年窗口 2016-11～2036-10），数组本身永远不变；基准月只在视图第一次创建时
    // 定一次（当月），之后不再动。pageIndex 是已落定的月份（汇总 + 记录都跟它走），
    // 拖拽中不动，只在分页落定时才变。
    @State private var pageIndex: Int = CalendarView.monthIndex(year: DateUtil.yearMonth(of: Date()).year, month: DateUtil.yearMonth(of: Date()).month)
    /// 标题跟的月份（2026-11-28 改，取代落定才变）：拖过一半就换（分页器的过半回调写这里），
    /// 落定时跟 pageIndex 同步；拖一半松手弹回时跟着回来。汇总/记录仍只跟 pageIndex（落定页）。
    /// 1.3.2.011（Gemini）：改成 MonthTitleState——过半变月只重绘标题，不带动整页重算与
    /// Metal 重栅格化；滑动中/0.28s 内连变禁动画，慢速单次点按保留数字滚动。
    @State private var titleState: MonthTitleState = {
        let now = DateUtil.yearMonth(of: Date())
        return MonthTitleState(monthIndex: CalendarView.monthIndex(year: now.year, month: now.month))
    }()
    /// 240 个月阴历预热 + 全年天数补齐只开一次（.task 切 Tab 回来会重跑，不加守卫
    /// 每次回来都重开一遍循环）。
    @State private var didStartBackgroundWarmup = false
    /// 冷启动回当天只做一次（切 Tab 闪跳的根因，见下面 .task）：
    /// .task 在切 Tab 回来时也会重跑（视图重进层级），不加标志每次回来都强制回当月，
    /// 先闪一帧离开时的月份再跳回当月；有了标志，只有第一次创建时才回当天。
    @State private var didInitialMonthAlign = false
    /// 基准月（视图第一次创建时的当月，之后不再动）：月份偏移数组相对它算。
    @State private var baseIndex: Int = {
        let now = DateUtil.yearMonth(of: Date())
        return CalendarView.monthIndex(year: now.year, month: now.month)
    }()
    private var pageRange: Range<Int> { (baseIndex - 120)..<(baseIndex + 120) }
    /// 固定月份偏移数组（-120..<120，共 240 个月，相对基准月）。
    private var monthOffsets: [Int] { Array(-120..<120) }
    /// 分页器用的已落定偏移（pageIndex 与 baseIndex 的差）：分页器落定时写回 pageIndex。
    private var selectedOffsetBinding: Binding<Int> {
        Binding(get: { pageIndex - baseIndex }, set: { pageIndex = baseIndex + $0 })
    }
    /// 今天所在的月份绝对序号（“今天”按钮的判断与跳转目标）。
    private var currentMonthIndex: Int {
        let now = DateUtil.yearMonth(of: Date())
        return Self.monthIndex(year: now.year, month: now.month)
    }

    /// 预加载窗口（1.3.2.004，老爷 2026-11-28 11:32 亲口定）：
    /// 当前页前后各 10 个月，共 21 页——“我每翻一页就加载 21 页”。
    /// 每页的格子在父视图提前算好存在这里，页滑过来时直接用，
    /// 不在滑动中现算、现拍快照（慢拖卡顿的根：下一页/上一页原来是现加载的）。
    private static let preloadRadius = 10
    @State private var preloadedGrids: [Int: [MonthPageView.GridDay]] = [:]
    /// 预加载格子的在途任务（1.3.2.010）：新任务来了旧任务直接取消，只留最新的；
    /// 取消时旧的 preloadedGrids 原样留着，不留半截状态。
    @State private var preloadTask: Task<Void, Never>?

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
    /// 1.3.2.010：改成异步任务、中心优先——原来 21 页同步一口气算完，
    /// 冷启动（或缓存失效后）几十毫秒全堵在主线程上，正好撞上落定动画，
    /// 快滑就抽帧。现在中心先算、相邻其次、外围最后，每算一月让出一次主线程，
    /// 落定动画的帧能插进来；整窗一次交出去，不等 21 页全完、算好的页随任务走。
    /// 任务可取消：快滑连续落定、旧任务被取消时，当前月也已经算好了，不会被打断。
    /// 1.3.2.011（Gemini）：当前页与左右邻页若缺失立刻同步补齐（保证滑过去零等待），
    /// 其余窗口内未缓存页按由近及远分步补齐，每次 yield 不抢滑动帧时间。
    private func preloadAround(_ center: Int, forceRebuild: Bool = false) {
        preloadTask?.cancel()
        let lo = max(pageRange.lowerBound, center - Self.preloadRadius)
        let hi = min(pageRange.upperBound - 1, center + Self.preloadRadius)

        var next: [Int: [MonthPageView.GridDay]] = [:]
        next.reserveCapacity(hi - lo + 1)
        if !forceRebuild {
            for idx in lo...hi {
                if let cached = preloadedGrids[idx] {
                    next[idx] = cached
                }
            }
        }

        // 当前页与左右邻页若缺失立刻补齐，保证滑过去零等待。
        let immediateIndices = [center, center + 1, center - 1].filter { $0 >= lo && $0 <= hi && next[$0] == nil }
        for idx in immediateIndices {
            let ym = yearMonth(from: idx)
            next[idx] = MonthPageView.buildGridDays(year: ym.year, month: ym.month, store: store)
        }
        if forceRebuild || !immediateIndices.isEmpty || next.count != preloadedGrids.count {
            preloadedGrids = next
        }

        // 其余窗口内未缓存页按由近及远分步补齐，每次 yield 不抢滑动帧时间。
        var remaining: [Int] = []
        for d in 2...Self.preloadRadius {
            let p = center + d
            let m = center - d
            if p <= hi, next[p] == nil { remaining.append(p) }
            if m >= lo, next[m] == nil { remaining.append(m) }
        }
        guard !remaining.isEmpty else { return }

        preloadTask = Task { @MainActor in
            var batch: [Int: [MonthPageView.GridDay]] = [:]
            for idx in remaining {
                if Task.isCancelled { return }
                let ym = yearMonth(from: idx)
                batch[idx] = MonthPageView.buildGridDays(year: ym.year, month: ym.month, store: store)
                await Task.yield()
            }
            guard !Task.isCancelled, !batch.isEmpty else { return }
            var merged = preloadedGrids
            for (k, v) in batch where k >= lo && k <= hi {
                merged[k] = v
            }
            preloadedGrids = merged
        }
    }

    /// 箭头 / 今天 / 邻月点按切月（重做）：直接改 pageIndex（已落定），标题立刻淡入过去
    ///（1.3.2.011：标题走 MonthTitleState，慢速单次点按保留数字滚动）；分页器收到 selectedOffset
    /// 变化滑过去（0.25s snappy，减弱动态效果时 0.15s 淡入）。不做位移、不做交叉淡入、
    /// 不碰视差——旧的 jumpToMonth（20pt 轻移 + 交叉淡入）整段删掉。
    private func goToMonth(_ index: Int) {
        let target = min(max(index, pageRange.lowerBound), pageRange.upperBound - 1)
        titleState.update(to: target)
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25)) {
            pageIndex = target
        }
    }

    /// 点“今天”（1.3.2.007，iOS.docx §3.2）：不在当月时平滑切回当月；目标日期格一次
    /// 极克制的轻高亮（微闪，不放大）；轻冲击触感与动画起点同一帧触发。
    /// 已在当月时只闪格子，不跳页。减弱动态效果时不闪（当天已有绿边框标识）。
    private func goToToday() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let target = currentMonthIndex
        if target == pageIndex {
            flashTodayCell()
        } else {
            goToMonth(target)
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
                // 1.3.2.012（老爷 2026-11-28 亲口令）：标题放最上、黑卡放标题下、
                // 班组选择放日历下面——和工资页同款顺序（标题→黑卡→内容），
                // 两页标题与黑卡同高，切 Tab 不再有割裂感。
                monthNavigator
                    .padding(.top, 8)
                    .sheet(isPresented: $showMonthJump) {
                        MonthJumpSheet(currentIndex: pageIndex, range: pageRange) { goToMonth($0) }
                    }
                // 顶卡（1.3.2.016，Gemini 升级版规格）：两区紧凑结构，高度固定。
                todayOverviewCard
                // 1.2.7.002：日历只留月视图（周视图已删）。
                monthPager
                // 班次切换栏（1.3.2.016，Gemini 升级版规格）：弹性滑块（纯实心、无玻璃），
                // 本人班组带 4pt 小圆点；选中变化写回 store.viewTeam（栏外不加 animation，
                // 栏自己有动画，会打架）。
                ElasticTeamSegmentedBar(
                    items: TeamInfo.allTeams.map { "\($0)班" },
                    myTeamIndex: TeamInfo.allTeams.firstIndex(of: store.myTeam),
                    selectedIndex: teamIndexBinding
                )
                summaryLine
                recordsSection
                syncTimeFooter
            }
            .padding(.horizontal, 16)
            // 底部留白（1.3.2.012，Gemini 2026-11-28 逐帧复核）：滑到底时统计卡和同步时间
            // 在底栏上方留 24pt 呼吸余量，不贴着底栏；统计行本身滑一下就能完整露出。
            .padding(.bottom, 24)
            // 底部留白（重做，老爷 2026-11-28 14:36 亲口令）：1.3.2.006 加的 88pt 删掉——
            // 那是给自定义底栏留的，底栏已改回原生 TabView（iOS 26+ 液态玻璃），
            // 安全区由原生底栏自动处理，不再手动垫大额留白。
            // 88pt 没起作用的根因（录屏实测）：统计栏（summaryLine）本来就在 ScrollView 内容里，
            // 不是固定 footer；88pt 只加在内容最底下、只影响滑到底的位置，静止时统计栏
            // 照样落在 iOS 26/27 悬浮胶囊底栏盖住的那截里——垫数字修不了静止位置。
            // 2026-11-28 底栏改成永不收起（.never）：底栏一直在、统计栏上面还有调班/请假卡
            // + 同步时间，统计栏本身在底栏上方，完整露出，不再被收起的小圆球盖住。
        }
        // 1.3.2.014：右下角悬浮「今天」删了（老爷令）——回到今天改成顶卡里的
        // 「今天」按钮（见 todayOverviewCard，1.3.2.016 起在顶卡上行右端），
        // 排班/工资两页一样；悬浮钮压底栏、又多一个浮层，不要了。
        // 1.3.0.013：滚动指示条常显（老爷 19:24 说「没有滑动框」）——.visible 没用，
        // 画廊实拍证明它根本不画出来，改走自绘滑块 AlwaysVisibleScrollIndicator。
        .modifier(AlwaysVisibleScrollIndicator())
        .background(AppStyle.pageBackground)
        // 导航栏毛玻璃隔离（Gemini 整改模块 3b）：向上滚时黑色概览卡的金额文字
        // 会透过导航栏、和「排班」标题重叠。2026-11-28 改回系统原生 .automatic：
        // .visible 强制始终显示毛玻璃背景，向上滚时仍是半透明、黑卡文字透过来还被
        // 栏底边切一半；.automatic 让系统按滚动状态切到不透的栏底，隔断才起作用。
        // 设置页同理（见 SettingsView）。
        .toolbarBackground(.automatic, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showShareSchedule = true
                } label: {
                    // 1.3.2.017（老爷 2026-11-28 20:45 亲口令）：分享图标在玻璃圆框里偏了——
                    // 系统玻璃圆框按 label 尺寸画，裸 Image 的 label 是字形紧包框，圆框与
                    // 字形不同心；给 label 定死 36×36 方框，圆框必与按钮同心。
                    // square.and.arrow.up 的视觉重心偏下（箭头细、方框重在下半），
                    // 再上移 1pt 回到光学中心。
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .offset(y: -1)
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
            // 切 Tab 闪跳的根因（2026-11-28 录屏 00:50）：.task 不只在视图第一次创建时跑——
            // 切 Tab 回来视图重进层级，.task 也重跑；原来每次都强制回当月，所以从设置切回
            // 排班时先闪一帧离开时的月份（2027年7月）再跳回当月（2026年11月）。
            // 真因不是 onAppear（三个页的 onAppear 都没有重置月份的代码），就是这个 .task。
            // 修法：只第一次跑时回当天（didInitialMonthAlign 标志），切 Tab 回来只做预取/刷新，
            // 月份保持原地不动。
            if !didInitialMonthAlign {
                didInitialMonthAlign = true
                let now = DateUtil.yearMonth(of: Date())
                pageIndex = min(max(Self.monthIndex(year: now.year, month: now.month), pageRange.lowerBound), pageRange.upperBound - 1)
                titleState.update(to: pageIndex)
                store.setCurrentMonth(year: now.year, month: now.month)
            }
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
            // 切 Tab 回来 .task 会重跑，这两趟只开一次（didStartBackgroundWarmup 守卫）。
            if !didStartBackgroundWarmup {
                didStartBackgroundWarmup = true
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
        }
        // 滑到哪页，汇总、调班/请假记录跟着走（但要等落定）。
        // 1.1.5（重叠根因之二）：原来这里立刻调 setCurrentMonth，写一串 @Published，
        // 正好落在 TabView 的 settle 动画里，整页重绘打断动画，两页错位重叠。
        // 现在滑页那一刻只记页码，什么数据都不换；等 0.4 秒没再滑页（落定了）
        // 再换月 + 预取前后月 + 刷新。标题和底部统计直接跟 pageIndex 走（见 pagerTitle /
        // displayedMonth），不经过 store.currentYearMonth，所以落定前也不错位。
        .onChange(of: pageIndex) { newIndex in
            // 落定就跟标题同步（标题平时跟过半回调走，落定时一定等于 pageIndex）。
            titleState.update(to: newIndex)
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
        }
        .onChange(of: store.viewTeam) { _ in
            // 1.3.2.014：切班闪屏修——.012 的 teamFade（先淡出 0.15s、150ms 后再淡入）
            // 就是闪屏本身：顶卡、日历、统计、记录四块同时淡到透明再回来，整页 blink 一下。
            // 删掉淡出淡入，换班组直接换数据——当前页 21 页预加载是同步算好的（buildGridDays
            // 纯本地轮班算，不走网络），切过去立刻就是新班组的日历，不用先藏起来；
            // 胶囊滑动（matchedGeometryEffect）本身就是切换动画，够了。
            // 1.3.2.004：换班组立刻按新班组重算 21 页（monthFor 按新班组算），再后台刷新。
            preloadAround(pageIndex, forceRebuild: true)
            Task { await store.refreshMonth() }
        }
        // 切 Tab 回来自动归位（1.3.2.016，老爷令）：切到别的 Tab（工资/设置）再回来，
        // 排班页回到本月。只认 Tab 选中态变化——日详情 sheet / 共享 / 手动排班页
        // 推入弹出回来不触发（selectedTab 没变），不误重置；同页内左右滑、
        // 点月份标题跳月、点「回到今天」都不受影响。设置页也在切换路径里。
        .onChange(of: store.selectedTab) { newTab in
            if newTab == 0 {
                goToMonth(currentMonthIndex)
            }
        }
        // 1.3.2.004：日历真数据到了 / 显示设置（周一首日、显示上下月）改了，
        // 预加载的 21 页整窗重算，已缓存的页直接复用。
        .onChange(of: store.calendarVersion) { _ in preloadAround(pageIndex, forceRebuild: true) }
        .onChange(of: store.calendarDisplay) { _ in preloadAround(pageIndex, forceRebuild: true) }
        .onChange(of: store.holidaysUpdatedAt) { _ in preloadAround(pageIndex, forceRebuild: true) }
        .sheet(isPresented: $showDayDetail) {
            if let selectedDay {
                DayDetailView(day: selectedDay)
            }
        }
    }

    // MARK: 头部

    /// 顶卡（1.3.2.016，Gemini 升级版规格 + 老爷令重构）：TodayOverviewCard，
    /// 两区紧凑结构（日期+徽标+今天 / 班次状态+今日已挣），高度固定。
    /// 徽标点回本班、「今天」按钮回当月（走 goToToday）。
    private var todayOverviewCard: some View {
        let inputs = store.todayEstimateInputs
        return TodayOverviewCard(
            dateText: todayDateLine,
            myTeam: store.myTeam,
            isViewingOtherTeam: store.viewTeam != store.myTeam,
            shiftName: todayShiftName,
            shiftTime: todayShiftTime,
            day: store.todaySchedule,
            earlyRate: inputs.earlyRate,
            midRate: inputs.midRate,
            inputs: inputs.inputs,
            payAccess: store.payAccess,
            hideAmounts: Bindable(store).hideAmounts,
            showBackToToday: pageIndex != currentMonthIndex,
            onTapMyTeamBadge: { store.viewTeam = store.myTeam },
            onBackToToday: goToToday
        )
    }

    /// 班组下标桥接（1.3.2.016）：弹性切换栏绑的是 selectedIndex（Int），
    /// 现有是 store.viewTeam（Team 字符串）。用 TeamInfo.allTeams 的下标换算，
    /// 选中变化写回 store.viewTeam；viewTeam 一定在四班里，fallback 只是兜底。
    private var teamIndexBinding: Binding<Int> {
        Binding(
            get: { TeamInfo.allTeams.firstIndex(of: store.viewTeam) ?? TeamInfo.allTeams.firstIndex(of: store.myTeam) ?? 1 },
            set: { index in
                guard TeamInfo.allTeams.indices.contains(index) else { return }
                let team = TeamInfo.allTeams[index]
                if team != store.viewTeam {
                    store.viewTeam = team
                }
            }
        )
    }

    /// 今天的年月日 + 周几，如“2026年11月24日 星期二”。
    private var todayDateLine: String {
        let today = Date()
        let ym = DateUtil.yearMonth(of: today)
        let day = DateUtil.calendar.component(.day, from: today)
        return "\(DateUtil.yearMonthTitle(year: ym.year, month: ym.month))\(day)日 \(DateUtil.weekdayCN(of: today))"
    }

    /// 今天什么班：名与时间分开给顶卡（1.3.3.004 上下排）。名如“中班”、
    /// 双班“早班 + 中班”、休息“休息”、请假“请假（年假）”；时间如“16:00–24:00”，
    /// 休息/请假/无数据时为 nil（卡片内透明占位）。
    private var todayShiftName: String {
        guard let day = store.todaySchedule else { return "—" }
        if day.onLeave == true {
            let t = day.leaveType ?? ""
            return t.isEmpty ? "请假" : "请假（\(t)）"
        }
        if day.isRest { return "休息" }
        let parts = ShiftStyle.parts(of: day.shift)
        if parts.count > 1 {
            return parts.joined(separator: " + ")
        }
        return day.shift
    }

    private var todayShiftTime: String? {
        guard let day = store.todaySchedule else { return nil }
        if day.onLeave == true || day.isRest { return nil }
        return day.displayTime
    }

    /// 月份标题栏（重做，老爷 2026-11-28 14:30 亲口令）：共用的 MonthHeaderView——
    /// 标题绝对居中（等宽数字，1.3.2.011：标题走 MonthTitleState，滑动中只重绘标题），
    /// 标题跟 titleState（过半就换），再也不会被挤偏（录屏 00:03/00:10 的毛病）。旧的 HStack
    ///（左右箭头 + Spacer + 标题 + 今天 + Spacer + 箭头）整段删掉。
    /// “今天”按钮不在标题栏里（1.3.2.014：顶卡右下角的「回到今天」按钮；
    /// 标题行只剩 < 标题 >，标题真正居中）。
    private var monthNavigator: some View {
        ObservedMonthHeaderView(
            state: titleState,
            onPrevious: { goToMonth(pageIndex - 1) },
            onNext: { goToMonth(pageIndex + 1) },
            onTitleTap: { showMonthJump = true }
        )
    }

    // MARK: 日历滑页（原生分页，跟着手指走）

    /// 周几行（在每页白卡里，跟着月份一起滑）：日、六绿色，其余深色，与参考图一致。
    /// 周一为每周首日时，顺序从周一开始（1.2.7.001）。
    /// 2026-11-28 改：原来固定在分页器外面，星期栏和网格是两套宽度，列对不齐
    ///（实测网格比星期栏右移 16pt）；现在放进每页里，和网格同一宽度，列永远对齐。
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
        VStack(spacing: 8) {
            // 月份分页重做（老爷 2026-11-28 14:30 亲口令）：共用的 SmoothMonthPager——
            // 原生分页 ScrollView + .scrollTargetBehavior(.paging)，手势物理曲线、回弹与
            // 打断全交给系统；月份索引是相对基准月的固定偏移数组，不动态改。旧的
            // TabView 分页 + 每页 GeometryReader 报位置（标题视差）整段删掉。
            // 每页固定高（外框总高不变），行距恒定 6pt；滑页时不再重新布局、不再因周数
            // 不同伸缩，根治掉帧与页边忽大忽小。
            // 月份数据走 store.monthFor：有缓存直接取，没缓存本地 8 天一轮算好缓存起来，
            // 滑页时不再现算、不再发网络请求。
            // 白卡进页（2026-11-28 改）：整张白卡（含星期栏）放进每一页里，跟着月份一起滑——
            // 星期栏和网格同一页、同一宽度，列永远对齐；滑走时星期栏也跟着走。
            // pagePadding 传 0：白卡自带 12pt 内边距，两页白卡之间自然有 24pt 白色间距，
            // 不粘连；再加 16pt 会把卡片挤窄、还让落点整体右移 16pt、周六列被右边缘切掉
            //（2026-11-28 实测：网格比星期栏右移 16pt，周六 pill 被切约 12pt）。
            // 每页高度由卡片自己定（星期栏 + 414pt 网格 + 12pt 内边距，全月恒定），
            // 不再在分页器上写死 414pt（那是旧结构、卡片在外面的高度）。
            SmoothMonthPager(monthOffsets: monthOffsets, selectedOffset: selectedOffsetBinding, pagePadding: 0, onMidpointPageChange: { offset in
                titleState.update(to: baseIndex + offset)
            }, onScrollingChange: { scrolling in
                titleState.setScrolling(scrolling)
            }) { offset in
                let ym = yearMonth(from: baseIndex + offset)
                VStack(spacing: 4) {
                    weekdayHeader
                    MonthPageView(
                        year: ym.year, month: ym.month,
                        preloadedDays: preloadedGrids[baseIndex + offset],
                        isSelected: { selectedDay?.date == $0 },
                        onSelectDay: { day in
                            selectedDay = day
                            showDayDetail = true
                        },
                        onSelectAdjacentMonth: { y, m in
                            // 邻月格点按也是跳页，走同一个 goToMonth。
                            goToMonth(Self.monthIndex(year: y, month: m))
                        },
                        flashDate: todayFlashDate
                    )
                    // 切班组时网格层不做隐式动画（1.3.2.016）：切换栏的 withAnimation(spring)
                    // 会顺着 viewTeam 的变化流进格子，色块跟着弹簧交叉淡入、看着重影；
                    // 这里把动画清掉，色块直接换。分页滑动（ScrollView 层）与今天格微闪
                    //（格子内部 withAnimation）不受影响。
                    .transaction { $0.animation = nil }
                }
                .padding(12)
                .background(AppStyle.surface1)
                .cornerRadius(16)
            }
            if store.isLoadingMonth {
                ProgressView("正在加载…")
                    .padding(.top, 8)
            }
            // 1.3.2.016（老爷令：直接删掉）：「看的是 D班的排班……」两行长文案整段删掉，
            // 不留开关；切班组时页面骨架不再上下跳动。归属提示改由切换栏上本人班组的
            // 4pt 小圆点承担；看别班点日期时，日详情页里的只读提示 +「切回」按钮引导。
        }
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
    /// 底部统计卡（1.3.2.014，Gemini 排版）：四列大数字（实际出勤/休息/三薪/加班），
    /// 下面一行小字放应出勤、基本天数、请假——信息一个不少，只是从一行小字改成
    /// 四列大数字 + 一行小字，好扫得多。
    /// 计算放 statsCard（普通函数）里，不塞进 Group 的 ViewBuilder——
    /// 几个 let/if-let 再加一个 VStack 全挤在 builder 里，编译器推不出类型
    ///（报 TableColumn 错，两轮编包都挂在这）。
    private var summaryLine: some View {
        // payInputsVersion 订阅从 MonthPageView.body 挪到这里（Gemini 1.3.2.011）：
        // 工资输入到齐时底部统计（三薪 X 天 / 加班 X 天）要重算，这里订阅就够了；
        // MonthPageView 的格子是快照/预计算，不依赖工资输入，不用跟着重画。
        let _ = store.payInputsVersion
        return Group {
            if let stats = displayedMonth?.stats {
                statsCard(stats: stats)
            }
        }
    }

    /// 底部统计卡本体（普通函数）：四列大数字 + 一行小字。
    private func statsCard(stats: MonthStats) -> some View {
        // 第 44 条（2026-11-26）：应出勤是排班算的出勤（基础轮班天数，
        // PayCalc.countBaseWork：数 baseShift 不是休息的天数，调班请假不影响），
        // 基本天数是法定口径（PayCalc.basicDays，与工资页同表），两个数不一样。
        // 之前应出勤那格误用了 stats.basicDays（那是法定基本天数），10 月/11 月
        // 和基本天数撞成两个一样的数（18/18、21/21）。
        let ym = yearMonth(from: pageIndex)
        var triple = "—"
        var overtime = "—"
        if let info = store.triplePayInfo(year: ym.year, month: ym.month) {
            triple = formatDays(info.tripleDays)
            overtime = formatDays(info.overtimeDays)
        }
        let baseWorkDays = PayCalc.countBaseWork(yearDays: displayedMonth?.days ?? [], year: ym.year, month: ym.month)
        let statutoryBasicDays = PayCalc.basicDays(year: ym.year, month: ym.month)
        return VStack(spacing: 8) {
            HStack(spacing: 0) {
                statCell(value: "\(MoneyUtil.int(stats.actualShifts))班", label: "实际出勤")
                Rectangle().fill(AppStyle.outline).frame(width: 1, height: 30)
                statCell(value: "\(MoneyUtil.int(stats.restDays))天", label: "休息")
                Rectangle().fill(AppStyle.outline).frame(width: 1, height: 30)
                statCell(value: triple == "—" ? "—" : "\(triple)天", label: "三薪")
                Rectangle().fill(AppStyle.outline).frame(width: 1, height: 30)
                statCell(value: overtime == "—" ? "—" : "\(overtime)天", label: "加班")
            }
            Text("当月应出勤 \(baseWorkDays) 天 · 基本天数 \(statutoryBasicDays) 天 · 请假 \(MoneyUtil.int(stats.leaveDays)) 天")
                .appFont(size: AppFont.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(AppStyle.cardPadding)
        .frame(maxWidth: .infinity)
        .background(AppStyle.surface1)
        .cornerRadius(AppStyle.cardRadius)
    }

    /// 统计卡里的一列：上面大号数字 + 单位，下面小字标签。
    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .appFont(size: AppFont.headline, weight: 700).monospacedDigit()
                .foregroundColor(AppStyle.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .appFont(size: AppFont.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
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
                    HStack(alignment: .center) {
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
        // 通栏长条（2026-11-28 老爷亲口令）：和上面统计卡同宽——原来这张卡没有
        // maxWidth，VStack 按内容收窄，看着比统计卡窄一截；加满宽后和统计卡一样宽。
        // 底栏已改成永不收起（.never），收起的小圆球不会再盖住这张卡的标题和第一条记录；
        // 右下角悬浮「今天」按钮只占右下角一小块，内容能往上滚开。
        .frame(maxWidth: .infinity, alignment: .leading)
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
                HStack(alignment: .center) {
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
    @Environment(AppStore.self) private var store: AppStore
    let year: Int
    let month: Int
    /// 父视图预加载好的本页格子（前后 10 个月共 21 页）：有就直接用，不拍快照、
    /// 不等出现时现算；没有（窗口外、刚翻过来的新页）才走原来的快照兜底。
    /// 1.3.2.004（老爷 2026-11-28 11:32 亲口定预加载 21 页）。
    /// 1.3.2.011（Gemini）：格子改成预计算好的 GridDay（三薪标/假班标/阴历文案
    /// 都在 buildGridDays 里一次算好），渲染 42 格时零字典分配、零线性扫描。
    let preloadedDays: [GridDay]?
    let isSelected: (String) -> Bool
    let onSelectDay: (DaySchedule) -> Void
    /// 点到上月/下月补的日期时跳到对应月。
    let onSelectAdjacentMonth: (Int, Int) -> Void
    /// 点“今天”后要微闪的日期（1.3.2.007，iOS.docx §3.2）：等于今天的格子闪一次，平时是 nil。
    /// 注意：let 常量带默认值时不能在 init 里再赋值（会报“只能初始化一次”），
    /// 所以这里不写默认值，默认值放在下面显式 init 的参数上（flashDate: String? = nil）。
    let flashDate: String?

    /// 显式初始化（1.3.2.007：合成的 memberwise init 在这台工具链上不认新加的
    /// flashDate 参数——疑似 @Environment(AppStore.self) store 干扰了合成；显式写死最稳妥）。
    init(
        year: Int,
        month: Int,
        preloadedDays: [GridDay]?,
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

    /// 预计算好三薪标、假/班标、阴历文案的格子数据，渲染 42 格时零字典分配、零线性扫描。
    struct GridDay {
        let day: DaySchedule
        let kind: GridDayKind
        let isTriplePay: Bool
        let holidayMark: String?
        let lunarText: String
        let isLunarRed: Bool
    }

    /// 1.1.5：本页的数据快照——出现时从 store 取一次存在 @State 里，滑动中只读快照，
    /// store 再怎么写（prefetch 回来、setCurrentMonth、refresh）都动不了正在滑的这一页。
    /// 只在三处重拍：刚出现（.task）、日历数据真变了（store.calendarVersion +1：
    /// 调班/请假保存、刷新成功）、换了班组（viewTeam 变了）。
    /// 快照没拍好之前的第一帧先用 live 的 gridDays 顶上（只此一帧，不在滑动中）。
    @State private var snapDays: [GridDay] = []
    @State private var snapLoaded = false

    private func takeSnapshot() {
        snapDays = gridDays
        snapLoaded = true
    }

    private static func makeGridDay(_ day: DaySchedule, kind: GridDayKind, statutory: [String: String], store: AppStore) -> GridDay {
        let extra = ChineseCalendar.info(for: day.date)
        let lunarRaw = extra.lunarText
        // 1.3.2.012：龙抬头→龙头（见 displayLunarText 的注释），两处同步改。
        let lunarText = lunarRaw == "龙抬头" ? "龙头" : ((lunarRaw.count == 3 && lunarRaw.hasSuffix("节")) ? String(lunarRaw.dropLast()) : lunarRaw)
        let holidayMark: String?
        if let h = store.holiday(for: day.date) {
            switch h.kind {
            case "legal", "rest": holidayMark = "假"
            case "workday": holidayMark = "班"
            default: holidayMark = nil
            }
        } else if let mark = extra.mark {
            holidayMark = mark == .holiday ? "假" : "班"
        } else {
            holidayMark = nil
        }
        return GridDay(
            day: day,
            kind: kind,
            isTriplePay: kind == .current && statutory[day.date] != nil,
            holidayMark: holidayMark,
            lunarText: lunarText,
            isLunarRed: extra.isRedText
        )
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
    /// 1.3.2.011（Gemini）：三薪标/假班标/阴历文案在建格子时一次算好进 GridDay；
    /// 法定表每页只建一次（原来每格都调 tripleDates、内部反复建 statutoryMap 字典，
    /// 每页约 900 次字典分配），三薪只按法定表标（和原来 tripleDates 一个口径）。
    static func buildGridDays(year: Int, month: Int, store: AppStore) -> [GridDay] {
        let prev = month == 1 ? (year - 1, 12) : (year, month - 1)
        let next = month == 12 ? (year + 1, 1) : (year, month + 1)
        let mondayFirst = store.calendarDisplay.mondayFirst
        let firstWeekday = DateUtil.firstWeekday(year: year, month: month)
        let leading = mondayFirst ? (firstWeekday + 6) % 7 : firstWeekday
        let statutory = PayCalc.statutoryMap(year: year)

        var result: [GridDay] = []
        result.reserveCapacity(42)
        if leading > 0 {
            let prevMonth = store.monthFor(year: prev.0, month: prev.1)
            result += (prevMonth.days ?? []).suffix(leading).map {
                makeGridDay($0, kind: .leading, statutory: statutory, store: store)
            }
        }
        let current = store.monthFor(year: year, month: month)
        result += (current.days ?? []).map {
            makeGridDay($0, kind: .current, statutory: statutory, store: store)
        }
        let days = DateUtil.daysInMonth(year: year, month: month)
        let remainder = (leading + days) % 7
        let trailing = remainder == 0 ? 0 : 7 - remainder
        let nextMonth = store.monthFor(year: next.0, month: next.1)
        var usedTrailing = 0
        if trailing > 0 {
            result += (nextMonth.days ?? []).prefix(trailing).map {
                makeGridDay($0, kind: .trailing, statutory: statutory, store: store)
            }
            usedTrailing = trailing
        }
        while result.count < 42 {
            let extra = (nextMonth.days ?? []).dropFirst(usedTrailing).prefix(7)
            guard extra.count == 7 else { break }
            result += extra.map {
                makeGridDay($0, kind: .trailing, statutory: statutory, store: store)
            }
            usedTrailing += 7
        }
        return result
    }

    private var gridDays: [GridDay] {
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
        // 1.3.2.011：payInputsVersion 订阅挪到 summaryLine（见 CalendarView），
        // 这里不再订阅——格子是快照/预计算，不依赖工资输入，输入到了不用整页重画。
        // 1.3.2.004：父视图预加载好的格子直接用（21 页窗口内）；窗口外才走快照兜底。
        let days = preloadedDays ?? (snapLoaded ? snapDays : gridDays)
        let weeks = max(1, days.count / 7)
        // 每页只格式化一次“今天”，避免在 42 格循环里重复调 DateFormatter。
        let todayStr = DateUtil.string(from: Date())
        VStack(spacing: calendarRowSpacing(weeks: weeks)) {
            ForEach(0..<weeks, id: \.self) { w in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { c in
                        let idx = w * 7 + c
                        if idx < days.count {
                            gridCell(item: days[idx], todayStr: todayStr)
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
    private func gridCell(item: GridDay, todayStr: String) -> some View {
        let day = item.day
        let kind = item.kind
        if (kind == .leading || kind == .trailing) && !store.calendarDisplay.showAdjacentMonths {
            Color.clear.frame(height: calendarCellHeight)
                .frame(maxWidth: .infinity)
        } else {
            switch kind {
            case .leading:
                Button { onSelectAdjacentMonth(prevYearMonth.year, prevYearMonth.month) } label: {
                    DayCell(
                        day: day, isToday: false, isSelected: false, isAdjacent: true,
                        precomputedHolidayMark: .some(item.holidayMark),
                        precomputedLunarText: item.lunarText,
                        precomputedLunarRed: item.isLunarRed
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(DayCellPressStyle())
            case .current:
                Button { onSelectDay(day) } label: {
                    DayCell(
                        day: day,
                        isToday: day.date == todayStr,
                        isSelected: isSelected(day.date),
                        isTriplePay: item.isTriplePay,
                        precomputedHolidayMark: .some(item.holidayMark),
                        precomputedLunarText: item.lunarText,
                        precomputedLunarRed: item.isLunarRed,
                        isFlashing: flashDate == day.date
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(DayCellPressStyle())
            case .trailing:
                Button { onSelectAdjacentMonth(nextYearMonth.year, nextYearMonth.month) } label: {
                    DayCell(
                        day: day, isToday: false, isSelected: false, isAdjacent: true,
                        precomputedHolidayMark: .some(item.holidayMark),
                        precomputedLunarText: item.lunarText,
                        precomputedLunarRed: item.isLunarRed
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(DayCellPressStyle())
            }
        }
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
/// 关键：所有班次的 pill 都是同一固定高度 24pt、通栏、圆角；
/// 双班时在同一个 24pt 高度里上下叠两个 11pt 小 pill，不撑高格子。
/// 整格固定 64pt（日期行 26 + 间距 2 + pill 24 + 上下边距 8），行距恒定 6pt。
/// 1.1.3：阳历数字 18→16pt（收一收、别太高）；日期与色块间距 4→2pt；
/// 1.2.2：窄屏（<400pt，如 iPhone 15 的 393pt）阳历数字 16→15pt + 缩放兜底，
/// 左右两列 12/9→11/8——之前两位数的号在窄屏上被截成「…」。
/// 请假「假」标从号数旁边移到左列、和法定「假/班」上下叠放（之前号数+红标太宽、压着右边阴历字）；
/// 三薪日：日期数字右侧小橙点；法定「假/班」保持原样，两套标法不混。
struct DayCell: View {
    @Environment(AppStore.self) private var store: AppStore
    /// 1.2.8.001：上下月补的日期在深色下 0.5 透明太暗、看着发虚，深色放宽到 0.65。
    @Environment(\.colorScheme) private var colorScheme

    let day: DaySchedule
    let isToday: Bool
    let isSelected: Bool
    /// 上月/下月补进来的日期：灰色显示，点后跳到对应月。
    var isAdjacent: Bool = false
    /// 三薪日（工资算法里 tripleDays 的那几天）：色块里加一行半透明「三薪」。
    var isTriplePay: Bool = false
    /// 预计算字段（Gemini 1.3.2.011）：MonthPageView.buildGridDays 里一次算好传进来，
    /// 渲染 42 格时不再每格重复查表/建字典；不传（nil）就按原来逻辑现算，兼容外部已有调用。
    /// precomputedHolidayMark 是双层 Optional：外层 nil = 没传、现算；.some(nil) = 传了、就是没标。
    var precomputedHolidayMark: String?? = nil
    var precomputedLunarText: String? = nil
    var precomputedLunarRed: Bool? = nil
    /// 点“今天”后的微闪（1.3.2.007，iOS.docx §3.2）：目标格一次底色微闪，不放大。
    var isFlashing: Bool = false
    /// 微闪的不透明度（1 → 0，0.55s easeOut）。
    @State private var flashOpacity: Double = 0
    /// 减弱动态效果：班次标签变化只做 0.15s 淡入、不缩放；微闪也取消。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pillHeight: CGFloat = 24

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
    /// 预计算值优先（MonthPageView 传进来的就是同一份逻辑算好的）。
    private var holidayMark: String? {
        if let pre = precomputedHolidayMark { return pre }
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
    /// 节气名（冬至、小寒等）没有「节」字，也不动。
    /// 1.3.2.012：龙抬头是唯一不带「节」的三字节日，竖排三行会顶到下面的班次 pill，
    /// 显示成「龙头」（龙头节的别名），和其余两字节日齐平。只改这里的显示，
    /// 不动 ChineseCalendar 的原始数据（当天详情等别处不受影响）。
    /// 预计算在 makeGridDay 里也有一份同样的映射，两处同步改。
    private var displayLunarText: String {
        if let pre = precomputedLunarText { return pre }
        let t = extra.lunarText
        if t == "龙抬头" { return "龙头" }
        if t.count == 3 && t.hasSuffix("节") { return String(t.dropLast()) }
        return t
    }

    /// 阴历小字是不是红字（节气/节日）：预计算值优先。
    private var isLunarRed: Bool {
        precomputedLunarRed ?? extra.isRedText
    }

    var body: some View {
        VStack(spacing: 2) {
            dateRow
            shiftPill
        }
        .padding(2)
        .frame(height: calendarCellHeight)
        // 选中底色用圆角矩形画，不用 .cornerRadius() 裁剪——圆角背景只画底色，不裁内容。
        // 1.3.2.014：选中色从系统蓝改成 navyAdaptive（老爷说蓝色框别扭）——系统蓝
        // 又亮又艳，跟红班次 pill、红节气字撞在一起很扎眼；navy 是全站选中态的
        // 颜色（班组 pill、按钮、本月胶囊都是它），选中格跟全站统一，低调耐看。
        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? AppStyle.navyAdaptive.opacity(0.10) : Color.clear))
        // 今天格微闪（1.3.2.007，iOS.docx §3.2）：底色微闪一次，0.55s 淡出，不放大；
        // 描边那层在上面，不会被闪盖住。
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.22))
                .opacity(flashOpacity)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                // 1.3.2.018（老爷 2026-11-28 21:33 亲口定）：描边做均匀——原来今天绿框 2pt、
                // 选中藏青框 1.5pt 粗细不一，且 .stroke 是居中描边、外侧一半容易被格子裁掉，
                // 看着一边粗一边细。改成统一 1.5pt + .strokeBorder（描边全收进框内、
                // 不出界、不被裁），形状仍是圆角矩形、不换。
                .strokeBorder(isToday ? Color.green : (isSelected ? AppStyle.navyAdaptive : Color.clear), lineWidth: 1.5)
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

    /// 日期行（三栏，互不重叠）：左 法定假/班 + 请假标上下叠（11pt，没有留空）
    /// + 中 阳历大数字（居中） + 右 阴历/节气/节日小字（竖排两字，节气/节日红字、阴历灰字）。
    /// 请假标放左列：之前跟在号数后面，号数+红标比中间栏宽、压着右边阴历字（11-02、11-03 就是这么叠上的）。
    /// 1.2.2：左列 12→11、右列 9→8，给中间阳历数字多腾 2pt（窄屏两位数的号不再截成「…」）。
    private var dateRow: some View {
        HStack(alignment: .top, spacing: 1) {
            leftMarkColumn
            // 号数 + 三薪小橙点（2026-11-28 老爷亲口令：角标缩小成一个小橙点，放日期数字右侧）。
            // 点 6pt，号数两位数时靠 minimumScaleFactor 稍缩一点让位，不挤农历列。
            HStack(spacing: 2) {
                Text("\(day.dayNumber)")
                    .appFont(size: dayNumberFontSize, weight: isToday ? 700 : 600).monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundColor(isAdjacent ? .secondary : .primary)
                if isTriplePay && !isAdjacent {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            // 阴历/节气/节日小字（1.2.7.001）：显示农历关了就留空（占位不变，布局不抖）。
            lunarColumn
        }
        .frame(height: 26)
    }

    /// 左列：法定假/班标 + 请假标上下叠（11pt 宽）。
    private var leftMarkColumn: some View {
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
    }

    /// 右列：阴历/节气/节日小字（竖排两字，节气/节日红字、阴历灰字），8pt 宽。
    private var lunarColumn: some View {
        VStack(spacing: 0) {
            if display.showLunar {
                ForEach(Array(displayLunarText.enumerated()), id: \.offset) { _, ch in
                    Text(String(ch))
                        .appFont(size: 9, weight: 400)
                        .foregroundColor(isLunarRed ? .red : AppStyle.tinySecondary)
                }
            }
        }
        .frame(width: 8, alignment: .leading)
        .padding(.top, 1)
    }

    /// 班次 pill + 换组动画（1.3.2.007，iOS.docx §3.2）：
    /// pill 固定 24pt；三薪不在色块上，改成日期数字右侧的小橙点（见 dateRow，
    /// 老爷 2026-11-28 亲口令）。所有格子的 pill 同高，视觉节奏一致。
    /// 双班：两个 11pt 小 pill 上下叠（11 + 2 + 11 = 24）；单班：一个 24pt pill。
    private var shiftPill: some View {
        shiftPillContent
            // 三薪标记不在 pill 上（2026-11-28 老爷亲口令：改成日期数字右侧的小橙点，见 dateRow）。
            // 班次标签变化（1.3.2.007，iOS.docx §3.2）：换班组时标签快速轻微缩放加交叉淡入，
            // 0.2s easeInOut，不整块日历横移；减弱动态效果时只做 0.15s 淡入、不缩放。
            .id(pillKey)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
            .animation(reduceMotion ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.2), value: pillKey)
            .opacity(isAdjacent ? (colorScheme == .dark ? 0.65 : 0.5) : 1.0)
    }

    /// 班次 pill 本体：双班两个 11pt 小 pill 上下叠，单班一个 24pt pill。
    private var shiftPillContent: some View {
        Group {
            if day.isDouble == true {
                VStack(spacing: 2) {
                    ForEach(ShiftStyle.parts(of: day.shift), id: \.self) { part in
                        Text(TeamInfo.shortName(part))
                            .appFont(size: 9, weight: 700)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 11)
                            .background(ShiftStyle.color(for: part))
                            .cornerRadius(4)
                    }
                }
                .frame(height: pillHeight)
            } else {
                Text(day.isRest ? "休" : TeamInfo.shortName(day.shift))
                    .appFont(size: 13, weight: 700)
                    .foregroundColor(day.isRest ? ShiftStyle.color(for: "休息") : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: pillHeight)
                    .background(day.isRest ? ShiftStyle.background(for: "休息") : ShiftStyle.color(for: day.shift))
                    .cornerRadius(6)
            }
        }
    }

    /// 三薪角标已改成日期数字右侧的小橙点（见 dateRow），这里不再留 capsule 版。
}
