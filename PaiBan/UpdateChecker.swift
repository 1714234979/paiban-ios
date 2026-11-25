import Foundation

/// 版本清单里的一条记录：GET <baseURL>/api/v1/version 返回的 data。
/// {latestVersion, releaseNotes, downloadUrl, extractionCode} —— downloadUrl 是服务端可配的
/// 下载链接（服务端版本文件 / 管理端接口里改），App 里不要写死。
/// extractionCode 是网盘提取码（服务端配，没有码时为空）；点「更新」时先复制到剪贴板再打开链接。
/// 1.2.2：downloadUrl 改成服务器 IPA 直链（不再是网盘链接），extractionCode 为空；
/// 没有码时不复制、直接打开链接下载安装（见 ContentView.openDownloadURL）。
/// 服务端 1.2.2 起多回的 androidVersion / androidDownloadUrl / androidReleaseNotes 等字段，
/// Codable 合成解码默认忽略未知键，不用特意声明，解码不受影响。
struct VersionInfo: Codable, Equatable, Identifiable {
    var latestVersion: String
    var releaseNotes: String?
    var downloadUrl: String?
    var extractionCode: String?
    /// 内测渠道（1.2.8）：服务端回的当前用户是不是内测人员、该平台有没有内测版、
    /// 这次回的是哪个渠道（beta/stable）。老版本服务端没有这三个字段，解码时按 nil 处理。
    var isBetaTester: Bool?
    var hasBeta: Bool?
    var channel: String?
    /// 节假日数据（1.2.7.001）：服务端节假日缓存的更新时间与已覆盖年份。
    /// App 启动时比对本地存的 holidaysUpdatedAt，变了就拉取新数据刷新日历。
    /// holidaysYear 是数组（如 [2026]），因为服务端可能覆盖多年。
    var holidaysUpdatedAt: String?
    var holidaysYear: [Int]?

    var id: String { latestVersion }

    /// 有可用的下载链接才算能更新；没有链接时只提示、不给「更新」按钮。
    var hasDownloadURL: Bool {
        guard let downloadUrl, !downloadUrl.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return URL(string: downloadUrl) != nil
    }

    /// 去掉空白后的提取码；没有码（字段缺失或空串）时为 nil。
    /// 老版本服务端没有这个字段，解码时按 nil 处理，只打开链接、不复制、不报错。
    var trimmedExtractionCode: String? {
        guard let code = extractionCode?.trimmingCharacters(in: .whitespaces), !code.isEmpty else { return nil }
        return code
    }
}

/// App 内更新检查器（可复用、无界面依赖）。
/// 流程：启动后（服务器连通时）调一次版本清单 → 语义化版本比较 →
/// 有新版且今天没点过「稍后」就返回记录，由调用方弹原生提示。
/// 检查失败（没网、服务器不通）一律静默，返回 nil，不弹错。
enum UpdateChecker {

    private static let dismissedDateKey = "paiban.updateDismissedDate"

    /// 当前版本：Bundle 的 CFBundleShortVersionString（Info.plist 里 1.1.1）。
    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    /// 语义化版本比较：分段比数字，1.0.0 < 1.1.0；缺的段按 0 算。
    /// latest 高于 current 时返回 true。
    /// 基础号相同：正式版比同号预发布版新（1.2.8 > 1.2.8-beta.1），
    /// 两个预发布版比后缀里的数字（beta.1 < beta.2）。
    static func isNewer(latest: String, than current: String) -> Bool {
        let l = splitVersion(latest)
        let c = splitVersion(current)
        let count = max(l.parts.count, c.parts.count)
        for i in 0..<count {
            let lv = i < l.parts.count ? l.parts[i] : 0
            let cv = i < c.parts.count ? c.parts[i] : 0
            if lv != cv { return lv > cv }
        }
        switch (l.pre, c.pre) {
        case (nil, nil): return false
        case (nil, _): return true
        case (_, nil): return false
        case (let lp?, let cp?):
            let ln = lp.split(separator: ".").compactMap { Int($0.prefix(while: { $0.isNumber })) }
            let cn = cp.split(separator: ".").compactMap { Int($0.prefix(while: { $0.isNumber })) }
            let n = max(ln.count, cn.count)
            for i in 0..<n {
                let a = i < ln.count ? ln[i] : 0
                let b = i < cn.count ? cn[i] : 0
                if a != b { return a > b }
            }
            return lp > cp
        }
    }

    /// 内测渠道偏好（1.2.8）：内测人员在设置页切内测 / 正式，存在本地；默认正式。
    /// 非内测人员切了也没用——服务端只给内测人员回内测版，其他人永远回正式版。
    private static let channelKey = "paiban.updateChannel"
    static var channel: String {
        get { UserDefaults.standard.string(forKey: channelKey) ?? "stable" }
        set { UserDefaults.standard.set(newValue, forKey: channelKey) }
    }

    /// "1.2.3" → [1, 2, 3]；每段只取开头的数字（"1.0-beta" 的段算 0 号后缀、按 1 算）。
    /// 内测版号带后缀（"1.2.8-beta.1"）：基础段 [1,2,8] + 预发布后缀 "beta.1" 分开比，
    /// 这样 1.2.8-beta.1 不会比同号正式版 1.2.8 更新（beta.1 < beta.2 同号内比后缀数字）。
    private static func versionParts(_ version: String) -> [Int] {
        splitVersion(version).parts
    }

    /// "1.2.8-beta.1" → (parts: [1,2,8], pre: "beta.1")；"1.2.8" → (parts: [1,2,8], pre: nil)。
    private static func splitVersion(_ version: String) -> (parts: [Int], pre: String?) {
        let comps = version.split(separator: "-", maxSplits: 1)
        let parts = comps[0].split(separator: ".").map { part in
            let digits = part.prefix(while: { $0.isNumber })
            return Int(digits) ?? 0
        }
        return (parts, comps.count > 1 ? String(comps[1]) : nil)
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
            let info = try await api.fetchVersion(channel: channel)
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
            let info = try await api.fetchVersion(channel: channel)
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
