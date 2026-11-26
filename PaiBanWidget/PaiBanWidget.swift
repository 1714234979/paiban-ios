import SwiftUI
import UIKit
import WidgetKit

// MARK: - 入口

/// 小组件时间线（1.2.7.006 重写）：密钥彻底拿掉，不再有任何配置项，
/// 小组件不再向用户要密钥。数据来源按顺序——
/// ① App Group 快照（App 写、小组件读；通的机器上最快、离线也能看；
///    权限与代码原样保留，后期上架商店正规签名时用它）；
/// ② 新鲜缓存（15 分钟内，立刻出数，不等网络）；
/// ③ 设备直连（App 登录时登记过 identifierForVendor，小组件带
///    X-Device-Id 拉；云和 NAS 隧道并行抢答、先到先得，总共 8 秒封顶；
///    班次是核心必须拿到，工资和配置拉不到也不拖垮整个快照）；
/// ④ 旧缓存的服务端数据（离线时显示上次的数，不回占位）；
/// ⑤ 都没有 → 占位「打开 App 登录后显示」。
/// 今日实时状态（倒计时/已挣）按 entry 时刻现算；工资是拉回/快照里算好的数。
///
/// 之前为什么坏（1.2.7.004/005 的教训，别再犯）：
/// 设备拉取串行云 10 秒 + 隧道 10 秒，失败后密钥再拉 20 秒，两段加起来
/// 40 秒，WidgetKit 预算一到就杀扩展、显示占位——密钥本身没错，是根本
/// 轮不到它跑完，所以「填了密钥也不能用」。这次云和隧道并行抢答，
/// 单次取数 8 秒封顶，密钥那条路整个删掉，不再让用户填。
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), snapshot: .preview, live: .rest)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        Task {
            completion(makeEntry(date: Date(), snapshot: await currentSnapshot()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Task {
            let now = Date()
            let snapshot = await currentSnapshot()
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
    }

    /// 当前快照：App Group 优先；新鲜缓存（15 分钟内）其次，立刻出数不等网络；
    /// 缓存过期才拉网（设备直连，不用密钥，云和隧道并行抢答 8 秒封顶）；
    /// 拉不到用旧缓存。
    private func currentSnapshot() async -> WidgetSnapshot? {
        if let snap = WidgetSnapshotStore.load() { return snap }
        if let fresh = WidgetServerClient.loadFreshCached() { return fresh }
        if let deviceId = UIDevice.current.identifierForVendor?.uuidString,
           let fetched = await WidgetServerClient.fetchSnapshot(deviceId: deviceId) {
            return fetched
        }
        return WidgetServerClient.loadCached()
    }

    /// 某时刻的 entry：按那一刻算今日实时状态（倒计时/已挣）。
    /// 预估口径是第 29 条（工资 + 奖金分摊 + 加班/三薪加成）；钱的显隐由各视图按快照 payAccess 定，
    /// 这里只算数、不藏数。
    private func makeEntry(date: Date, snapshot: WidgetSnapshot? = nil) -> Entry {
        let snap = snapshot ?? WidgetSnapshotStore.load()
        let live: PayCalc.TodayLiveState
        if let today = snap?.today, let todayDate = DateUtil.date(from: today.date) {
            live = PayCalc.todayLiveState(shift: today.shift, onLeave: today.onLeave, day: todayDate, now: date, earlyRate: snap?.earlyRate ?? 70, midRate: snap?.midRate ?? 30, inputs: snap?.todayInputs ?? PayCalc.DayEstimateInputs())
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
