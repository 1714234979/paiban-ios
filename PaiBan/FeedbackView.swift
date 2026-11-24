import PhotosUI
import SwiftUI
import UIKit

/// 反馈问题：先选类型（Bug / 建议）和出问题的页面，可选传一张截图，
/// 最下边写问题描述。点发送后把类型 + 页面 + 正文 + 截图 + 最近 24 小时
/// 运行日志一起发到 NAS 的反馈文件夹（POST /api/v1/me/feedback），方便定位。
struct FeedbackView: View {
    enum FeedbackType: String, CaseIterable, Identifiable {
        case bug = "bug"
        case suggestion = "suggestion"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .bug: return "Bug（问题反馈）"
            case .suggestion: return "建议"
            }
        }
    }

    static let locations = ["排班页", "工资页", "设置页", "登录/注册", "管理后台", "其他"]

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var type: FeedbackType = .bug
    @State private var location = "排班页"
    @State private var message = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var screenshot: UIImage?
    @State private var isSending = false
    @State private var resultText: String?

    /// 1.2.2 反馈双向回复：自己的反馈列表（最新在前），点开一条看回复 thread、能继续回。
    @State private var myFeedback: [FeedbackItem] = []
    @State private var isLoadingMyFeedback = false
    @State private var myFeedbackError: String?
    @State private var expandedFile: String?
    @State private var replyText = ""
    @State private var isReplying = false
    @State private var replyError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                Text("遇到什么问题？")
                    .font(.title2).bold()
                Text("选一下类型和出问题的页面，再写清楚是哪个月出了问题。发送时会附上最近 24 小时的运行日志（只含 App 自己的运行记录，不含密码）。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    Text("反馈类型")
                    Spacer()
                    Picker("反馈类型", selection: $type) {
                        ForEach(FeedbackType.allCases) { t in
                            Text(t.label).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack {
                    Text("出问题的页面")
                    Spacer()
                    Picker("出问题的页面", selection: $location) {
                        ForEach(Self.locations, id: \.self) { loc in
                            Text(loc).tag(loc)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack(alignment: .top, spacing: 12) {
                    PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                        Label("上传截图", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)
                    if let screenshot {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: screenshot)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 96, height: 96)
                                .cornerRadius(8)
                            Button {
                                self.screenshot = nil
                                pickerItem = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .background(Circle().fill(Color(.systemBackground)))
                            }
                            .offset(x: 6, y: -6)
                        }
                    }
                }
                .onChange(of: pickerItem?.itemIdentifier) { _ in
                    Task { await loadScreenshot(from: pickerItem) }
                }

                Text("问题描述")
                    .font(.subheadline).bold()
                TextEditor(text: $message)
                    .frame(minHeight: 100, maxHeight: 180)
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppStyle.buttonRadius)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
                if let resultText {
                    Text(resultText)
                        .font(.subheadline)
                        .foregroundColor(resultText.hasPrefix("已发送") ? .green : .red)
                }
                Button {
                    Task { await send() }
                } label: {
                    Text(isSending ? "发送中…" : "发送反馈")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppStyle.buttonHeight)
                        .background(AppStyle.navy)
                        .foregroundColor(.white)
                        .cornerRadius(AppStyle.buttonRadius)
                }
                .buttonStyle(.plain)
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)

                Divider()
                    .padding(.top, 4)
                myFeedbackSection
            }
            .padding(AppStyle.pagePadding)
            }
            .navigationTitle("反馈问题")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .task {
                await loadMyFeedback()
            }
        }
    }

    /// 把选中的图压成边长不超过 1280 的 JPEG（质量 0.8），转 base64。
    private static func jpegBase64(_ image: UIImage) -> String? {
        let maxEdge: CGFloat = 1280
        let size = image.size
        let scale = min(1, maxEdge / max(size.width, size.height))
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        guard let data = resized.jpegData(compressionQuality: 0.8) else { return nil }
        return data.base64EncodedString()
    }

    private func loadScreenshot(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                screenshot = image
            }
        } catch {
            AppLogger.shared.log("截图读取失败：\(error.localizedDescription)", tag: "Feedback")
            resultText = "截图读取失败，请再试一次"
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        let logs = AppLogger.shared.recentLogs(hours: 24)
        let imageBase64 = screenshot.flatMap(Self.jpegBase64)
        do {
            try await store.api.sendFeedback(
                message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                logs: logs,
                type: type.rawValue,
                location: location,
                imageBase64: imageBase64
            )
            AppLogger.shared.log("反馈已发送", tag: "Feedback")
            resultText = "已发送，谢谢！"
            // 停一下让用户看到“已发送”，再关掉。
            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()
        } catch {
            AppLogger.shared.log("反馈发送失败：\((error as? APIError)?.message ?? error.localizedDescription)", tag: "Feedback")
            resultText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    // MARK: - 我的反馈（1.2.2 双向回复）

    /// 「我的反馈」区：自己的反馈列表（最新在前），点开一条看回复 thread、能继续回。
    /// 每次打开反馈页拉一次；新反馈发完关页面，下次打开就能看到。
    private var myFeedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("我的反馈")
                    .font(.headline)
                Spacer()
                if isLoadingMyFeedback { ProgressView() }
            }
            if let myFeedbackError {
                Text(myFeedbackError)
                    .font(.subheadline)
                    .foregroundColor(.red)
            } else if myFeedback.isEmpty && !isLoadingMyFeedback {
                Text("还没有反馈记录，上面提交后会出现在这里。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            ForEach(myFeedback) { item in
                feedbackRow(item)
            }
        }
    }

    /// 一条反馈的行：时间、类型、页面；点开展开回复 thread 和回复框。
    private func feedbackRow(_ item: FeedbackItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation {
                    if expandedFile == item.file {
                        expandedFile = nil
                    } else {
                        expandedFile = item.file
                        replyText = ""
                        replyError = nil
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feedbackTitle(item))
                            .font(.subheadline).bold()
                            .foregroundColor(.primary)
                        Text(Self.displayTime(item.at))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(replyCountText(item))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: expandedFile == item.file ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            if expandedFile == item.file {
                Divider()
                replyThread(item)
                replyComposer(item)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(AppStyle.buttonRadius)
    }

    /// 行标题：类型 · 页面（有截图的再加「有截图」）。
    private func feedbackTitle(_ item: FeedbackItem) -> String {
        let typeLabel: String
        switch item.type {
        case "bug": typeLabel = "Bug"
        case "suggestion": typeLabel = "建议"
        default: typeLabel = item.type ?? "反馈"
        }
        var title = "\(typeLabel) · \(item.location ?? "其他")"
        if item.hasImage == true { title += " · 有截图" }
        return title
    }

    /// 右边小字：有几条回复，没有就写「暂无回复」。
    private func replyCountText(_ item: FeedbackItem) -> String {
        let count = item.replies?.count ?? 0
        return count == 0 ? "暂无回复" : "\(count) 条回复"
    }

    /// 回复 thread：管理员和自己的回复按时间排；管理员那条带浅 navy 底、名字写「管理员」，
    /// 自己的那条写「我」（服务端 by 有名字时显示名字）。
    private func replyThread(_ item: FeedbackItem) -> some View {
        let replies = (item.replies ?? []).sorted { $0.at < $1.at }
        return VStack(alignment: .leading, spacing: 8) {
            if replies.isEmpty {
                Text("还没有回复，管理员回复后会出现在这里。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            ForEach(replies) { reply in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(replySpeaker(reply))
                            .font(.caption).bold()
                            .foregroundColor(reply.from == "admin" ? AppStyle.navy : .primary)
                        Text(Self.displayTime(reply.at))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(reply.text)
                        .font(.subheadline)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(reply.from == "admin" ? AppStyle.navy.opacity(0.08) : Color(.systemBackground))
                .cornerRadius(8)
            }
        }
    }

    /// 回复人名字：服务端 by 有名字显示名字，没有时管理员写「管理员」、自己写「我」。
    private func replySpeaker(_ reply: FeedbackReply) -> String {
        if let by = reply.by, !by.isEmpty { return by }
        return reply.from == "admin" ? "管理员" : "我"
    }

    /// 回复框：输入 + 发送；失败显示服务端中文错误（1–2000 字是服务端校验）。
    private func replyComposer(_ item: FeedbackItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("继续回复…", text: $replyText)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await sendReply(to: item) }
                } label: {
                    Text(isReplying ? "发送中…" : "发送")
                        .font(.subheadline).bold()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppStyle.navy)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isReplying)
            }
            if let replyError {
                Text(replyError)
                    .font(.subheadline)
                    .foregroundColor(.red)
            }
        }
    }

    private func loadMyFeedback() async {
        isLoadingMyFeedback = true
        defer { isLoadingMyFeedback = false }
        do {
            myFeedback = try await store.api.fetchMyFeedback()
            myFeedbackError = nil
        } catch {
            myFeedbackError = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    /// 继续回一条：成功就把新回复追加到本地这条的 thread 里，不用整列表重拉。
    private func sendReply(to item: FeedbackItem) async {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isReplying = true
        defer { isReplying = false }
        do {
            let reply = try await store.api.postFeedbackReply(file: item.file, text: text)
            if let idx = myFeedback.firstIndex(where: { $0.file == item.file }) {
                var updated = myFeedback[idx]
                var replies = updated.replies ?? []
                replies.append(reply)
                updated.replies = replies
                myFeedback[idx] = updated
            }
            replyText = ""
            replyError = nil
            AppLogger.shared.log("反馈回复已发送", tag: "Feedback")
        } catch {
            AppLogger.shared.log("反馈回复失败：\((error as? APIError)?.message ?? error.localizedDescription)", tag: "Feedback")
            replyError = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    /// 服务端 at 是 ISO 时间戳，显示成“11-24 10:31”；解析不出就原样截一段显示。
    private static func displayTime(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else {
            return String(iso.prefix(16)).replacingOccurrences(of: "T", with: " ")
        }
        let out = DateFormatter()
        out.locale = Locale(identifier: "zh_CN")
        out.dateFormat = "MM-dd HH:mm"
        return out.string(from: date)
    }
}
