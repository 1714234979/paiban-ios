import SwiftUI

/// 工资页：月份步进（默认上个月），全部数字取自服务端 GET /me/pay，
/// 客户端不重算公式。另有全年视图（GET /me/pay/year）。
struct PayView: View {
    @EnvironmentObject private var store: AppStore

    @State private var mode = 0 // 0 月度，1 全年

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                Picker("视图", selection: $mode) {
                    Text("月度").tag(0)
                    Text("全年").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                monthStepper
                if mode == 0 {
                    monthBreakdown
                } else {
                    yearBreakdown
                }
                noteCard
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .task {
            if store.pay == nil {
                await store.refreshPay()
            }
        }
        .onChange(of: store.payYearMonth.year) { _ in Task { await store.refreshPay() } }
        .onChange(of: store.payYearMonth.month) { _ in Task { await store.refreshPay() } }
        .onChange(of: mode) { newMode in
            if newMode == 1 {
                Task { await store.refreshPayYear() }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("工资奖金")
                .font(.title2).bold()
                .foregroundColor(.white)
            Text("数字以服务端计算为准")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.75))
            if store.isOffline {
                Label("离线缓存", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(red: 0.11, green: 0.15, blue: 0.23))
        .cornerRadius(16)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var monthStepper: some View {
        HStack {
            Button { stepPayMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
            }
            Spacer()
            Text("\(store.payYearMonth.year)年\(store.payYearMonth.month)月")
                .font(.title3).bold()
            Spacer()
            Button { stepPayMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
    }

    private func stepPayMonth(by offset: Int) {
        var year = store.payYearMonth.year
        var month = store.payYearMonth.month + offset
        while month < 1 { month += 12; year -= 1 }
        while month > 12 { month -= 12; year += 1 }
        store.payYearMonth = (year, month)
    }

    // MARK: 月度明细

    @ViewBuilder
    private var monthBreakdown: some View {
        if store.isLoadingPay && store.pay == nil {
            ProgressView("正在加载…")
                .padding()
        } else if let pay = store.pay {
            VStack(spacing: 16) {
                paySection(title: "工资", rows: [
                    ("基本工资", MoneyUtil.money(pay.baseSalary)),
                    ("岗位", pay.position ?? "—"),
                    ("早夜班补贴", MoneyUtil.money(pay.allowance)),
                    ("高温费", MoneyUtil.money(pay.heat)),
                    ("工龄津贴", MoneyUtil.money(pay.seniority)),
                    ("应发工资", MoneyUtil.money(pay.salarySubtotal)),
                    ("养老（8%）", MoneyUtil.money(pay.pension)),
                    ("医疗（2%）", MoneyUtil.money(pay.medical)),
                    ("失业（0.3%）", MoneyUtil.money(pay.unemployment)),
                    ("五险一金合计", MoneyUtil.money(pay.contributionTotal)),
                    ("公积金", MoneyUtil.money(pay.housingFund)),
                    ("水电费", MoneyUtil.money(pay.utilities)),
                    ("实发工资", MoneyUtil.money(pay.salaryNet)),
                ])
                paySection(title: "奖金", rows: [
                    ("科室绩效", MoneyUtil.money(pay.deptPerf)),
                    ("其他奖罚", MoneyUtil.money(pay.otherReward)),
                    ("绩效系数", MoneyUtil.number(pay.perfCoef)),
                    ("奖金系数", MoneyUtil.number(pay.bonusCoef)),
                    ("加班费（含三薪）", MoneyUtil.money(pay.overtimePay)),
                    ("三薪天数", pay.tripleDays.map { String(format: "%.1f 天", $0) } ?? "—"),
                    ("三薪金额", MoneyUtil.money(pay.triplePay)),
                    ("加班天数", pay.overtimeDays.map { String(format: "%.1f 天", $0) } ?? "—"),
                    ("税前奖金", MoneyUtil.money(pay.bonusTotal)),
                    ("个税（累计预扣，税从奖金里扣）", MoneyUtil.money(pay.incomeTax)),
                    ("实发奖金", MoneyUtil.money(pay.bonusAfterTax)),
                ])
                paySection(title: "合计", rows: [
                    ("实发工资 + 实发奖金", MoneyUtil.money(pay.grandTotal)),
                    ("餐贴", MoneyUtil.money(pay.mealAllowance)),
                ])
                paySection(title: "出勤", rows: [
                    ("当月应出勤", pay.basicDays.map { "\($0) 天" } ?? "—"),
                    ("实际出勤", pay.attendance.map { "\($0) 天" } ?? "—"),
                    ("日班 / 早班 / 中班", "\(MoneyUtil.int(pay.counts?.day)) / \(MoneyUtil.int(pay.counts?.early)) / \(MoneyUtil.int(pay.counts?.mid)) 个"),
                    ("请假", pay.leaveDays.map { "\($0) 天" } ?? "—"),
                    ("年假剩余", pay.annualLeaveRemaining.map { "\($0) 天（全年 \(pay.annualLeaveTotal ?? 5) 天，已用 \(pay.annualLeaveYearUsed ?? 0) 天）" } ?? "—"),
                ])
                if let tripleDates = pay.tripleDates, !tripleDates.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("三薪明细")
                            .font(.headline)
                        ForEach(tripleDates, id: \.date) { item in
                            HStack {
                                Text(item.date ?? "")
                                Text(item.name ?? "")
                                Spacer()
                                Text(item.shift ?? "")
                                    .foregroundColor(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(14)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                }
            }
        } else {
            Text("暂无工资数据，稍后再试")
                .foregroundColor(.secondary)
                .padding()
        }
    }

    private func paySection(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 8)
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(row.1)
                        .bold(row.0.hasPrefix("实发") || row.0.hasPrefix("应发") || row.0.hasPrefix("税前") || row.0.contains("合计"))
                }
                .font(.subheadline)
                .padding(.vertical, 5)
                Divider()
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    // MARK: 全年视图

    @ViewBuilder
    private var yearBreakdown: some View {
        if let yearData = store.payYearData, let months = yearData.months {
            VStack(spacing: 8) {
                ForEach(months, id: \.month) { month in
                    Button {
                        store.payYearMonth = (month.year ?? store.payYearMonth.year, month.month ?? 1)
                        mode = 0
                    } label: {
                        HStack {
                            Text("\(month.month ?? 0)月")
                                .bold()
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("合计 \(MoneyUtil.money(month.grandTotal))")
                                Text("工资 \(MoneyUtil.money(month.salaryNet)) · 奖金 \(MoneyUtil.money(month.bonusAfterTax))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .font(.subheadline)
                        .padding(12)
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
                let yearTotal = months.compactMap(\.grandTotal).reduce(0, +)
                HStack {
                    Text("全年合计").bold()
                    Spacer()
                    Text(MoneyUtil.money(yearTotal)).bold()
                }
                .font(.subheadline)
                .padding(12)
                .background(Color(.systemBackground))
                .cornerRadius(10)
            }
            .padding(.horizontal, 16)
        } else {
            ProgressView("正在加载全年数据…")
                .padding()
        }
    }

    private var noteCard: some View {
        Text("计算工资仅供参考，请按照自己车间的平均绩效奖金填写，工资奖金会根据排班变化。")
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.top, 4)
    }
}
