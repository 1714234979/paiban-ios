#if DEBUG
import SwiftUI

/// 小组件截图画廊：只在 DEBUG 包里编进（Release 包没有，不会发出去）。
/// 模拟器启动参数：--widget-preview <today|week|pay|month|lock-circular|lock-rectangular>
/// 演示数据：2026-11-24 周二、B 班早班 00:00–08:00，05:23 上班中。
/// 班次按真 8 天轮算（ScheduleCalculator），工资按基本工资 2420 口径——
/// 不是真人实时数据，是给老爷看样子用的；真机装上后小组件读 App 里自己的排班/工资。
/// 注意：画廊里的倒计时是系统 timer 文本、按真实现在走；截图 workflow 会先把
/// runner 的系统时间拨到 2026-11-24 05:23，再跑画廊，倒计时才对得上。
struct WidgetPreviewGallery: View {
    let kind: String

    var body: some View {
        let snap = Self.demoSnapshot()
        let entry = Self.demoEntry(snapshot: snap)
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            widgetView(entry: entry, snapshot: snap)
        }
    }

    @ViewBuilder
    private func widgetView(entry: Entry, snapshot: WidgetSnapshot) -> some View {
        switch kind {
        case "week":
            WeekWidgetView(entry: entry, snapshot: snapshot)
                .frame(width: 379, height: 184)
                .background(Color(.systemBackground))
                .cornerRadius(22)
        case "pay":
            PayWidgetView(entry: entry, snapshot: snapshot)
                .frame(width: 379, height: 184)
                .background(Color(.systemBackground))
                .cornerRadius(22)
        case "month":
            MonthWidgetView(entry: entry, snapshot: snapshot)
                .frame(width: 379, height: 390)
                .background(Color(.systemBackground))
                .cornerRadius(22)
        case "lock-circular":
            LockWidgetView(entry: entry, snapshot: snapshot, overrideFamily: .accessoryCircular)
                .environment(\.colorScheme, .dark)
                .frame(width: 76, height: 76)
                .background(Color.black)
                .clipShape(Circle())
        case "lock-rectangular":
            LockWidgetView(entry: entry, snapshot: snapshot, overrideFamily: .accessoryRectangular)
                .environment(\.colorScheme, .dark)
                .frame(width: 152, height: 68)
                .background(Color.black)
                .cornerRadius(16)
        default: // "today" — 临时改成开屏 v4 预览（1.2.7.010 验开屏用，验完改回 TodayWidgetView）
            SplashView()
        }
    }

    /// 演示快照：2026-11-24 周二、B 班早班；本周 11-22（周日）起、本月 11 月整月。
    private static func demoSnapshot() -> WidgetSnapshot {
        let cal = DateUtil.calendar
        let demoDay = cal.date(from: DateComponents(year: 2026, month: 11, day: 24))!
        func day(_ date: Date) -> WidgetSnapshot.Day {
            let ds = DateUtil.string(from: date)
            let shift = ScheduleCalculator.baseShift(team: "B", date: date)
            return WidgetSnapshot.Day(date: ds, shift: shift, onLeave: false, leaveType: nil, isToday: ds == "2026-11-24")
        }
        let weekStart = DateUtil.addingDays(demoDay, -2) // 11-22 周日
        let week = (0..<7).map { day(DateUtil.addingDays(weekStart, $0)) }
        var monthDays: [WidgetSnapshot.Day] = []
        for d in 1...30 {
            if let date = cal.date(from: DateComponents(year: 2026, month: 11, day: d)) {
                monthDays.append(day(date))
            }
        }
        return WidgetSnapshot(
            savedAt: demoDay,
            displayName: "张晓文",
            team: "B",
            teamHistory: [TeamHistoryEntry(team: "B", effectiveFrom: "2026-11-02")],
            today: day(demoDay),
            week: week,
            monthDays: monthDays,
            monthYear: 2026,
            month: 11,
            pay: WidgetSnapshot.preview.pay,
            baseSalary: 2420,
            earlyRate: 70,
            midRate: 30,
            mealRate: 10
        )
    }

    /// 演示 entry：2026-11-24 05:23:11，上班中（倒计时到 08:00，已挣约 ¥129）。
    private static func demoEntry(snapshot: WidgetSnapshot) -> Entry {
        let cal = DateUtil.calendar
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 5, minute: 23, second: 11))!
        let dayStart = cal.startOfDay(for: now)
        let live = PayCalc.todayLiveState(shift: "早班", onLeave: false, day: dayStart, now: now, baseSalary: 2420, dateString: "2026-11-24", earlyRate: 70, midRate: 30, mealRate: 10)
        return Entry(date: now, snapshot: snapshot, live: live)
    }
}

/// 模拟器启动参数 --widget-preview <kind>，没传返回 nil（正常进 App）。
enum WidgetPreviewLaunch {
    static var kind: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--widget-preview"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
#endif
