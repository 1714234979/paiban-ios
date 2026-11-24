import WidgetKit
import SwiftUI

// 小组件视图（App 与小组件扩展共用）：
// 小组件本体（PaiBanWidget.swift）只留 Provider + 五个 Widget 结构；
// 调试图（WidgetPreviewGallery，DEBUG）也直接渲染同一套视图，出图与真机一致。

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?   // nil = 没登录/没数据 → 显示占位
    let live: PayCalc.TodayLiveState
}

// MARK: - 视图

/// 没登录/没数据时的占位：点一下进 App（登录后就有数据）。
struct WidgetPlaceholderView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("打开 App 登录后显示")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "paiban://schedule"))
    }
}

/// 锁屏上的占位（圆形里放不下整句话，只放一个日历标）。
struct LockPlaceholderView: View {
    var body: some View {
        Image(systemName: "calendar")
            .widgetURL(URL(string: "paiban://schedule"))
    }
}

/// 小：今日班次。
/// 上：日期 + 班组；中：班次大字（班次色）+ 时间段；下：倒计时（系统 timer 文本、实时走）+ 已挣/预估。
struct TodayWidgetView: View {
    let entry: Entry
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(dateLine)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(snapshot.team)班")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let today = snapshot.today {
                if today.onLeave {
                    Text("请假")
                        .font(.title2).bold()
                        .foregroundColor(.secondary)
                    Text(today.leaveType ?? "请假")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if today.shift == "休息" {
                    Text("休息")
                        .font(.title2).bold()
                        .foregroundColor(ShiftStyle.color(for: "休息"))
                    Text("今日休息")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(today.shift)
                        .font(.title2).bold()
                        .foregroundColor(shiftPillColor(today.shift))
                    Text(ShiftStyle.timeRange(for: today.shift))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    // 倒计时（系统 timer 文本，iOS 自己实时走；小组件不让每秒刷新，工资数靠时间线 15 分钟一跳）。
                    if let range = countdownRange {
                        Text(timerInterval: range, countsDown: true)
                            .font(.headline)
                            .monospacedDigit()
                    }
                    if let money = moneyLine {
                        Text(money)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .widgetURL(URL(string: "paiban://schedule"))
    }

    /// 「11月25日 周三」。
    private var dateLine: String {
        let ym = DateUtil.yearMonth(of: entry.date)
        let day = DateUtil.calendar.component(.day, from: entry.date)
        return "\(ym.month)月\(day)日 \(DateUtil.weekdayCN(of: entry.date))"
    }

    /// 倒计时区间：上班前 → 到上班；上班中 → 到下班；两班之间 → 到下一班；下班后/休息 → 没有。
    private var countdownRange: ClosedRange<Date>? {
        switch entry.live {
        case .before(let start, _): return entry.date...start
        case .working(let end, _, _): return entry.date...end
        case .between(let nextStart, _, _): return entry.date...nextStart
        default: return nil
        }
    }

    /// 钱那行：上班前「预估 ¥XXX」；上班中「已挣 ¥X · 预估 ¥XXX」；下班后「今日已挣 ¥XXX」；休息没有。
    /// 三薪那天末尾带「（三薪）」。
    private var moneyLine: String? {
        let triple = (snapshot.today.map { PayCalc.isStatutoryDay($0.date) } ?? false) ? "（三薪）" : ""
        switch entry.live {
        case .rest: return nil
        case .before(_, let total): return "预估 \(MoneyUtil.money(total))\(triple)"
        case .working(_, let earned, let total): return "已挣 \(MoneyUtil.money(earned)) · 预估 \(MoneyUtil.money(total))\(triple)"
        case .between(_, let earned, let total): return "已挣 \(MoneyUtil.money(earned)) · 预估 \(MoneyUtil.money(total))\(triple)"
        case .done(let total): return "今日已挣 \(MoneyUtil.money(total))\(triple)"
        }
    }
}

/// 中①：本周排班——七天班次色块，当天高亮，底下一行今天的班次与时间。
struct WeekWidgetView: View {
    let entry: Entry
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("本周排班")
                    .font(.headline)
                Spacer()
                Text(weekDateLine)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 2) {
                ForEach(snapshot.week, id: \.date) { day in
                    VStack(spacing: 3) {
                        Text(weekdayShort(day.date))
                            .font(.caption2)
                            .foregroundColor(day.isToday ? .primary : .secondary)
                        Text(dayNumber(day.date))
                            .font(.subheadline)
                            .bold(day.isToday)
                        Text(shiftPillText(day.shift))
                            .font(.caption2).bold()
                            .foregroundColor(day.shift == "休息" ? ShiftStyle.color(for: "休息") : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                            .background(day.shift == "休息" ? ShiftStyle.background(for: "休息") : shiftPillColor(day.shift))
                            .cornerRadius(5)
                    }
                    .padding(.vertical, 2)
                    .background(day.isToday ? Color.primary.opacity(0.06) : Color.clear)
                    .cornerRadius(6)
                }
            }
            if let today = snapshot.today {
                Text(todayLine(today))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .widgetURL(URL(string: "paiban://schedule"))
    }

    /// 「11月25日 周三」。
    private var weekDateLine: String {
        let ym = DateUtil.yearMonth(of: entry.date)
        let day = DateUtil.calendar.component(.day, from: entry.date)
        return "\(ym.month)月\(day)日 \(DateUtil.weekdayCN(of: entry.date))"
    }

    /// 「今天 · 日班 08:00–16:00」/「今天 · 休息」/「今天 · 请假（年假）」。
    private func todayLine(_ today: WidgetSnapshot.Day) -> String {
        if today.onLeave {
            return "今天 · 请假" + (today.leaveType.map { "（\($0)）" } ?? "")
        }
        if today.shift == "休息" {
            return "今天 · 休息"
        }
        return "今天 · \(today.shift) \(ShiftStyle.timeRange(for: today.shift))"
    }
}

/// 中②：本月工资——应发/实发工资/实发奖金/合计（App 本地算好的数）。
/// 快照里的工资月份对不上当前月时（App 很久没开），显示「打开 App 同步一下」，不拿旧数充数。
struct PayWidgetView: View {
    let entry: Entry
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("本月工资")
                    .font(.headline)
                Text("· \(snapshot.month)月")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("预估")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(5)
            }
            if let pay = snapshot.pay, pay.year == DateUtil.yearMonth(of: entry.date).year, pay.month == DateUtil.yearMonth(of: entry.date).month {
                payRow("应发", pay.salarySubtotal)
                payRow("实发工资", pay.salaryNet)
                payRow("实发奖金", pay.bonusAfterTax)
                Divider()
                HStack {
                    Text("合计")
                        .font(.subheadline).bold()
                    Spacer()
                    Text(MoneyUtil.money(pay.grandTotal))
                        .font(.headline).bold()
                }
            } else {
                Text("打开 App 同步一下")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .widgetURL(URL(string: "paiban://pay"))
    }

    private func payRow(_ label: String, _ value: Double?) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(MoneyUtil.money(value))
        }
        .font(.subheadline)
    }
}

/// 大：本月日历——整月网格 + 班次色块 + 当天高亮，底下一行今天的班次。
struct MonthWidgetView: View {
    let entry: Entry
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(snapshot.month)月")
                    .font(.headline)
                Text("· \(snapshot.team)班")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(monthDateLine)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 2) {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { w in
                    Text(w)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(cells, id: \.id) { cell in
                    if let day = cell.day {
                        VStack(spacing: 1) {
                            Text(dayNumber(day.date))
                                .font(.system(size: 12))
                            Text(shiftPillText(day.shift))
                                .font(.system(size: 9)).bold()
                                .foregroundColor(day.shift == "休息" ? ShiftStyle.color(for: "休息") : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 2)
                                .background(day.shift == "休息" ? ShiftStyle.background(for: "休息") : shiftPillColor(day.shift))
                                .cornerRadius(4)
                        }
                        .padding(2)
                        .background(day.isToday ? Color.green.opacity(0.12) : Color.clear)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(day.isToday ? Color.green : Color.clear, lineWidth: 1.5)
                        )
                    } else {
                        Color.clear
                            .frame(minHeight: 40)
                    }
                }
            }
            if let today = snapshot.today {
                Text(todayLine(today))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(12)
        .widgetURL(URL(string: "paiban://schedule"))
    }

    /// 「11月25日 周三」。
    private var monthDateLine: String {
        let ym = DateUtil.yearMonth(of: entry.date)
        let day = DateUtil.calendar.component(.day, from: entry.date)
        return "\(ym.month)月\(day)日 \(DateUtil.weekdayCN(of: entry.date))"
    }

    /// 网格格子：月初空白 + 本月每天，不足 5 行补到 35 格、不足 6 行补到 42 格（行数固定，不跳）。
    private var cells: [MonthCell] {
        var result: [MonthCell] = []
        var id = 0
        let first = DateUtil.firstDayOfMonth(year: snapshot.monthYear, month: snapshot.month) ?? Date()
        let blanks = DateUtil.calendar.component(.weekday, from: first) - 1
        for _ in 0..<blanks {
            result.append(MonthCell(id: id, day: nil))
            id += 1
        }
        for day in snapshot.monthDays {
            result.append(MonthCell(id: id, day: day))
            id += 1
        }
        let target = result.count <= 35 ? 35 : 42
        while result.count < target {
            result.append(MonthCell(id: id, day: nil))
            id += 1
        }
        return result
    }

    private func todayLine(_ today: WidgetSnapshot.Day) -> String {
        if today.onLeave {
            return "今天 · 请假" + (today.leaveType.map { "（\($0)）" } ?? "")
        }
        if today.shift == "休息" {
            return "今天 · 休息"
        }
        return "今天 · \(today.shift) \(ShiftStyle.timeRange(for: today.shift))"
    }
}

private struct MonthCell: Identifiable {
    let id: Int
    let day: WidgetSnapshot.Day?
}

/// 锁屏：圆形 = 今日已挣大数字（班次色点缀），休息显示「休」；
/// 矩形 = 两行「早班 · 已挣 ¥123.45」+「还剩 3小时12分」，休息显示「今日休息」。
struct LockWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry
    let snapshot: WidgetSnapshot

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        default:
            circularView
        }
    }

    private var circularView: some View {
        Group {
            if let today = snapshot.today {
                if today.onLeave {
                    Text("假")
                        .font(.title2).bold()
                        .foregroundColor(.secondary)
                } else if today.shift == "休息" {
                    Text("休")
                        .font(.title2).bold()
                        .foregroundColor(ShiftStyle.color(for: "休息"))
                } else {
                    VStack(spacing: 0) {
                        Text(MoneyUtil.money0(earnedAmount))
                            .font(.title3).bold()
                            .foregroundColor(shiftPillColor(today.shift))
                            .minimumScaleFactor(0.6)
                        Text("已挣")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .widgetURL(URL(string: "paiban://schedule"))
    }

    private var rectangularView: some View {
        Group {
            if let today = snapshot.today {
                if today.onLeave {
                    Text("今日请假")
                        .font(.headline)
                } else if today.shift == "休息" {
                    Text("今日休息")
                        .font(.headline)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(today.shift) · 已挣 \(MoneyUtil.money(earnedAmount))")
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let range = countdownRange {
                            HStack(spacing: 2) {
                                Text(countdownPrefix)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(timerInterval: range, countsDown: true)
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                        } else {
                            Text("今日已下班")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .widgetURL(URL(string: "paiban://schedule"))
    }

    /// 已挣：上班中/两班之间 = 到 entry 时刻挣的；下班后 = 全额；上班前/休息 = 0。
    private var earnedAmount: Double {
        switch entry.live {
        case .working(_, let earned, _), .between(_, let earned, _): return earned
        case .done(let total): return total
        default: return 0
        }
    }

    /// 倒计时区间（同小组件）：上班前 → 到上班；上班中 → 到下班；两班之间 → 到下一班。
    private var countdownRange: ClosedRange<Date>? {
        switch entry.live {
        case .before(let start, _): return entry.date...start
        case .working(let end, _, _): return entry.date...end
        case .between(let nextStart, _, _): return entry.date...nextStart
        default: return nil
        }
    }

    /// 倒计时前缀：上班前是「距上班」，上班中/两班之间是「还剩」。
    private var countdownPrefix: String {
        if case .before = entry.live { return "距上班 " }
        return "还剩 "
    }
}

// MARK: - 小工具

/// 班次色块上的字：单班取单字（日/中/早/休），双班取两字（早中/日中）。
private func shiftPillText(_ shift: String) -> String {
    let parts = ShiftStyle.parts(of: shift)
    if parts.count == 2 {
        return parts.map { TeamInfo.shortName($0) }.joined()
    }
    return TeamInfo.shortName(shift)
}

/// 班次色：双班取第一个班的颜色（早中班取早班紫，日中班取日班绿），其余照 ShiftStyle。
private func shiftPillColor(_ shift: String) -> Color {
    let parts = ShiftStyle.parts(of: shift)
    if parts.count == 2 {
        return ShiftStyle.color(for: parts[0])
    }
    return ShiftStyle.color(for: shift)
}

/// 「周三」→「三」；「周日」→「日」。
private func weekdayShort(_ dateString: String) -> String {
    guard let date = DateUtil.date(from: dateString) else { return "" }
    return String(DateUtil.weekdayCN(of: date).suffix(1))
}

/// 「2026-11-25」→「25」。
private func dayNumber(_ dateString: String) -> String {
    guard let date = DateUtil.date(from: dateString) else { return "" }
    return String(DateUtil.calendar.component(.day, from: date))
}
