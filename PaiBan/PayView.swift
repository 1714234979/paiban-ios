import SwiftUI

/// 预估工资页：月份步进（默认上个月），只按月看（全年视图已删）。
/// 数字在手机本地算（服务端只给排班与工资配置原始数据），切月秒出。
struct PayView: View {
    @EnvironmentObject private var store: AppStore

    /// 改科室绩效：点奖金里的科室绩效行，弹出输入框改当月那个数。
    @State private var editingDeptPerf = false
    @State private var deptPerfText = ""
    @State private var deptPerfSaving = false
    @State private var deptPerfError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                monthStepper
                monthBreakdown
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
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("预估工资")
                .font(.title2).bold()
                .foregroundColor(.white)
            Text("本地计算，仅供参考")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.75))
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
                bonusSection(pay: pay)
                paySection(title: "合计", rows: [
                    ("实发工资 + 实发奖金", MoneyUtil.money(pay.grandTotal)),
                    ("餐贴", MoneyUtil.money(pay.mealAllowance)),
                ])
                paySection(title: "出勤", rows: [
                    ("当月应出勤", pay.basicDays.map { "\($0) 天" } ?? "—"),
                    ("实际出勤", attendanceText(pay.attendance)),
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

    /// 奖金区：科室绩效那行点一下就能改当月那个数（只有老爷能改，改完存服务端、本地立刻重算）。
    private func bonusSection(pay: PayMonth) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("奖金")
                .font(.headline)
                .padding(.bottom, 8)
            // 科室绩效行：点一下改数（带“可改”小字提示）。
            Button {
                if store.isOwner {
                    deptPerfText = pay.deptPerf.map { String(format: "%.2f", $0) } ?? "4000"
                    deptPerfError = nil
                    editingDeptPerf = true
                }
            } label: {
                HStack {
                    Text("科室绩效")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(MoneyUtil.money(pay.deptPerf))
                    if store.isOwner {
                        Text("可改")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.08))
                            .cornerRadius(6)
                    }
                }
                .font(.subheadline)
                .padding(.vertical, 5)
            }
            .disabled(!store.isOwner)
            Divider()
            if editingDeptPerf {
                VStack(spacing: 8) {
                    HStack {
                        TextField("科室绩效（如 3800）", text: $deptPerfText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        Button("保存") { Task { await saveDeptPerf() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(deptPerfSaving)
                        Button("取消") { editingDeptPerf = false }
                            .buttonStyle(.bordered)
                    }
                    if let deptPerfError {
                        Text(deptPerfError)
                            .font(.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 8)
                Divider()
            }
            ForEach([
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
            ], id: \.0) { row in
                HStack {
                    Text(row.0)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(row.1)
                        .bold(row.0.hasPrefix("实发") || row.0.hasPrefix("税前"))
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

    private func saveDeptPerf() async {
        deptPerfError = nil
        guard let value = Double(deptPerfText.trimmingCharacters(in: .whitespaces)),
              value >= 0, value <= 10000 else {
            deptPerfError = "输个 0–10000 之间的数"
            return
        }
        deptPerfSaving = true
        defer { deptPerfSaving = false }
        let key = String(format: "%04d-%02d", store.payYearMonth.year, store.payYearMonth.month)
        await store.updateDeptPerf(monthKey: key, deptPerf: value)
        editingDeptPerf = false
    }

    /// 实际出勤可能是小数（如录入的 23.4、24.31）：整数按整数显示，小数保留 1 位。
    private func attendanceText(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value == value.rounded() { return "\(Int(value)) 天" }
        return String(format: "%.1f 天", value)
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
