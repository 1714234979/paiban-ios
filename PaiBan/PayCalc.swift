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
        let statutoryWorked = tripleDates.count
        // 三薪提纯：只有超出基本天数的部分算三薪，其余节假日天数转加班。
        // 注意 attendance 可能是小数（如 23.4），这里按服务端原样用浮点算，不取整。
        let tripleDays = record?.tripleDays ?? min(Double(statutoryWorked), max(0, attendance - Double(bd)))
        let convertedTripleDays = Double(statutoryWorked) - tripleDays
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
        let salarySubtotal = round2(baseSalary + allowance + heat + seniority)

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

        let bonusTotal = round2((deptPerf + otherReward) * perfCoef * bonusCoef + overtimePay)

        // 年假：全年已用 = 抵扣 + 全年请年假/年休假的天数（只算有班的日子）。
        let annualLeaveTotal = userSettings?.annualLeaveTotal ?? global.annualLeaveTotal ?? 5
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
}
