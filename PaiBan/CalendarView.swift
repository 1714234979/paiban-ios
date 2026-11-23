import SwiftUI

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
        }
        // 滑到哪页，Store 就跟到哪月（汇总、调班/请假记录都跟着走），并预取前后月。
        // 相邻月预取不等当前月刷新完，并行发起，切月不再出现「加载中」。
        .onChange(of: pageIndex) { newIndex in
            let ym = yearMonth(from: newIndex)
            store.setCurrentMonth(year: ym.year, month: ym.month)
            let next = yearMonth(from: newIndex + 1)
            let prev = yearMonth(from: newIndex - 1)
            store.prefetchMonth(year: next.year, month: next.month)
            store.prefetchMonth(year: prev.year, month: prev.month)
            Task {
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
        .background(Color(red: 0.11, green: 0.15, blue: 0.23))
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
                        .background(store.viewTeam == team ? Color(red: 0.11, green: 0.15, blue: 0.23) : Color(.systemBackground))
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
    private var displayedMonth: MonthSchedule? {
        let ym = store.currentYearMonth
        return store.monthFor(year: ym.year, month: ym.month)
    }

    // MARK: 月度汇总

    private var summaryLine: some View {
        Group {
            if let stats = displayedMonth?.stats {
                Text("当月应出勤 \(MoneyUtil.int(stats.basicDays)) 天 · 实际出勤 \(MoneyUtil.int(stats.actualShifts)) 个班 · 双班 \(MoneyUtil.int(stats.doubleDays)) 天 · 请假 \(MoneyUtil.int(stats.leaveDays)) 天 · 休息 \(MoneyUtil.int(stats.restDays)) 天")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
            }
        }
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
                        HStack {
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
                .padding(12)
                .background(Color(.systemBackground))
                .cornerRadius(16)
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
                HStack {
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
/// 没缓存先按本地 8 天一轮算顶上（秒出、不闪白），真数据到了页面自己刷新。
struct MonthPageView: View {
    @EnvironmentObject private var store: AppStore
    let year: Int
    let month: Int
    let isSelected: (String) -> Bool
    let onSelectDay: (DaySchedule) -> Void
    /// 点到上月/下月补的日期时跳到对应月。
    let onSelectAdjacentMonth: (Int, Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    /// 本月占几行（4–6 周）。
    private var numberOfWeeks: Int {
        let first = DateUtil.firstWeekday(year: year, month: month)
        let days = DateUtil.daysInMonth(year: year, month: month)
        return Int(ceil(Double(first + days) / 7.0))
    }

    var body: some View {
        // 行距按行数自适应（6 行紧、5 行松），外框总高固定，滑动不伸缩。
        // 周几行已抽到 TabView 外面固定不动，这里只画日期网格。
        LazyVGrid(columns: columns, spacing: calendarRowSpacing(weeks: numberOfWeeks)) {
            // 上月末尾几天（灰色，点后跳到上月），第一周不再留空白格。
            ForEach(leadingDays, id: \.date) { day in
                DayCell(day: day, isToday: false, isSelected: false, isAdjacent: true)
                    .onTapGesture { onSelectAdjacentMonth(prevYearMonth.year, prevYearMonth.month) }
            }
            ForEach(monthData.days ?? [], id: \.date) { day in
                DayCell(day: day, isToday: day.date == DateUtil.string(from: Date()), isSelected: isSelected(day.date))
                    .onTapGesture { onSelectDay(day) }
            }
            // 下月开头几天（灰色，点后跳到下月），最后一周补满，左右滑动无断层。
            ForEach(trailingDays, id: \.date) { day in
                DayCell(day: day, isToday: false, isSelected: false, isAdjacent: true)
                    .onTapGesture { onSelectAdjacentMonth(nextYearMonth.year, nextYearMonth.month) }
            }
        }
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
/// 整格固定 64pt（日期行 28 + 间距 4 + pill 28 + 上下边距 4），行距自适应靠网格间距调。
struct DayCell: View {
    let day: DaySchedule
    let isToday: Bool
    let isSelected: Bool
    /// 上月/下月补进来的日期：灰色显示，点后跳到对应月。
    var isAdjacent: Bool = false

    private let pillHeight: CGFloat = 28

    /// 当天的阴历/节气/节日/假班信息（查表 + 中国日历算，带缓存，渲染时不重算）。
    private var extra: ChineseCalendar.DayInfo {
        ChineseCalendar.info(for: day.date)
    }

    var body: some View {
        VStack(spacing: 4) {
            // 日期行（三栏，互不重叠）：左 假/班角标（10pt，没有留空、号数位置一致）
            // + 中 阳历大数字（居中，请假红标跟在号数后）
            // + 右 阴历/节气/节日小字（竖排两字，节气/节日红字、阴历灰字）。
            HStack(alignment: .top, spacing: 1) {
                if let mark = extra.mark, !isAdjacent {
                    Text(mark == .holiday ? "假" : "班")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(mark == .holiday ? .green : .red)
                        .frame(width: 10, alignment: .leading)
                } else {
                    Color.clear.frame(width: 10, height: 9)
                }
                HStack(alignment: .top, spacing: 2) {
                    Text("\(day.dayNumber)")
                        .font(.system(size: 18, weight: isToday ? .bold : .semibold))
                        .foregroundColor(isAdjacent ? .secondary : .primary)
                    if day.onLeave == true && !isAdjacent {
                        Text("假")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.red)
                            .cornerRadius(4)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                VStack(spacing: 0) {
                    ForEach(Array(extra.lunarText.enumerated()), id: \.offset) { _, ch in
                        Text(String(ch))
                            .font(.system(size: 9))
                            .foregroundColor(extra.isRedText ? .red : .secondary)
                    }
                }
                .frame(width: 9, alignment: .leading)
                .padding(.top, 1)
            }
            .frame(height: 28)

            // 班次 pill：固定 28pt；补的日期用班次色但半透明（班次色不变，只是淡一点）。
            Group {
                if day.isDouble == true {
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
