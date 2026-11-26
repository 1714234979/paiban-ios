import SwiftUI

/// 倒班方式设置（1.2.7.001，第 23 条）：先选排班方式（手动/周期），
/// 周期再进分类（四班三倒 5 种方式，每种带循环示意）；只有选中了倒班方式，
/// 才显示选择班次（选哪个班 + 基准日）；班组名可改。
/// 样式：精美、简约；循环示意图二风格但紧凑（横排卡片 + 箭头 +「第 N+1 天回到第 1 天」）。
struct RotationSettingsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var modeId: String
    @State private var team: String
    @State private var baseDate: Date
    @State private var teamNames: [String]
    @State private var selectedModeId: String?
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var doneMessage: String?
    @State private var showSwitchConfirm = false

    init() {
        // 初始值从 store 的 rotation 取（视图创建时 store 已有数据；进页后 task 里再同步一次）。
        _modeId = State(initialValue: "4-3-b")
        _team = State(initialValue: "B")
        _baseDate = State(initialValue: DateUtil.date(from: RotationModes.commonBaseDate) ?? Date())
        _teamNames = State(initialValue: ["A", "B", "C", "D"])
    }

    private var isManual: Bool { modeId == RotationModes.manualId }
    private var selectedMode: RotationMode? { RotationModes.mode(id: selectedModeId ?? modeId) }

    var body: some View {
        Form {
            Section {
                Text("先选一种排班方式，再选班次。切方式后日历按新方式算，现有调班/请假记录只重算基础轮次、不删记录。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // 排班方式：手动 / 周期两张大卡片（图五样式，收紧）。
            Section("排班方式") {
                HStack(spacing: 12) {
                    methodCard(
                        title: "手动排班", subtitle: "班次无周期规律\n灵活性强但需逐日点击",
                        color: .green, selected: isManual
                    ) { modeId = RotationModes.manualId }
                    methodCard(
                        title: "周期排班", subtitle: "班次周期固定\n一次生成多月日历",
                        color: .blue, selected: !isManual
                    ) {
                        // 切回周期：默认方式 A（新用户推荐）；已有方式就用已有的。
                        if isManual { modeId = RotationModes.defaultModeId }
                        selectedModeId = modeId == RotationModes.manualId ? RotationModes.defaultModeId : modeId
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            if isManual {
                Section {
                    Text("手动排班：班次没有周期规律。去手动排班页逐日点班次；没设的当天算休息。调班就是改某天的班。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    NavigationLink {
                        ManualScheduleView()
                    } label: {
                        HStack {
                            Text("打开手动排班")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                // 周期：按分类列出全部方式（1.2.7.002：20 种）。
                ForEach(RotationModes.categories, id: \.title) { cat in
                    Section(cat.title) {
                        ForEach(RotationModes.allModes.filter { cat.ids.contains($0.id) }) { mode in
                            Button {
                                selectMode(mode)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.name)
                                            .foregroundColor(.primary)
                                        Text("\(mode.cycleDays) 天一循环 · \(mode.sequence) · \(mode.shiftHours) 小时/班 · 周均 \(mode.weeklyHours) 小时")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if let note = mode.note {
                                            Text(note)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        if mode.isPayTBD {
                                            Text("工资口径待定：工资页只显示班次统计，金额暂不算")
                                                .font(.caption)
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
                        }
                    }
                }

                // 其他分类：列出来、标即将推出，不可选。
                Section("更多方式（即将推出）") {
                    ForEach(RotationModes.comingSoon, id: \.category) { item in
                        HStack {
                            Text(item.category)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(item.note)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("即将推出")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray5))
                                .clipShape(Capsule())
                        }
                    }
                }

                // 循环示意（选中方式后）：紧凑横排卡片 + 箭头 + 回到第 1 天。
                if let mode = selectedMode {
                    Section("循环示意 · \(store.rotation.teamName(for: team))\(mode.name)") {
                        CyclePreviewView(mode: mode, team: team, baseDate: baseDate)
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    }
                }

                // 只有选中了倒班方式，才显示选择班次。
                Section("选择班次") {
                    Picker("班组", selection: $team) {
                        ForEach(selectedMode?.teamIds ?? TeamInfo.allTeams, id: \.self) { t in
                            Text("\(teamName(for: t))班").tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("基准日", selection: $baseDate, displayedComponents: .date)
                    Text("基准日是循环第 1 天。\(team)班在基准日上 \(selectedMode?.cycles[team]?.first ?? "日班")。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let mode = selectedMode, mode.id == "2-a" || mode.id == "3-3-a" || mode.id == "4-6-a" {
                        Text("基准日请选周一（按下周一起算，周六日休息）。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // 班组名（第 26 条）：班组数跟着方式走，各一行可改。
            Section("班组名") {
                ForEach(selectedMode?.teamIds ?? TeamInfo.allTeams, id: \.self) { teamId in
                    HStack {
                        Text("\(teamId)班")
                            .foregroundColor(.secondary)
                        TextField("班组名", text: Binding(
                            get: { teamName(for: teamId) },
                            set: { setTeamName($0, for: teamId) }
                        ))
                        .multilineTextAlignment(.trailing)
                    }
                }
                Text("班组名改了，日历、调班、工资页、共享班表里显示的班组名跟着变；已有的调班/请假记录按班组 ID 关联，不因改名丢。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Button {
                    if modeId != store.rotation.modeId && !store.rotation.isManual {
                        showSwitchConfirm = true
                    } else {
                        Task { await save() }
                    }
                } label: {
                    if isBusy {
                        ProgressView()
                    } else {
                        Text("保存倒班方式")
                    }
                }
                .disabled(isBusy)
            }

            if let errorText {
                Section {
                    Text(errorText).foregroundColor(.red)
                }
            }
            if let doneMessage {
                Section {
                    Text(doneMessage).foregroundColor(.green)
                }
            }
        }
        .navigationTitle("倒班方式设置")
        .navigationBarTitleDisplayMode(.inline)
        .task { syncFromStore() }
        .alert("切换倒班方式", isPresented: $showSwitchConfirm) {
            Button("取消", role: .cancel) {}
            Button("切换", role: .destructive) {
                Task { await save() }
            }
        } message: {
            Text("切换后现有调班/请假记录按新循环重算（只重算基础轮次，不删记录）。若某条记录在新循环下冲突，请自己去调班里处理。")
        }
    }

    /// 选一种方式：班组夹到该方式的班组里、班组名按新班组数补齐/截断。
    private func selectMode(_ mode: RotationMode) {
        selectedModeId = mode.id
        modeId = mode.id
        if !mode.teamIds.contains(team) { team = mode.teamIds.first ?? "A" }
        teamNames = mode.teamIds.enumerated().map { idx, tid in
            if idx < teamNames.count, !teamNames[idx].isEmpty { return teamNames[idx] }
            return tid
        }
    }

    private func teamName(for teamId: String) -> String {
        let ids = selectedMode?.teamIds ?? TeamInfo.allTeams
        guard let idx = ids.firstIndex(of: teamId), idx < teamNames.count,
              !teamNames[idx].isEmpty else { return teamId }
        return teamNames[idx]
    }

    private func setTeamName(_ name: String, for teamId: String) {
        let ids = selectedMode?.teamIds ?? TeamInfo.allTeams
        guard let idx = ids.firstIndex(of: teamId) else { return }
        while teamNames.count <= idx { teamNames.append("") }
        teamNames[idx] = name
    }

    private func syncFromStore() {
        let r = store.rotation
        modeId = r.modeId
        team = r.team
        baseDate = DateUtil.date(from: r.baseDate) ?? Date()
        teamNames = r.teamNames
        selectedModeId = r.isManual ? nil : r.modeId
    }

    private func save() async {
        errorText = nil
        doneMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            var r = store.rotation
            r.modeId = modeId
            // 班组夹到该方式的班组里；班组名按该方式班组数补齐/截断。
            if let mode = selectedMode {
                if !mode.teamIds.contains(team) { team = mode.teamIds.first ?? "A" }
                r.teamNames = mode.teamIds.enumerated().map { idx, tid in
                    if idx < teamNames.count, !teamNames[idx].isEmpty { return teamNames[idx] }
                    return tid
                }
            } else {
                r.teamNames = teamNames
            }
            r.team = team
            r.baseDate = DateUtil.string(from: baseDate)
            // 班组变了：记一条换班记录（生效日 = 基准日），历史保持一致。
            if team != store.myTeam {
                _ = try await store.api.addTeamHistory(team: team, effectiveFrom: r.baseDate)
            }
            try await store.saveRotation(r)
            doneMessage = isManual ? "已保存：手动排班，去排班页逐日设班次。" : "已保存：\(selectedMode?.name ?? "") · \(r.teamName(for: team))班，基准日 \(r.baseDate)。"
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func methodCard(title: String, subtitle: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppStyle.whiteText(opacity: 0.9))
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .padding(12)
            .background(color.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Color.primary : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

/// 循环示意（图二风格，紧凑）：横排卡片，每格一天 + 班次色块，箭头串联，
/// 底下「第 N+1 天回到第 1 天」。12 天分两行（横向滚动），8 天 / 4 天一行。
/// 循环示意（横排卡片 + 箭头 +「第 N+1 天回到第 1 天」）：设置页与新用户引导共用
///（第 32 条：引导里也要能看到每种方式的循环，不然 12 天/4 天的不好分辨）。
struct CyclePreviewView: View {
    var mode: RotationMode
    var team: String
    var baseDate: Date

    private var shifts: [String] { mode.cycles[team] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(shifts.indices, id: \.self) { idx in
                        HStack(spacing: 4) {
                            VStack(spacing: 4) {
                                Text(dayLabel(idx))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(TeamInfo.shortName(RotationModes.shiftName(for: shifts[idx])))
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 22)
                                    .background(ShiftStyle.color(for: RotationModes.shiftName(for: shifts[idx])))
                                    .clipShape(Capsule())
                            }
                            .frame(width: 40)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            if idx < shifts.count - 1 {
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            Text("第 \(mode.cycleDays + 1) 天回到第 1 天 · \(mode.cycleDays) 天一循环 · \(mode.sequence)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func dayLabel(_ idx: Int) -> String {
        let date = DateUtil.addingDays(baseDate, idx)
        let m = DateUtil.calendar.component(.month, from: date)
        let d = DateUtil.calendar.component(.day, from: date)
        return "\(m)/\(d)"
    }
}
