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

    var body: some View {
        NavigationStack {
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
                Spacer()
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
            }
            .padding(AppStyle.pagePadding)
            .navigationTitle("反馈问题")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
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
}
