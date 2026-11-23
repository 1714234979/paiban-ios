import Foundation

/// 服务器地址配置 — 全 App 唯一的服务器地址来源。
/// 选路顺序：Cloudflare Tunnel 公网地址（若已填）→ Tailscale → 局域网。
/// 任何地方都不要再写死第二个地址；改地址只改这里。
enum ServerConfig {

    // MARK: - ★★★ 公网地址（Cloudflare Tunnel）★★★
    // 溟月的容器隧道（paiban-tunnel，随 NAS 重启自动起），当前唯一公网地址。
    // Quick Tunnel（临时地址）：cloudflared 一重启地址就变；
    // 固定地址要 Cloudflare 账号＋域名，老爷现在没有，等他定。
    // 注意：不要带末尾斜杠，不要带 /app 之类的路径，只要根地址。
    static let tunnelBaseURL: String? = "https://warrant-maternity-fathers-idle.trycloudflare.com"

    /// NAS 的 Tailscale 地址（100.66.88.28:3003）
    static let tailscaleBaseURL = "http://100.66.88.28:3003"

    /// 家里局域网地址（192.168.1.101:3003）
    static let lanBaseURL = "http://192.168.1.101:3003"

    // MARK: - App 内更新提示（版本清单）
    // canonical 接口：GET <baseURL>/api/v1/version（公开，不用认证），
    // 返回 {ok, data: {latestVersion, releaseNotes, downloadUrl}}。
    // 清单地址 = 当前 baseURL + "/api/v1/version"（跟 baseURL 走，不用另写一个域名）。
    // 约定：downloadUrl 为空表示没有更新——即使 latestVersion 高于当前版也不弹提示；
    // 只有 latestVersion 高于当前版且 downloadUrl 非空时才提示更新。
    // downloadUrl 是服务端可配的（服务端版本文件 / 管理端接口里改），不要写死在 App 里；
    // 老爷只需要在服务端把新版 IPA 的网盘链接填进 downloadUrl，App 就会提示更新。
    // App 内不直接下载安装包：点「更新」只是在系统浏览器里打开 downloadUrl，
    // 用户在网盘里下载新 IPA 再安装。
    static let versionPath = "/api/v1/version"

    /// 设置页里手动选的地址（UserDefaults 持久化）；为空表示自动选路。
    private static let overrideKey = "paiban.serverOverride"

    static var manualOverride: String? {
        get { UserDefaults.standard.string(forKey: overrideKey) }
        set {
            if let value = newValue {
                UserDefaults.standard.set(value, forKey: overrideKey)
            } else {
                UserDefaults.standard.removeObject(forKey: overrideKey)
            }
        }
    }

    /// 所有候选地址（按优先级），供设置页手动切换。
    static var allCandidates: [(kind: ServerKind, baseURL: String)] {
        var list: [(ServerKind, String)] = []
        if let tunnel = tunnelBaseURL, !tunnel.isEmpty {
            list.append((.tunnel, tunnel))
        }
        list.append((.tailscale, tailscaleBaseURL))
        list.append((.lan, lanBaseURL))
        return list
    }

    /// 依次对每个候选地址的 /health 做探测，返回第一个通的。
    /// 手动指定过地址时先试它，通了就用它。
    static func resolve() async -> (baseURL: String, kind: ServerKind)? {
        if let manual = manualOverride, !manual.isEmpty {
            if await probe(baseURL: manual) {
                return (manual, kind(for: manual))
            }
        }
        for (kind, baseURL) in allCandidates {
            if await probe(baseURL: baseURL) {
                return (baseURL, kind)
            }
        }
        return nil
    }

    /// 探一个地址的 /health，200 即为可达。3 秒超时。
    static func probe(baseURL: String) async -> Bool {
        guard let url = URL(string: baseURL + "/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        request.httpMethod = "GET"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    static func kind(for baseURL: String) -> ServerKind {
        if baseURL == tunnelBaseURL { return .tunnel }
        if baseURL == tailscaleBaseURL { return .tailscale }
        if baseURL == lanBaseURL { return .lan }
        return .manual
    }
}

/// 服务器线路。
enum ServerKind: String {
    case tunnel
    case tailscale
    case lan
    case manual

    var displayName: String {
        switch self {
        case .tunnel: return "公网隧道"
        case .tailscale: return "Tailscale"
        case .lan: return "局域网"
        case .manual: return "手动指定"
        }
    }
}
