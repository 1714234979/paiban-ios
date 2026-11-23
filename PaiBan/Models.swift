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
struct PublicUser: Codable, Equatable {
    var id: String?
    var username: String?
    var role: String?
    var enabled: Bool?
    var canWrite: Bool?
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
    var perfCoefDefault: Double?
    var annualLeaveTotal: Int?
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
/// perfCoef / tripleDays / overtimeDays，缺失即按排班表算。
struct PayMonthRecord: Codable, Equatable {
    var attendance: Double? = nil
    var allowance: Double? = nil
    var deptPerf: Double? = nil
    var perfCoef: Double? = nil
    var tripleDays: Double? = nil
    var overtimeDays: Double? = nil
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
    var otherReward: Double? = nil
    var otherRewardFull: Bool? = nil
    var heat: Double? = nil
    var heatNote: String? = nil
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
