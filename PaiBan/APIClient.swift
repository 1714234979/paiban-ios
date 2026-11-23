import Foundation
import Security
import UIKit

// MARK: - 错误

/// API 错误：message 直接展示给用户（服务端返回的中文错误原样透传）。
struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }

    static let unreachable = APIError(message: "连不上服务器（云服务器与 NAS 备份都试过了），请检查网络后再试")
    static let notLoggedIn = APIError(message: "未登录，请先登录")
    /// 管理账号不能进 App（CONTRACT.md 账号规矩）：服务端 403 与客户端拦截共用同一句提示。
    static let adminBlocked = APIError(message: "管理账号不能登录 App，请使用用户账号登录")
}

// MARK: - 通用信封

/// 服务端通用返回：{ok, data} 或 {ok:false, error}。
struct Envelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T?
    let error: String?
}

/// 登录 / 注册返回：{ok, user} 或 {ok:false, error}（注意：这里是 user，不是 data）。
struct AuthResponse: Decodable {
    let ok: Bool
    let user: PublicUser?
    let apiKey: String?
    let error: String?
    let note: String?
}

/// 空 data（只关心 ok/error 的接口）。
struct EmptyData: Decodable {}


// MARK: - Keychain（只存 Basic 认证用的账号密码，不存 session）

/// 最小 Keychain 封装：存取 / 删除一条通用密码（service 固定）。
enum KeychainHelper {
    private static let service = "com.paiban.app.basic-auth"

    static func save(username: String, password: String) {
        let account = username
        guard let data = password.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        SecItemAdd(attrs as CFDictionary, nil)
    }

    /// 返回 (username, password)，没有则返回 nil。
    static func load() -> (username: String, password: String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let dict = item as? [String: Any],
              let account = dict[kSecAttrAccount as String] as? String,
              let data = dict[kSecValueData as String] as? Data,
              let password = String(data: data, encoding: .utf8)
        else { return nil }
        return (account, password)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}


// MARK: - API 客户端

/// 排班空间 API 客户端（CONTRACT.md v1）。
/// 认证：优先 session cookie（HTTPCookieStorage 自动存取，7 天有效）；
/// cookie 失效（401）时，若 Keychain 里有账号密码，自动用 Basic 认证重试一次。
final class APIClient {

    static let shared = APIClient()

    /// 当前在用的服务器根地址（由 ServerConfig.resolve() 决定）。
    var baseURL: String?

    /// 当前线路（展示用）。
    var serverKind: ServerKind = .cloud

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        // 默认就用 shared HTTPCookieStorage，session cookie 自动持久化。
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: config)
    }

    // MARK: 选路

    /// 探测并确定服务器地址。返回是否找到可达地址。
    @discardableResult
    func resolveServer() async -> Bool {
        if let found = await ServerConfig.resolve() {
            baseURL = found.baseURL
            serverKind = found.kind
            return true
        }
        return false
    }

    // MARK: 底层请求

    private func url(for path: String, query: [String: String] = [:]) throws -> URL {
        guard let base = baseURL, var components = URLComponents(string: base + path) else {
            throw APIError.unreachable
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.unreachable }
        return url
    }

    /// 发请求并解出 data；ok=false 时抛中文 error；401 时用 Basic 重试一次。
    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        query: [String: String] = [:],
        jsonBody: [String: Any]? = nil,
        retriedWithBasic: Bool = false
    ) async throws -> T {
        let url = try url(for: path, query: query)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let jsonBody {
            req.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            AppLogger.shared.log("\(method) \(path) 联不上服务器", tag: "API")
            throw APIError.unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, !retriedWithBasic, let creds = KeychainHelper.load() {
            // cookie 失效：用 Basic 认证重试一次。
            var retry = req
            let token = Data("\(creds.username):\(creds.password)".utf8).base64EncodedString()
            retry.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (retryData, retryResponse) = try await session.data(for: retry)
                return try decodeEnvelope(data: retryData, status: (retryResponse as? HTTPURLResponse)?.statusCode ?? 0)
            } catch let apiError as APIError {
                throw apiError
            } catch {
                AppLogger.shared.log("\(method) \(path) Basic 重试也联不上服务器", tag: "API")
                throw APIError.unreachable
            }
        }
        if status >= 400 {
            AppLogger.shared.log("\(method) \(path) HTTP \(status)", tag: "API")
        }
        return try decodeEnvelope(data: data, status: status)
    }

    private func decodeEnvelope<T: Decodable>(data: Data, status: Int) throws -> T {
        let envelope: Envelope<T>
        do {
            envelope = try decoder.decode(Envelope<T>.self, from: data)
        } catch {
            if status == 401 { throw APIError.notLoggedIn }
            AppLogger.shared.log("解码失败（HTTP \(status)，\(data.count) 字节）", tag: "API")
            throw APIError(message: "服务器返回了看不懂的数据（HTTP \(status)）")
        }
        if envelope.ok, let value = envelope.data {
            return value
        }
        throw APIError(message: envelope.error ?? "请求失败（HTTP \(status)）")
    }

    /// 不带 data 的请求（只关心 ok/error，如删除类接口）：ok=false 时照样抛中文错误。
    private func requestNoData(path: String, method: String = "GET",
                               query: [String: String] = [:],
                               jsonBody: [String: Any]? = nil) async throws {
        let url = try url(for: path, query: query)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let jsonBody {
            req.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, let creds = KeychainHelper.load() {
            var retry = req
            let token = Data("\(creds.username):\(creds.password)".utf8).base64EncodedString()
            retry.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (retryData, retryResponse) = try await session.data(for: retry)
                try checkEnvelope(data: retryData, status: (retryResponse as? HTTPURLResponse)?.statusCode ?? 0)
                return
            } catch let apiError as APIError {
                throw apiError
            } catch {
                throw APIError.unreachable
            }
        }
        try checkEnvelope(data: data, status: status)
    }

    private func checkEnvelope(data: Data, status: Int) throws {
        let envelope: Envelope<EmptyData>
        do {
            envelope = try decoder.decode(Envelope<EmptyData>.self, from: data)
        } catch {
            if status == 401 { throw APIError.notLoggedIn }
            throw APIError(message: "服务器返回了看不懂的数据（HTTP \(status)）")
        }
        if !envelope.ok {
            throw APIError(message: envelope.error ?? "请求失败（HTTP \(status)）")
        }
    }

    // MARK: 登录 / 注册

    /// POST /api/v1/auth/login — App 专用登录（CONTRACT.md 账号规矩）：
    /// 只允许 role=user 的普通账号；role=admin 返回 403，错误原样透传。
    /// 成功后服务端 Set-Cookie: paiban_session（7 天）。
    /// 注意：不要再用 /api/v1/admin/login，那个只给管理端（网页）用。
    @discardableResult
    func login(username: String, password: String) async throws -> PublicUser {
        guard baseURL != nil else { throw APIError.unreachable }
        let url = try url(for: "/api/v1/auth/login")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let auth: AuthResponse
        do {
            auth = try decoder.decode(AuthResponse.self, from: data)
        } catch {
            throw APIError(message: "登录失败（HTTP \(status)）")
        }
        guard auth.ok, let user = auth.user else {
            // 服务端 403 的管理账号提示（auth.error）原样透传给用户。
            throw APIError(message: auth.error ?? "账号或密码不对")
        }
        // 客户端纵深防御：万一服务端放行了 admin（旧版/异常），这里拦住——
        // 不存 Keychain、不进 App，并清掉可能已发的 session cookie。
        // 张晓文与普通同事的 role 都是 "user"，不会触发这一支。
        if user.role == "admin" {
            clearSessionCookies()
            throw APIError.adminBlocked
        }
        // 登录成功：把账号密码存进 Keychain，供以后 Basic 兜底。
        KeychainHelper.save(username: username, password: password)
        return user
    }

    /// POST /api/v1/auth/register — 公开注册，成功后同样发 session cookie。
    @discardableResult
    func register(username: String, password: String) async throws -> PublicUser {
        guard baseURL != nil else { throw APIError.unreachable }
        let url = try url(for: "/api/v1/auth/register")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "username": username, "password": password, "confirmPassword": password,
        ])
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let auth: AuthResponse
        do {
            auth = try decoder.decode(AuthResponse.self, from: data)
        } catch {
            throw APIError(message: "注册失败（HTTP \(status)）")
        }
        guard auth.ok, let user = auth.user else {
            throw APIError(message: auth.error ?? "注册失败")
        }
        KeychainHelper.save(username: username, password: password)
        return user
    }

    /// POST /api/v1/auth/logout — 清服务端 session + 本地 cookie + Keychain。
    /// 说明：服务端目前只在合同里定义了 /api/v1/auth/login；/auth/logout 与
    /// 旧 /api/v1/admin/logout 同形（只清 session、不验角色），请 API 端补上；
    /// 即便服务端还没接这个接口，调用失败也会被忽略，本地 cookie 与 Keychain
    /// 照样清干净，App 侧退出登录不受影响。
    func logout() async {
        if baseURL != nil, let url = try? url(for: "/api/v1/auth/logout") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            _ = try? await session.data(for: req)
        }
        clearSessionCookies()
        KeychainHelper.delete()
    }

    /// 只清本地的 paiban_session cookie（登录拦截与退出共用）。
    private func clearSessionCookies() {
        if let base = baseURL, let baseURLObject = URL(string: base) {
            for cookie in HTTPCookieStorage.shared.cookies ?? [] where cookie.domain.contains(baseURLObject.host ?? "") {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        // session cookie 的域名可能是隧道域名，上面按 host 删可能漏掉；兜底全清本应用的 paiban_session。
        for cookie in HTTPCookieStorage.shared.cookies ?? [] where cookie.name == "paiban_session" {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    // MARK: /me/*

    /// GET /api/v1/me
    func fetchMe() async throws -> UserProfile {
        try await request(path: "/api/v1/me")
    }

    /// PUT /api/v1/me/profile — 只传给定的字段（合并更新）。
    func updateProfile(team: String? = nil, paySettings: [String: Any]? = nil, onboardingDone: Bool? = nil) async throws -> UserProfile {
        var body: [String: Any] = [:]
        if let team { body["team"] = team }
        if let paySettings { body["paySettings"] = paySettings }
        if let onboardingDone { body["onboardingDone"] = onboardingDone }
        // PUT /me/profile 返回更新后的 profile（data 包装）。
        return try await request(path: "/api/v1/me/profile", method: "PUT", jsonBody: body)
    }

    /// GET /api/v1/me/team-history
    func fetchTeamHistory() async throws -> [TeamHistoryEntry] {
        try await request(path: "/api/v1/me/team-history")
    }

    /// POST /api/v1/me/team-history
    func addTeamHistory(team: String, effectiveFrom: String) async throws -> [TeamHistoryEntry] {
        try await request(path: "/api/v1/me/team-history", method: "POST",
                          jsonBody: ["team": team, "effectiveFrom": effectiveFrom])
    }

    /// DELETE /api/v1/me/team-history?effectiveFrom=YYYY-MM-DD
    func deleteTeamHistory(effectiveFrom: String) async throws -> [TeamHistoryEntry] {
        try await request(path: "/api/v1/me/team-history", method: "DELETE",
                          query: ["effectiveFrom": effectiveFrom])
    }

    /// GET /api/v1/me/day?date=YYYY-MM-DD
    func fetchDay(date: String) async throws -> DaySchedule {
        try await request(path: "/api/v1/me/day", query: ["date": date])
    }

    /// GET /api/v1/me/month?year=&month=
    func fetchMonth(year: Int, month: Int) async throws -> MonthSchedule {
        try await request(path: "/api/v1/me/month",
                          query: ["year": String(year), "month": String(month)])
    }

    /// GET /api/v1/config —— 工资配置（pay 一节），本地算工资的输入。
    /// 注意此接口要认证（无会话会 401，走 Basic 重试）；返回的 data 只取 pay。
    func fetchPayConfig() async throws -> PayConfigData {
        let resp: ServerConfigData = try await request(path: "/api/v1/config")
        return resp.pay ?? PayConfigData()
    }

    /// POST /api/v1/me/feedback — 提交反馈：正文 + 最近 24 小时运行日志，服务端写到 NAS 的反馈文件夹。
    func sendFeedback(message: String, logs: String, type: String = "bug", location: String = "排班页", imageBase64: String? = nil) async throws {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let device = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion) (\(UIDevice.current.model))"
        var body: [String: Any] = [
            "message": message,
            "logs": logs,
            "appVersion": "\(appVersion) (\(build))",
            "device": device,
            "type": type,
            "location": location,
        ]
        if let imageBase64 { body["image"] = imageBase64 }
        try await requestNoData(path: "/api/v1/me/feedback", method: "POST", jsonBody: body)
    }

    /// GET /api/v1/me/range?start=YYYY-MM-DD&days=N —— 连续若干天的 day 对象。
    /// 服务端返回 {team, start, days} 对象（旧版按数组解会一直失败、走兜底）。
    func fetchRangeDays(start: String, days: Int) async throws -> [DaySchedule] {
        let resp: RangeResponse = try await request(path: "/api/v1/me/range",
                          query: ["start": start, "days": String(days)])
        return resp.days ?? []
    }

    /// GET /api/v1/me/pay?year=&month= —— 仅作本地算的兜底（本地算不出时才走服务端）。
    func fetchPay(year: Int, month: Int) async throws -> PayMonth {
        try await request(path: "/api/v1/me/pay",
                          query: ["year": String(year), "month": String(month)])
    }

    /// GET /api/v1/me/swaps?year=&month=
    func fetchSwaps(year: Int, month: Int) async throws -> [SwapRecord] {
        try await request(path: "/api/v1/me/swaps",
                          query: ["year": String(year), "month": String(month)])
    }

    /// GET /api/v1/me/leaves?year=&month=
    func fetchLeaves(year: Int, month: Int) async throws -> [LeaveRecord] {
        try await request(path: "/api/v1/me/leaves",
                          query: ["year": String(year), "month": String(month)])
    }

    /// POST /api/v1/me/override — 成功返回当天 day 对象。
    func postOverride(date: String, shift: String, note: String?, partner: String?, partnerShift: String?) async throws -> DaySchedule {
        var body: [String: Any] = ["date": date, "shift": shift]
        if let note, !note.isEmpty { body["note"] = note }
        if let partner, !partner.isEmpty { body["partner"] = partner }
        if let partnerShift, !partnerShift.isEmpty { body["partnerShift"] = partnerShift }
        return try await request(path: "/api/v1/me/override", method: "POST", jsonBody: body)
    }

    /// DELETE /api/v1/me/override?date=YYYY-MM-DD
    func deleteOverride(date: String) async throws {
        try await requestNoData(path: "/api/v1/me/override", method: "DELETE", query: ["date": date])
    }

    /// POST /api/v1/me/leave
    func postLeave(date: String, type: String?, note: String?) async throws {
        var body: [String: Any] = ["date": date]
        if let type, !type.isEmpty { body["type"] = type }
        if let note, !note.isEmpty { body["note"] = note }
        try await requestNoData(path: "/api/v1/me/leave", method: "POST", jsonBody: body)
    }

    /// POST /api/v1/me/leave/range
    func postLeaveRange(start: String, end: String, type: String?, note: String?) async throws {
        var body: [String: Any] = ["start": start, "end": end]
        if let type, !type.isEmpty { body["type"] = type }
        if let note, !note.isEmpty { body["note"] = note }
        try await requestNoData(path: "/api/v1/me/leave/range", method: "POST", jsonBody: body)
    }

    /// DELETE /api/v1/me/leave?date=YYYY-MM-DD
    func deleteLeave(date: String) async throws {
        try await requestNoData(path: "/api/v1/me/leave", method: "DELETE", query: ["date": date])
    }

    // MARK: 加班（/me/overtime）

    /// GET /api/v1/me/overtime?year=&month=
    func fetchOvertime(year: Int, month: Int) async throws -> [OvertimeRecord] {
        try await request(path: "/api/v1/me/overtime",
                          query: ["year": String(year), "month": String(month)])
    }

    /// POST /api/v1/me/overtime — 成功返回当天那条加班记录（服务端已算好时长）。
    func postOvertime(date: String, start: String, end: String, note: String?) async throws -> OvertimeRecord {
        var body: [String: Any] = ["date": date, "start": start, "end": end]
        if let note, !note.isEmpty { body["note"] = note }
        return try await request(path: "/api/v1/me/overtime", method: "POST", jsonBody: body)
    }

    /// DELETE /api/v1/me/overtime?date=YYYY-MM-DD
    func deleteOvertime(date: String) async throws {
        try await requestNoData(path: "/api/v1/me/overtime", method: "DELETE", query: ["date": date])
    }

    /// POST /api/v1/me/pay/month — 老爷改自己当月录入数里的某一个字段
    ///（科室绩效 / 绩效系数 / 奖金系数 / 加班天数 / 水电费）。value 传 nil 发 null，清掉该覆盖值。
    /// 成功返回重算后的当月工资。
    func postPayMonthField(monthKey: String, field: PayRecordField, value: Double?) async throws -> PayMonth {
        var body: [String: Any] = ["monthKey": monthKey]
        if let value {
            body[field.rawValue] = value
        } else {
            body[field.rawValue] = NSNull()
        }
        return try await request(path: "/api/v1/me/pay/month", method: "POST", jsonBody: body)
    }

    // MARK: 版本清单（公开接口，不用认证）

    /// GET <baseURL>/api/v1/version → {ok, data: {latestVersion, releaseNotes, downloadUrl, extractionCode}}。
    /// 清单地址跟 baseURL 走（见 ServerConfig.versionPath），downloadUrl 与 extractionCode 由服务端配。
    func fetchVersion() async throws -> VersionInfo {
        try await request(path: ServerConfig.versionPath)
    }
}
