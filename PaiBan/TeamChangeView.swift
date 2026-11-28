import SwiftUI
import UIKit // 1.3.2.017：保存成功轻震动用 UIImpactFeedbackGenerator（iOS 16 可用，不用 iOS 17 的 sensoryFeedback）

/// 更换班组（不是单日调班）：选新班组 + 生效日，从生效日零点起排班按新班组算，工资也跟着变。
/// 历史可多条、可删（至少保留一条）。走 POST / DELETE /api/v1/me/team-history。
struct TeamChangeView: View {
    @Environment(AppStore.self) private var store: AppStore

    @State private var history: [TeamHistoryEntry] = []
    @State private var newTeam = "A"
    @State private var effectiveFrom = Date()
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var doneMessage: String?

    var body: some View {
        Form {
            Section {
                Text("自生效日 00:00 起按新班组计算排班与预估工资，生效日前记录保持不变。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Section("当前换班记录") {
                if history.isEmpty {
                    Text("暂无记录（当前 \(store.myTeam)班）")
                        .foregroundColor(.secondary)
                }
                ForEach(history.sorted { $0.effectiveFrom < $1.effectiveFrom }) { entry in
                    HStack {
                        Text("\(entry.team)班")
                            .bold()
                        Spacer()
                        Text("从 \(entry.effectiveFrom) 起")
                            .foregroundColor(.secondary)
                    }
                }
                .onDelete(perform: deleteEntries)
            }

            Section("新增换班") {
                Picker("新班组", selection: $newTeam) {
                    ForEach(TeamInfo.allTeams, id: \.self) { team in
                        Text("\(team)班").tag(team)
                    }
                }
                .pickerStyle(.segmented)
                DatePicker("生效日", selection: $effectiveFrom, displayedComponents: .date)
                cyclePreview
            }

            // 保存换班（1.3.2.013）：移出卡片，独立居中的深炭黑胶囊主按钮。
            Section {
                Button {
                    Task { await addEntry() }
                } label: {
                    HStack {
                        Spacer()
                        if isBusy {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("保存换班")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(AppStyle.navyAdaptive)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .foregroundColor(.red)
                }
            }
            if let doneMessage {
                Section {
                    Text(doneMessage)
                        .foregroundColor(.green)
                }
            }
        }
        .navigationTitle("更换班组")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadHistory()
        }
    }

    /// 轮次预览（1.3.2.013）：复用日历里的微型彩色圆角小标签（紫早 / 绿日 / 红中 / 灰休），
    /// 核对班次比纯文字直观；8 天一排横向可滑。
    private var cyclePreview: some View {
        let shifts = TeamInfo.cycles[newTeam] ?? []
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(shifts.indices, id: \.self) { idx in
                    HStack(spacing: 4) {
                        Text(TeamInfo.shortName(shifts[idx]))
                            .font(.caption)
                            .bold()
                            .foregroundColor(.white)
                            .frame(width: 26, height: 22)
                            .background(ShiftStyle.color(for: shifts[idx]))
                            .clipShape(Capsule())
                        if idx < shifts.count - 1 {
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func loadHistory() async {
        do {
            history = try await store.refreshTeamHistory()
            if let last = history.sorted(by: { $0.effectiveFrom < $1.effectiveFrom }).last {
                newTeam = last.team == "A" ? "B" : "A"
            }
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func addEntry() async {
        errorText = nil
        doneMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            history = try await store.api.addTeamHistory(
                team: newTeam,
                effectiveFrom: DateUtil.string(from: effectiveFrom)
            )
            // 1.3.2.017：保存成功轻震一下确认（再加绿字提示，双重确认）。
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            doneMessage = "已保存：从 \(DateUtil.string(from: effectiveFrom)) 起按 \(newTeam)班排班"
            await store.refreshMonth()
            await store.refreshPayInputs()
            await store.refreshPay()
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func deleteEntries(at offsets: IndexSet) async {
        let sorted = history.sorted { $0.effectiveFrom < $1.effectiveFrom }
        errorText = nil
        doneMessage = nil
        if sorted.count <= 1 {
            errorText = "至少要保留一条换班记录，不能全删"
            return
        }
        for index in offsets {
            let entry = sorted[index]
            do {
                history = try await store.api.deleteTeamHistory(effectiveFrom: entry.effectiveFrom)
            } catch {
                errorText = (error as? APIError)?.message ?? error.localizedDescription
            }
        }
        await store.refreshMonth()
        await store.refreshPayInputs()
        await store.refreshPay()
    }

    // onDelete 要求同步闭包，这里包一层 Task。
    private func deleteEntries(_ offsets: IndexSet) {
        Task { await deleteEntries(at: offsets) }
    }
}
