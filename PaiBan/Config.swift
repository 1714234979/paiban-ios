import Foundation

/// 服务器地址配置 — 全 App 唯一的服务器地址来源。
/// 主备两条（老爷 2026-11-24 定）：
///   ① 云服务器 http://47.97.168.14:3003（主用，平时只走它）
///   ② NAS 公网隧道 https://warrant-maternity-fathers-idle.trycloudflare.com（备份，只有云连不上时才切）
/// Tailscale（100.66.88.28:3003）与局域网（192.168.1.101:3003）不再进地址链。
/// 选路：先试云（10 秒探活），云超时或明确失败才试 NAS 隧道；两条都不通就置离线、走本地缓存。
/// 云优先：每次选路都先试云，所以切到 NAS 后云一恢复，下次启动/下次选路就切回云；平时不来回跳。
/// 任何地方都不要再写死第二个地址；改地址只改这里。
enum ServerConfig {

    // MARK: - ★★★ 云服务器（主用）★★★
    // 阿里云试用服务器（2026-11-24），排班 API 已搬上云。
    static let cloudBaseURL = "http://47.97.168.14:3003"

    // MARK: - ★★★ NAS 公网隧道（备份）★★★
    // 溟月的容器隧道（paiban-tunnel，随 NAS 重启自动起），只有云连不上时才用。
    // Quick Tunnel（临时地址）：cloudflared 一重启地址就变，变了再改这里。
    // 注意：不要带末尾斜杠，不要带 /app 之类的路径，只要根地址。
    static let nasTunnelBaseURL: String? = "https://warrant-maternity-fathers-idle.trycloudflare.com"

    // MARK: - App 内更新提示（版本清单）
    // canonical 接口：GET <baseURL>/api/v1/version（公开，不用认证），
    // 返回 {ok, data: {latestVersion, releaseNotes, downloadUrl, extractionCode}}。
    // 清单地址 = 当前 baseURL + "/api/v1/version"（跟 baseURL 走，不用另写一个域名）。
    // 约定：downloadUrl 为空表示没有更新——即使 latestVersion 高于当前版也不弹提示；
    // 只有 latestVersion 高于当前版且 downloadUrl 非空时才提示更新。
    // downloadUrl 与 extractionCode 是服务端可配的（服务端版本文件 / 管理端接口里改），不要写死在 App 里；
    // 老爷只需要在服务端把新版 IPA 的网盘链接填进 downloadUrl，App 就会提示更新。
    // App 内不直接下载安装包：点「更新」先把 extractionCode 复制到剪贴板，
    // 再在系统浏览器里打开 downloadUrl，用户在网盘里粘贴提取码、下载新 IPA 再安装。
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

    /// 所有候选地址（按优先级），供设置页手动切换：云 → NAS 隧道。
    static var allCandidates: [(kind: ServerKind, baseURL: String)] {
        var list: [(ServerKind, String)] = [(.cloud, cloudBaseURL)]
        if let tunnel = nasTunnelBaseURL, !tunnel.isEmpty {
            list.append((.nasTunnel, tunnel))
        }
        return list
    }

    /// 依次对每个候选地址的 /health 做探测，返回第一个通的。
    /// 云优先：每次都先试云，云通就用云；云不通才试 NAS 隧道；两条都不通返回 nil（离线）。
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

    /// 探一个地址的 /health，200 即为可达。10 秒超时：
    /// 公网隧道首启常要 DNS + TLS 握手，3 秒太紧、手机 5G 下容易误判连不上。
    static func probe(baseURL: String) async -> Bool {
        guard let url = URL(string: baseURL + "/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.httpMethod = "GET"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    static func kind(for baseURL: String) -> ServerKind {
        if baseURL == cloudBaseURL { return .cloud }
        if baseURL == nasTunnelBaseURL { return .nasTunnel }
        return .manual
    }
}

/// 服务器线路。
enum ServerKind: String {
    case cloud
    case nasTunnel
    case manual

    var displayName: String {
        switch self {
        case .cloud: return "云服务器"
        case .nasTunnel: return "NAS 隧道（备份）"
        case .manual: return "手动指定"
        }
    }
}
