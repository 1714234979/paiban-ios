import SwiftUI

/// 新用户引导（注册后、onboardingDone=false 时只显示一次）：
/// (1) 哪个班组 (2) 基本工资 (3) 奖金系数 (4) 养老月扣 → 系统反推社保缴费基数
/// (5) 学历 (6) 缺员补贴。每步都可跳过（用默认值），最后 PUT /me/profile 保存并标记 onboardingDone=true。
struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore

    @State private var step = 0
    @State private var team = "B"
    @State private var baseSalaryText = "2420"
    @State private var bonusCoef = 1.0
    @State private var pensionText = "475.04"
    @State private var education = "其他"
    @State private var hasShortage = false
    @State private var shortageAmountText = ""
    @State private var shortageStartDate = Date()
    @State private var shortageEndDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var errorText: String?
    @State private var isBusy = false

    /// 养老月扣反推缴费基数：基数 = 养老月扣 ÷ 0.08（保留两位小数）。
    /// 医疗 = 基数 × 2%、失业 = 基数 × 0.3%，当场算出来对照工资条。
    private var derivedBase: Double? {
        guard let pension = Double(pensionText.trimmingCharacters(in: .whitespaces)), pension > 0 else { return nil }
        return PayCalc.round2(pension / 0.08)
    }

    private let totalSteps = 6

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(totalSteps))
                    .tint(AppStyle.navy)
                    .padding(.horizontal, AppStyle.pagePadding)
                    .padding(.top, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                        Text("第 \(step + 1) 步 / 共 \(totalSteps) 步")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        stepBody
                        if let errorText {
                            Text(errorText)
                                .font(.subheadline)
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
                    Button("跳过这步") { nextStep() }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button(step == totalSteps - 1 ? "完成" : "下一步") {
                        if step == totalSteps - 1 {
                            Task { await finish() }
                        } else {
                            nextStep()
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

    private func nextStep() {
        if step < totalSteps - 1 { step += 1 }
    }

    // MARK: 各步内容

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case 0:
            stepTeam
        case 1:
            stepBaseSalary
        case 2:
            stepBonusCoef
        case 3:
            stepContributionBase
        case 4:
            stepEducation
        default:
            stepShortage
        }
    }

    private var stepTeam: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("你在哪个班？")
                .font(.title2).bold()
            Text("603车间四个班，都是 8 天一轮倒班。")
                .foregroundColor(.secondary)
            Picker("班组", selection: $team) {
                ForEach(TeamInfo.allTeams, id: \.self) { t in
                    Text("\(t)班").tag(t)
                }
            }
            .pickerStyle(.segmented)
            ForEach(TeamInfo.allTeams, id: \.self) { t in
                HStack {
                    Text("\(t)班")
                        .bold()
                        .frame(width: 36, alignment: .leading)
                    Text(TeamInfo.cycleText(team: t))
                        .font(.subheadline)
                        .foregroundColor(t == team ? .primary : .secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(t == team ? Color.blue.opacity(0.08) : Color(.secondarySystemBackground))
                .cornerRadius(10)
                .onTapGesture { team = t }
            }
            Text("日=日班 08–16，中=中班 16–24，早=早班 00–08，休=休息")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var stepBaseSalary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("基本工资")
                .font(.title2).bold()
            Text("每月的基本工资（元），以后可以在设置里改。")
                .foregroundColor(.secondary)
            TextField("基本工资", text: $baseSalaryText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
            Text("默认 2420 元，和车间现在的一样。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var stepBonusCoef: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("奖金系数")
                .font(.title2).bold()
            Text("奖金 =（科室绩效 + 其他奖罚）× 绩效系数 × 奖金系数 + 加班费。")
                .foregroundColor(.secondary)
            HStack {
                Text(String(format: "%.1f", bonusCoef))
                    .font(.largeTitle).bold()
                    .frame(width: 90)
                Stepper("", value: $bonusCoef, in: 1.0...2.0, step: 0.1)
                    .labelsHidden()
            }
            Slider(value: $bonusCoef, in: 1.0...2.0, step: 0.1)
            Text("范围 1.0–2.0，保留一位小数；默认 1.0。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var stepContributionBase: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("养老月扣")
                .font(.title2).bold()
            Text("直接输工资条上的养老月扣（元/月），系统自动反推社保缴费基数。")
                .foregroundColor(.secondary)
            TextField("养老月扣", text: $pensionText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
            if let base = derivedBase {
                VStack(alignment: .leading, spacing: 6) {
                    Text("算出来的数，对照工资条：")
                        .bold()
                    Text("社保缴费基数 \(PayCalc.jsNum(base)) 元/月")
                    Text("医疗 \(MoneyUtil.money(PayCalc.round2(base * 0.02)))（基数 × 2%）")
                    Text("失业 \(MoneyUtil.money(PayCalc.round2(base * 0.003)))（基数 × 0.3%）")
                    Text("三项都和工资条对上才算准。")
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.10))
                .cornerRadius(12)
            } else {
                Text("输一个大于 0 的数，比如 475.04。")
                    .font(.subheadline)
                    .foregroundColor(.red)
            }
            Text("不填就按默认 5938（养老 475.04、医疗 118.76、失业 17.81）。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var stepEducation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("你的学历？")
                .font(.title2).bold()
            Text("学历补贴每月发进工资：专科 50 元，本科 100 元，其他 0 元。")
                .foregroundColor(.secondary)
            Picker("学历", selection: $education) {
                Text("专科").tag("专科")
                Text("本科").tag("本科")
                Text("其他").tag("其他")
            }
            .pickerStyle(.segmented)
            Text("选错了以后可以在设置 → 工资设置里改。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var stepShortage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("有没有缺员补贴？")
                .font(.title2).bold()
            Text("缺员补贴按月发进奖金：期限内每月计入，期限到了就不计了。")
                .foregroundColor(.secondary)
            Picker("缺员补贴", selection: $hasShortage) {
                Text("没有").tag(false)
                Text("有").tag(true)
            }
            .pickerStyle(.segmented)
            if hasShortage {
                TextField("每月金额（元）", text: $shortageAmountText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                DatePicker("开始日期", selection: $shortageStartDate, displayedComponents: .date)
                DatePicker("结束日期", selection: $shortageEndDate, displayedComponents: .date)
                Text("期限到了自动停发，不用再来改。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: 保存

    private func parsedDouble(_ text: String, fallback: Double) -> Double {
        Double(text.trimmingCharacters(in: .whitespaces)) ?? fallback
    }

    /// 把起始班组写成第一条换班记录：没有更早记录的日期按第一条的班组算。
    /// 生效日取完成引导的当天；同一天重复写会替换，不会多出一条。
    private func seedInitialTeamHistory() async throws {
        let today = DateUtil.string(from: Date())
        _ = try await store.api.addTeamHistory(team: team, effectiveFrom: today)
        _ = try await store.refreshTeamHistory()
    }

    private func finish() async {
        errorText = nil
        if hasShortage && shortageEndDate < shortageStartDate {
            errorText = "缺员补贴结束日期不能早于开始日期"
            return
        }
        isBusy = true
        defer { isBusy = false }
        var settings: [String: Any] = [
            "baseSalary": parsedDouble(baseSalaryText, fallback: 2420),
            "bonusCoef": (bonusCoef * 10).rounded() / 10,
            "contributionBase": derivedBase ?? 5938,
            "education": education,
        ]
        if hasShortage {
            settings["shortageSubsidy"] = [
                "amount": parsedDouble(shortageAmountText, fallback: 0),
                "startDate": DateUtil.string(from: shortageStartDate),
                "endDate": DateUtil.string(from: shortageEndDate),
            ]
        } else {
            settings["shortageSubsidy"] = ["amount": 0]
        }
        do {
            try await store.saveProfile(team: team, paySettings: settings, onboardingDone: true)
            try await seedInitialTeamHistory()
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    /// “以后再说”：只标记引导完成，班组和工资全用默认值。
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
