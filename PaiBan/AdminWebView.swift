import SwiftUI
import WebKit

/// 管理后台：张晓文点设置页「切换管理员后台」后打开。
/// 用 WKWebView 打开云服务器的管理端（http://47.97.168.14:3003/admin），
/// 并把 App 已有的登录会话（paiban_session cookie）注入 WebView，免得再输一遍密码。
/// 设置页原生 push 进来，左上角是系统自带的“‹ 设置”返回（Gemini 整改模块 1c，
/// 之前 fullScreenCover + 自定义“‹ 返回”按钮已删掉）；下面的排班/工资页
/// 状态、登录态、本地缓存都不动。两边互不干扰：切到管理后台再切回来，两边都保持原样。
struct AdminBackendView: View {
    @State private var isLoading = true
    @State private var title = "管理后台"

    /// 管理端地址：云服务器（主用）。
    private var adminURL: URL {
        URL(string: ServerConfig.cloudBaseURL + "/admin")!
    }

    var body: some View {
        ZStack {
            AdminWebView(url: adminURL, isLoading: $isLoading, title: $title)
            if isLoading {
                ProgressView()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 包一层 WKWebView：先把 App 的 paiban_session cookie 写进 WebView 的
/// cookie 仓库，再加载 /admin；没拿到 cookie 就直接加载（管理端登录页会让再登一次）。
struct AdminWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var title: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        // 注入 App 的登录会话 cookie，免再登。App 的 URLSession 与
        // HTTPCookieStorage.shared 共用 cookie，登录后 paiban_session 就在里面。
        let store = WKWebsiteDataStore.default().httpCookieStore
        let sessionCookies = (HTTPCookieStorage.shared.cookies ?? []).filter { $0.name == "paiban_session" }
        if sessionCookies.isEmpty {
            webView.load(URLRequest(url: url))
        } else {
            let group = DispatchGroup()
            for cookie in sessionCookies {
                group.enter()
                store.setCookie(cookie) { group.leave() }
            }
            group.notify(queue: .main) {
                webView.load(URLRequest(url: url))
            }
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: AdminWebView
        init(_ parent: AdminWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            if let t = webView.title, !t.isEmpty { parent.title = t }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
    }
}
