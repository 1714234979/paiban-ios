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

    /// 内测渠道版本（1.3.0.012，弹窗根因修）：服务端公开回包里就有
    /// data.beta.ios / data.beta.android（各含 version/downloadUrl/releaseNotes），
    /// 不用认证也能读到。之前 App 根本没解这个字段，内测更新全指望服务端把
    /// latestVersion 换成内测版号——而服务端只在「登录后带认证 + 是内测人员」
    /// 时才换；版本请求一旦没带上有效 session（启动时序、切线路、7 天 session
    /// 过期、短信登录没 Keychain 密码兜底），服务端就回正式版 1.3.0，比装的
    /// 1.3.0.010 旧，弹窗永远不弹。007 的 installedChannel 只修了「问哪条线」，
    /// 没修这个认证依赖。这次内测用户直接读公开的 beta.ios 比，不再依赖认证。
    var beta: BetaChannelVersions?

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

/// 内测渠道某平台的版本（1.3.0.012）：服务端公开回包 data.beta.ios /
/// data.beta.android 里就是这个形状，不用认证也能读到。
struct BetaVersionInfo: Codable, Equatable {
    var version: String?
    var downloadUrl: String?
    var releaseNotes: String?
}

/// 内测渠道两平台的版本（1.3.0.012）。
struct BetaChannelVersions: Codable, Equatable {
    var ios: BetaVersionInfo?
    var android: BetaVersionInfo?
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

    /// 当前装的版本属于哪个渠道（按版本号定）：四段号或带 beta 后缀是内测版，三段号是正式版。
    /// 和存的更新偏好（channel）是两回事——偏好只决定查更新走哪条线；装的版本才是现在用的那条线。
    /// 1.2.7.009 根因：偏好只在确认切换时才写，从不跟装的版本同步；一旦脱节（重装、手动装包），
    /// 设置页就把错的那个标成已选中，点它时 guard 直接 return，看着就是点不动。
    /// 选中态和 guard 必须按装的版本定，偏好是什么都不影响点不点得动。
    static var installedChannel: String {
        channelLabel(for: currentVersion) == "内测版" ? "beta" : "stable"
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

    /// 查更新的结果（1.3.0.012）：必须区分「确实没新版」和「查失败了」——
    /// 查失败（没网、服务器不通）不能清掉已经排队等着弹的更新提示，否则切回前台
    /// 时一次瞬断就把弹窗吞了。Store 里只在 .upToDate 时清 pendingUpdate，
    /// .failed 时保留已有的 pendingUpdate。
    enum CheckResult {
        case updateAvailable(VersionInfo)
        case upToDate
        case failed
    }

    /// 某条线最新可装的版本（版号 + 链接 + 说明）：内测线直接读回包里公开的
    /// beta.ios（不用等服务端按认证换 latestVersion，1.3.0.012 弹窗根因修），
    /// 正式线读 latestVersion。没发这条线 / 没链接时返回 nil。
    private static func offeredVersion(for channel: String, in info: VersionInfo) -> (version: String, downloadUrl: String, releaseNotes: String?)? {
        if channel == "beta" {
            guard let v = info.beta?.ios?.version, !v.isEmpty,
                  let u = info.beta?.ios?.downloadUrl, !u.trimmingCharacters(in: .whitespaces).isEmpty,
                  URL(string: u) != nil else { return nil }
            return (v, u, info.beta?.ios?.releaseNotes)
        }
        guard info.hasDownloadURL, let u = info.downloadUrl else { return nil }
        return (info.latestVersion, u, info.releaseNotes)
    }

    /// 按装的版本那条线评回包：内测版看公开的 beta.ios，正式版看 latestVersion。
    /// 有新版且有下载链接 → .updateAvailable（把版号/链接/说明换成那条线的），
    /// 否则 .upToDate。调用方（Store）按 CheckResult 决定清不清除排队的提示。
    private static func evaluate(info: VersionInfo) -> CheckResult {
        let channel = installedChannel
        guard let offered = offeredVersion(for: channel, in: info) else {
            AppLogger.shared.log("查更新：装的 \(currentVersion)（\(channel)），那条线没发新版", tag: "Update")
            return .upToDate
        }
        AppLogger.shared.log("查更新：装的 \(currentVersion)（\(channel)），线上 \(offered.version)", tag: "Update")
        guard isNewer(latest: offered.version, than: currentVersion) else { return .upToDate }
        var out = info
        out.latestVersion = offered.version
        out.downloadUrl = offered.downloadUrl
        out.releaseNotes = offered.releaseNotes ?? info.releaseNotes
        return .updateAvailable(out)
    }

    /// 启动后调用一次：有新版 → .updateAvailable；确实没新版 → .upToDate；
    /// 查失败 → .failed。失败不弹错，也不清排队的提示（见 CheckResult）。
    /// 约定（canonical）：downloadUrl 为空表示没有更新——即使 latestVersion 高于当前版，
    /// 只要 downloadUrl 为空就不弹。失败（没网、服务器不通、清单格式不对）返回 .failed。
    /// 1.3.0.007：查更新走装的版本那条线（installedChannel），不用存的偏好 channel——
    /// 偏好只在设置页确认切换时才写，从不跟装的版本同步（1.2.7.009 同一个毛病）；
    /// 一旦脱节（偏好是 stable、装的是 1.3.0.005 内测版），查更新拿到的就是正式版 1.3.0，
    /// 1.3.0 比 1.3.0.005 旧，isNewer 直接 false，内测版 006 永远弹不出来。
    /// 装的版本才是现在用的那条线，查更新必须按它走。
    /// 1.3.0.012：光问对线还不够——内测线还要服务端按认证换 latestVersion 才回内测版号，
    /// 请求没带有效 session 时服务端照旧回正式版 1.3.0，弹窗还是不弹。这次内测线直接读
    /// 回包里公开的 beta.ios（见 offeredVersion），不再依赖认证。
    static func checkAfterLaunch(api: APIClient) async -> CheckResult {
        guard !dismissedToday else { return .upToDate }
        do {
            let info = try await api.fetchVersion(channel: installedChannel)
            return evaluate(info: info)
        } catch {
            AppLogger.shared.log("查更新失败：\(error.localizedDescription)", tag: "Update")
            return .failed
        }
    }

    /// 两个版本号是不是同一个（数字段逐段比，缺段按 0；预发布后缀也比）。
    /// 1.2.7 与 1.2.7.001 不是同一个（第 4 段 0 vs 1）。
    static func isSameVersion(_ a: String, _ b: String) -> Bool {
        let av = splitVersion(a), bv = splitVersion(b)
        let count = max(av.parts.count, bv.parts.count)
        for i in 0..<count {
            let x = i < av.parts.count ? av.parts[i] : 0
            let y = i < bv.parts.count ? bv.parts[i] : 0
            if x != y { return false }
        }
        return av.pre == bv.pre
    }

    /// 版本号对应的渠道名（1.2.7.002）：四段号（1.2.7.001）或带 beta 后缀的是内测版，
    /// 三段号（1.2.7）是正式版。内测版号从 1.2.7.001 开始，四段式；正式版三段式。
    static func channelLabel(for version: String) -> String {
        let v = splitVersion(version)
        if v.parts.count >= 4 { return "内测版" }
        if let pre = v.pre, pre.contains("beta") { return "内测版" }
        return "正式版"
    }

    /// 切渠道后立刻按新渠道查一次（1.2.7.002）：渠道不同就是不同的线，
    /// 新渠道的版本和装的不一样就推出来（哪怕数字上更低，如从 1.2.7.001 切到正式版 1.2.7），
    /// 让用户自己决定装不装；只有版本完全一样才说已是最新版本。
    /// 1.3.0.012：内测线直接读公开的 beta.ios（见 offeredVersion），不用等服务端按认证换
    /// latestVersion——切到内测时请求还没带上新身份也照样能看到内测版号。
    static func checkAfterChannelSwitch(api: APIClient, channel: String) async -> ManualResult {
        do {
            let info = try await api.fetchVersion(channel: channel)
            guard let offered = offeredVersion(for: channel, in: info) else { return .upToDate }
            guard !isSameVersion(offered.version, currentVersion) else { return .upToDate }
            var out = info
            out.latestVersion = offered.version
            out.downloadUrl = offered.downloadUrl
            out.releaseNotes = offered.releaseNotes ?? info.releaseNotes
            return .updateAvailable(out)
        } catch {
            return .upToDate
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
    /// 1.3.0.007：跟 checkAfterLaunch 同理，走装的版本那条线（installedChannel），
    /// 不用存的偏好——不然偏好是 stable 时手动查也只能查到正式版，内测版永远查不出来。
    /// 1.3.0.012：内测线直接读公开的 beta.ios（见 offeredVersion），不再依赖认证。
    static func checkManually(api: APIClient) async -> ManualResult {
        do {
            let info = try await api.fetchVersion(channel: installedChannel)
            switch evaluate(info: info) {
            case .updateAvailable(let offered):
                return .updateAvailable(offered)
            case .upToDate, .failed:
                return .upToDate
            }
        } catch {
            return .upToDate
        }
    }
}
