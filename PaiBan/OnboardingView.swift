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
                .font(.title2).bold()
            Text("先选一种排班方式，之后在设置 → 倒班方式设置里随时能改。")
                .foregroundColor(.secondary)
            Button {
                method = "manual"
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("手动排班").font(.headline).foregroundColor(.white)
                    Text("班次无周期规律\n灵活性强但需逐日点击")
                        .font(.subheadline).foregroundColor(.white.opacity(0.9))
                }
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                .padding(16)
                .background(Color.green.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(method == "manual" ? Color.primary : Color.clear, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
            Button {
                method = "periodic"
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("周期排班").font(.headline).foregroundColor(.white)
                    Text("班次周期固定\n一次生成多月日历")
                        .font(.subheadline).foregroundColor(.white.opacity(0.9))
                }
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                .padding(16)
                .background(Color.blue.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(method == "periodic" ? Color.primary : Color.clear, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// 第 2 步：周期 → 选倒班方式 + 班组 + 基准日；手动 → 只选班组。
    private var stepSchedule: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isManual {
                Text("你在哪个班？")
                    .font(.title2).bold()
                Text("手动排班没有周期规律。选好班组后，去排班页点某一天设当天班次。")
                    .foregroundColor(.secondary)
            } else {
                Text("选倒班方式和班组")
                    .font(.title2).bold()
                Text("四班三倒，8 小时三班。方式 A 是最标准的 8 天循环。")
                    .foregroundColor(.secondary)
                ForEach(RotationModes.fourThree) { mode in
                    Button {
                        modeId = mode.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.name)
                                    .foregroundColor(.primary)
                                Text("\(mode.cycleDays) 天一循环 · \(mode.sequence)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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

            Text("你在哪个班？")
                .font(.headline)
            Picker("班组", selection: $team) {
                ForEach(TeamInfo.allTeams, id: \.self) { t in
                    Text("\(t)班").tag(t)
                }
            }
            .pickerStyle(.segmented)

            if !isManual {
                DatePicker("基准日", selection: $baseDate, displayedComponents: .date)
                if let mode = RotationModes.mode(id: modeId) {
                    Text("\(team)班在基准日上 \(RotationModes.shiftName(for: mode.cycles[team]?.first ?? "D"))；基准日是循环第 1 天。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Text("日=日班 08–16，中=中班 16–24，早=早班 00–08，休=休息")
                .font(.caption)
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
