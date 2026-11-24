import SwiftUI

/// 预估工资页：月份步进（1.2.6 冷启动回当天：默认当月），只按月看（全年视图已删）。
/// 数字在手机本地算（服务端只给排班与工资配置原始数据），切月秒出。
/// 1.1.4：切月改成原生 TabView 分页滑（和排班页一样，跟着手指走、左右月预渲染）。
/// 原来是自定义 DragGesture（minimumDistance 12）+ onEnded 里才调 stepPayMonth，
/// 手指拖动时内容完全不动、松手后才用 0.25s 动画切月——这就是「不跟手」。
/// 现在 TabView 自己管滑动，内容跟着手指走；每页是自己的 ScrollView（竖滚），
/// 横滑归 TabView、竖滚归页内 ScrollView，两边不抢手势。
struct PayView: View {
    @EnvironmentObject private var store: AppStore

    /// 单月可改的 inline 编辑框：一次只改一行（科室绩效 / 绩效系数 / 奖金系数 / 加班天数 / 水电费），
    /// 样式与收起规则五种字段完全一致。点外面或切页面就收起，丢弃未保存的改动。
    @State private var editingField: PayRecordField? = nil
    @State private var editText = ""
    @State private var editSaving = false
    @State private var editError: String?
    @FocusState private var editFieldFocused: Bool
    /// 滑页的页码 = 月份绝对序号（年*12 + 月-1），与排班页同一套。
    /// 1.2.6 冷启动回当天：默认当月。
    @State private var pageIndex: Int = PayView.monthIndex(year: DateUtil.yearMonth(of: Date()).year, month: DateUtil.yearMonth(of: Date()).month)
    /// 滑页范围：一次生成 12 个月，当前月居中（前后各 5–6 个月），和排班页对齐。
    @State private var windowStartIndex: Int = {
        let now = DateUtil.yearMonth(of: Date())
        return PayView.monthIndex(year: now.year, month: now.month) - 5
    }()
    private var pageRange: Range<Int> { windowStartIndex..<(windowStartIndex + 12) }

    static func monthIndex(year: Int, month: Int) -> Int { year * 12 + (month - 1) }
    private func yearMonth(from index: Int) -> (year: Int, month: Int) { (index / 12, index % 12 + 1) }

    var body: some View {
        VStack(spacing: 16) {
            headerCard
            monthStepper
            // 1.1.4：原生 TabView 分页（每页一个 ScrollView 竖滚）。
            // 顶栏和月份步进固定在上面不滚动，工资明细在页内上下滚、左右滑切月；
            // TabView 只预渲染当前页与相邻页，切月不整页重算（工资走 payFor 缓存）。
            TabView(selection: $pageIndex) {
                ForEach(pageRange, id: \.self) { idx in
                    let ym = yearMonth(from: idx)
                    ScrollView {
                        VStack(spacing: 16) {
                            monthBreakdown(year: ym.year, month: ym.month)
                            noteCard
                        }
                        .padding(.bottom, 24)
                        // 点编辑框以外的地方就收起（丢弃未保存的改动）。Tap 手势只认轻点，
                        // 拖动（滚动/横滑）不会触发，不跟左右滑切月、上下滚动冲突。
                        .onTapGesture {
                            if editingField != nil { dismissEdit() }
                        }
                    }
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Color(.systemGroupedBackground))
        // 滑到哪页，Store 就跟到哪月（setPayMonth 同步算好当月工资、写进缓存）；
        // 切月时把敞着的编辑框收起（那是上个月的数，别留在新月上误触）。
        .onChange(of: pageIndex) { newIndex in
            let ym = yearMonth(from: newIndex)
            dismissEdit()
            store.setPayMonth(year: ym.year, month: ym.month)
        }
        // 切到别的页面（排班/设置）时，敞着的编辑框自动收起，丢弃未保存的改动。
        .onDisappear { dismissEdit() }
        .task {
            // 1.2.6 冷启动回当天：进页先对齐到今天所在的月（不再跟 Store 恢复的月份走），
            // 窗口以当月为中心重定。只在视图第一次创建时跑，从后台切回来不重跑、不强制回当月。
            let now = DateUtil.yearMonth(of: Date())
            windowStartIndex = Self.monthIndex(year: now.year, month: now.month) - 5
            pageIndex = Self.monthIndex(year: now.year, month: now.month)
            store.setPayMonth(year: now.year, month: now.month)
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
        .background(AppStyle.navy)
        .cornerRadius(16)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// 月份步进：标题直接取当前页（跟着滑页走，不用等网络）；左右箭头改页码，
    /// onChange 里 setPayMonth，同样有滑动动画。滑页范围与排班页一致（12 页窗口，到边就停）。
    private var monthStepper: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    pageIndex = max(pageRange.lowerBound, pageIndex - 1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
            }
            Spacer()
            Text(DateUtil.yearMonthTitle(year: yearMonth(from: pageIndex).year, month: yearMonth(from: pageIndex).month))
                .font(.title3).bold()
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    pageIndex = min(pageRange.upperBound - 1, pageIndex + 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: 月度明细

    /// 某月的工资明细：工资取 store.payFor（带 payCache 备忘，同一月只算一次），
    /// 相邻月预渲染时直接读缓存、不现算、不发网络；输入没到齐算不出时先显示加载，
    /// refreshPay 把输入补齐后重画。只看当前页这一份，不用等整页刷新。
    @ViewBuilder
    private func monthBreakdown(year: Int, month: Int) -> some View {
        if let pay = store.payFor(year: year, month: month) {
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
                    .padding(AppStyle.cardPadding)
                    .background(Color(.systemBackground))
                    .cornerRadius(AppStyle.cardRadius)
                    .padding(.horizontal, 16)
                }
            }
        } else if store.isLoadingPay {
            ProgressView("正在加载…")
                .padding()
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
        .padding(AppStyle.cardPadding)
        .background(Color(.systemBackground))
        .cornerRadius(AppStyle.cardRadius)
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
            staticRow(title: "缺员补贴", valueText: MoneyUtil.money(pay.shortageSubsidy), bold: false)
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
        .padding(AppStyle.cardPadding)
        .background(Color(.systemBackground))
        .cornerRadius(AppStyle.cardRadius)
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
            staticRow(title: "学历补贴", valueText: MoneyUtil.money(pay.educationSubsidy), bold: false)
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
        .padding(AppStyle.cardPadding)
        .background(Color(.systemBackground))
        .cornerRadius(AppStyle.cardRadius)
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
    /// 1.1.4：TabView 滑页时手指从行上划过也不会再打开编辑框（行本身不是按钮，
    /// TabView 的横滑手势优先），这条保留、继续有效。
    private func editableRow(title: String, valueText: String, field: PayRecordField, currentValue: String, placeholder: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .foregroundColor(.secondary)
                Spacer()
                Text(valueText)
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

    /// 打开某行的 inline 编辑框（1.2.7 起每人改自己的当月数，不再只对老爷开放；打开时填当前值、弹键盘）。
    private func openEdit(_ field: PayRecordField, currentValue: String) {
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
