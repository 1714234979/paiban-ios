import SwiftUI

/// 反馈问题：写一句话说明遇到的问题，点发送后把正文 + 最近 24 小时运行日志
/// 一起发到 NAS 的反馈文件夹（POST /api/v1/feedback），方便定位。
struct FeedbackView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var message = ""
    @State private var isSending = false
    @State private var resultText: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("遇到什么问题？")
                    .font(.title2).bold()
                Text("写清楚是哪个月、哪个页面出了问题。发送时会附上最近 24 小时的运行日志（只含 App 自己的运行记录，不含密码）。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextEditor(text: $message)
                    .frame(minHeight: 140)
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
                if let resultText {
                    Text(resultText)
                        .font(.subheadline)
                        .foregroundColor(resultText.hasPrefix("已发送") ? .green : .red)
                }
                Spacer()
                Button {
                    Task { await send() }
                } label: {
                    Text(isSending ? "发送中…" : "发送反馈")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding(20)
            .navigationTitle("反馈问题")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        let logs = AppLogger.shared.recentLogs(hours: 24)
        do {
            try await store.api.sendFeedback(
                message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                logs: logs
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
}
