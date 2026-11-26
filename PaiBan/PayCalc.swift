import Foundation

/// 本地工资计算：服务端 core.js `monthPay` / `computePay`（老爷）与
/// `monthPayForUser` / `computePayForUser`（同事）的 Swift 移植。
///
/// 输入是已从服务端拿到的原始数据（全年天数 + 工资配置），计算本身不走网络，
/// 所以切月、看工资都是本地秒出；服务端只负责给原始数据（排班与配置）。
/// 移植前已用服务端现行配置 + 全年天数，在 Python 镜像里逐项对过 2026 全年
/// 12 个月（工资、奖金、个税、累计、三薪、出勤全部字段），0 误差。
enum PayCalc {

    // MARK: - 静态表（与服务端 core.js 一致）

    /// 基本天数（法定口径）。2026 已对过工资条；2027 按公开日历推算，用前须核对官方安排。
    static let basicDaysTable: [Int: [Int: Int]] = [
        2026: [1: 21, 2: 16, 3: 22, 4: 21, 5: 19, 6: 21, 7: 23, 8: 21, 9: 22, 10: 18, 11: 21, 12: 23],
        2027: [1: 21, 2: 16, 3: 23, 4: 21, 5: 19, 6: 22, 7: 22, 8: 22, 9: 22, 10: 18, 11: 22, 12: 23],
    ]

    /// 法定节假日（用于三薪）。2026 已对过；2027 按公开日历推算。
    static let statutoryTable: [Int: [(String, String)]] = [
        2026: [("2026-01-01", "元旦"),
               ("2026-02-16", "春节"), ("2026-02-17", "春节"), ("2026-02-18", "春节"), ("2026-02-19", "春节"),
               ("2026-04-05", "清明节"),
               ("2026-05-01", "劳动节"), ("2026-05-02", "劳动节"),
               ("2026-06-19", "端午节"),
               ("2026-09-25", "中秋节"),
               ("2026-10-01", "国庆节"), ("2026-10-02", "国庆节"), ("2026-10-03", "国庆节")],
        2027: [("2027-01-01", "元旦"),
               ("2027-02-05", "春节"), ("2027-02-06", "春节"), ("2027-02-07", "春节"), ("2027-02-08", "春节"),
               ("2027-04-05", "清明节"),
               ("2027-05-01", "劳动节"),
               ("2027-06-18", "端午节"),
               ("2027-09-25", "中秋节"),
               ("2027-10-01", "国庆节"), ("2027-10-02", "国庆节"), ("2027-10-03", "国庆节")],
    ]

    /// 累计预扣预缴税率表（upTo, rate, 速算扣除数）。
    static let taxBrackets: [(upTo: Double, rate: Double, deduction: Double)] = [
        (36000, 0.03, 0),
        (144000, 0.10, 2520),
        (300000, 0.20, 16920),
        (420000, 0.25, 31920),
        (660000, 0.30, 52920),
        (960000, 0.35, 85920),
        (.infinity, 0.45, 181920),
    ]

    // MARK: - 基础工具

    /// 与服务端 round2 一致：Math.round((x + EPSILON) * 100) / 100。
    /// Double.ulpOfOne 就是 JS 的 Number.EPSILON；Swift 默认舍入是“就近、 ties 远离零”，
    /// 正数上与 JS 的 Math.round（.5 向上）一致。
    static func round2(_ x: Double) -> Double {
        ((x + Double.ulpOfOne) * 100).rounded() / 100
    }

    /// 按 JS 的数字转字符串（整数不带 .0），只用于 heatNote 这类展示文案。
    static func jsNum(_ x: Double) -> String {
        x == x.rounded() ? String(Int(x)) : String(x)
    }

    static func basicDays(year: Int, month: Int) -> Int {
        if let t = basicDaysTable[year], let v = t[month] { return v }
        // 表里没有的年份：按工作日（周一至周五）数兜底（与服务端 fallback 一致）。
        var n = 0
        let dim = DateUtil.daysInMonth(year: year, month: month)
        for d in 1...dim {
            if let date = DateUtil.calendar.date(from: DateComponents(year: year, month: month, day: d)) {
                let w = DateUtil.calendar.component(.weekday, from: date) // 1=周日 … 7=周六
                if w != 1 && w != 7 { n += 1 }
            }
        }
        return n
    }

    static func statutoryMap(year: Int) -> [String: String] {
        var m: [String: String] = [:]
        for (d, name) in statutoryTable[year] ?? [] { m[d] = name }
        return m
    }

    static func taxFor(_ taxable: Double) -> Double {
        if taxable <= 0 { return 0 }
        for b in taxBrackets where taxable <= b.upTo {
            return round2(taxable * b.rate - b.deduction)
        }
        return 0
    }

    /// 按 monthKey 生效的设置（baseSalary / position / bonusCoef）：取 <= key 的全部条目按 key 升序合并。
    static func effectiveFor(_ effective: [String: PayEffective], key: String) -> PayEffective {
        var out = PayEffective()
        for k in effective.keys.filter({ $0 <= key }).sorted() {
            let e = effective[k]!
            if let v = e.baseSalary { out.baseSalary = v }
            if let v = e.position { out.position = v }
            if let v = e.bonusCoef { out.bonusCoef = v }
        }
        return out
    }

    // MARK: - 月度聚合（与服务端 aggregateDays 一致）

    /// 对已算好的某月天数做聚合：班次计数、实际出勤、双班、请假、休息。
    /// 注意请假口径：只有 baseShift 不是休息的日子才计请假；请假的日子不计实际出勤。
    static func aggregateDays(_ days: [DaySchedule], year: Int, month: Int) -> MonthStats {
        var weekendDays = 0, restDays = 0, actualWork = 0, actualShifts = 0, doubleDays = 0, leaveDays = 0
        var dayCount = 0, earlyCount = 0, midCount = 0
        for d in days {
            if let w = d.weekday, (w == 0 || w == 6) { weekendDays += 1 }
            if d.onLeave == true && d.baseShift != "休息" { leaveDays += 1 }
            if d.isWork != true { restDays += 1; continue }
            if d.onLeave == true { continue }
            actualWork += 1
            if d.isDouble == true { doubleDays += 1 }
            for p in ShiftStyle.parts(of: d.shift) {
                actualShifts += 1
                if p == "日班" { dayCount += 1 }
                else if p == "早班" { earlyCount += 1 }
                else if p == "中班" { midCount += 1 }
            }
        }
        let bd = basicDays(year: year, month: month)
        return MonthStats(
            totalDays: days.count, weekendDays: weekendDays, basicDays: bd,
            restDays: restDays, actualWork: actualWork, actualShifts: actualShifts,
            doubleDays: doubleDays, leaveDays: leaveDays, overtime: actualWork - bd,
            counts: ShiftCounts(day: dayCount, early: earlyCount, mid: midCount)
        )
    }

    /// 当月应出勤（只按基础班次算：数 baseShift 不是休息的天数，调班请假不影响）。
    static func countBaseWork(yearDays: [DaySchedule], year: Int, month: Int) -> Int {
        let prefix = String(format: "%04d-%02d-", year, month)
        var n = 0
        for d in yearDays where d.date.hasPrefix(prefix) && d.baseShift != "休息" { n += 1 }
        return n
    }

    // MARK: - 单月工资（不含累计个税字段）

    /// 算某一个月的工资（不含累计个税）。与服务端 monthPay / monthPayForUser 同构。
    /// - yearDays: 该年的全部天数（/me/range 一次取回，已按换班记录解析过）。
    /// - global: 全局工资设置（GET /api/v1/config 的 pay.settings）。
    /// - userSettings: 本人 paySettings（只填改过的字段；老爷为空）。
    /// - record: 该月录入数（老爷：config.pay.months[monthKey]；同事：无）。
    /// - effective: 生效表（老爷：config.pay.effective；同事：无）。
    /// - annualLeaveOffset: 年假已用抵扣（老爷：config 的 annualLeaveUsedOffset[年]；同事：0）。
    static func monthPay(
        yearDays: [DaySchedule],
        global: PayGlobalSettings,
        userSettings: PaySettings?,
        record: PayMonthRecord?,
        effective: [String: PayEffective],
        annualLeaveOffset: Int,
        year: Int, month: Int
    ) -> PayMonth {
        let key = String(format: "%04d-%02d", year, month)
        let eff = effectiveFor(effective, key: key)
        // 设置：全局 + 本人 paySettings（本人只覆盖填过的字段）。
        func pick(_ user: Double?, _ g: Double?) -> Double? { user ?? g }
        let baseSalary = eff.baseSalary ?? pick(userSettings?.baseSalary, global.baseSalary) ?? 2420
        let position = eff.position ?? userSettings?.position ?? "员工"
        // 奖金系数取值链：单月记录 > 生效表 > 用户设置 > 1（别写成 4 层 ?? 链，拆开写）。
        var bonusCoef = userSettings?.bonusCoef ?? 1
        if let v = eff.bonusCoef { bonusCoef = v }
        if let v = record?.bonusCoef { bonusCoef = v }

        let monthPrefix = key + "-"
        let days = yearDays.filter { $0.date.hasPrefix(monthPrefix) }
        let stats = aggregateDays(days, year: year, month: month)
        let counts = stats.counts ?? ShiftCounts(day: 0, early: 0, mid: 0)
        let bd = stats.basicDays ?? basicDays(year: year, month: month)
        let dailyRate = baseSalary / 21.75

        let attendance = record?.attendance ?? Double(stats.actualShifts ?? 0)
        let earlyRate = global.earlyRate ?? 70
        let midRate = global.midRate ?? 30
        let allowanceAuto = Double(counts.early ?? 0) * earlyRate + Double(counts.mid ?? 0) * midRate
        let allowance = record?.allowance ?? allowanceAuto
        // 科室绩效取值链：单月记录 > 用户默认 > 用户全局默认 > 全局默认 > 4000。
        // 注意：不要写成一条 5 层 ?? 链，Swift 编译器算不过来（2026-11-24 构建 e5001ea 在此报错）。
        var deptPerf = global.deptPerfDefault ?? 4000
        if let v = userSettings?.deptPerfDefault { deptPerf = v }
        if let v = userSettings?.deptPerf { deptPerf = v }
        if let v = record?.deptPerf { deptPerf = v }
        var perfCoef = global.perfCoefDefault ?? 1
        if let v = userSettings?.perfCoefDefault { perfCoef = v }
        if let v = record?.perfCoef { perfCoef = v }

        // 法定节假日当天上班的天。
        let stat = statutoryMap(year: year)
        var tripleDates: [TripleDate] = []
        for d in days {
            if stat[d.date] != nil && d.isWork == true && d.onLeave != true {
                tripleDates.append(TripleDate(date: d.date, name: stat[d.date], shift: d.shift))
            }
        }
        // 三薪按班次算（2026-11-24 老爷定）：法定节假日上了几个班就有几个三薪，双班那天算 2 个。
        let statutoryWorkedShifts = tripleDates.reduce(0) { $0 + ShiftStyle.parts(of: $1.shift ?? "").count }
        // 三薪提纯：只有超出基本天数的部分算三薪，其余节假日班次转加班。
        // 注意 attendance 可能是小数（如 23.4），这里按服务端原样用浮点算，不取整。
        let tripleDays = record?.tripleDays ?? min(Double(statutoryWorkedShifts), max(0, attendance - Double(bd)))
        let convertedTripleDays = Double(statutoryWorkedShifts) - tripleDays
        let overtimeDays = record?.overtimeDays ?? round2(max(0, attendance - Double(bd) - tripleDays) + convertedTripleDays)
        let triplePay = round2(tripleDays * 3 * dailyRate)
        let overtimePayPart = round2(overtimeDays * 2 * dailyRate)
        let overtimePay = round2(triplePay + overtimePayPart)

        let otherFull = global.otherRewardFull ?? 300
        let otherReward = attendance >= Double(bd) ? otherFull
            : max(0, round2(otherFull - 15 * (Double(bd) - attendance)))
        let heat: Double
        if month >= 6 && month <= 9 {
            heat = round2((global.heatMonthly ?? 250) * min(1, attendance / Double(bd)))
        } else {
            heat = 0
        }
        let seniority = (global.seniorityPerYear ?? 20) * Double(year - (userSettings?.hireYear ?? global.hireYear ?? 2018) + 1)
        // 学历补贴（2026-11-24 老爷定）：专科 50、本科 100、其他 0；进工资小计，跟着计税。
        var educationSubsidy: Double = 0
        if userSettings?.education == "专科" { educationSubsidy = 50 }
        else if userSettings?.education == "本科" { educationSubsidy = 100 }
        let salarySubtotal = round2(baseSalary + allowance + heat + educationSubsidy + seniority)

        let base = userSettings?.contributionBase ?? global.contributionBase ?? 5938
        let pension = round2(base * 0.08)
        let medical = round2(base * 0.02)
        let unemployment = round2(base * 0.003)
        let socialInsurance = round2(pension + medical + unemployment)
        let housingFund = floor(base * 0.068)
        let contributionTotal = round2(socialInsurance + housingFund)
        let salaryPayable = round2(salarySubtotal - contributionTotal)
        // 水电费取值链：单月记录 > 用户设置 > 全局默认 > 0（老爷自己的 60 存在他自己的 paySettings 里）。
        // 单月覆盖只影响当月实发（salaryNet = salaryPayable − 当月水电费）。
        var utilities = global.utilities ?? 0
        if let v = userSettings?.utilities { utilities = v }
        if let v = record?.utilities { utilities = v }
        let salaryNet = round2(salaryPayable - utilities)

        // 缺员补贴（2026-11-24 老爷定）：用户级设置 {amount, startDate, endDate}；
        // 当月在 [开始月，结束月] 内才计入（按月比，不足月也算整月），直接加进奖金，不乘系数。
        var shortageSubsidy: Double = 0
        let ssAmount = userSettings?.shortageSubsidy?.amount ?? 0
        if ssAmount > 0 {
            var inRange = true
            if let s = userSettings?.shortageSubsidy?.startDate, key < String(s.prefix(7)) { inRange = false }
            if let e = userSettings?.shortageSubsidy?.endDate, key > String(e.prefix(7)) { inRange = false }
            if inRange { shortageSubsidy = round2(ssAmount) }
        }
        let bonusTotal = round2((deptPerf + otherReward) * perfCoef * bonusCoef + overtimePay + shortageSubsidy)

        // 年假：全年已用 = 抵扣 + 全年请年假/年休假的天数（只算有班的日子）。
        // 1.2.6：存了剩余天数时（引导里填的余额，含上年结转），全年可用 = 存的余额，
        // 剩余 = 余额 − 本年已用；不存时仍按全年 5 天 − 已用算（年假累计，不跨年清零）。
        var annualLeaveTotal = 5
        if let stored = userSettings?.annualLeaveRemaining {
            annualLeaveTotal = stored
        } else if let total = userSettings?.annualLeaveTotal {
            annualLeaveTotal = total
        } else if let total = global.annualLeaveTotal {
            annualLeaveTotal = total
        }
        var yearUsed = annualLeaveOffset
        var monthUsed = 0
        for d in yearDays {
            if d.onLeave == true && (d.leaveType == "年假" || d.leaveType == "年休假") && d.baseShift != "休息" {
                yearUsed += 1
                if d.date.hasPrefix(monthPrefix) { monthUsed += 1 }
            }
        }

        var pay = PayMonth()
        pay.year = year
        pay.month = month
        pay.monthKey = key
        pay.baseSalary = baseSalary
        pay.position = position
        pay.bonusCoef = bonusCoef
        pay.basicDays = bd
        pay.rosterTotalWork = countBaseWork(yearDays: yearDays, year: year, month: month)
        pay.rosterWork = stats.actualWork
        pay.attendance = attendance
        pay.attendanceRecorded = record?.attendance != nil
        pay.counts = counts
        pay.allowance = allowance
        pay.allowanceAuto = allowanceAuto
        pay.allowanceRecorded = record?.allowance != nil
        pay.deptPerf = deptPerf
        pay.deptPerfRecorded = record?.deptPerf != nil
        pay.perfCoef = perfCoef
        pay.bonusCoefRecorded = record?.bonusCoef != nil
        pay.otherReward = otherReward
        pay.otherRewardFull = attendance >= Double(bd)
        pay.heat = heat
        pay.heatNote = (month >= 6 && month <= 9)
            ? (attendance >= Double(bd) ? "出勤满应出勤 \(bd) 天，高温费发满 \(jsNum(global.heatMonthly ?? 250)) 元" : "按出勤折算：\(jsNum(global.heatMonthly ?? 250)) × \(jsNum(attendance)) 天 ÷ 应出勤 \(bd) 天")
            : "高温费只在 6、7、8、9 月有"
        pay.seniority = seniority
        pay.educationSubsidy = educationSubsidy
        pay.salarySubtotal = salarySubtotal
        pay.contributionBase = base
        pay.pension = pension
        pay.medical = medical
        pay.unemployment = unemployment
        pay.socialInsurance = socialInsurance
        pay.housingFund = housingFund
        pay.contributionTotal = contributionTotal
        pay.salaryPayable = salaryPayable
        pay.utilities = utilities
        pay.utilitiesRecorded = record?.utilities != nil
        pay.salaryNet = salaryNet
        pay.tripleDates = tripleDates
        pay.tripleDays = tripleDays
        pay.triplePay = triplePay
        pay.tripleRecorded = record?.tripleDays != nil
        pay.convertedTripleDays = convertedTripleDays
        pay.overtimeDays = overtimeDays
        pay.overtimePay = overtimePay
        pay.overtimePayPart = overtimePayPart
        pay.overtimeRecorded = record?.overtimeDays != nil
        pay.shortageSubsidy = shortageSubsidy
        pay.bonusTotal = bonusTotal
        pay.leaveDays = stats.leaveDays
        pay.excessDays = (pay.rosterTotalWork ?? 0) - bd
        pay.mealAllowance = round2(attendance * (global.mealRate ?? 10))
        pay.dailyRate = round2(dailyRate)
        pay.annualLeaveTotal = annualLeaveTotal
        pay.annualLeaveYearUsed = yearUsed
        pay.annualLeaveRemaining = max(0, annualLeaveTotal - yearUsed)
        pay.annualLeaveMonth = monthUsed
        pay.annualLeaveApplied = monthUsed > 0
        pay.annualLeaveOffsetUsed = annualLeaveOffset
        return pay
    }

    // MARK: - 全月工资（含累计预扣个税）

    /// 算某月工资（含累计预扣个税）：从 1 月算到当月，累计口径与服务端 computePay 一致。
    /// 税从奖金里扣：当月扣税 = 本月累计个税总额 − 上月累计个税总额。
    static func computePay(
        yearDays: [DaySchedule],
        global: PayGlobalSettings,
        userSettings: PaySettings?,
        recordedMonths: [String: PayMonthRecord],
        effective: [String: PayEffective],
        annualLeaveOffset: Int,
        year: Int, month: Int
    ) -> PayMonth {
        var cumGross: Double = 0
        var cumContrib: Double = 0
        var prevCumTax: Double = 0
        var result = PayMonth()
        for mm in 1...month {
            var mp = monthPay(
                yearDays: yearDays, global: global, userSettings: userSettings,
                record: recordedMonths[String(format: "%04d-%02d", year, mm)],
                effective: effective, annualLeaveOffset: annualLeaveOffset,
                year: year, month: mm
            )
            cumGross = round2(cumGross + (mp.salaryPayable ?? 0) + (mp.contributionTotal ?? 0) + (mp.bonusTotal ?? 0))
            cumContrib = round2(cumContrib + (mp.contributionTotal ?? 0))
            let cumTaxable = round2(cumGross - cumContrib - 5000 * Double(mm))
            let cumTax = taxFor(cumTaxable)
            let incomeTax = round2(cumTax - prevCumTax)
            prevCumTax = cumTax
            mp.cumulativeGross = cumGross
            mp.cumulativeContributions = cumContrib
            mp.cumulativeMonths = mm
            mp.cumulativeTaxableIncome = cumTaxable
            mp.cumulativeTaxTotal = cumTax
            mp.previousCumulativeTaxTotal = round2(cumTax - incomeTax)
            mp.incomeTax = incomeTax
            mp.bonusAfterTax = round2((mp.bonusTotal ?? 0) - incomeTax)
            mp.grandTotal = round2((mp.salaryNet ?? 0) + ((mp.bonusTotal ?? 0) - incomeTax))
            mp.taxableIncome = cumTaxable
            result = mp
        }
        return result
    }

    // MARK: - 今日预估工资与实时倒计时（1.2.7，老爷 2026-11-25 定）

    /// 单个班次的起止（从 0 点起的分钟数）：早班 00:00–08:00，日班 08:00–16:00，中班 16:00–24:00。
    static func segmentRange(for part: String) -> (start: Int, end: Int)? {
        switch part {
        case "早班": return (0, 480)
        case "日班": return (480, 960)
        case "中班": return (960, 1440)
        default: return nil
        }
    }

    /// 某天是不是法定节假日三薪日（三薪表里那几天）。
    static func isStatutoryDay(_ dateString: String) -> Bool {
        guard let year = Int(dateString.prefix(4)) else { return false }
        return statutoryMap(year: year)[dateString] != nil
    }

    /// 解析基本工资：与 monthPay 同链——生效表（当月）> 个人设置 > 全局 > 2420。
    static func resolvedBaseSalary(effective: [String: PayEffective], userSettings: PaySettings?, global: PayGlobalSettings, monthKey: String) -> Double {
        let eff = effectiveFor(effective, key: monthKey)
        if let v = eff.baseSalary { return v }
        if let v = userSettings?.baseSalary { return v }
        if let v = global.baseSalary { return v }
        return 2420
    }

    /// 每日奖金分摊（第 29 条，2026-11-26）：当月绩效奖金部分 ÷ 当月实际出勤班数。
    /// 绩效奖金部分 = 奖金总额 − 加班费（加班费按天另算，不摊进每天）。
    /// 直接用 monthPay 已算好的数推（(科室绩效 + 其他奖罚) × 绩效系数 × 奖金系数 + 缺员补贴），
    /// 不重算取值链，免得两边对不上。出勤 0 班时分摊 0。
    /// 例（他 11 月）：(4300 − 0) ÷ 21 = 204.76。
    static func dailyBonusShare(bonusTotal: Double?, overtimePay: Double?, attendance: Double?) -> Double {
        guard let att = attendance, att > 0 else { return 0 }
        let perfPart = (bonusTotal ?? 0) - (overtimePay ?? 0)
        return round2(perfPart / att)
    }

    /// 某天有几个班次算加班（第 29 条，2026-11-26）：当月累计到当天的班次数超过当月基本天数，
    /// 超出的班次才算加班；三薪日优先算三薪、不算加班；休息/请假不算。
    /// monthDays 是当月每天 (date, shift, onLeave)；只认当月内的天，不要求事先排好序。
    /// 返回 0…当天班次数（双班那天最多 2）。累计按班次算（双班那天算 2 个），
    /// 和月度公式里出勤（班数）对基本天数（天数）是同一口径。
    static func overtimeShiftCount(dateString: String, monthDays: [(date: String, shift: String, onLeave: Bool)], year: Int, month: Int) -> Int {
        let prefix = String(format: "%04d-%02d", year, month)
        guard let target = monthDays.first(where: { $0.date == dateString }) else { return 0 }
        if target.onLeave || target.shift == "休息" { return 0 }
        if isStatutoryDay(dateString) { return 0 } // 三薪优先，不算加班
        let bd = basicDays(year: year, month: month)
        var before = 0
        var dayParts = 0
        for d in monthDays {
            if !d.date.hasPrefix(prefix) || d.date > dateString { continue }
            if d.onLeave || d.shift == "休息" { continue }
            let n = ShiftStyle.parts(of: d.shift).count
            if d.date == dateString { dayParts = n } else { before += n }
        }
        let over = before + dayParts - bd
        if over <= 0 { return 0 }
        return min(over, dayParts)
    }

    /// 今日预估工资（第 29 条口径，2026-11-26，取代第 19 条只算工资的老口径）：
    /// 每个班 = 日工资（基本工资 ÷ 21.75）+ 班次补贴（早 70 / 中 30 / 日 0）+ 餐补 10
    ///          + 每日奖金分摊；三薪日每班再加 3 倍日工资；加班班次每个再加 2 倍日工资；
    /// 双班两班都算；休息 0 元。
    /// 三薪日按当天全额算，不走月度工资里「三薪提纯」（超出基本天数的部分才算三薪）那条——
    /// 单日预估按当天全额算（和第 19 条现有做法一致）。
    /// 加班班次是当天靠后的几个（累计到当天才超出的那几个），每个加 2 倍日工资。
    /// 例（他 11 月：基本 2420、分摊 204.76）：普通日班日 = 111.26 + 0 + 10 + 204.76 = 326.02；
    /// 早班三薪日 = 111.26 + 70 + 10 + 204.76 + 333.79 = 729.81。
    /// - shift: 今日实际班次（日班/中班/早班/休息/早中班/日中班）。
    /// - baseSalary: 基本工资（已按生效表/个人设置/全局解析好）。
    /// - dateString: 今日 "yyyy-MM-dd"，用于查三薪表。
    /// - earlyRate/midRate/mealRate: 补贴率（全局设置，缺失用 70/30/10）。
    /// - dailyBonusShare: 每日奖金分摊（当月绩效奖金部分 ÷ 当月实际出勤班数）。
    /// - overtimeShifts: 当天算加班的班次数（0…当天班次数；三薪日传 0）。
    /// 返回 (total: 当日预估总额，isRest: 是否休息，isTriple: 是否三薪日，isOvertime: 是否加班日）。
    static func todayEstimate(shift: String, baseSalary: Double, dateString: String,
                              earlyRate: Double = 70, midRate: Double = 30, mealRate: Double = 10,
                              dailyBonusShare: Double = 0, overtimeShifts: Int = 0) -> (total: Double, isRest: Bool, isTriple: Bool, isOvertime: Bool) {
        if shift == "休息" { return (0, true, false, false) }
        let dailyRate = baseSalary / 21.75
        let triple = isStatutoryDay(dateString)
        // 每项先取整到分再加（老爷的算法：111.26 + 333.79 + 70 + 10 = 525.05）；
        // 先加未取整的数再取整会得 525.06，差一分。
        let dayPay = round2(dailyRate)
        let triplePay = round2(3 * dailyRate)
        let overtimePay = round2(2 * dailyRate)
        let parts = ShiftStyle.parts(of: shift)
        // 加班班次在当天靠后的几个；三薪日不算加班（ot 强制 0）。
        let ot = triple ? 0 : min(max(overtimeShifts, 0), parts.count)
        var total: Double = 0
        for (index, p) in parts.enumerated() {
            var pay = dayPay + mealRate + dailyBonusShare
            if p == "早班" { pay += earlyRate }
            else if p == "中班" { pay += midRate }
            if triple { pay += triplePay }
            if index >= parts.count - ot { pay += overtimePay }
            total += pay
        }
        return (round2(total), false, triple, ot > 0)
    }

    /// 今日的班次时段（供倒计时用）：每个单班一段，起止是当天 0 点起的 Date。
    /// 早中班两段（00:00–08:00 与 16:00–24:00，中间歇着）；日中班两段连着（08:00–24:00）。
    /// 每段带该段的预估工资（按 todayEstimate 的口径分段算：奖金分摊每段一份，
    /// 三薪每段加 3 倍日工资，加班的段（当天靠后的几个）每段加 2 倍日工资）。
    static func todaySegments(shift: String, day: Date, baseSalary: Double, dateString: String,
                              earlyRate: Double = 70, midRate: Double = 30, mealRate: Double = 10,
                              dailyBonusShare: Double = 0, overtimeShifts: Int = 0) -> [(start: Date, end: Date, pay: Double)] {
        let cal = DateUtil.calendar
        let startOfDay = cal.startOfDay(for: day)
        let dailyRate = baseSalary / 21.75
        let triple = isStatutoryDay(dateString)
        // 每项先取整到分再加（与 todayEstimate 同口径：111.26 + 333.79 + 70 + 10 = 525.05）。
        let dayPay = round2(dailyRate)
        let triplePay = round2(3 * dailyRate)
        let overtimePay = round2(2 * dailyRate)
        let parts = ShiftStyle.parts(of: shift)
        let ot = triple ? 0 : min(max(overtimeShifts, 0), parts.count)
        var out: [(start: Date, end: Date, pay: Double)] = []
        for (index, p) in parts.enumerated() {
            guard let r = segmentRange(for: p) else { continue }
            guard let s = cal.date(byAdding: .minute, value: r.start, to: startOfDay),
                  let e = cal.date(byAdding: .minute, value: r.end, to: startOfDay) else { continue }
            var pay = dayPay + mealRate + dailyBonusShare
            if p == "早班" { pay += earlyRate }
            else if p == "中班" { pay += midRate }
            if triple { pay += triplePay }
            if index >= parts.count - ot { pay += overtimePay }
            out.append((start: s, end: e, pay: round2(pay)))
        }
        return out.sorted { $0.start < $1.start }
    }

    /// 今日实时状态（第 20 条：倒计时 + 工资实时涨）。
    enum TodayLiveState: Equatable {
        case rest                                        // 休息 / 请假：¥0
        case before(start: Date, total: Double)          // 上班前：倒计时到上班，已挣 ¥0
        case working(end: Date, earned: Double, total: Double) // 上班中：倒计时到下班，已挣实时涨
        case between(nextStart: Date, earned: Double, total: Double) // 两班之间歇着：倒计时到下一班
        case done(total: Double)                         // 下班后：今日已挣全额
    }

    /// 今日实时状态：今日总工资 ÷ 班时长 = 每秒单价；已挣 = 已过时间 × 每秒单价。
    /// 双班按两个班连着算（每段各有自己的单价）；跨夜的早班是当天 00:00–08:00，不跨日期。
    /// - shift: 今日实际班次；onLeave: 请假按休息算（¥0）。
    /// - day: 今天 0 点；now: 当前时刻。
    /// - dailyBonusShare / overtimeShifts: 第 29 条（奖金分摊 / 当天加班班次数），透传给 todaySegments。
    static func todayLiveState(shift: String, onLeave: Bool, day: Date, now: Date,
                               baseSalary: Double, dateString: String,
                               earlyRate: Double = 70, midRate: Double = 30, mealRate: Double = 10,
                               dailyBonusShare: Double = 0, overtimeShifts: Int = 0) -> TodayLiveState {
        if onLeave || shift == "休息" { return .rest }
        let segs = todaySegments(shift: shift, day: day, baseSalary: baseSalary, dateString: dateString, earlyRate: earlyRate, midRate: midRate, mealRate: mealRate, dailyBonusShare: dailyBonusShare, overtimeShifts: overtimeShifts)
        guard let first = segs.first, let last = segs.last else { return .rest }
        let total = round2(segs.reduce(0) { $0 + $1.pay })
        if now < first.start { return .before(start: first.start, total: total) }
        if now >= last.end { return .done(total: total) }
        var earned: Double = 0
        for seg in segs {
            if now >= seg.end {
                earned += seg.pay
            } else if now >= seg.start {
                let duration = seg.end.timeIntervalSince(seg.start)
                let elapsed = now.timeIntervalSince(seg.start)
                let rate = duration > 0 ? seg.pay / duration : 0
                earned += elapsed * rate
                return .working(end: seg.end, earned: round2(earned), total: total)
            } else {
                return .between(nextStart: seg.start, earned: round2(earned), total: total)
            }
        }
        return .done(total: total)
    }

    /// 小组件时间线刷新点（第 20 条）：班中每 15 分钟 + 上下班边界各一次 + 次日 0 点。
    /// 返回今天从 now 起的刷新时刻（已按时间升序，含 now 本身与次日 0 点）。
    static func todayRefreshDates(shift: String, day: Date, now: Date) -> [Date] {
        let cal = DateUtil.calendar
        var dates: [Date] = [now]
        let startOfDay = cal.startOfDay(for: day)
        guard let nextMidnight = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return dates }
        var bounds: [Date] = []
        for p in ShiftStyle.parts(of: shift) {
            guard let r = segmentRange(for: p) else { continue }
            if let s = cal.date(byAdding: .minute, value: r.start, to: startOfDay) { bounds.append(s) }
            if let e = cal.date(byAdding: .minute, value: r.end, to: startOfDay) { bounds.append(e) }
            var m = r.start + 15
            while m < r.end {
                if let d = cal.date(byAdding: .minute, value: m, to: startOfDay) { bounds.append(d) }
                m += 15
            }
        }
        for d in bounds.sorted() where d > now && d < nextMidnight {
            dates.append(d)
        }
        dates.append(nextMidnight)
        return dates
    }
}
