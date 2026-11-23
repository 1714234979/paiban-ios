import Foundation

/// 版本清单里的一条记录：GET <baseURL>/api/v1/version 返回的 data。
/// {latestVersion, releaseNotes, downloadUrl} —— downloadUrl 是服务端可配的
/// 网盘链接（服务端版本文件 / 管理端接口里改），App 里不要写死。
struct VersionInfo: Codable, Equatable, Identifiable {
    var latestVersion: String
    var releaseNotes: String?
    var downloadUrl: String?

    var id: String { latestVersion }

    /// 有可用的下载链接才算能更新；没有链接时只提示、不给「更新」按钮。
    var hasDownloadURL: Bool {
        guard let downloadUrl, !downloadUrl.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return URL(string: downloadUrl) != nil
    }
}

/// App 内更新检查器（可复用、无界面依赖）。
/// 流程：启动后（服务器连通时）调一次版本清单 → 语义化版本比较 →
/// 有新版且今天没点过「稍后」就返回记录，由调用方弹原生提示。
/// 检查失败（没网、服务器不通）一律静默，返回 nil，不弹错。
enum UpdateChecker {

    private static let dismissedDateKey = "paiban.updateDismissedDate"

    /// 当前版本：Bundle 的 CFBundleShortVersionString（Info.plist 里 1.0）。
    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    /// 语义化版本比较：分段比数字，1.0.0 < 1.1.0；缺的段按 0 算。
    /// latest 高于 current 时返回 true。
    static func isNewer(latest: String, than current: String) -> Bool {
        let latestParts = versionParts(latest)
        let currentParts = versionParts(current)
        let count = max(latestParts.count, currentParts.count)
        for i in 0..<count {
            let l = i < latestParts.count ? latestParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if l != c { return l > c }
        }
        return false
    }

    /// "1.2.3" → [1, 2, 3]；每段只取开头的数字（"1.0-beta" 的段算 0 号后缀、按 1 算）。
    private static func versionParts(_ version: String) -> [Int] {
        version.split(separator: ".").map { part in
            let digits = part.prefix(while: { $0.isNumber })
            return Int(digits) ?? 0
        }
    }

    /// 今天是不是已经点过「稍后」。
    static var dismissedToday: Bool {
        let today = DateUtil.string(from: Date())
        return UserDefaults.standard.string(forKey: dismissedDateKey) == today
    }

    /// 点「稍后」：记下当天日期，当天不再弹。
    static func markDismissedToday() {
        UserDefaults.standard.set(DateUtil.string(from: Date()), forKey: dismissedDateKey)
    }

    /// 启动后调用一次：有新版且今天没点过「稍后」→ 返回版本记录；否则返回 nil。
    /// 约定（canonical）：downloadUrl 为空表示没有更新——即使 latestVersion 高于当前版，
    /// 只要 downloadUrl 为空就不弹。失败（没网、服务器不通、清单格式不对）静默返回 nil。
    static func checkAfterLaunch(api: APIClient) async -> VersionInfo? {
        guard !dismissedToday else { return nil }
        do {
            let info = try await api.fetchVersion()
            guard info.hasDownloadURL else { return nil }
            guard isNewer(latest: info.latestVersion, than: currentVersion) else { return nil }
            return info
        } catch {
            return nil
        }
    }

    /// 设置页「检查更新」手动查的结果。
    enum ManualResult {
        case updateAvailable(VersionInfo)  // 有新版且有下载链接：弹同样的提示
        case upToDate                      // 没有更新（含 downloadUrl 为空的情况）
    }

    /// 手动检查：失败时静默返回 .upToDate（不弹错，由调用方只在有结果时提示）。
    /// 注意：手动检查不看「稍后」的当天记录，点一次就查一次。
    /// 约定（canonical）：downloadUrl 为空表示没有更新，即使版本号有差异也按无更新处理。
    static func checkManually(api: APIClient) async -> ManualResult {
        do {
            let info = try await api.fetchVersion()
            guard info.hasDownloadURL else {
                return .upToDate
            }
            guard isNewer(latest: info.latestVersion, than: currentVersion) else {
                return .upToDate
            }
            return .updateAvailable(info)
        } catch {
            return .upToDate
        }
    }
}
