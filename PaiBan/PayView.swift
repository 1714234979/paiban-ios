import SwiftUI

/// 预估工资页：月份步进（默认上个月），只按月看（全年视图已删）。
/// 数字在手机本地算（服务端只给排班与工资配置原始数据），切月秒出。
struct PayView: View {
    @EnvironmentObject private var store: AppStore

    /// 单月可改的 inline 编辑框：一次只改一行（科室绩效 / 绩效系数 / 奖金系数 / 加班天数 / 水电费），
    /// 样式与收起规则五种字段完全一致。点外面或切页面就收起，丢弃未保存的改动。
    @State private var editingField: PayRecordField? = nil
    @State private var editText = ""
    @State private var editSaving = false
    @State private var editError: String?
    @FocusState private var editFieldFocused: Bool
    /// 横滑锁定：横向位移占优时锁成横滑、禁掉纵向滚动，斜滑按主导方向判定。
    @State private var horizontalSwipeLocked = false
    /// 切月滑动方向（1 = 下个月：左滑，新内容从右边滑入；-1 = 上个月：右滑，从左边滑入）。
    @State private var slideDirection: Int = 1

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                monthStepper
                // 1.1.3：切月动画——内容按月份给唯一 id，换月时旧内容滑出、新内容滑入；
                // 方向由 slideDirection 定（左滑下个月从右入、右滑上个月从左入）。
                // 之前只在 withAnimation 里改月份，工资内容是 onChange 里异步刷的、
                // 不在同一个动画事务里，又没有 .transition，所以看着没有动画。
                monthBreakdown
                    .id("\(store.payYearMonth.year)-\(store.payYearMonth.month)")
                    .transition(.asymmetric(
                        insertion: .move(edge: slideDirection > 0 ? .trailing : .leading),
                        removal: .move(edge: slideDirection > 0 ? .leading : .trailing)
                    ))
                noteCard
            }
            .padding(.bottom, 24)
            // 点编辑框以外的地方就收起（丢弃未保存的改动）。Tap 手势只认轻点，
            // 拖动（滚动/横滑）不会触发，不跟左右滑切月、上下滚动冲突。
            .onTapGesture {
                if editingField != nil { dismissEdit() }
            }
        }
        .background(Color(.systemGroupedBackground))
        .scrollDisabled(horizontalSwipeLocked)
        // 左右滑动切月（与排班页的滑页体验一致）：横向位移明显大于竖向时才切月，
        // 竖向滚动不受影响。横滑一旦锁定就禁掉纵向滚动，左右滑的时候上下不再跟着动；
        // 左滑下个月、右滑上个月，到 2024-01 / 2030-12 的边就停。
        // 切月用平滑过渡动画（0.25s），动画期间不重算——工资是本地算、切月秒出。
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    let w = abs(value.translation.width)
                    let h = abs(value.translation.height)
                    if w > 24 && w > h * 1.5 {
                        horizontalSwipeLocked = true
                    }
                }
                .onEnded { value in
                    defer { horizontalSwipeLocked = false }
                    let w = value.translation.width
                    let h = value.translation.height
                    guard abs(w) > 60, abs(w) > abs(h) * 1.5 else { return }
                    stepPayMonth(by: w < 0 ? 1 : -1)
                }
        )
        // 切到别的页面（排班/设置）时，敞着的编辑框自动收起，丢弃未保存的改动。
        .onDisappear { dismissEdit() }
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
            Text(DateUtil.yearMonthTitle(year: store.payYearMonth.year, month: store.payYearMonth.month))
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
        // 切月时把敞着的编辑框收起（那是上个月的数，别留在新月上误触）。
        dismissEdit()
        var year = store.payYearMonth.year
        var month = store.payYearMonth.month + offset
        while month < 1 { month += 12; year -= 1 }
        while month > 12 { month -= 12; year += 1 }
        // 滑页范围与排班页一致：2024-01 ~ 2030-12，到边就停。
        let idx = year * 12 + (month - 1)
        guard idx >= 2024 * 12, idx < 2031 * 12 else { return }
        // 滑动方向：左滑下个月（新内容从右边滑入）、右滑上个月（从左边滑入）。
        slideDirection = offset > 0 ? 1 : -1
        // 1.1.3：月份 + 工资内容包在同一个动画事务里（setPayMonth 同步算好当月工资），
        // 再靠 monthBreakdown 的 .id + .transition 做左右滑动；按钮切月也走这里，同样有动画。
        withAnimation(.easeInOut(duration: 0.25)) {
            store.setPayMonth(year: year, month: month)
        }
    }

    // MARK: 月度明细

    @ViewBuilder
    private var monthBreakdown: some View {
        if store.isLoadingPay && store.pay == nil {
            ProgressView("正在加载…")
                .padding()
        } else if let pay = store.pay {
            VStack(spacing: 16) {
                salarySection(pay: pay)
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

    /// 奖金区：科室绩效、绩效系数、奖金系数、加班天数四行点一下就能改当月那个数
    ///（只有老爷能改，改完存服务端、本地立刻重算）。其余行只看。行顺序跟原来一样。
    private func bonusSection(pay: PayMonth) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("奖金")
                .font(.headline)
                .padding(.bottom, 8)
            editableRow(title: "科室绩效", valueText: MoneyUtil.money(pay.deptPerf), field: .deptPerf,
                        currentValue: pay.deptPerf.map { String(format: "%.2f", $0) } ?? "4000",
                        placeholder: "科室绩效（如 3800）")
            staticRow(title: "其他奖罚", valueText: MoneyUtil.money(pay.otherReward), bold: false)
            editableRow(title: "绩效系数", valueText: MoneyUtil.number(pay.perfCoef), field: .perfCoef,
                        currentValue: pay.perfCoef.map { String(format: "%.2f", $0) } ?? "1",
                        placeholder: "绩效系数（如 1.2）")
            editableRow(title: "奖金系数", valueText: MoneyUtil.number(pay.bonusCoef), field: .bonusCoef,
                        currentValue: pay.bonusCoef.map { String(format: "%.2f", $0) } ?? "1",
                        placeholder: "奖金系数（如 1.2）")
            staticRow(title: "加班费（含三薪）", valueText: MoneyUtil.money(pay.overtimePay), bold: false)
            staticRow(title: "三薪天数", valueText: pay.tripleDays.map { String(format: "%.1f 天", $0) } ?? "—", bold: false)
            staticRow(title: "三薪金额", valueText: MoneyUtil.money(pay.triplePay), bold: false)
            editableRow(title: "加班天数", valueText: pay.overtimeDays.map { String(format: "%.1f 天", $0) } ?? "—", field: .overtimeDays,
                        currentValue: pay.overtimeDays.map { String(format: "%.1f", $0) } ?? "0",
                        placeholder: "加班天数（如 2）")
            staticRow(title: "税前奖金", valueText: MoneyUtil.money(pay.bonusTotal), bold: true)
            staticRow(title: "个税（累计预扣，税从奖金里扣）", valueText: MoneyUtil.money(pay.incomeTax), bold: false)
            staticRow(title: "实发奖金", valueText: MoneyUtil.money(pay.bonusAfterTax), bold: true)
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    /// 工资区：水电费那行点一下就能改当月那个数（只有老爷能改），其余行只看。
    /// 行顺序跟原来 paySection 那张表一样。
    private func salarySection(pay: PayMonth) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("工资")
                .font(.headline)
                .padding(.bottom, 8)
            staticRow(title: "基本工资", valueText: MoneyUtil.money(pay.baseSalary), bold: false)
            staticRow(title: "岗位", valueText: pay.position ?? "—", bold: false)
            staticRow(title: "早夜班补贴", valueText: MoneyUtil.money(pay.allowance), bold: false)
            staticRow(title: "高温费", valueText: MoneyUtil.money(pay.heat), bold: false)
            staticRow(title: "工龄津贴", valueText: MoneyUtil.money(pay.seniority), bold: false)
            staticRow(title: "应发工资", valueText: MoneyUtil.money(pay.salarySubtotal), bold: true)
            staticRow(title: "养老（8%）", valueText: MoneyUtil.money(pay.pension), bold: false)
            staticRow(title: "医疗（2%）", valueText: MoneyUtil.money(pay.medical), bold: false)
            staticRow(title: "失业（0.3%）", valueText: MoneyUtil.money(pay.unemployment), bold: false)
            staticRow(title: "五险一金合计", valueText: MoneyUtil.money(pay.contributionTotal), bold: true)
            staticRow(title: "公积金", valueText: MoneyUtil.money(pay.housingFund), bold: false)
            editableRow(title: "水电费", valueText: MoneyUtil.money(pay.utilities), field: .utilities,
                        currentValue: pay.utilities.map { String(format: "%.2f", $0) } ?? "0",
                        placeholder: "水电费（如 60）")
            staticRow(title: "实发工资", valueText: MoneyUtil.money(pay.salaryNet), bold: true)
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    /// 只看的行（标签 + 值 + 分隔线），样式跟原来 paySection 里的一致。
    private func staticRow(title: String, valueText: String, bold: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .foregroundColor(.secondary)
                Spacer()
                Text(valueText)
                    .bold(bold)
            }
            .font(.subheadline)
            .padding(.vertical, 5)
            Divider()
        }
    }

    /// 一行可改的数值：点“可改”弹出 inline 编辑框（输入框 + 保存/取消），下面再跟分隔线。
    /// 只有老爷能改；点外面或切页面自动收起（dismissEdit）。
    /// 1.1.3：只有「可改」这个小徽标是按钮（明确的编辑入口），整行不再是按钮。
    /// 之前整行都是 Button，左右滑切月时手指从行上划过、抬手还在行内，
    /// Button 就当成一次点按、把编辑框打开了。现在行本身不可点，横滑只会触发切月；
    /// 想改就点「可改」徽标（小目标，横滑起止很难同时落在它上面），误触基本杜绝。
    private func editableRow(title: String, valueText: String, field: PayRecordField, currentValue: String, placeholder: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .foregroundColor(.secondary)
                Spacer()
                Text(valueText)
                if store.isOwner {
                    Button {
                        openEdit(field, currentValue: currentValue)
                    } label: {
                        Text("可改")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.08))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.subheadline)
            .padding(.vertical, 5)
            if editingField == field {
                VStack(spacing: 8) {
                    HStack {
                        TextField(placeholder, text: $editText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .focused($editFieldFocused)
                        Button("保存") { Task { await saveEdit() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(editSaving)
                        Button("取消") { dismissEdit() }
                            .buttonStyle(.bordered)
                    }
                    if let editError {
                        Text(editError)
                            .font(.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 8)
            }
            Divider()
        }
    }

    /// 打开某行的 inline 编辑框（只有老爷能改；打开时填当前值、弹键盘）。
    private func openEdit(_ field: PayRecordField, currentValue: String) {
        guard store.isOwner else { return }
        editText = currentValue
        editError = nil
        editSaving = false
        editingField = field
        editFieldFocused = true
    }

    /// 收起编辑框（丢弃未保存的改动：输入框恢复成原来的值——下次打开时重新填当前值；同时收键盘）。
    private func dismissEdit() {
        editingField = nil
        editText = ""
        editError = nil
        editSaving = false
        editFieldFocused = false
    }

    /// 保存当前编辑框（按字段校验范围，写服务端，本地立刻重算；保存完收起）。
    private func saveEdit() async {
        guard let field = editingField else { return }
        editError = nil
        guard let value = Double(editText.trimmingCharacters(in: .whitespaces)) else {
            editError = "输个数字"
            return
        }
        let range: ClosedRange<Double>
        let hint: String
        switch field {
        case .deptPerf:
            range = 0...10000; hint = "0–10000"
        case .perfCoef, .bonusCoef:
            range = 0...3; hint = "0–3"
        case .overtimeDays:
            range = 0...31; hint = "0–31"
        case .utilities:
            range = 0...1000; hint = "0–1000"
        }
        guard range.contains(value) else {
            editError = "输个 \(hint) 之间的数"
            return
        }
        editSaving = true
        let key = String(format: "%04d-%02d", store.payYearMonth.year, store.payYearMonth.month)
        await store.updatePayMonthField(monthKey: key, field: field, value: value)
        editSaving = false
        dismissEdit()
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
