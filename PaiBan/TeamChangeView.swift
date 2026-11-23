import SwiftUI

/// 永久换班（不是单日调班）：选新班组 + 生效日，从生效日零点起排班按新班组算，工资也跟着变。
/// 历史可多条、可删（至少保留一条）。走 POST / DELETE /api/v1/me/team-history。
struct TeamChangeView: View {
    @EnvironmentObject private var store: AppStore

    @State private var history: [TeamHistoryEntry] = []
    @State private var newTeam = "A"
    @State private var effectiveFrom = Date()
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var doneMessage: String?

    var body: some View {
        Form {
            Section {
                Text("从生效日零点起，你的排班按新班组算；工资也跟着变。")
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
                Text(TeamInfo.cycleText(team: newTeam))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button {
                    Task { await addEntry() }
                } label: {
                    if isBusy {
                        ProgressView()
                    } else {
                        Text("保存换班")
                    }
                }
                .disabled(isBusy)
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
        .navigationTitle("永久换班")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadHistory()
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
            doneMessage = "已保存：从 \(DateUtil.string(from: effectiveFrom)) 起按 \(newTeam)班排班"
            await store.refreshMonth()
            await store.refreshPay()
            await store.refreshToday()
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
        await store.refreshPay()
    }

    // onDelete 要求同步闭包，这里包一层 Task。
    private func deleteEntries(_ offsets: IndexSet) {
        Task { await deleteEntries(at: offsets) }
    }
}
