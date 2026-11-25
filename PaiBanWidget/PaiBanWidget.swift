import AppIntents
import SwiftUI
import WidgetKit

// MARK: - 入口

/// 小组件时间线（1.2.8）：数据来源按顺序——
/// ① App Group 快照（App 写、小组件读；通的机器上最快、离线也能看）；
/// ② 服务端直拉（小组件配置里填了 API 密钥才拉；重签描述文件不带 App Group 时的后备路）；
/// ③ 缓存的服务端数据（离线时显示上次的数，不回占位）；
/// ④ 都没有 → 占位「打开 App 登录后显示」。
/// 今日实时状态（倒计时/已挣）按 entry 时刻现算；工资是拉回/快照里算好的数。
struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), snapshot: .preview, live: .rest)
    }

    func snapshot(for configuration: WidgetAPIKeyIntent, in context: Context) async -> Entry {
        makeEntry(date: Date(), snapshot: await currentSnapshot(apiKey: configuration.apiKey))
    }

    func timeline(for configuration: WidgetAPIKeyIntent, in context: Context) async -> Timeline<Entry> {
        let now = Date()
        let snapshot = await currentSnapshot(apiKey: configuration.apiKey)
        var dates: [Date] = [now]
        if let today = snapshot?.today {
            // 班中每 15 分钟 + 上下班边界各一次（工资数靠这些点刷新；倒计时是系统 timer 文本、实时走）。
            dates += PayCalc.todayRefreshDates(shift: today.shift, day: DateUtil.calendar.startOfDay(for: now), now: now)
        }
        // 明天 00:00 再来一条（跨天换班次）。
        dates.append(DateUtil.calendar.startOfDay(for: DateUtil.addingDays(now, 1)))
        let entries = dates.map { makeEntry(date: $0, snapshot: snapshot) }
        return Timeline(entries: entries, policy: .atEnd)
    }

    /// 当前快照：App Group 优先；没有就服务端直拉（配了密钥才拉）；拉不到用缓存。
    private func currentSnapshot(apiKey: String?) async -> WidgetSnapshot? {
        if let snap = WidgetSnapshotStore.load() { return snap }
        let key = (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty, let fetched = await WidgetServerClient.fetchSnapshot(apiKey: key) {
            return fetched
        }
        return WidgetServerClient.loadCached()
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
        AppIntentConfiguration(kind: "TodayWidget", intent: WidgetAPIKeyIntent.self, provider: Provider()) { entry in
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
        AppIntentConfiguration(kind: "WeekWidget", intent: WidgetAPIKeyIntent.self, provider: Provider()) { entry in
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
        AppIntentConfiguration(kind: "PayWidget", intent: WidgetAPIKeyIntent.self, provider: Provider()) { entry in
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
        AppIntentConfiguration(kind: "MonthWidget", intent: WidgetAPIKeyIntent.self, provider: Provider()) { entry in
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
        AppIntentConfiguration(kind: "LockWidget", intent: WidgetAPIKeyIntent.self, provider: Provider()) { entry in
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
