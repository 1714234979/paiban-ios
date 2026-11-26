import Foundation

/// App Group 共享标识：App 与小组件扩展共用（entitlements 两边都要配 group.com.paiban.app）。
/// 注意：重签（全能签）用的描述文件必须带这个 App Group，否则共享区读不到、小组件只显示占位。
enum WidgetGroup {
    static let suiteID = "group.com.paiban.app"
    static let snapshotFileName = "widget-snapshot.json"
}

/// 小组件快照：App 把小组件要显示的数据写一份到 App Group 共享区，小组件只读它。
/// 小组件不跑网络、不跑重计算（工资是 App 本地算好的数，班次是 App 拼好的天）。
/// 轻量：只含今天、本周、本月与本月工资（不含全年天数、不含配置原文、不含密码/session）。
struct WidgetSnapshot: Codable, Equatable {
    struct Day: Codable, Equatable {
        var date: String       // yyyy-MM-dd
        var shift: String      // 日班/中班/早班/休息/早中班/日中班
        var onLeave: Bool
        var leaveType: String?
        var isToday: Bool
    }
    struct Pay: Codable, Equatable {
        var year: Int
        var month: Int
        var salarySubtotal: Double?   // 应发
        var salaryNet: Double?        // 实发工资
        var bonusAfterTax: Double?    // 实发奖金
        var grandTotal: Double?       // 合计
        var bonusTotal: Double?       // 税前奖金
        var incomeTax: Double?        // 个税
        var attendance: Double?
        var tripleDays: Double?
        var overtimeDays: Double?
    }

    var savedAt: Date
    var displayName: String?   // 昵称/用户名
    var team: String           // 当前班组
    var teamHistory: [TeamHistoryEntry]
    var today: Day?            // 今天
    var week: [Day]            // 本周 7 天（周日开头）
    var monthDays: [Day]       // 本月每天
    var monthYear: Int
    var month: Int
    var pay: Pay?
    var baseSalary: Double     // 解析好的基本工资（今日预估/实时工资用）
    var earlyRate: Double      // 早班补贴（默认 70）
    var midRate: Double        // 中班补贴（默认 30）
    var mealRate: Double       // 餐补（默认 10）
    // 第 29 条（2026-11-26）：钱跟着工资权限走——只有开了工资权限才显示钱数。
    // payAccess=false 时小组件只显示班次和倒计时，不显示钱（今日/锁屏/本月工资都一样）。
    // 字段都有默认值：老快照（磁盘缓存）缺这几个键也能解出来，不会整个快照读失败。
    var payAccess: Bool = true
    // 第 40 条（2026-11-26）：今天的每日净预估输入（分摊 + 加成种类 + 零头班次），
    // 小组件的今日/锁屏实时工资就按这份算。老快照没有这个键时用全 0 的默认输入。
    var todayInputs: PayCalc.DayEstimateInputs = PayCalc.DayEstimateInputs()

    /// 组件库预览用的假数据（不含真人信息）：11 月 25 日周三、B 班、休息，
    /// 本周 22–28 日轮次，本月工资应发 3370、实发工资 2355.39。
    static var preview: WidgetSnapshot {
        let weekShifts = ["休息", "早班", "早班", "休息", "日班", "日班", "中班"]
        var week: [Day] = []
        for i in 0..<7 {
            let d = 22 + i
            week.append(Day(date: String(format: "2026-11-%02d", d), shift: weekShifts[i], onLeave: false, leaveType: nil, isToday: d == 25))
        }
        var monthDays: [Day] = []
        let cycles = ["日班", "日班", "中班", "中班", "休息", "早班", "早班", "休息"]
        for d in 1...30 {
            let shift = cycles[(d + 3) % 8]
            monthDays.append(Day(date: String(format: "2026-11-%02d", d), shift: shift, onLeave: false, leaveType: nil, isToday: d == 25))
        }
        return WidgetSnapshot(
            savedAt: Date(),
            displayName: "张晓文",
            team: "B",
            teamHistory: [TeamHistoryEntry(team: "B", effectiveFrom: "2026-11-02")],
            today: Day(date: "2026-11-25", shift: "休息", onLeave: false, leaveType: nil, isToday: true),
            week: week,
            monthDays: monthDays,
            monthYear: 2026,
            month: 11,
            pay: Pay(year: 2026, month: 11, salarySubtotal: 3370, salaryNet: 2355.39, bonusAfterTax: 4682.05, grandTotal: 7037.44, bonusTotal: 4745.06, incomeTax: 63.01, attendance: 21, tripleDays: 0, overtimeDays: 2),
            baseSalary: 2420,
            earlyRate: 70,
            midRate: 30,
            mealRate: 10,
            payAccess: true,
            // 预览那天（11 月 25 日）是休息日，kinds 为空；分摊数是 11 月正常日的数（仅作占位）。
            todayInputs: PayCalc.DayEstimateInputs(
                baseShare: 2420 / 21, extraShare: 180 / 21, contribShare: 1014.61 / 21,
                taxShare: 46.36 / 21, bonusShare: 4300 / 21, dailyRate: 2420 / 21.75,
                kinds: [], fractionExtra: 0, fractionKind: .normal)
        )
    }
}

/// 快照读写：App 写、小组件读，都走 App Group 共享区（不是 App 沙盒 Documents）。
enum WidgetSnapshotStore {
    static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetGroup.suiteID)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let url = containerURL()?.appendingPathComponent(WidgetGroup.snapshotFileName) else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load() -> WidgetSnapshot? {
        guard let url = containerURL()?.appendingPathComponent(WidgetGroup.snapshotFileName),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func clear() {
        guard let url = containerURL()?.appendingPathComponent(WidgetGroup.snapshotFileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
