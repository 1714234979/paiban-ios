import SwiftUI

/// 排班页：原生月历。每个日期格里的班次 pill 都是同一固定高度（28pt、通栏圆角），
/// 修掉网页版“日班绿块占满整格、别的班只是短 pill”的 bug。
struct CalendarView: View {
    @EnvironmentObject private var store: AppStore

    @State private var selectedDay: DaySchedule?
    @State private var showDayDetail = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdayTitles = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                teamSwitcher
                monthNavigator
                calendarGrid
                summaryLine
                recordsSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .task {
            if store.month == nil {
                await store.refreshMonth()
            }
        }
        .onChange(of: store.currentMonth) { _ in
            Task { await store.refreshMonth() }
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

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("排班空间")
                .font(.title2).bold()
                .foregroundColor(.white)
            Text("603车间 · 8天一轮倒班")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.75))
            if store.isOffline {
                Label("离线缓存", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(red: 0.11, green: 0.15, blue: 0.23))
        .cornerRadius(16)
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
            Button { store.moveMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
            }
            Spacer()
            Text(DateUtil.monthFormatter.string(from: store.currentMonth))
                .font(.title3).bold()
            Button {
                store.goToTodayMonth()
            } label: {
                Text("今天")
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemBackground))
                    .cornerRadius(14)
            }
            Spacer()
            Button { store.moveMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
            }
        }
    }

    // MARK: 日历网格

    private var calendarGrid: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(weekdayTitles, id: \.self) { title in
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(blankCells, id: \.self) { _ in
                    Color.clear
                        .frame(height: cellHeight)
                }
                ForEach(store.month?.days ?? [], id: \.date) { day in
                    DayCell(day: day, isToday: isToday(day), isSelected: selectedDay?.date == day.date)
                        .onTapGesture {
                            selectedDay = day
                            showDayDetail = true
                        }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        if value.translation.width < -50 {
                            store.moveMonth(by: 1)
                        } else if value.translation.width > 50 {
                            store.moveMonth(by: -1)
                        }
                    }
            )
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

    /// 日期格总高：日期行 + 28pt pill + 节假日名行，保持每格等高。
    private var cellHeight: CGFloat { 26 + 28 + 14 + 6 }

    private var blankCells: [Int] {
        let ym = store.currentYearMonth
        let count = DateUtil.firstWeekday(year: ym.year, month: ym.month)
        return Array(0..<count)
    }

    private func isToday(_ day: DaySchedule) -> Bool {
        day.date == DateUtil.string(from: Date())
    }

    // MARK: 月度汇总

    private var summaryLine: some View {
        Group {
            if let stats = store.month?.stats {
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
        VStack(alignment: .leading, spacing: 8) {
            Text("本月调班 / 请假")
                .font(.headline)
            if mergedSwapRows.isEmpty && store.leaves.isEmpty {
                Text("本月没有调班和请假记录")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            }
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

// MARK: - 日期格

/// 关键：所有班次的 pill 都是同一固定高度 28pt、通栏、圆角；
/// 双班时在同一个 28pt 高度里上下叠两个 13pt 小 pill，不撑高格子。
struct DayCell: View {
    let day: DaySchedule
    let isToday: Bool
    let isSelected: Bool

    private let pillHeight: CGFloat = 28

    var body: some View {
        VStack(spacing: 2) {
            // 日期行：号数 + 请假红标
            ZStack {
                if isToday {
                    Circle()
                        .fill(Color(red: 0.11, green: 0.15, blue: 0.23))
                        .frame(width: 24, height: 24)
                }
                HStack(spacing: 2) {
                    Text("\(day.dayNumber)")
                        .font(.system(size: 13, weight: isToday ? .bold : .regular))
                        .foregroundColor(isToday ? .white : .primary)
                    if day.onLeave == true {
                        Text("假")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                }
            }
            .frame(height: 26)

            // 班次 pill：固定 28pt，所有班次一样高
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

            // 节假日名行：固定高度，没有就留空，保证每格等高
            Text(day.holiday ?? "")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(height: 14)
        }
        .padding(2)
        .background(isSelected ? Color.blue.opacity(0.12) : Color.clear)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
        )
    }
}
