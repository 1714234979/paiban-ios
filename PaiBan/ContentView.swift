import SwiftUI
import UIKit

/// 根视图（原 WKWebView 壳已整体删掉，全部原生）：
/// 未登录 → 登录页；登录后没走完引导 → 引导页；否则 → 四个 Tab 的主界面。
/// 启动时先读缓存、后台刷新；服务器全不通且无缓存时显示离线页。
/// 新版本提示（Alert）也挂在这里：启动检查或设置页手动检查到新版时弹出。
struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            if store.isStarting {
                ProgressView("正在连接服务器…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.isLoggedIn {
                if store.user?.onboardingDone == false {
                    OnboardingView()
                } else {
                    MainTabView()
                }
            } else if let startupError = store.startupError {
                OfflineView(message: startupError) {
                    Task { await store.startup() }
                }
            } else {
                LoginView()
            }
        }
        .task {
            await store.startup()
        }
        .alert("发现新版本", isPresented: updateAlertBinding) {
            if let info = store.pendingUpdate, info.hasDownloadURL {
                Button("更新") {
                    openDownloadURL(info)
                }
                Button("稍后", role: .cancel) {
                    store.dismissUpdateForToday()
                }
            } else {
                Button("知道了", role: .cancel) {
                    store.dismissUpdateForToday()
                }
            }
        } message: {
            if let info = store.pendingUpdate {
                Text(updateMessage(for: info))
            }
        }
    }

    private var updateAlertBinding: Binding<Bool> {
        Binding(
            get: { store.pendingUpdate != nil },
            set: { newValue in
                if !newValue { store.pendingUpdate = nil }
            }
        )
    }

    private func updateMessage(for info: VersionInfo) -> String {
        var text = "最新版本 \(info.latestVersion)，当前版本 \(UpdateChecker.currentVersion)。"
        if let notes = info.releaseNotes, !notes.isEmpty {
            text += "\n\n\(notes)"
        } else {
            text += "\n\n新版本已发布，建议更新到最新版使用。"
        }
        if !info.hasDownloadURL {
            text += "\n\n（暂无下载链接，请稍后再试）"
        }
        return text
    }

    /// 点「更新」：只在系统浏览器里打开清单里的 downloadUrl（网盘链接），
    /// 用户在网盘里下载新 IPA 安装；不在 App 内直接下载安装包。
    private func openDownloadURL(_ info: VersionInfo) {
        guard let urlString = info.downloadUrl, let url = URL(string: urlString) else { return }
        store.pendingUpdate = nil
        UIApplication.shared.open(url)
    }
}

/// 服务器连不上、又没有可离线看的缓存时显示的页面。
struct OfflineView: View {
    let message: String
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("连不上服务器")
                .font(.title2).bold()
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Text("手机要和 NAS 在同一个网络里：家里 Wi-Fi、Tailscale，或者等公网隧道地址填好。")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button("重新连接", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
