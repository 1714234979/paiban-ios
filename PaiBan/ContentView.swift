import SwiftUI
import WebKit

// NAS 地址：先试家里局域网，再试 Tailscale
private let lanBase = "http://192.168.1.101:3003"
private let tailscaleBase = "http://100.66.88.28:3003"

enum LoadState {
    case checking
    case online(URL)
    case offline
}

struct ContentView: View {
    @State private var state: LoadState = .checking
    @State private var reloadID = UUID()

    var body: some View {
        Group {
            switch state {
            case .checking:
                ProgressView("正在连接 NAS…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .online(let url):
                NavigationStack {
                    WebView(url: url, reloadID: reloadID, onLoadFailed: { state = .offline })
                        .navigationTitle("排班空间")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button { reloadID = UUID() } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                            }
                        }
                }
            case .offline:
                OfflineView(onRetry: checkConnection)
            }
        }
        .onAppear(perform: checkConnection)
    }

    func checkConnection() {
        state = .checking
        probe(base: lanBase) { ok in
            if ok {
                state = .online(URL(string: lanBase + "/app")!)
                return
            }
            probe(base: tailscaleBase) { ok2 in
                if ok2 {
                    state = .online(URL(string: tailscaleBase + "/app")!)
                } else {
                    state = .offline
                }
            }
        }
    }

    func probe(base: String, done: @escaping (Bool) -> Void) {
        guard let url = URL(string: base + "/health") else { done(false); return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { done(ok) }
        }.resume()
    }
}

struct OfflineView: View {
    var onRetry: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text("连不上 NAS")
                .font(.title2).bold()
            Text("手机要和 NAS 在同一个网络里：\n家里 Wi-Fi，或者打开 Tailscale 再试。")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button("重新连接", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    let reloadID: UUID
    let onLoadFailed: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLoadFailed: onLoadFailed) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        if view.url == nil {
            view.load(URLRequest(url: url))
        } else if context.coordinator.lastReloadID != reloadID {
            context.coordinator.lastReloadID = reloadID
            view.reload()
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let onLoadFailed: () -> Void
        var lastReloadID: UUID?
        init(onLoadFailed: @escaping () -> Void) { self.onLoadFailed = onLoadFailed }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onLoadFailed()
        }
    }
}
