#if DEBUG
import SwiftUI

/// 小组件截图画廊：只在 DEBUG 包里编进（Release 包没有，不会发出去）。
/// 模拟器启动参数：--widget-preview <today|today-narrow|week|pay|month|lock-circular|lock-rectangular|app-calendar-dark|app-pay-dark|app-settings-dark|app-calendar-light|app-pay-light|app-settings-light|app-daydetail-dark|app-daydetail-light|app-payguide-dark|app-payguide-light|app-hireyear-light>
/// 演示数据：2026-11-24 周二、B 班早班 00:00–08:00，05:23 上班中。
/// 班次按真 8 天轮算（ScheduleCalculator），工资按基本工资 2420 口径——
/// 不是真人实时数据，是给老爷看样子用的；真机装上后小组件读 App 里自己的排班/工资。
/// 注意：画廊里的倒计时是系统 timer 文本、按真实现在走；截图 workflow 会先把
/// runner 的系统时间拨到 2026-11-24 05:23，再跑画廊，倒计时才对得上。
struct WidgetPreviewGallery: View {
    let kind: String

    var body: some View {
        if kind.hasPrefix("app-") {
            // App 页面截图（1.2.8.001）：排班 / 工资 / 设置三页 × 深 / 浅，渲染真页面。
            AppPagePreview(kind: kind)
        } else {
            let snap = kind == "today-narrow" ? Self.demoSnapshotNarrow() : Self.demoSnapshot()
            let entry = Self.demoEntry(snapshot: snap)
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                widgetView(entry: entry, snapshot: snap)
            }
        }
    }

    @ViewBuilder
    private func widgetView(entry: Entry, snapshot: WidgetSnapshot) -> some View {
        switch kind {
        case "week":
            WeekWidgetView(entry: entry, snapshot: snapshot)
                .frame(width: 379, height: 184)
                .background(AppStyle.surface1)
                .cornerRadius(22)
        case "pay":
            PayWidgetView(entry: entry, snapshot: snapshot)
                .frame(width: 379, height: 184)
                .background(AppStyle.surface1)
                .cornerRadius(22)
        case "month":
            MonthWidgetView(entry: entry, snapshot: snapshot)
                .frame(width: 379, height: 390)
                .background(AppStyle.surface1)
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
        case "today-narrow":
            // 窄屏小号（155×155，最小的小号尺寸）：验钱那行最长的情况完整显示。
            TodayWidgetView(entry: entry, snapshot: snapshot)
                .frame(width: 155, height: 155)
                .background(AppStyle.surface1)
                .cornerRadius(22)
        default: // "today"
            TodayWidgetView(entry: entry, snapshot: snapshot)
                .frame(width: 184, height: 184)
                .background(AppStyle.surface1)
                .cornerRadius(22)
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
            mealRate: 10,
            payAccess: true,
            // 演示那天（11 月 24 日）是正常早班：第 40 条输入（11 月正常日分摊 204.76）。
            todayInputs: PayCalc.DayEstimateInputs(
                baseShare: 2420 / 21, extraShare: 180 / 21, contribShare: 1014.61 / 21,
                taxShare: 46.36 / 21, bonusShare: 4300 / 21, dailyRate: 2420 / 21.75,
                kinds: [.normal], fractionExtra: 0, fractionKind: .normal)
        )
    }

    /// 窄屏验钱那行：同一天、同一时刻，只把输入改成三薪日（分摊 0 + 三薪加成，
    /// 钱那行带「（三薪）」后缀，是小号上最长的一行）。不是真数据——11 月 24 日
    /// 本来是正常早班，只借它验窄屏下这行缩不缩得下、截不截断。
    private static func demoSnapshotNarrow() -> WidgetSnapshot {
        var snap = demoSnapshot()
        snap.todayInputs = PayCalc.DayEstimateInputs(
            baseShare: 2420 / 21, extraShare: 180 / 21, contribShare: 1014.61 / 21,
            taxShare: 46.36 / 21, bonusShare: 0, dailyRate: 2420 / 21.75,
            kinds: [.triple], fractionExtra: 0, fractionKind: .normal)
        return snap
    }

    /// 演示 entry：2026-11-24 05:23:11，上班中（倒计时到 08:00）。
    /// 第 40 条新口径：早班预估 ¥348.05（115.24 + 70 + 8.57 − 48.31 + 204.76 − 2.21），已挣约 ¥234.34。
    private static func demoEntry(snapshot: WidgetSnapshot) -> Entry {
        let cal = DateUtil.calendar
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 5, minute: 23, second: 11))!
        let dayStart = cal.startOfDay(for: now)
        let live = PayCalc.todayLiveState(shift: "早班", onLeave: false, day: dayStart, now: now, earlyRate: 70, midRate: 30, inputs: snapshot.todayInputs)
        return Entry(date: now, snapshot: snapshot, live: live)
    }
}

/// App 页面截图（1.2.8.001）：排班 / 工资 / 设置三页 × 深 / 浅，用演示数据渲染真页面。
/// 演示账号：张晓文（B 班，内测人员，有工资权限）；演示时间 2026-11-24（画廊时钟）。
/// 日历走本地 8 天轮算（不用联网）；工资用预览那份 11 月工资；设置页直接读演示账号。
/// 只在 DEBUG 包里编进（Release 包没有）。
private struct AppPagePreview: View {
    let kind: String // app-calendar-dark / app-pay-dark / app-settings-dark / …-light
    @State private var store: AppStore = AppPagePreview.makeDemoStore()

    private var isDark: Bool { kind.hasSuffix("-dark") }
    private var tabIndex: Int {
        if kind.contains("-pay-") { return 1 }
        if kind.contains("-settings-") { return 2 }
        return 0
    }

    var body: some View {
        Group {
            if kind.hasPrefix("app-hireyear") {
                // 入职时间年份滚轮（1.2.9.001，第 36 条）：验年份显示纯数字。
                // 菜单行（真控件的样子，选中 2018）+ 滚轮（同批标签，2018 居中）。
                HireYearGalleryPreview()
            } else if kind.hasPrefix("app-payguide") {
                // 工资引导（1.2.9.001，第 30 条）：演示账号刚开通工资权限，弹窗走一遍 3 步引导。
                PayGuideView()
                    .environment(store)
            } else if kind.contains("-daydetail-") {
                // 当天详情（1.2.8.002）：2026-11-24 早班那天的详情页直接渲染，
                // 验深色下调班/请假入口、提示文字、选中描边清不清楚。
                NavigationStack {
                    DayDetailView(day: Self.demoDay())
                }
                .environment(store)
                .onAppear { store.selectedTab = tabIndex }
            } else {
                MainTabView()
                    .environment(store)
                    .onAppear { store.selectedTab = tabIndex }
            }
        }
        .preferredColorScheme(isDark ? .dark : .light)
        .onAppear {
            store.appearance = isDark ? .dark : .light
        }
    }

    /// 演示那天（2026-11-24 周二、B 班早班 00:00–08:00）：按真 8 天轮本地算。
    static func demoDay() -> DaySchedule {
        let days = ScheduleCalculator.localMonth(team: "B", year: 2026, month: 11).days ?? []
        if let d = days.first(where: { $0.date == "2026-11-24" }) { return d }
        return DaySchedule(date: "2026-11-24", team: "B", baseShift: "早班", shift: "早班",
                           start: "00:00", end: "08:00", timeLabel: "00:00–08:00",
                           totalHours: 8, isDouble: false, isWork: true)
    }

    @MainActor
    static func makeDemoStore() -> AppStore {
        let store = AppStore()
        store.user = UserProfile(
            id: "demo-zhangxiaowen", username: "18765766628", role: "admin",
            enabled: true, canWrite: true, phone: "18765766628", displayName: "张晓文",
            lastPhoneChangeAt: nil, passwordViewable: nil, team: "B",
            teamHistory: [TeamHistoryEntry(team: "B", effectiveFrom: "2026-11-02")],
            paySettings: PaySettings(
                baseSalary: 2420, bonusCoef: 1, contributionBase: 5938, position: nil,
                utilities: 60, hireYear: 2018, hireMonth: 10, deptPerfDefault: nil,
                deptPerf: nil, perfCoefDefault: nil, annualLeaveTotal: 5,
                annualLeaveRemaining: 0, education: "其他", shortageSubsidy: nil
            ),
            payMonths: nil, onboardingDone: true, isBetaTester: true, payAccess: true,
            rotation: nil, displaySettings: nil
        )
        store.isLoggedIn = true
        store.isStarting = false
        store.serverBaseURL = "http://47.97.168.14:3003"
        store.serverKind = .cloud
        store.pay = AppPagePreview.demoPay()
        // 1.2.9.001：演示日历/详情的今日预估要走新口径（奖金分摊 + 加班判定），
        // 得有全年天数和工资配置，本地现算——和真机同一条链。
        store.yearDaysCache = ["2026": AppPagePreview.demoYearDays()]
        store.payConfig = PayConfigData(settings: PayGlobalSettings(), months: [:], effective: [:])
        return store
    }

    /// 演示全年天数（2026 年，B 班 8 天轮本地算；11-02、11-03 按真记录记年休假；
    /// 11-17 → 中班、11-28 → 日班两条真调班记录也带上，不然 11 月出勤少算 1 班、
    /// 预估会偏高（演示数 405.51，真数 396.02；2026-11-26 画廊验出后补））。
    static func demoYearDays() -> [DaySchedule] {
        var yearDays: [DaySchedule] = []
        for m in 1...12 {
            yearDays += ScheduleCalculator.localMonth(team: "B", year: 2026, month: m).days ?? []
        }
        yearDays = yearDays.map { d in
            var d = d
            if d.date == "2026-11-02" || d.date == "2026-11-03" {
                d.onLeave = true
                d.leaveType = "年休假"
            }
            if d.date == "2026-11-17" {
                d.shift = "中班"
                d.overridden = true
                d.note = "临时调班"
            }
            if d.date == "2026-11-28" {
                d.shift = "日班"
                d.overridden = true
                d.note = "临时调班"
            }
            // 改了班次就要把派生字段一起改：aggregateDays 按 isWork 计数，
            // 只改 shift 不改 isWork 的话 11-17 还是算休息，出勤少 1 班、预估偏高
            //（405.51 而不是 396.02；2026-11-26 画廊第二轮验出后补）。
            if d.overridden == true {
                let parts = d.shift == "休息" ? [] : ShiftStyle.parts(of: d.shift)
                d.isWork = !parts.isEmpty
                d.isDouble = parts.count == 2
                d.totalHours = parts.count * 8
                d.timeLabel = parts.isEmpty ? nil : parts.map { ShiftStyle.timeRange(for: $0) }.joined(separator: " + ")
            }
            return d
        }
        return yearDays
    }

    /// 演示工资（2026 年 11 月）：全年天数按 B 班 8 天轮本地算，
    /// 11-02、11-03 按真记录记年休假，PayCalc 现算（和 App 本地算同一条链）。
    static func demoPay() -> PayMonth? {
        let yearDays = demoYearDays()
        let settings = PaySettings(
            baseSalary: 2420, bonusCoef: 1, contributionBase: 5938, position: nil,
            utilities: 60, hireYear: 2018, hireMonth: 10, deptPerfDefault: nil,
            deptPerf: nil, perfCoefDefault: nil, annualLeaveTotal: 5,
            annualLeaveRemaining: 0, education: "其他", shortageSubsidy: nil
        )
        return PayCalc.computePay(
            yearDays: yearDays, global: PayGlobalSettings(), userSettings: settings,
            recordedMonths: [:], effective: [:], annualLeaveOffset: 0, year: 2026, month: 11
        )
    }
}

/// 入职时间年份滚轮画廊（1.2.9.001，第 36 条，DEBUG 专属）：验年份显示纯数字。
/// 菜单行是真控件的样子（选中 2018）；滚轮用同一批标签（2018 居中），
/// 滚轮里 2016–2020 都是纯数字即算过——2012 与 2018 是同一批标签。
private struct HireYearGalleryPreview: View {
    @State private var hireYear = 2018
    @State private var hireMonth = 10
    private var years: [Int] { Array(1990...Calendar.current.component(.year, from: Date())) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // 38 条：和工资设置页真行同结构（年份 + 月份两个 Picker 都在），
                    // 验拥挤那行里年份是不是横着一行纯数字。
                    HStack {
                        Text("入职时间")
                        Spacer()
                        Picker("年份", selection: $hireYear) {
                            ForEach(years, id: \.self) { y in
                                Text(verbatim: "\(y)").tag(y)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                        Text("年")
                        Picker("月份", selection: $hireMonth) {
                            ForEach(1...12, id: \.self) { m in
                                Text(verbatim: "\(m)").tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                        Text("月")
                    }
                } header: {
                    Text("工资设置 → 入职时间（第 36、38 条）")
                } footer: {
                    Text("年份显示纯数字（2012、2018），不带千分位逗号；横着一行，不折行。")
                }
                Section("年份滚轮") {
                    Picker("年份", selection: $hireYear) {
                        ForEach(years, id: \.self) { y in
                            Text(verbatim: "\(y)").tag(y)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 200)
                }
            }
            .navigationTitle("入职时间")
        }
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
