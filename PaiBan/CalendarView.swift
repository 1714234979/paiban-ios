import SwiftUI
import UIKit

/// 日历格固定高 64pt；网格外框总高固定 414pt（按 6 行 × 64 + 5 × 6 算），
/// 行距按行数自适应：6 行紧（6pt）、5 行松（23.5pt）、4 行更松。
/// 只调行内间距，外框总高度不变，左右滑动时页面尺寸不伸缩。
private let calendarCellHeight: CGFloat = 64
private let calendarGridHeight: CGFloat = 6 * 64 + 5 * 6
private func calendarRowSpacing(weeks: Int) -> CGFloat {
    guard weeks > 1 else { return 6 }
    return (calendarGridHeight - CGFloat(weeks) * calendarCellHeight) / CGFloat(weeks - 1)
}

/// 排班页：原生月历。每个日期格里的班次 pill 都是同一固定高度（28pt、通栏圆角），
/// 修掉网页版“日班绿块占满整格、别的班只是短 pill”的 bug。
struct CalendarView: View {
    @EnvironmentObject private var store: AppStore

    @State private var selectedDay: DaySchedule?
    @State private var showDayDetail = false
    /// 1.1.4：滑页刷新防抖任务（见 .onChange(of: pageIndex)）。
    @State private var refreshTask: Task<Void, Never>?
    // 滑页的页码 = 月份绝对序号（年*12 + 月-1），2026年11月 = 24322。
    // 用原生 TabView 分页滑，切月跟着手指走、左右月预渲染，不再整格闪白重画。
    @State private var pageIndex: Int = CalendarView.monthIndex(year: DateUtil.yearMonth(of: Date()).year, month: DateUtil.yearMonth(of: Date()).month)
    // 滑页范围：一次生成 12 个月，当前月居中（前后各 5–6 个月）。
    // 现在是 2026 年 11 月，窗口就是 2026-06 ~ 2027-05，滑到边就停。
    // 12 页比原来 84 页轻得多，滑页不再为几十页做布局，卡顿的根也去了。
    @State private var windowStartIndex: Int = {
        let now = DateUtil.yearMonth(of: Date())
        return CalendarView.monthIndex(year: now.year, month: now.month) - 5
    }()
    private var pageRange: Range<Int> { windowStartIndex..<(windowStartIndex + 12) }

    static func monthIndex(year: Int, month: Int) -> Int { year * 12 + (month - 1) }
    private func yearMonth(from index: Int) -> (year: Int, month: Int) { (index / 12, index % 12 + 1) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                teamSwitcher
                monthNavigator
                monthPager
                summaryLine
                recordsSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .task {
            // 进页先对齐到 Store 正在看的月（恢复的缓存可能是别的月），钳在 12 个月窗口里。
            let ym = store.currentYearMonth
            pageIndex = min(max(Self.monthIndex(year: ym.year, month: ym.month), pageRange.lowerBound), pageRange.upperBound - 1)
            if store.month == nil {
                await store.refreshMonth()
            }
            // 进页就把前后月也预取好，第一次左右滑就不等网络。
            let next = yearMonth(from: pageIndex + 1)
            let prev = yearMonth(from: pageIndex - 1)
            store.prefetchMonth(year: next.year, month: next.month)
            store.prefetchMonth(year: prev.year, month: prev.month)
            // 1.1.3：阴历缓存预热 + 工资输入补齐（日历的三薪标与底部统计要用）。
            // 阴历按月分批算（主线程，DateFormatter 不线程安全），每批之间让出主线程，
            // 避免一次算 12 个月堵住界面；滑到新月时阴历已是缓存，不再现算。
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
            Task { await store.refreshMonth() }
        }
        .sheet(isPresented: $showDayDetail) {
            if let selectedDay {
                DayDetailView(day: selectedDay)
            }
        }
    }

    // MARK: 头部

    /// 顶栏黑框：今天的年月日、周几、什么班（切到别的月份也照样显示今天）。
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(todayDateLine)
                .font(.title2).bold()
                .foregroundColor(.white)
            Text(todayShiftLine)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppStyle.navy)
        .cornerRadius(16)
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
                    store.viewTeam = team
                } label: {
                    Text("\(team)班")
                        .bold(store.viewTeam == team)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(store.viewTeam == team ? AppStyle.navy : Color(.systemBackground))
                        .foregroundColor(store.viewTeam == team ? .white : .primary)
                        .cornerRadius(20)
                }
            }
        }
    }

    private var monthNavigator: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    pageIndex = max(pageRange.lowerBound, pageIndex - 1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
            }
            Spacer()
            Text(pagerTitle)
                .font(.title3).bold()
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    pageIndex = Self.monthIndex(year: DateUtil.yearMonth(of: Date()).year, month: DateUtil.yearMonth(of: Date()).month)
                }
            } label: {
                Text("今天")
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemBackground))
                    .cornerRadius(14)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    pageIndex = min(pageRange.upperBound - 1, pageIndex + 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
            }
        }
    }

    /// 当前页的标题，如“2027年2月”（跟着滑页走，不用等网络；年份纯数字不带逗号）。
    private var pagerTitle: String {
        let ym = yearMonth(from: pageIndex)
        return DateUtil.yearMonthTitle(year: ym.year, month: ym.month)
    }

    // MARK: 日历滑页（原生分页，跟着手指走）

    /// 周几行（固定在日历上方，不跟月份滑动）：日、六绿色，其余深色，与参考图一致。
    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(Array(weekdayTitles.enumerated()), id: \.offset) { i, title in
                Text(title)
                    .font(.caption)
                    .foregroundColor(i == 0 || i == 6 ? .green : .primary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    private let weekdayTitles = ["日", "一", "二", "三", "四", "五", "六"]

    private var monthPager: some View {
        VStack(spacing: 4) {
            // 周几固定在最上面，不跟月份一起滑（原来在每页里，滑走就没了）。
            weekdayHeader
            // 12 页 TabView：每页固定高（外框总高不变），行距按行数自适应。
            // 滑页时不再重新布局、不再因周数不同伸缩，根治掉帧与页边忽大忽小。
            // 月份数据走 store.monthFor：有缓存直接取，没缓存本地 8 天一轮算好缓存起来，
            // 滑页时不再现算、不再发网络请求。
            TabView(selection: $pageIndex) {
                ForEach(pageRange, id: \.self) { idx in
                    let ym = yearMonth(from: idx)
                    MonthPageView(
                        year: ym.year, month: ym.month,
                        isSelected: { selectedDay?.date == $0 },
                        onSelectDay: { day in
                            selectedDay = day
                            showDayDetail = true
                        },
                        onSelectAdjacentMonth: { y, m in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                pageIndex = Self.monthIndex(year: y, month: m)
                            }
                        }
                    )
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: calendarGridHeight)
            // 1.1.5：裁剪——每页内容绝不漏到邻页上（重叠的最后一道保险）。
            .clipped()
            if store.isLoadingMonth {
                ProgressView("正在加载…")
                    .padding(.top, 8)
            } else if store.viewTeam != store.myTeam {
                Text("看的是 \(store.viewTeam)班的基础排班（8 天一轮），调班/请假只在自己班上显示。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
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
    private var summaryLine: some View {
        Group {
            if let stats = displayedMonth?.stats {
                Text(summaryText(stats: stats))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(AppStyle.cardPadding)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
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
        return "当月应出勤 \(MoneyUtil.int(stats.basicDays)) 天 · 实际出勤 \(MoneyUtil.int(stats.actualShifts)) 个班 · 三薪 \(triple) 天 · 加班 \(overtime) 天 · 请假 \(MoneyUtil.int(stats.leaveDays)) 天 · 休息 \(MoneyUtil.int(stats.restDays)) 天"
    }

    /// 天数显示：整数不带小数（如 0、1），小数保留 1 位。
    private func formatDays(_ value: Double) -> String {
        if value == value.rounded() { return "\(Int(value))" }
        return String(format: "%.1f", value)
    }

    // MARK: 调班 / 请假记录

    private var recordsSection: some View {
        // 本月没有任何调班和请假记录时，整张卡片直接藏掉，不显示“没有记录”那行。
        Group {
            if !mergedSwapRows.isEmpty || !store.leaves.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("本月调班 / 请假")
                        .font(.headline)
                    ForEach(mergedSwapRows, id: \.key) { row in
                        swapRow(row)
                    }
                    ForEach(store.leaves, id: \.date) { leave in
                        HStack(alignment: .top) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text(leave.date)
                                .font(.subheadline)
                            Text(leave.type ?? "请假")
                                .font(.subheadline)
                                .foregroundColor(.red)
                            Spacer()
                            if let note = leave.note, !note.isEmpty {
                                Text(note)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(AppStyle.cardPadding)
                .background(Color(.systemBackground))
                .cornerRadius(AppStyle.cardRadius)
            }
        }
    }

    /// 调班记录按“替班日 + 还班日”并成一条：coverDate / paybackDate 互相指向的算一对。
    private struct SwapRow: Identifiable {
        let key: String
        let records: [SwapRecord]
        var id: String { key }
    }

    private var mergedSwapRows: [SwapRow] {
        let sorted = store.swaps.sorted { $0.date < $1.date }
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
                        .font(.subheadline)
                    Text("调成 \(record.shift ?? "")")
                        .font(.subheadline)
                    if let partner = record.partner, !partner.isEmpty {
                        Text("与 \(partner)班对调")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if let note = record.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            if row.records.count > 1,
               let payback = row.records.compactMap({ $0.paybackDate ?? $0.coverDate }).first {
                Text("还班日：\(payback)")
                    .font(.caption)
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
    let isSelected: (String) -> Bool
    let onSelectDay: (DaySchedule) -> Void
    /// 点到上月/下月补的日期时跳到对应月。
    let onSelectAdjacentMonth: (Int, Int) -> Void

    /// 一格的身份：上月补的 / 本月 / 下月补的（点上月/下月补的跳到对应月）。
    private enum GridDayKind { case leading, current, trailing }

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

    /// 整页的格子（上月补 + 本月 + 下月补，拼满整周）：数据走 store.monthFor（缓存，
    /// 只算一次）。格子总数恒等于 行数×7（上月补 + 本月 + 下月补正好拼满整周）。
    /// 1.1.4：原来是 LazyVGrid，滑页中预取回来写 @Published、视图重算，
    /// LazyVGrid 懒加载重排、格子错位。改成固定 VStack + HStack：
    /// 每格固定 64pt、7 列写死，格子永远在固定位置。
    private var gridDays: [(day: DaySchedule, kind: GridDayKind)] {
        var result: [(DaySchedule, GridDayKind)] = []
        for d in leadingDays { result.append((d, .leading)) }
        for d in (monthData.days ?? []) { result.append((d, .current)) }
        for d in trailingDays { result.append((d, .trailing)) }
        return result
    }

    var body: some View {
        // 1.2.1（老爷 06:57 纠正「固定 6 行」的做法）：总高固定 414pt 不变，
        // 行距按本月行数自适应——5 行的月松一些（23.5pt）、6 行的月紧凑一些（6pt），
        // 行数不同但总高一样，整体对齐，5 行的月不再底部空一行。
        // 关键：行数从快照 snapDays 里算（days.count / 7），快照在滑动中一动不动，
        // 所以行距在动画中途绝不变；快照 + 防抖换月 + 裁剪三件不变。
        // 周几行已抽到 TabView 外面固定不动，这里只画日期网格。
        // 订阅 payInputsVersion：工资输入到齐时三薪标要出现，日历得重画
        //（之前没订阅，输入到了也不重画，三薪标要等别的状态变了才冒出来）。
        // 三薪标仍走 live 的 tripleDates（只是 pill 里一行小字，不动网格结构），
        // 网格本身（snapDays）是快照，滑动中不动。
        let _ = store.payInputsVersion
        let days = snapLoaded ? snapDays : gridDays
        // 格子总数恒等于 行数×7（上月补 + 本月 + 下月补正好拼满整周），行数从快照算。
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
        .clipped()
        .task { takeSnapshot() }
        .onChange(of: store.calendarVersion) { _ in takeSnapshot() }
        .onChange(of: store.viewTeam) { _ in takeSnapshot() }
    }

    /// 一格：按身份给不同的点按行为（本月点开详情，上月/下月补的跳到对应月）。
    /// maxWidth 让格子在 HStack 里均分 7 列（原来 LazyVGrid 的 .flexible() 就是这个作用）。
    @ViewBuilder
    private func gridCell(day: DaySchedule, kind: GridDayKind) -> some View {
        switch kind {
        case .leading:
            DayCell(day: day, isToday: false, isSelected: false, isAdjacent: true)
                .frame(maxWidth: .infinity)
                .onTapGesture { onSelectAdjacentMonth(prevYearMonth.year, prevYearMonth.month) }
        case .current:
            DayCell(day: day, isToday: day.date == DateUtil.string(from: Date()), isSelected: isSelected(day.date), isTriplePay: tripleDates.contains(day.date))
                .frame(maxWidth: .infinity)
                .onTapGesture { onSelectDay(day) }
        case .trailing:
            DayCell(day: day, isToday: false, isSelected: false, isAdjacent: true)
                .frame(maxWidth: .infinity)
                .onTapGesture { onSelectAdjacentMonth(nextYearMonth.year, nextYearMonth.month) }
        }
    }

    /// 本月三薪日（工资算法里 tripleDays 的那几天）：本地算、带缓存；
    /// 输入没到齐算不出时为空（先不标，等输入到了重画）。只在看自己班时有。
    private var tripleDates: Set<String> {
        store.triplePayInfo(year: year, month: month)?.tripleDates ?? []
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

    /// 每月第一周前面补上月末尾几天。
    private var leadingDays: [DaySchedule] {
        let count = DateUtil.firstWeekday(year: year, month: month)
        guard count > 0 else { return [] }
        let prev = store.monthFor(year: prevYearMonth.year, month: prevYearMonth.month)
        return Array((prev.days ?? []).suffix(count))
    }

    /// 每月最后一周后面补下月开头几天，补满整周。
    private var trailingDays: [DaySchedule] {
        let first = DateUtil.firstWeekday(year: year, month: month)
        let days = DateUtil.daysInMonth(year: year, month: month)
        let remainder = (first + days) % 7
        let count = remainder == 0 ? 0 : 7 - remainder
        guard count > 0 else { return [] }
        let next = store.monthFor(year: nextYearMonth.year, month: nextYearMonth.month)
        return Array((next.days ?? []).prefix(count))
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
    let day: DaySchedule
    let isToday: Bool
    let isSelected: Bool
    /// 上月/下月补进来的日期：灰色显示，点后跳到对应月。
    var isAdjacent: Bool = false
    /// 三薪日（工资算法里 tripleDays 的那几天）：色块里加一行半透明「三薪」。
    var isTriplePay: Bool = false

    private let pillHeight: CGFloat = 28

    /// 1.2.2：阳历数字字号按屏宽自适应——iPhone 15 标准版屏宽只有 393pt，
    /// 日期行里左 11pt 假/班列 + 右 8pt 阴历列是写死的，中间只剩约 24pt，
    /// 两位数的号在 16pt 下会被截成「…」；窄屏（<400pt）用 15pt，
    /// 宽屏保持 16pt；再加 lineLimit(1) + minimumScaleFactor(0.75) 兜底，绝不截断。
    private var dayNumberFontSize: CGFloat {
        UIScreen.main.bounds.width < 400 ? 15 : 16
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
                    if let mark = extra.mark, !isAdjacent {
                        if mark == .holiday {
                            // 1.1.5：放假的「假」用白色字体——白字得配绿底 pill 才看得见
                            //（原来是绿字无底；只改字色会白底白字看不见，所以底色跟着换成绿，
                            // 位置/大小/布局不动）。请假的「假」见下面，用红色字体。
                            Text("假")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 1)
                                .padding(.vertical, 1)
                                .background(Color.green)
                                .cornerRadius(3)
                        } else {
                            Text("班")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.red)
                        }
                    } else {
                        Color.clear.frame(width: 11, height: 9)
                    }
                    if day.onLeave == true && !isAdjacent {
                        // 1.1.5：请假的「假」用红色字体——红字配红底看不见，底色去掉变透明
                        //（位置/大小/布局不动，只换字色和底色，和放假的白字绿底区分开）。
                        Text("假")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.red)
                            .padding(.horizontal, 2)
                            .padding(.vertical, 1)
                    }
                }
                .frame(width: 11, alignment: .leading)
                Text("\(day.dayNumber)")
                    .font(.system(size: dayNumberFontSize, weight: isToday ? .bold : .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundColor(isAdjacent ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .center)
                VStack(spacing: 0) {
                    ForEach(Array(displayLunarText.enumerated()), id: \.offset) { _, ch in
                        Text(String(ch))
                            .font(.system(size: 9))
                            .foregroundColor(extra.isRedText ? .red : .secondary)
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
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 15)
                                        .background(ShiftStyle.color(for: part))
                                        .cornerRadius(4)
                                }
                            }
                            Text("三薪")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                                .frame(maxWidth: .infinity)
                                .frame(height: 13)
                                .background(Color.black.opacity(0.22))
                        }
                        .frame(height: pillHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    } else {
                        VStack(spacing: 2) {
                            ForEach(ShiftStyle.parts(of: day.shift), id: \.self) { part in
                                Text(TeamInfo.shortName(part))
                                    .font(.system(size: 10, weight: .bold))
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
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(day.isRest ? ShiftStyle.color(for: "休息") : .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 15)
                        Text("三薪")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .frame(height: 13)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: pillHeight)
                    .background(day.isRest ? ShiftStyle.background(for: "休息") : ShiftStyle.color(for: day.shift))
                    .cornerRadius(7)
                } else {
                    Text(day.isRest ? "休" : TeamInfo.shortName(day.shift))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(day.isRest ? ShiftStyle.color(for: "休息") : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: pillHeight)
                        .background(day.isRest ? ShiftStyle.background(for: "休息") : ShiftStyle.color(for: day.shift))
                        .cornerRadius(7)
                }
            }
            .opacity(isAdjacent ? 0.5 : 1.0)
        }
        .padding(2)
        .frame(height: calendarCellHeight)
        .background(isSelected ? Color.blue.opacity(0.12) : Color.clear)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isToday ? Color.green : (isSelected ? Color.blue : Color.clear), lineWidth: isToday ? 2 : 1.5)
        )
    }
}
