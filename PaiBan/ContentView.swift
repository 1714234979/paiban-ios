import SwiftUI
import UIKit

/// 根视图（原 WKWebView 壳已整体删掉，全部原生）：
/// 未登录 → 登录页；登录后没走完引导 → 引导页；没绑手机号 → 强制绑定门；
/// 否则 → 四个 Tab 的主界面。
/// 启动时先读缓存、后台刷新；服务器全不通且无缓存时显示离线页。
/// 新版本提示（Alert）也挂在这里：启动检查或设置页手动检查到新版时弹出。
struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    /// 本次启动里已放行过强制绑定门（只在短信服务没开通/查不到状态时才放行；
    /// 换账号登录时重置，免得另一个没绑手机号的账号也被放行）。
    @State private var bindGateDismissedForSession = false

    /// 1.1.3 强制绑手机号：已登录、引导已过、还没绑手机号、本次还没放行过。
    private var needsForcedBind: Bool {
        guard store.isLoggedIn, store.user?.onboardingDone == true else { return false }
        guard let phone = store.user?.phone, phone.isEmpty else { return false }
        return !bindGateDismissedForSession
    }

    var body: some View {
        Group {
            if store.isStarting {
                ProgressView("正在连接服务器…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.isLoggedIn {
                if store.user?.onboardingDone == false {
                    OnboardingView()
                } else if needsForcedBind {
                    // 1.1.3 强制绑手机号：老账号首次打开必须绑完才能进主界面，没有跳过。
                    // 短信服务没开通时只提示、可先进入（见 ForcedBindGateView），
                    // 一旦开通，下次打开自动变严格——不用等 App 更新。
                    ForcedBindGateView(onEnterAnyway: { bindGateDismissedForSession = true })
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
        .onChange(of: store.isLoggedIn) { _ in bindGateDismissedForSession = false }
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
        // 1.1.3：提取码直接写进提示框里——之前只写“会自动复制”，
        // 剪贴板一旦出问题用户看不到码（1.1.2 报的“点更新没复制”就是这么来的，
        // 另：1.1.1 的 VersionInfo 根本没有 extractionCode 字段，点更新本来就不会复制）。
        // 点「更新」先复制提取码再打开链接；万一粘贴不到，照着这个码手动输入也行。
        if let code = info.trimmedExtractionCode {
            text += "\n\n提取码：\(code)（点「更新」会自动复制，打开网盘后粘贴即可；粘贴不到就手动输入这个码）"
        }
        return text
    }

    /// 点「更新」：先把网盘提取码复制到剪贴板（有码才复制，没码就只打开链接），
    /// 再在系统浏览器里打开清单里的 downloadUrl（网盘链接），
    /// 用户在网盘里粘贴提取码、下载新 IPA 安装；不在 App 内直接下载安装包。
    /// 复制在先、打开在后：复制失败也不影响打开链接，提示框里也直接写了提取码可手动输入。
    private func openDownloadURL(_ info: VersionInfo) {
        guard let urlString = info.downloadUrl, let url = URL(string: urlString) else { return }
        if let code = info.trimmedExtractionCode {
            UIPasteboard.general.string = code
        }
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
            Text("平时走云服务器，云连不上时自动切 NAS 备份；两条都不通就是离线，本地缓存先顶着。")
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

/// 1.1.3 强制绑手机号的门：挡在主界面前面，没绑手机号进不去。
/// 先查短信服务是否已开通（GET /api/v1/auth/sms/status）：
/// 已开通 → 严格强制绑定（BindPhoneSheet forced 模式，没有取消）；
/// 没开通 → 只提示服务尚未开通，可先进入 App（这是服务没配好的放行，
/// 不是给用户的跳过；配好后下次打开自动变严格，不用等 App 更新）；
/// 查不到状态（离线）→ 也不硬拦，先进 App。
struct ForcedBindGateView: View {
    @EnvironmentObject private var store: AppStore
    var onEnterAnyway: () -> Void
    @State private var smsConfigured: Bool?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let configured = smsConfigured {
                if configured {
                    BindPhoneSheet(forced: true)
                } else {
                    gateNotice(
                        title: "手机号绑定尚未开通",
                        body: "短信绑定服务还没配置好，暂时绑不了手机号。先进入 App，等服务开通后，下次打开会提醒绑定。",
                        buttonTitle: "先进入 App"
                    )
                }
            } else if loadFailed {
                gateNotice(
                    title: "查不到绑定服务状态",
                    body: "现在连不上服务器，查不到短信绑定服务开没开通。先进入 App，联网后下次打开会提醒绑定。",
                    buttonTitle: "先进入 App"
                )
            } else {
                ProgressView("正在检查绑定服务…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await loadStatus()
        }
    }

    private func gateNotice(title: String, body: String, buttonTitle: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(title)
                .font(.title2).bold()
            Text(body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button(buttonTitle) {
                onEnterAnyway()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadStatus() async {
        do {
            smsConfigured = try await store.api.fetchSmsStatus()
        } catch {
            loadFailed = true
        }
    }
}
