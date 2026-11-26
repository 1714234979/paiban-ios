import SwiftUI
import UIKit

/// 共享班表（1.2.7.001，第 24 条，图四样式）：
/// 只共享基础日历（倒班方式 + 班组 + 基准日 + 班组名），不共享调班/请假/加班/工资。
/// 三步：① 分享给同事排班表 → ② 同事完成排班 → ③ 查看对应日期班次以协商调换班。
/// 入口在排班页；收到同事的分享自动进「同事分享给我的」（这就是导入，不用再点）。
struct ShareScheduleView: View {
    @EnvironmentObject private var store: AppStore

    @State private var toUsername = ""
    @State private var note = ""
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var doneMessage: String?
    @State private var linkURL: String?
    @State private var viewingShare: ScheduleShare?

    var body: some View {
        List {
            // 三步（图四）。抽成单独属性，避免 body 表达式过大导致类型检查超时。
            Section {
                shareSteps
            }

            // 分享给同事：输对方账号（手机号/用户名）+ 备注。
            Section("分享给同事") {
                TextField("同事账号（手机号）", text: $toUsername)
                    .keyboardType(.phonePad)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                TextField("备注（可选）", text: $note)
                Button {
                    Task { await share() }
                } label: {
                    if isBusy {
                        ProgressView()
                    } else {
                        Text("分享给同事排班表")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isBusy || toUsername.trimmingCharacters(in: .whitespaces).isEmpty)
                Text("只分享基础日历，不含你的调班、请假、加班和工资。对方只能看到你这个班组的基础轮次。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 我分享的。
            Section("我分享的") {
                if store.sharesSent.isEmpty {
                    Text("还没有分享出去的班表")
                        .foregroundColor(.secondary)
                }
                ForEach(store.sharesSent) { share in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(share.toUsername ?? "")
                                .bold()
                            Spacer()
                            Text(modeName(for: share))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text("分享于 \(share.updatedAt ?? share.createdAt ?? "")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 16) {
                            Button("更新快照") { Task { try? await store.refreshShare(id: share.id) } }
                            Button("生成链接") { Task { await makeLink(id: share.id) } }
                            Button("撤销", role: .destructive) { Task { try? await store.deleteShare(id: share.id) } }
                        }
                        .font(.caption)
                    }
                }
            }

            // 同事分享给我的（导入）。
            Section("同事分享给我的") {
                if store.sharesReceived.isEmpty {
                    Text("还没有同事分享班表给你")
                        .foregroundColor(.secondary)
                }
                ForEach(store.sharesReceived) { share in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(share.fromDisplayName ?? share.fromUsername ?? "")
                                .bold()
                            Spacer()
                            Text(modeName(for: share))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text("分享于 \(share.updatedAt ?? share.createdAt ?? "")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 16) {
                            Button("查看班表") { viewingShare = share }
                            Button("拒绝", role: .destructive) { Task { try? await store.deleteShare(id: share.id) } }
                        }
                        .font(.caption)
                    }
                }
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
        .navigationTitle("共享班表")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.fetchShares() }
        .sheet(item: $viewingShare) { share in
            NavigationStack {
                SharedMonthView(share: share)
            }
        }
        .sheet(item: Binding(
            get: { linkURL.map { ShareLinkItem(url: $0) } },
            set: { linkURL = $0?.url }
        )) { item in
            NavigationStack {
                VStack(spacing: 16) {
                    Text("分享链接（公开查看，不用登录；不含个人信息和工资）")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    Text(item.url)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                    Button("复制链接") {
                        UIPasteboard.general.string = item.url
                    }
                    .buttonStyle(.borderedProminent)
                    Button("关闭") { linkURL = nil }
                }
                .padding()
                .navigationTitle("分享链接")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    /// 分享记录的倒班方式名（modeId 是可选的，先解包）。
    private func modeName(for share: ScheduleShare) -> String {
        guard let modeId = share.modeId else { return "—" }
        if modeId == "manual" { return "手动排班" }
        return RotationModes.mode(id: modeId)?.name ?? modeId
    }

    /// 三步（图四）：单独抽出来，避免 body 表达式过大导致类型检查超时。
    private var shareSteps: some View {
        VStack(alignment: .leading, spacing: 10) {
            shareStep(number: "1", title: "分享给同事排班表",
                      subtitle: "把你的基础日历（倒班方式 + 班组）发给同事")
            shareStep(number: "2", title: "同事完成排班",
                      subtitle: "同事在他的 App 里看到你的班表")
            shareStep(number: "3", title: "查看对应日期班次以协商调换班",
                      subtitle: "点开同事分享给你的班表，对照日期看班次，调班只改自己的日历")
        }
        .padding(.vertical, 4)
    }

    private func shareStep(number: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(Color.green)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func share() async {
        errorText = nil
        doneMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await store.shareSchedule(toUsername: toUsername.trimmingCharacters(in: .whitespaces),
                                              note: note.isEmpty ? nil : note)
            doneMessage = "已分享给 \(toUsername)。对方在 App 里就能看到你的基础日历。"
            toUsername = ""
            note = ""
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func makeLink(id: String) async {
        do {
            linkURL = try await store.api.createShareLink(id: id)
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

private struct ShareLinkItem: Identifiable {
    let id = UUID()
    let url: String
}

/// 同事分享的班表（只读月视图）：只看基础轮次，对照日期看班次；
/// 想调班回自己日历上改（调班只改自己的日历，不改对方的）。
private struct SharedMonthView: View {
    var share: ScheduleShare
    @EnvironmentObject private var store: AppStore

    @State private var yearMonth: (year: Int, month: Int) = DateUtil.yearMonth(of: Date())
    @State private var days: [ShareMonthDay] = []
    @State private var isLoading = false
    @State private var errorText: String?

    private var senderName: String {
        let name = share.fromName
        return name.isEmpty ? "同事" : name
    }
    private var modeName: String {
        guard let modeId = share.modeId else { return "—" }
        if modeId == "manual" { return "手动排班" }
        return RotationModes.mode(id: modeId)?.name ?? modeId
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            monthNavView
            contentView
            Text("只看基础轮次，不含对方的调班/请假。调班回自己日历上改。")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
        }
        .navigationTitle("\(senderName)的班表")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var headerView: some View {
        HStack {
            Text("\(senderName) · \(modeName)")
                .font(.headline)
            Spacer()
            Button {
                yearMonth = DateUtil.yearMonth(of: Date())
                Task { await load() }
            } label: { Text("今天") }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var monthNavView: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            // 36 条：年份走 yearMonthTitle 拼纯数字（Text("\(year)年\(month)月") 是 LocalizedStringKey，会变 2,026）。
            Text(DateUtil.yearMonthTitle(year: yearMonth.year, month: yearMonth.month))
                .font(.headline)
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal)
    }

    private var contentView: some View {
        Group {
            if isLoading {
                ProgressView().padding()
            } else if let errorText {
                Text(errorText).foregroundColor(.red).padding()
            } else {
                monthGridView
            }
        }
    }

    private var monthGridView: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { w in
                    Text(w).font(.caption).foregroundColor(.secondary)
                }
                ForEach(days) { day in
                    monthDayCell(day)
                }
            }
            .padding(.horizontal)
        }
    }

    private func monthDayCell(_ day: ShareMonthDay) -> some View {
        VStack(spacing: 2) {
            Text("\(day.day)")
                .font(.system(size: 15))
                .foregroundColor(day.shift == "休息" ? .secondary : .primary)
            Text(TeamInfo.shortName(day.shift))
                .font(.caption2)
                .foregroundColor(.white)
                .frame(width: 26, height: 18)
                .background(ShiftStyle.color(for: day.shift))
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func shiftMonth(_ delta: Int) {
        let base = DateUtil.firstDayOfMonth(year: yearMonth.year, month: yearMonth.month) ?? Date()
        let next = DateUtil.addingMonths(base, delta)
        yearMonth = DateUtil.yearMonth(of: next)
        Task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            days = try await store.api.fetchShareMonth(id: share.id, year: yearMonth.year, month: yearMonth.month)
            errorText = nil
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
