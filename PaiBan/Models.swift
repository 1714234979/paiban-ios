import Foundation
import SwiftUI

// MARK: - 日期工具

enum DateUtil {
    static let calendar = Calendar(identifier: .gregorian)

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f
    }()

    /// 年月标题，如“2027年1月”。年份直接拼纯数字，绝不走带千分位分组符的
    /// NumberFormatter（1.0 曾把 2027 显示成 2,027）；金额里的千分位逗号不受影响。
    static func yearMonthTitle(year: Int, month: Int) -> String {
        "\(year)年\(month)月"
    }

    static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()

    static func string(from date: Date) -> String { dayFormatter.string(from: date) }

    static func date(from string: String) -> Date? { dayFormatter.date(from: string) }

    static func yearMonth(of date: Date) -> (year: Int, month: Int) {
        let c = calendar.dateComponents([.year, .month], from: date)
        return (c.year ?? 2026, c.month ?? 1)
    }

    static func firstDayOfMonth(year: Int, month: Int) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: 1))
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        guard let first = firstDayOfMonth(year: year, month: month),
              let range = calendar.range(of: .day, in: .month, for: first) else { return 30 }
        return range.count
    }

    /// 是不是闰年（全年天数 366 还是 365）。
    static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    /// 当月 1 号是星期几（0=周日 … 6=周六），日历从周日开始排。
    static func firstWeekday(year: Int, month: Int) -> Int {
        guard let first = firstDayOfMonth(year: year, month: month) else { return 0 }
        return calendar.component(.weekday, from: first) - 1
    }

    static func addingMonths(_ date: Date, _ months: Int) -> Date {
        calendar.date(byAdding: .month, value: months, to: date) ?? date
    }

    static func addingDays(_ date: Date, _ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func weekdayCN(_ weekday: Int) -> String {
        ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][weekday % 7]
    }

    static func weekdayCN(of date: Date) -> String {
        weekdayCN(calendar.component(.weekday, from: date) - 1)
    }

    /// 上个月（工资页默认显示上个月）。
    static func lastMonth(from date: Date = Date()) -> (year: Int, month: Int) {
        let prev = addingMonths(date, -1)
        return yearMonth(of: prev)
    }
}

// MARK: - 数字格式

enum MoneyUtil {
    static func money(_ value: Double?) -> String {
        guard let value else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return "¥" + (f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value))
    }

    static func money0(_ value: Double?) -> String {
        guard let value else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return "¥" + (f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value))
    }

    static func number(_ value: Double?, decimals: Int = 2) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(decimals)f", value)
    }

    static func int(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value)"
    }
}

// MARK: - 班次

/// 班次值：日班 / 中班 / 早班 / 休息 / 早中班 / 日中班。
enum ShiftStyle {
    /// 班次主色：日班绿、中班粉红、早班紫、休息青灰。
    static func color(for shift: String) -> Color {
        switch shift {
        case "日班": return Color(red: 0.16, green: 0.65, blue: 0.32)   // 绿
        case "中班": return Color(red: 0.92, green: 0.35, blue: 0.45)   // 粉红
        case "早班": return Color(red: 0.55, green: 0.40, blue: 0.85)   // 紫
        case "休息": return Color(red: 0.10, green: 0.65, blue: 0.65)   // 青
        default: return .gray
        }
    }

    static func background(for shift: String) -> Color {
        color(for: shift).opacity(0.14)
    }

    /// 班次时间：日班 08–16，中班 16–24，早班 00–08。
    static func timeRange(for shift: String) -> String {
        switch shift {
        case "日班": return "08:00–16:00"
        case "中班": return "16:00–24:00"
        case "早班": return "00:00–08:00"
        case "休息": return "休息"
        case "早中班": return "00:00–08:00 + 16:00–24:00"
        case "日中班": return "08:00–16:00 + 16:00–24:00"
        default: return shift
        }
    }

    /// 双班拆成两个单班。
    static func parts(of shift: String) -> [String] {
        switch shift {
        case "早中班": return ["早班", "中班"]
        case "日中班": return ["日班", "中班"]
        case "早日班": return ["早班", "日班"]
        default: return [shift]
        }
    }

    /// 几个单班并成一个（顶岗/替班后那天上的班）：单班 + 单班 → 双班；
    /// 休息 + 单班 → 那个单班。顺序按 早、日、中（早中班、日中班）。
    /// 调用前应已排除相同班与早日组合。
    static func combined(_ parts: [String]) -> String {
        let comps = parts.filter { $0 != "休息" }
        if comps.isEmpty { return "休息" }
        if comps.count == 1 { return comps[0] }
        let order = ["早班", "日班", "中班"]
        let sorted = comps.sorted { (order.firstIndex(of: $0) ?? 99) < (order.firstIndex(of: $1) ?? 99) }
        return sorted.map { String($0.prefix(1)) }.joined() + "班"
    }

    static func isDouble(_ shift: String) -> Bool {
        shift == "早中班" || shift == "日中班" || shift == "早日班"
    }

    /// 所有可调成的班次（含双班）。
    static let allShifts = ["日班", "中班", "早班", "休息", "早中班", "日中班"]

    /// 请假类型。
    static let leaveTypes = ["事假", "病假", "年假", "年休假", "婚假", "产假", "调休"]
}

/// 四班 8 天循环（CONTRACT.md）：A/C/D 基准 2026-11-01，B 基准 2026-11-02。
enum TeamInfo {
    static let allTeams = ["A", "B", "C", "D"]

    static let cycles: [String: [String]] = [
        "A": ["早班", "早班", "休息", "日班", "日班", "中班", "中班", "休息"],
        "B": ["日班", "日班", "中班", "中班", "休息", "早班", "早班", "休息"],
        "C": ["日班", "中班", "中班", "休息", "早班", "早班", "休息", "日班"],
        "D": ["中班", "休息", "早班", "早班", "休息", "日班", "日班", "中班"],
    ]

    static let baseDates: [String: String] = [
        "A": "2026-11-01",
        "B": "2026-11-02",
        "C": "2026-11-01",
        "D": "2026-11-01",
    ]

    static func cycleText(team: String) -> String {
        (cycles[team] ?? []).map { shortName($0) }.joined(separator: " → ")
    }

    /// 循环里的单字简写：日 / 中 / 早 / 休。
    static func shortName(_ shift: String) -> String {
        switch shift {
        case "日班": return "日"
        case "中班": return "中"
        case "早班": return "早"
        case "休息": return "休"
        default: return shift
        }
    }
}

/// 本地基础排班计算：只按班组 + 基准日算 8 天一轮（不含调班/请假），
/// 用于即时显示与查看其他班组；最终以服务端 /me/month 为准。
enum ScheduleCalculator {
    static func baseShift(team: String, date: Date) -> String {
        guard let cycle = TeamInfo.cycles[team],
              let baseString = TeamInfo.baseDates[team],
              let base = DateUtil.date(from: baseString) else { return "休息" }
        let startOfDay = DateUtil.calendar.startOfDay(for: date)
        let baseDay = DateUtil.calendar.startOfDay(for: base)
        let diff = DateUtil.calendar.dateComponents([.day], from: baseDay, to: startOfDay).day ?? 0
        let idx = ((diff % 8) + 8) % 8
        return cycle[idx]
    }

    /// 按 teamHistory 取某天实际班组；没有 history 时用当前班组。
    static func teamForDate(_ dateString: String, history: [TeamHistoryEntry], fallbackTeam: String) -> String {
        let sorted = history.sorted { $0.effectiveFrom < $1.effectiveFrom }
        var result: String? = nil
        for entry in sorted where entry.effectiveFrom <= dateString {
            result = entry.team
        }
        return result ?? sorted.first?.team ?? fallbackTeam
    }

    /// 本地算某班组某月的基础排班（查看其他班组时用，无调班/请假）。
    static func localMonth(team: String, year: Int, month: Int) -> MonthSchedule {
        var days: [DaySchedule] = []
        let dim = DateUtil.daysInMonth(year: year, month: month)
        for d in 1...dim {
            guard let date = DateUtil.calendar.date(from: DateComponents(year: year, month: month, day: d)) else { continue }
            let shift = baseShift(team: team, date: date)
            let parts = shift == "休息" ? [] : ShiftStyle.parts(of: shift)
            days.append(DaySchedule(
                date: DateUtil.string(from: date),
                team: team,
                baseShift: shift,
                shift: shift,
                start: parts.isEmpty ? nil : timeStart(of: parts.first!),
                end: parts.isEmpty ? nil : timeEnd(of: parts.last!),
                timeLabel: parts.isEmpty ? nil : parts.map { ShiftStyle.timeRange(for: $0) }.joined(separator: " + "),
                totalHours: parts.count * 8,
                isDouble: parts.count == 2,
                isWork: !parts.isEmpty,
                onLeave: false,
                leaveType: nil,
                leaveNote: nil,
                overridden: false,
                note: nil,
                partner: nil,
                partnerShift: nil,
                coverDate: nil,
                paybackDate: nil,
                holiday: nil,
                weekday: DateUtil.calendar.component(.weekday, from: date) - 1
            ))
        }
        var restDays = 0, actualWork = 0, actualShifts = 0, doubleDays = 0
        var dayCount = 0, earlyCount = 0, midCount = 0
        for d in days {
            if d.isWork != true { restDays += 1; continue }
            actualWork += 1
            if d.isDouble == true { doubleDays += 1 }
            for p in ShiftStyle.parts(of: d.shift) {
                actualShifts += 1
                if p == "日班" { dayCount += 1 }
                else if p == "早班" { earlyCount += 1 }
                else if p == "中班" { midCount += 1 }
            }
        }
        // 基本天数（法定口径）与服务端口径一致：取当月基础班次非休息天数作近似时
        // 会偏大；这里 basicDays 先用休息日之外的天数，工资仍以服务端 /me/pay 为准。
        let stats = MonthStats(
            totalDays: days.count, weekendDays: nil, basicDays: actualWork,
            restDays: restDays, actualWork: actualWork, actualShifts: actualShifts,
            doubleDays: doubleDays, leaveDays: 0, overtime: nil,
            counts: ShiftCounts(day: dayCount, early: earlyCount, mid: midCount)
        )
        return MonthSchedule(team: team, year: year, month: month, days: days, stats: stats)
    }

    private static func timeStart(of shift: String) -> String {
        switch shift {
        case "日班": return "08:00"
        case "中班": return "16:00"
        case "早班": return "00:00"
        default: return ""
        }
    }

    private static func timeEnd(of shift: String) -> String {
        switch shift {
        case "日班": return "16:00"
        case "中班": return "24:00"
        case "早班": return "08:00"
        default: return ""
        }
    }
}

// MARK: - 用户 / Profile

/// GET /api/v1/auth/login 与注册返回的公开用户信息（user 字段）。
/// 大陆手机号工具（1.1.3，登录 / 绑定 / 改密码共用）。
enum PhoneUtil {
    /// 校验：1 开头、第二位 3–9、共 11 位。
    static func isValid(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count == 11, t.hasPrefix("1") else { return false }
        let second = t[t.index(t.startIndex, offsetBy: 1)]
        guard ("3"..."9").contains(second) else { return false }
        return t.allSatisfy { $0.isNumber }
    }
    /// 脱敏：13812345678 → 138****5678。
    static func masked(_ phone: String?) -> String? {
        guard let phone, phone.count == 11 else { return nil }
        return "\(phone.prefix(3))****\(phone.suffix(4))"
    }
}

struct PublicUser: Codable, Equatable {
    var id: String?
    var username: String?
    var role: String?
    var enabled: Bool?
    var canWrite: Bool?
    var phone: String?
    var displayName: String?
    var lastPhoneChangeAt: String?
    var apiKeyHint: String?
    var passwordViewable: Bool?
    var createdAt: String?
    var updatedAt: String?
}

/// GET /api/v1/me 返回的当前用户（含 profile 字段）。
struct UserProfile: Codable, Equatable {
    var id: String?
    var username: String?
    var role: String?
    var enabled: Bool?
    var canWrite: Bool?
    var phone: String?
    var displayName: String?
    var lastPhoneChangeAt: String?
    var passwordViewable: Bool?
    var team: String?
    var teamHistory: [TeamHistoryEntry]?
    var paySettings: PaySettings?
    var onboardingDone: Bool?

    var displayTeam: String { team ?? "B" }
    var isAdmin: Bool { role == "admin" }
}

/// 用户工资设置（缺失字段回落到服务端全局设置）。
struct PaySettings: Codable, Equatable {
    var baseSalary: Double?
    var bonusCoef: Double?
    var contributionBase: Double?
    var position: String?
    var utilities: Double?
    var hireYear: Int?
    var hireMonth: Int?
    var deptPerfDefault: Double?
    /// 设置里的默认科室绩效奖金（用户默认，0–10000；随 PUT /me/profile 保存）。
    var deptPerf: Double?
    var perfCoefDefault: Double?
    var annualLeaveTotal: Int?
    /// 学历（1.1.5）：专科 / 本科 / 其他，默认其他；专科 50、本科 100、其他 0。
    var education: String?
    /// 缺员补贴（1.1.5）：用户级设置，金额 + 期限；期限内每月计入奖金。
    var shortageSubsidy: ShortageSubsidy?
}

/// 缺员补贴（用户级设置）：金额 + 期限（开始/结束日期，YYYY-MM-DD；空表示不限）。
struct ShortageSubsidy: Codable, Equatable {
    var amount: Double? = nil
    var startDate: String? = nil
    var endDate: String? = nil
}

/// 更换班组记录：从 effectiveFrom 起按 team 排班。
struct TeamHistoryEntry: Codable, Equatable, Identifiable {
    var team: String
    var effectiveFrom: String
    var id: String { effectiveFrom }
}

// MARK: - 排班

/// 单日排班（/me/day 与 /me/month 的 day 对象同形）。
struct DaySchedule: Codable, Equatable, Identifiable {
    var date: String
    var team: String?
    var baseShift: String?
    var shift: String
    var start: String?
    var end: String?
    var timeLabel: String?
    var totalHours: Int?
    var isDouble: Bool?
    var isWork: Bool?
    var onLeave: Bool?
    var leaveType: String?
    var leaveNote: String?
    var overridden: Bool?
    var note: String?
    var partner: String?
    var partnerShift: String?
    var coverDate: String?
    var paybackDate: String?
    var holiday: String?
    var weekday: Int?

    var id: String { date }

    var displayShift: String { shift }
    var displayTime: String {
        if let timeLabel, !timeLabel.isEmpty { return timeLabel }
        return ShiftStyle.timeRange(for: shift)
    }
    var isRest: Bool { shift == "休息" }
    var dayNumber: Int { Int(date.suffix(2)) ?? 0 }
    var weekdayText: String {
        if let weekday { return DateUtil.weekdayCN(weekday) }
        if let d = DateUtil.date(from: date) { return DateUtil.weekdayCN(of: d) }
        return ""
    }
}

/// 班次计数：日班 / 早班 / 中班各多少个。
struct ShiftCounts: Codable, Equatable {
    var day: Int?
    var early: Int?
    var mid: Int?
}

/// 月度统计（与 /api/v1/month 的 stats 同形）。
struct MonthStats: Codable, Equatable {
    var totalDays: Int?
    var weekendDays: Int?
    var basicDays: Int?
    var restDays: Int?
    var actualWork: Int?
    var actualShifts: Int?
    var doubleDays: Int?
    var leaveDays: Int?
    var overtime: Int?
    var counts: ShiftCounts?
}

/// GET /api/v1/me/month 返回。
struct MonthSchedule: Codable, Equatable {
    var team: String?
    var year: Int?
    var month: Int?
    var days: [DaySchedule]?
    var stats: MonthStats?

    func day(for dateString: String) -> DaySchedule? {
        days?.first { $0.date == dateString }
    }
}

/// GET /api/v1/me/range 返回：{team, start, days:[DaySchedule]}。
/// （服务端返回的是对象不是数组，旧版按数组解会一直失败、走兜底。）
struct RangeResponse: Decodable {
    var team: String?
    var start: String?
    var days: [DaySchedule]?
}

// MARK: - 调班 / 请假记录

/// 调班记录（overrides 列表里的单条）。
struct SwapRecord: Codable, Equatable, Identifiable {
    var date: String
    var shift: String?
    var note: String?
    var partner: String?
    var partnerShift: String?
    var coverDate: String?
    var paybackDate: String?
    var id: String { date }
}

/// 请假记录（leaves 列表里的单条）。
struct LeaveRecord: Codable, Equatable, Identifiable {
    var date: String
    var type: String?
    var note: String?
    var id: String { date }
}

/// POST /api/v1/me/swap 返回：{coverDate, paybackDate}（paybackDate 为空 = 待还班）。
struct SwapSaveResult: Decodable {
    var coverDate: String?
    var paybackDate: String?
}

// MARK: - 反馈双向回复（1.2.2）

/// 自己的某一条反馈（GET /api/v1/me/feedback 的 items 里的一条，最新在前）：
/// file 是服务端文件名（回复接口的 :file 就用它），at 是提交时间（ISO 时间戳），
/// replies 是这条反馈下的来回回复（管理员 + 自己），按时间排。
struct FeedbackItem: Codable, Equatable, Identifiable {
    var file: String
    var at: String
    var type: String?
    var location: String?
    var hasImage: Bool?
    var size: Int?
    var replies: [FeedbackReply]?
    var id: String { file }
}

/// 一条反馈下的一次回复：from 是 "admin"（管理员）或 "user"（自己），by 是说话人名字。
struct FeedbackReply: Codable, Equatable, Identifiable {
    var id: String
    var from: String?
    var by: String?
    var at: String
    var text: String
}

/// GET /api/v1/me/feedback 返回：{ok, items}（注意：这里是 items，不是 data，
/// 通用 request 只解 {ok, data}，所以走 APIClient.requestResponse）。
struct FeedbackListResponse: Decodable {
    var ok: Bool
    var items: [FeedbackItem]?
    var error: String?
}

/// POST /api/v1/me/feedback/:file/reply 返回：{ok, reply}（同样不是 data，见上）。
struct FeedbackReplyResponse: Decodable {
    var ok: Bool
    var reply: FeedbackReply?
    var error: String?
}

/// GET /api/v1/me/teams/range 返回：{start, teams: {A:[DaySchedule], B:[...], C:[...], D:[...]}}。
/// 调班候选卡片与还班日列表用（四班同取）；自己班的日程以 /me/month 为准，不用这里的。
struct TeamsRangeResponse: Decodable {
    var start: String?
    var teams: [String: [DaySchedule]]?
}

/// 顶岗/替班评估（空间 evalCover 的 App 版）：某人替我上某个班，
/// 他那天变成什么、行不行、不行是为什么。
/// - ownShift：他那天原来的班；result：替我之后他那天变成的班（nil 表示不行）。
/// - ownShift 是“休息”时 result 就是加上去的那个班——只上一个班，不算双班。
struct CoverEval {
    var eligible: Bool
    var reason: String?
    var ownShift: String
    var result: String?
}

/// 单日加班记录：{date, start, end, minutes, note}。start/end 是 HH:MM；
/// minutes 是服务端算好的时长（分钟，结束 <= 开始算跨夜）。一天一条，改了就覆盖。
struct OvertimeRecord: Codable, Equatable, Identifiable {
    var date: String
    var start: String
    var end: String
    var minutes: Int?
    var note: String?
    var id: String { date }

    /// 时长显示，如“4小时”“4小时30分”。minutes 为空时按起止时间本地算。
    var durationText: String {
        let m = minutes ?? OvertimeCalc.minutes(start: start, end: end)
        return OvertimeCalc.text(minutes: m)
    }
}

/// 加班时长本地算：跟服务端同一规则（结束 <= 开始算跨夜，加 24 小时）。
enum OvertimeCalc {
    static func minutes(start: String, end: String) -> Int {
        func toMin(_ s: String) -> Int {
            let p = s.split(separator: ":").compactMap { Int($0) }
            guard p.count == 2 else { return 0 }
            return p[0] * 60 + p[1]
        }
        var s = toMin(start), e = toMin(end)
        if e <= s { e += 1440 }
        return e - s
    }

    static func text(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if m == 0 { return "\(h)小时" }
        return "\(h)小时\(m)分"
    }
}

/// 三薪明细里的单天：{date, name, shift}。
struct TripleDate: Codable, Equatable {
    var date: String?
    var name: String?
    var shift: String?
}

// MARK: - 工资

/// GET /api/v1/config 返回的工资配置（pay 一节）：本地算工资的输入。
/// 全部可选，缺失时用与服务端一致的默认值。
struct PayGlobalSettings: Codable, Equatable {
    var annualLeaveTotal: Int? = nil
    var annualLeaveUsedOffset: [String: Int]?
    var baseSalary: Double? = nil
    var contributionBase: Double? = nil
    var deptPerfDefault: Double? = nil
    var earlyRate: Double? = nil
    var heatMonthly: Double? = nil
    var hireMonth: Int? = nil
    var hireYear: Int? = nil
    var mealRate: Double? = nil
    var midRate: Double? = nil
    var otherRewardFull: Double? = nil
    var perfCoefDefault: Double? = nil
    var seniorityPerYear: Double? = nil
    var utilities: Double? = nil
}

/// 某月录入数（config.pay.months[monthKey]）：attendance / allowance / deptPerf /
/// perfCoef / bonusCoef / tripleDays / overtimeDays / utilities，缺失即按排班表算。
/// bonusCoef 与 utilities 是单月覆盖值：填了只影响当月，没填用原来的来源。
struct PayMonthRecord: Codable, Equatable {
    var attendance: Double? = nil
    var allowance: Double? = nil
    var deptPerf: Double? = nil
    var perfCoef: Double? = nil
    var bonusCoef: Double? = nil
    var tripleDays: Double? = nil
    var overtimeDays: Double? = nil
    var utilities: Double? = nil
}

/// 当月录入数里可单月覆盖的字段（工资页 inline 编辑用；服务端 /me/pay/month 同名）。
enum PayRecordField: String, CaseIterable {
    case deptPerf, perfCoef, bonusCoef, overtimeDays, utilities
}

/// 按月生效的设置（config.pay.effective[monthKey]）：baseSalary / position / bonusCoef。
struct PayEffective: Codable, Equatable {
    var baseSalary: Double? = nil
    var position: String? = nil
    var bonusCoef: Double? = nil
}

/// GET /api/v1/config 的 pay 一节。
struct PayConfigData: Codable, Equatable {
    var settings: PayGlobalSettings? = nil
    var months: [String: PayMonthRecord]?
    var effective: [String: PayEffective]?
}

/// GET /api/v1/config 返回的 data（只解 pay 一节，其余字段忽略）。
struct ServerConfigData: Decodable {
    var pay: PayConfigData?
}

/// 单月工资奖金（服务端 /me/pay 返回与本地 PayCalc 算出同形）。
/// 字段名与服务端 monthPay / computePay 返回一致；全部可选以兼容字段缺失。
/// 注意 attendance 是 Double：录入的实际出勤可能是小数（如 23.4、24.31）。
struct PayMonth: Codable, Equatable {
    var year: Int? = nil
    var month: Int? = nil
    var monthKey: String? = nil
    var baseSalary: Double? = nil
    var position: String? = nil
    var bonusCoef: Double? = nil
    var basicDays: Int? = nil
    var rosterTotalWork: Int? = nil
    var rosterWork: Int? = nil
    var attendance: Double? = nil
    var attendanceRecorded: Bool? = nil
    var counts: ShiftCounts? = nil
    var allowance: Double? = nil
    var allowanceAuto: Double? = nil
    var allowanceRecorded: Bool? = nil
    var deptPerf: Double? = nil
    var deptPerfRecorded: Bool? = nil
    var perfCoef: Double? = nil
    var bonusCoefRecorded: Bool? = nil
    var otherReward: Double? = nil
    var otherRewardFull: Bool? = nil
    var heat: Double? = nil
    var heatNote: String? = nil
    var educationSubsidy: Double? = nil
    var seniority: Double? = nil
    var salarySubtotal: Double? = nil
    var contributionBase: Double? = nil
    var pension: Double? = nil
    var medical: Double? = nil
    var unemployment: Double? = nil
    var socialInsurance: Double? = nil
    var housingFund: Double? = nil
    var contributionTotal: Double? = nil
    var salaryPayable: Double? = nil
    var utilities: Double? = nil
    var utilitiesRecorded: Bool? = nil
    var salaryNet: Double? = nil
    var tripleDates: [TripleDate]? = nil
    var tripleDays: Double? = nil
    var triplePay: Double? = nil
    var tripleRecorded: Bool? = nil
    var convertedTripleDays: Double? = nil
    var overtimeDays: Double? = nil
    var overtimePay: Double? = nil
    var overtimePayPart: Double? = nil
    var overtimeRecorded: Bool? = nil
    var shortageSubsidy: Double? = nil
    var bonusTotal: Double? = nil
    var leaveDays: Int? = nil
    var excessDays: Int? = nil
    var mealAllowance: Double? = nil
    var dailyRate: Double? = nil
    var annualLeaveTotal: Int? = nil
    var annualLeaveYearUsed: Int? = nil
    var annualLeaveRemaining: Int? = nil
    var annualLeaveMonth: Int? = nil
    var annualLeaveApplied: Bool? = nil
    var annualLeaveOffsetUsed: Int? = nil
    // 累计预扣个税字段（computePay 追加）。
    var cumulativeGross: Double? = nil
    var cumulativeContributions: Double? = nil
    var cumulativeMonths: Int? = nil
    var cumulativeTaxableIncome: Double? = nil
    var cumulativeTaxTotal: Double? = nil
    var previousCumulativeTaxTotal: Double? = nil
    var incomeTax: Double? = nil
    var bonusAfterTax: Double? = nil
    var grandTotal: Double? = nil
    var taxableIncome: Double? = nil
}

/// 全年工资视图已删（预估工资只按月看），PayYear 与睡眠窗口 QuietInfo 一并移除。

// MARK: - 中国日历（阴历 / 节气 / 节日 / 法定假日）

/// 中国日历：阴历、24 节气、节日、法定节假日（假/班），供排班日历格显示。
/// 阴历用 iOS 自带的中国日历（Calendar(identifier: .chinese)）算；
/// 24 节气 Foundation 不直接给，用按年份查表补齐；
/// 法定节假日（假）与调休上班日（班）用公开放假安排表。
/// 注意：三薪和法定节假日是两回事——日历上只标法定节假日（假/班），
/// 三薪是工资计算里的概念（PayCalc 按 STATUTORY 算），不在日历上另标。
/// 法定节假日表（STATUTORY，PayCalc.statutoryTable）只含法定那几天（如国庆 10/01–10/03），
/// 日历上的“假”按整段公共假期标（如国庆 10/01–10/07），与参考图一致。
enum ChineseCalendar {

    /// 某天在日历格里的附加信息。
    struct DayInfo {
        /// 阴历小字：节气/节日名（红字）优先，其次阴历日（初二、廿九），
        /// 阴历月初一显示月份名（九月、冬月）。
        var lunarText: String
        /// 是不是红字（节气或节日）。
        var isRedText: Bool
        /// 假/班角标：.holiday（绿“假”）、.workday（红“班”）、nil（无）。
        var mark: Mark?
        enum Mark { case holiday, workday }
    }

    private static let chinese = Calendar(identifier: .chinese)
    private static let gregorian = Calendar(identifier: .gregorian)

    private static let lunarMonths = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
    private static let lunarDays = ["初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
                                    "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
                                    "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"]

    /// 24 节气（阳历月-日，北京时间）。2026/2027 按万年历；其它年份没有表时返回 nil。
    /// 已按参考图核对：2026 寒露 10-08、霜降 10-23、大雪 12-07、冬至 12-22；
    /// 2027 小寒 01-05、大寒 01-20。
    private static let solarTerms: [Int: [String: String]] = [
        2026: ["01-05": "小寒", "01-20": "大寒", "02-04": "立春", "02-18": "雨水",
               "03-05": "惊蛰", "03-20": "春分", "04-04": "清明", "04-20": "谷雨",
               "05-05": "立夏", "05-21": "小满", "06-05": "芒种", "06-21": "夏至",
               "07-07": "小暑", "07-22": "大暑", "08-07": "立秋", "08-23": "处暑",
               "09-07": "白露", "09-23": "秋分", "10-08": "寒露", "10-23": "霜降",
               "11-07": "立冬", "11-22": "小雪", "12-07": "大雪", "12-22": "冬至"],
        2027: ["01-05": "小寒", "01-20": "大寒", "02-04": "立春", "02-18": "雨水",
               "03-05": "惊蛰", "03-20": "春分", "04-04": "清明", "04-20": "谷雨",
               "05-05": "立夏", "05-21": "小满", "06-05": "芒种", "06-21": "夏至",
               "07-07": "小暑", "07-23": "大暑", "08-07": "立秋", "08-23": "处暑",
               "09-07": "白露", "09-23": "秋分", "10-08": "寒露", "10-23": "霜降",
               "11-07": "立冬", "11-22": "小雪", "12-07": "大雪", "12-22": "冬至"],
    ]

    /// 阳历固定节日（月-日 → 名）。国庆、劳动节走假期首日那条，不放这里。
    private static let gregorianFestivals: [String: String] = [
        "01-01": "元旦", "02-14": "情人节", "03-08": "妇女节", "04-01": "愚人节",
        "06-01": "儿童节", "09-10": "教师节",
        "10-31": "万圣节", "12-24": "平安夜", "12-25": "圣诞节",
    ]

    /// 阴历节日（农历月-日 → 名）。除夕是腊月最后一天，单独算。
    private static let lunarFestivals: [String: String] = [
        "1-1": "春节", "1-15": "元宵节", "2-2": "龙抬头",
        "5-5": "端午", "7-7": "七夕", "7-15": "中元节",
        "8-15": "中秋", "9-9": "重阳", "12-8": "腊八", "12-23": "小年",
    ]

    /// 法定节假日放假安排（整段假期标“假”）。2026 已按官方安排与参考图核对；
    /// 2027 为公开日历推算，须核对官方安排。名字是日历上显示的短名（国庆、春节、元旦）。
    private static let holidayPeriods: [Int: [(start: String, end: String, name: String)]] = [
        2026: [("2026-01-01", "2026-01-01", "元旦"),
               ("2026-02-15", "2026-02-21", "春节"),
               ("2026-04-04", "2026-04-06", "清明"),
               ("2026-05-01", "2026-05-05", "劳动节"),
               ("2026-06-19", "2026-06-21", "端午"),
               ("2026-09-25", "2026-09-27", "中秋"),
               ("2026-10-01", "2026-10-07", "国庆")],
        2027: [("2027-01-01", "2027-01-01", "元旦"),
               ("2027-02-05", "2027-02-11", "春节"),
               ("2027-04-04", "2027-04-06", "清明"),
               ("2027-05-01", "2027-05-05", "劳动节"),
               ("2027-06-18", "2027-06-20", "端午"),
               ("2027-09-25", "2027-09-27", "中秋"),
               ("2027-10-01", "2027-10-07", "国庆")],
    ]

    /// 调休上班日（标红“班”）。已在假期里的日子优先算“假”，不重复标“班”
    /// （如 2026-09-27 是中秋假期最后一天，参考图里标“假”不标“班”，故不列入）。
    private static let adjustedWorkdays: [Int: Set<String>] = [
        2026: ["2026-02-14", "2026-02-22", "2026-04-26", "2026-05-09", "2026-10-10"],
        2027: ["2027-01-30", "2027-02-13", "2027-04-25", "2027-05-08", "2027-09-26", "2027-10-09"],
    ]

    /// 某天的信息（带缓存：同一天只算一次，滑页时不重算）。
    private static var cache: [String: DayInfo] = [:]

    /// 1.1.3：预热某个月所有日期的阴历缓存（只填缓存、不返回值）。
    /// 必须在主线程调用（DateUtil 用共享 DateFormatter，非线程安全）。
    /// 调用方按月分批、每批之间让出主线程，避免一次算 12 个月堵住界面。
    static func warmMonth(year: Int, month: Int) {
        guard let first = DateUtil.firstDayOfMonth(year: year, month: month) else { return }
        let days = DateUtil.daysInMonth(year: year, month: month)
        for offset in 0..<days {
            guard let date = DateUtil.calendar.date(byAdding: .day, value: offset, to: first) else { continue }
            _ = info(for: DateUtil.string(from: date))
        }
    }

    static func info(for dateString: String) -> DayInfo {
        if let cached = cache[dateString] { return cached }
        let result = compute(for: dateString)
        cache[dateString] = result
        return result
    }

    static func info(for date: Date) -> DayInfo {
        info(for: DateUtil.string(from: date))
    }

    private static func compute(for dateString: String) -> DayInfo {
        guard let date = DateUtil.date(from: dateString) else {
            return DayInfo(lunarText: "", isRedText: false, mark: nil)
        }
        let comps = gregorian.dateComponents([.year, .month, .day], from: date)
        let year = comps.year ?? 2026
        let md = String(format: "%02d-%02d", comps.month ?? 1, comps.day ?? 1)

        // 阴历（中国日历算）。
        // 注意：.isLeapMonth 是 iOS 17 才有的 API，App 最低支持 iOS 16，不能用。
        // 闰月与上一个月同号：取本月初一的前一天，若其阴历月份与本月相同，则本月是闰月。
        let lunar = chinese.dateComponents([.month, .day], from: date)
        let lunarMonth = lunar.month ?? 1
        let lunarDay = lunar.day ?? 1
        let isLeap: Bool = {
            guard let interval = chinese.dateInterval(of: .month, for: date) else { return false }
            let dayBefore = interval.start.addingTimeInterval(-86400)
            return chinese.component(.month, from: dayBefore) == lunarMonth
        }()
        let monthName = (isLeap ? "闰" : "") + lunarMonths[(lunarMonth - 1 + 12) % 12]
        let lunarText: String
        if lunarDay == 1 {
            lunarText = monthName
        } else {
            lunarText = lunarDays[(lunarDay - 1 + 30) % 30]
        }

        // 节气优先显示（红字）。
        if let term = solarTerms[year]?[md] {
            return DayInfo(lunarText: term, isRedText: true, mark: mark(for: dateString, year: year))
        }
        // 节日：阳历固定节日，其次阴历节日。
        if let fest = gregorianFestivals[md] {
            return DayInfo(lunarText: fest, isRedText: true, mark: mark(for: dateString, year: year))
        }
        let lunarKey = "\(lunarMonth)-\(lunarDay)"
        if let fest = lunarFestivals[lunarKey] {
            return DayInfo(lunarText: fest, isRedText: true, mark: mark(for: dateString, year: year))
        }
        // 除夕：腊月最后一天（即春节前一天）。
        if isLunarNewYearsEve(date: date) {
            return DayInfo(lunarText: "除夕", isRedText: true, mark: mark(for: dateString, year: year))
        }
        // 假期首日显示假期名（如国庆只在 10-01 显示，10-02 起显示阴历）。
        if let holidayName = holidayNameIfFirstDay(dateString: dateString, year: year) {
            return DayInfo(lunarText: holidayName, isRedText: true, mark: mark(for: dateString, year: year))
        }
        return DayInfo(lunarText: lunarText, isRedText: false, mark: mark(for: dateString, year: year))
    }

    /// 是不是腊月最后一天（除夕）：明天是农历正月初一就是除夕。
    private static func isLunarNewYearsEve(date: Date) -> Bool {
        guard let tomorrow = gregorian.date(byAdding: .day, value: 1, to: date) else { return false }
        let next = chinese.dateComponents([.month, .day], from: tomorrow)
        return next.month == 1 && next.day == 1
    }

    /// 假期首日的名字（如 2026-10-01 → 国庆），不是首日返回 nil。
    private static func holidayNameIfFirstDay(dateString: String, year: Int) -> String? {
        for period in holidayPeriods[year] ?? [] where period.start == dateString {
            return period.name
        }
        return nil
    }

    /// 假/班角标：假期里标“假”，调休上班日标“班”，假期优先。
    private static func mark(for dateString: String, year: Int) -> DayInfo.Mark? {
        for period in holidayPeriods[year] ?? [] {
            if dateString >= period.start && dateString <= period.end {
                return .holiday
            }
        }
        if adjustedWorkdays[year]?.contains(dateString) == true {
            return .workday
        }
        return nil
    }
}
