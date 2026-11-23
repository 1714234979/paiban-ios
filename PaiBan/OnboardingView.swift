import SwiftUI

/// 新用户引导（注册后、onboardingDone=false 时只显示一次）：
/// (1) 哪个班组 (2) 基本工资 (3) 奖金系数 (4) 社保缴费基数。
/// 每步都可跳过（用默认值），最后 PUT /me/profile 保存并标记 onboardingDone=true。
struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore

    @State private var step = 0
    @State private var team = "B"
    @State private var baseSalaryText = "2420"
    @State private var bonusCoef = 1.0
    @State private var contributionBaseText = "5938"
    @State private var errorText: String?
    @State private var isBusy = false

    private let totalSteps = 4

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(totalSteps))
                    .tint(Color(red: 0.11, green: 0.15, blue: 0.23))
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
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
                    .padding(20)
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
                .padding(.horizontal, 20)
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
        default:
            stepContributionBase
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
            Text("社保缴费基数")
                .font(.title2).bold()
            Text("用来算养老、医疗、失业和公积金的基数（元/月）。")
                .foregroundColor(.secondary)
            TextField("缴费基数", text: $contributionBaseText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
            VStack(alignment: .leading, spacing: 8) {
                Text("不知道基数？看工资条：")
                    .bold()
                Text("养老月扣 ÷ 0.08 = 基数，再验算医疗 = 基数 × 2%、失业 = 基数 × 0.3%，都对上才算准；示例数字不能直接抄。")
            }
            .font(.subheadline)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.12))
            .cornerRadius(12)
            Text("默认 5938（养老 475.04、医疗 118.76、失业 17.81）。")
                .font(.caption)
                .foregroundColor(.secondary)
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
        isBusy = true
        defer { isBusy = false }
        let settings: [String: Any] = [
            "baseSalary": parsedDouble(baseSalaryText, fallback: 2420),
            "bonusCoef": (bonusCoef * 10).rounded() / 10,
            "contributionBase": parsedDouble(contributionBaseText, fallback: 5938),
        ]
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
