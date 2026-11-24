import WidgetKit
import SwiftUI

// MARK: - 入口

/// 小组件时间线：快照只读 App Group 共享区里的 WidgetSnapshot（App 写、小组件读），
/// 不跑网络、不算月工资（工资是 App 本地算好的数）；今日实时状态（倒计时/已挣）按 entry 时刻现算。
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), snapshot: .preview, live: .rest)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(makeEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore.load()
        var dates: [Date] = [now]
        if let today = snapshot?.today {
            // 班中每 15 分钟 + 上下班边界各一次（工资数靠这些点刷新；倒计时是系统 timer 文本、实时走）。
            dates += PayCalc.todayRefreshDates(shift: today.shift, day: DateUtil.calendar.startOfDay(for: now), now: now)
        }
        // 明天 00:00 再来一条（跨天换班次）。
        dates.append(DateUtil.calendar.startOfDay(for: DateUtil.addingDays(now, 1)))
        let entries = dates.map { makeEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// 某时刻的 entry：按那一刻算今日实时状态（倒计时/已挣）。
    private func makeEntry(date: Date, snapshot: WidgetSnapshot? = nil) -> Entry {
        let snap = snapshot ?? WidgetSnapshotStore.load()
        let live: PayCalc.TodayLiveState
        if let today = snap?.today, let todayDate = DateUtil.date(from: today.date) {
            live = PayCalc.todayLiveState(shift: today.shift, onLeave: today.onLeave, day: todayDate, now: date, baseSalary: snap?.baseSalary ?? 2420, dateString: today.date, earlyRate: snap?.earlyRate ?? 70, midRate: snap?.midRate ?? 30, mealRate: snap?.mealRate ?? 10)
        } else {
            live = .rest
        }
        return Entry(date: date, snapshot: snap, live: live)
    }
}

@main
struct PaiBanWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        WeekWidget()
        PayWidget()
        MonthWidget()
        LockWidget()
    }
}

// MARK: - 五个组件

/// 小：今日班次 + 倒计时 + 今日预估工资。点进排班页。
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: Provider()) { entry in
            if let snap = entry.snapshot {
                TodayWidgetView(entry: entry, snapshot: snap)
            } else {
                WidgetPlaceholderView()
            }
        }
        .configurationDisplayName("今日排班")
        .description("今天的班次、倒计时与今日预估工资。")
        .supportedFamilies([.systemSmall])
    }
}

/// 中①：本周排班。点进排班页。
struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekWidget", provider: Provider()) { entry in
            if let snap = entry.snapshot {
                WeekWidgetView(entry: entry, snapshot: snap)
            } else {
                WidgetPlaceholderView()
            }
        }
        .configurationDisplayName("本周排班")
        .description("本周七天班次，当天高亮。")
        .supportedFamilies([.systemMedium])
    }
}

/// 中②：本月工资。点进工资页。
struct PayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PayWidget", provider: Provider()) { entry in
            if let snap = entry.snapshot {
                PayWidgetView(entry: entry, snapshot: snap)
            } else {
                WidgetPlaceholderView()
            }
        }
        .configurationDisplayName("本月工资")
        .description("本月应发、实发工资与实发奖金。")
        .supportedFamilies([.systemMedium])
    }
}

/// 大：本月日历。点进排班页。
struct MonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MonthWidget", provider: Provider()) { entry in
            if let snap = entry.snapshot {
                MonthWidgetView(entry: entry, snapshot: snap)
            } else {
                WidgetPlaceholderView()
            }
        }
        .configurationDisplayName("本月日历")
        .description("整月网格与班次色块，当天高亮。")
        .supportedFamilies([.systemLarge])
    }
}

/// 锁屏：圆形 + 矩形。点进排班页。
struct LockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockWidget", provider: Provider()) { entry in
            if let snap = entry.snapshot {
                LockWidgetView(entry: entry, snapshot: snap)
            } else {
                LockPlaceholderView()
            }
        }
        .configurationDisplayName("今日已挣")
        .description("锁屏上看今天已挣多少钱、还剩多久下班。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
