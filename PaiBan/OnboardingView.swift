import SwiftUI

/// 新用户引导（注册后、onboardingDone=false 时只显示一次），1.2.7.001：
/// 只问排班（排班方式 + 倒班方式/班组/基准日），工资相关的选择全部隐藏
/// （基本工资、奖金系数、社保基数、入职时间、剩余年休假、学历都不问；
/// 工资设置以后在设置页填，或管理员帮填）。
/// 第 1 步：排班方式（手动/周期，两张大卡片，图五样式）；
/// 第 2 步：周期 → 选倒班方式 + 班组 + 基准日；手动 → 只选班组。
/// 最后 PUT /me/profile 保存 rotation + team 并标记 onboardingDone=true。
struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore

    @State private var step = 0
    @State private var method: String = "periodic"   // manual / periodic
    @State private var modeId = RotationModes.defaultModeId
    @State private var team = "B"
    @State private var baseDate = DateUtil.date(from: RotationModes.commonBaseDate) ?? Date()
    @State private var errorText: String?
    @State private var isBusy = false

    private var totalSteps: Int { 2 }
    private var isManual: Bool { method == "manual" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(totalSteps))
                    // 1.2.8.002：进度条填色走自适应强调色（之前是 navyAdaptive，
                    // 深色 0.18/0.23/0.34 在黑底上太暗，几乎看不见进度）。
                    .tint(.accentColor)
                    .padding(.horizontal, AppStyle.pagePadding)
                    .padding(.top, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                        Text("第 \(step + 1) 步 / 共 \(totalSteps) 步")
                            .appFont(size: AppFont.caption)
                            .foregroundColor(.secondary)
                        stepBody
                        if let errorText {
                            Text(errorText)
                                .appFont(size: AppFont.bodySmall)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(AppStyle.pagePadding)
                }

                HStack(spacing: 12) {
                    if step > 0 {
                        Button("上一步") { step -= 1 }
                            .buttonStyle(.bordered)
                    }
                    Spacer()
                    Button(step == totalSteps - 1 ? "完成" : "下一步") {
                        if step == totalSteps - 1 {
                            Task { await finish() }
                        } else {
                            step += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
                }
                .padding(.horizontal, AppStyle.pagePadding)
                .padding(.bottom, 24)
            }
            .navigationTitle("设置你的排班")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("以后再说") { Task { await skipAll() } }
                        .disabled(isBusy)
                }
            }
        }
    }

    // MARK: 各步内容

    @ViewBuilder
    private var stepBody: some View {
        if step == 0 {
            stepMethod
        } else {
            stepSchedule
        }
    }

    /// 第 1 步：排班方式（图五样式，两张大卡片）。
    private var stepMethod: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("你的班次怎么排？")
                .appFont(size: AppFont.titleLarge, weight: 700)
            Text("先选一种排班方式，之后在设置 → 倒班方式设置里随时能改。")
                .foregroundColor(.secondary)
            Button {
                method = "manual"
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("手动排班").appFont(size: AppFont.headline, weight: 600).foregroundColor(.white)
                    Text("班次无周期规律\n灵活性强但需逐日点击")
                        .appFont(size: AppFont.bodySmall).foregroundColor(AppStyle.whiteText(opacity: 0.9))
                }
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                .padding(16)
                .background(Color.green.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(method == "manual" ? 0.12 : 0))
                )
                .shadow(color: method == "manual" ? Color.black.opacity(0.25) : .clear, radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            Button {
                method = "periodic"
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("周期排班").appFont(size: AppFont.headline, weight: 600).foregroundColor(.white)
                    Text("班次周期固定\n一次生成多月日历")
                        .appFont(size: AppFont.bodySmall).foregroundColor(AppStyle.whiteText(opacity: 0.9))
                }
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                .padding(16)
                .background(Color.blue.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(method == "periodic" ? 0.12 : 0))
                )
                .shadow(color: method == "periodic" ? Color.black.opacity(0.25) : .clear, radius: 6, y: 2)
            }
            .buttonStyle(.plain)
        }
    }

    /// 第 2 步：周期 → 选倒班方式 + 班组 + 基准日；手动 → 只选班组。
    private var stepSchedule: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isManual {
                Text("你在哪个班？")
                    .appFont(size: AppFont.titleLarge, weight: 700)
                Text("手动排班没有周期规律。选好班组后，去排班页点某一天设当天班次。")
                    .foregroundColor(.secondary)
            } else {
                Text("选倒班方式和班组")
                    .appFont(size: AppFont.titleLarge, weight: 700)
                Text("方式 A 是最标准的 8 天循环。班组数跟着方式走（五班三倒 5 个班，三班二倒 3 个班）。")
                    .foregroundColor(.secondary)
                // 1.2.7.002：全部方式按分类列出（四班三倒 5 种 + 新 15 种）；六班三倒序列未核实，继续留「即将推出」。
                // 第 32 条：行信息与设置页对齐（小时/班、周均小时、备注），不然 12 天/4 天的
                // 只看名字和循环天数不好分辨——引导里四班三倒 5 种本来就全列着，缺的是这些。
                ForEach(RotationModes.categories, id: \.title) { cat in
                    Text(cat.title)
                        .appFont(size: AppFont.bodySmall).bold()
                        .padding(.top, 4)
                    ForEach(cat.ids.compactMap { RotationModes.mode(id: $0) }) { mode in
                        Button {
                            modeId = mode.id
                            // 班组跟着方式走：新方式没有当前班就回到第一个班。
                            if let ids = RotationModes.mode(id: mode.id)?.teamIds, !ids.contains(team) {
                                team = ids.first ?? "A"
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.name)
                                        .foregroundColor(.primary)
                                    Text("\(mode.cycleDays) 天一循环 · \(mode.sequence) · \(mode.shiftHours) 小时/班 · 周均 \(mode.weeklyHours) 小时")
                                        .appFont(size: AppFont.caption)
                                        .foregroundColor(.secondary)
                                    if let note = mode.note {
                                        Text(note)
                                            .appFont(size: AppFont.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    if mode.isPayTBD {
                                        Text("工资口径待定（金额暂不算）")
                                            .appFont(size: AppFont.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                                Spacer()
                                if modeId == mode.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(modeId == mode.id ? Color.blue.opacity(0.08) : Color(.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                }
                ForEach(RotationModes.comingSoon, id: \.category) { item in
                    HStack {
                        Text(item.category)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("即将推出")
                            .appFont(size: AppFont.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray5))
                            .cornerRadius(6)
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }

                // 第 32 条：选中方式的循环示意（和设置页同一套 CyclePreviewView），
                // 选完一眼就能看到这方式每天上什么班，不用凭名字猜。
                if let mode = RotationModes.mode(id: modeId) {
                    Text("循环示意 · \(team)班 \(mode.name)")
                        .appFont(size: AppFont.bodySmall).bold()
                        .padding(.top, 4)
                    CyclePreviewView(mode: mode, team: team, baseDate: baseDate)
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                }
            }

            Text("你在哪个班？")
                .appFont(size: AppFont.headline, weight: 600)
            Picker("班组", selection: $team) {
                ForEach(RotationModes.mode(id: modeId)?.teamIds ?? TeamInfo.allTeams, id: \.self) { t in
                    Text("\(t)班").tag(t)
                }
            }
            .pickerStyle(.segmented)

            if !isManual {
                DatePicker("基准日", selection: $baseDate, displayedComponents: .date)
                if let mode = RotationModes.mode(id: modeId) {
                    Text("\(team)班在基准日上 \(RotationModes.shiftName(for: mode.cycles[team]?.first ?? "D"))；基准日是循环第 1 天。")
                        .appFont(size: AppFont.caption)
                        .foregroundColor(.secondary)
                    if mode.id == "2-a" || mode.id == "3-3-a" || mode.id == "4-6-a" {
                        Text("基准日请选周一（按下周一起算，周六日休息）。")
                            .appFont(size: AppFont.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Text("日=日班 08–16，中=中班 16–24，早=早班 00–08，休=休息")
                .appFont(size: AppFont.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: 保存

    /// 把起始班组写成第一条换班记录：没有更早记录的日期按第一条的班组算。
    /// 生效日取完成引导的当天；同一天重复写会替换，不会多出一条。
    private func seedInitialTeamHistory() async throws {
        let today = DateUtil.string(from: Date())
        _ = try await store.api.addTeamHistory(team: team, effectiveFrom: today)
        _ = try await store.refreshTeamHistory()
    }

    private func finish() async {
        errorText = nil
        isBusy = true
        defer { isBusy = false }
        do {
            var rotation = RotationSetting(
                modeId: isManual ? RotationModes.manualId : modeId,
                team: team,
                baseDate: DateUtil.string(from: baseDate)
            )
            rotation.teamNames = store.rotation.teamNames
            try await store.saveProfile(team: team, onboardingDone: true, rotation: rotation)
            try await seedInitialTeamHistory()
            await store.refreshMonth()
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    /// “以后再说”：只标记引导完成，班组和倒班方式全用默认值（周期 A 方式、B 班）。
    private func skipAll() async {
        errorText = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await store.saveProfile(team: team, paySettings: nil, onboardingDone: true)
            try await seedInitialTeamHistory()
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

/// 工资引导（第 30 条，2026-11-26）：管理端给用户开了工资权限后，下次进软件弹窗走一遍。
/// 弹窗（sheet）3 步，不是全屏页；字段与校验和设置页「工资设置」同一套（养老月扣反推基数、
/// 岗位四档、入职年月、剩余年休假 0–365），只取新用户引导里藏起来的那 6 项核心设定。
/// 保存走 store.saveProfile(paySettings:)（和设置页同一条路，服务端合并、不洗掉其他设定）。
/// 「以后再说」可跳过，但不记完成——下次进软件还会再弹，直到走完为止（见 Store.skipPayGuide）。
/// 完成时记完成（Store.completePayGuide），不再弹。
struct PayGuideView: View {
    @EnvironmentObject private var store: AppStore
    /// 引导现在从工资页的空状态按钮打开（2026-11-27 10:28，取代第 30 条自动弹窗）：
    /// 完成/跳过时自己关掉这页（以前是 ContentView 的 needsPayGuide 绑定在关）。
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var baseSalaryText = ""
    @State private var bonusCoefText = ""
    @State private var pensionText = ""
    @State private var position = "员工"
    @State private var hireYear = 2018
    @State private var hireMonth = 10
    @State private var annualLeaveText = "5"
    @State private var errorText: String?
    @State private var isBusy = false

    private var totalSteps: Int { 3 }
    private let positions = ["员工", "现场组长", "自控组长", "班长"]

    /// 养老月扣反推缴费基数：基数 = 养老月扣 ÷ 0.08（和设置页同一公式，保留两位小数）。
    private var derivedBase: Double? {
        guard let pension = Double(pensionText.trimmingCharacters(in: .whitespaces)), pension > 0 else { return nil }
        return PayCalc.round2(pension / 0.08)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(totalSteps))
                    .tint(.accentColor)
                    .padding(.horizontal, AppStyle.pagePadding)
                    .padding(.top, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                        Text("第 \(step + 1) 步 / 共 \(totalSteps) 步")
                            .appFont(size: AppFont.caption)
                            .foregroundColor(.secondary)
                        stepBody
                        if let errorText {
                            Text(errorText)
                                .appFont(size: AppFont.bodySmall)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(AppStyle.pagePadding)
                }

                HStack(spacing: 12) {
                    if step > 0 {
                        Button("上一步") { step -= 1 }
                            .buttonStyle(.bordered)
                    }
                    Spacer()
                    Button(step == totalSteps - 1 ? "完成" : "下一步") {
                        if step == totalSteps - 1 {
                            Task { await finish() }
                        } else {
                            step += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
                }
                .padding(.horizontal, AppStyle.pagePadding)
                .padding(.bottom, 24)
            }
            .navigationTitle("设置你的工资")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("以后再说") {
                        store.skipPayGuide()
                        dismiss()
                    }
                    .disabled(isBusy)
                }
            }
            .interactiveDismissDisabled(true)
        }
        .onAppear(perform: fillFields)
    }

    // MARK: 各步内容

    @ViewBuilder
    private var stepBody: some View {
        if step == 0 {
            stepSalary
        } else if step == 1 {
            stepContribution
        } else {
            stepHire
        }
    }

    /// 第 1 步：基本工资 + 奖金系数（必填，工资页按这两个数算）。
    private var stepSalary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("先填工资底数")
                .appFont(size: AppFont.titleLarge, weight: 700)
            Text("基本工资和奖金系数决定了工资和奖金的底数，填好后工资页就能按你的数算。")
                .foregroundColor(.secondary)
            HStack {
                Text("基本工资")
                Spacer()
                TextField("2420", text: $baseSalaryText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
            }
            HStack {
                Text("奖金系数")
                Spacer()
                TextField("1.0", text: $bonusCoefText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
            }
            Text("不知道填多少就问管理员，或先按默认的 2420 / 1.0，之后在设置 → 工资设置里改。")
                .appFont(size: AppFont.caption)
                .foregroundColor(.secondary)
        }
    }

    /// 第 2 步：养老月扣（反推缴费基数）+ 岗位。
    /// 养老月扣看工资条上扣的那笔养老保险；基数 = 月扣 ÷ 0.08，当场验算医疗 × 2%、失业 × 0.3%。
    private var stepContribution: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("社保缴费基数和岗位")
                .appFont(size: AppFont.titleLarge, weight: 700)
            Text("养老月扣填工资条上扣的养老保险那笔，基数会自动反推出来。")
                .foregroundColor(.secondary)
            HStack {
                Text("养老月扣")
                Spacer()
                TextField("475.04", text: $pensionText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
            }
            if let base = derivedBase {
                HStack {
                    Text("社保缴费基数")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(PayCalc.jsNum(base))（医疗 \(MoneyUtil.money(PayCalc.round2(base * 0.02))) · 失业 \(MoneyUtil.money(PayCalc.round2(base * 0.003)))）")
                        .foregroundColor(.secondary)
                }
                .appFont(size: AppFont.caption)
            } else {
                Text("养老月扣空着也行，基数先按默认的 5938，之后在设置 → 工资设置里补。")
                    .appFont(size: AppFont.caption)
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("岗位")
                Spacer()
                Picker("岗位", selection: $position) {
                    ForEach(positions, id: \.self) { p in
                        Text(p).tag(p)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    /// 第 3 步：入职时间 + 剩余年休假天数。
    private var stepHire: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("入职时间和年休假")
                .appFont(size: AppFont.titleLarge, weight: 700)
            Text("入职时间只到月份，用来算工龄津贴；剩余年休假是今年还没休的年假天数。")
                .foregroundColor(.secondary)
            HStack {
                Text("入职时间")
                Spacer()
                // 38 条：同设置页——这行太挤，年份的值会被压折成两行；藏掉和「年」/「月」
                // 重复的「年份」/「月份」标签、只留值，再加 fixedSize，横着一行显示。
                Picker("年份", selection: $hireYear) {
                    ForEach(1990...Calendar.current.component(.year, from: Date()), id: \.self) { y in
                        // 36 条：同设置页——Text("\(y)") 是 LocalizedStringKey，2018 会变 2,018；verbatim 拼纯数字。
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
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("剩余年休假天数")
                    Text("没休完的累计到明年，不清零；休了年假会自动扣")
                        .appFont(size: AppFont.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                TextField("5", text: $annualLeaveText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
            }
            Text("填完点「完成」，工资页就按这些数算。以后在设置 → 工资设置里随时能改。")
                .appFont(size: AppFont.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: 预填与保存

    /// 预填：用户已有的设定（管理员可能先帮填了一部分）；没有就按设置页同一套默认值。
    private func fillFields() {
        let settings = store.user?.paySettings
        baseSalaryText = settings?.baseSalary.map { moneyText($0) } ?? "2420"
        bonusCoefText = settings?.bonusCoef.map { String(format: "%.1f", $0) } ?? "1.0"
        let base = settings?.contributionBase ?? 5938
        pensionText = moneyText(PayCalc.round2(base * 0.08))
        position = settings?.position ?? "员工"
        hireYear = settings?.hireYear ?? 2018
        hireMonth = settings?.hireMonth ?? 10
        annualLeaveText = settings?.annualLeaveRemaining.map { String($0) } ?? "5"
    }

    private func moneyText(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(value)
    }

    /// 完成：校验 → 保存 6 项设定 → 记引导完成、关弹窗。
    private func finish() async {
        errorText = nil
        isBusy = true
        defer { isBusy = false }
        guard let baseSalary = Double(baseSalaryText.trimmingCharacters(in: .whitespaces)), baseSalary > 0 else {
            errorText = "基本工资要填一个大于 0 的数"
            return
        }
        guard let bonusCoef = Double(bonusCoefText.trimmingCharacters(in: .whitespaces)), bonusCoef > 0 else {
            errorText = "奖金系数要填一个大于 0 的数"
            return
        }
        let leave = Int(annualLeaveText.trimmingCharacters(in: .whitespaces)) ?? -1
        guard leave >= 0, leave <= 365 else {
            errorText = "剩余年休假天数要在 0–365 之间"
            return
        }
        var settings: [String: Any] = [:]
        settings["baseSalary"] = baseSalary
        settings["bonusCoef"] = bonusCoef
        if let base = derivedBase { settings["contributionBase"] = base }
        settings["position"] = position
        settings["hireYear"] = hireYear
        settings["hireMonth"] = hireMonth
        settings["annualLeaveRemaining"] = leave
        do {
            try await store.saveProfile(paySettings: settings)
            store.completePayGuide()
            dismiss()
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

/// 公积金弹窗（第 47 条，1.3.0.001）：公积金没填时，更新后首次打开 App 弹一次窗让用户填。
/// 框里留空（不预填算出来的数），用户照工资条上的实际月扣金额填、保存；能关掉，
/// 没填的下次打开再弹，直到填了为止。正式版出来时没填的还会再弹一次——开关就是
/// 「公积金为空就弹」（见 Store.checkHousingFundPrompt），不用另写版本逻辑。
/// 保存走 store.saveProfile(paySettings:)（和设置页同一条路，服务端合并、不洗掉其他设定）。
/// 「以后再说」只关掉这次弹窗，不记完成——下次进软件还会再弹，直到填了为止。
struct HousingFundPromptView: View {
    @EnvironmentObject private var store: AppStore

    @State private var housingFundText = ""
    @State private var errorText: String?
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                Text("公积金按工资条上的实际月扣金额填。以前按缴费基数×6.8% 反推，算出来的和工资条对不上，所以现在直接填；不填按 0 算（不扣公积金）。")
                    .appFont(size: AppFont.bodySmall)
                    .foregroundColor(.secondary)
                HStack {
                    Text("公积金")
                    Spacer()
                    TextField("", text: $housingFundText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 140)
                }
                .font(.body)
                if let errorText {
                    Text(errorText)
                        .appFont(size: AppFont.bodySmall)
                        .foregroundColor(.red)
                }
                Spacer()
                Button {
                    Task { await save() }
                } label: {
                    if isBusy {
                        ProgressView()
                    } else {
                        Text("保存")
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(isBusy)
            }
            .padding(AppStyle.pagePadding)
            .navigationTitle("填一下公积金")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("以后再说") { store.needsHousingFundPrompt = false }
                        .disabled(isBusy)
                }
            }
        }
    }

    /// 保存：0–10000；空着不保存——提示用户填了再保存，不填就点右上角「以后再说」。
    private func save() async {
        errorText = nil
        let trimmed = housingFundText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            errorText = "还没填数：填了再保存，不填就点右上角「以后再说」"
            return
        }
        guard let value = Double(trimmed), value >= 0, value <= 10000 else {
            errorText = "公积金要在 0–10000 之间"
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await store.saveProfile(paySettings: ["housingFund": value])
            await store.refreshPay()
            store.needsHousingFundPrompt = false
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
