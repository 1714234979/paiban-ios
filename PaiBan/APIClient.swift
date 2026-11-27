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

/// GET /api/v1/auth/sms/status 返回的 data：{configured: Bool}。
struct SmsStatus: Decodable {
    var configured: Bool
}


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

    /// 直接按完整响应体解码（{ok, ...} 信封里 payload 字段不是 data 的接口用，
    /// 如反馈列表的 items、回复的 reply）；ok=false 时由调用方按 error 抛中文错误；
    /// 401 时用 Basic 重试一次（跟 request 同一套逻辑）。
    private func requestResponse<E: Decodable>(
        path: String,
        method: String = "GET",
        jsonBody: [String: Any]? = nil,
        retriedWithBasic: Bool = false
    ) async throws -> E {
        let url = try url(for: path)
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
            var retry = req
            let token = Data("\(creds.username):\(creds.password)".utf8).base64EncodedString()
            retry.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (retryData, retryResponse) = try await session.data(for: retry)
                return try decodeResponse(data: retryData, status: (retryResponse as? HTTPURLResponse)?.statusCode ?? 0)
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
        return try decodeResponse(data: data, status: status)
    }

    /// requestResponse 的解码：整包按 E 解，解不出按老规矩报中文错。
    private func decodeResponse<E: Decodable>(data: Data, status: Int) throws -> E {
        do {
            return try decoder.decode(E.self, from: data)
        } catch {
            if status == 401 { throw APIError.notLoggedIn }
            AppLogger.shared.log("解码失败（HTTP \(status)，\(data.count) 字节）", tag: "API")
            throw APIError(message: "服务器返回了看不懂的数据（HTTP \(status)）")
        }
    }

    // MARK: 登录 / 注册

    // MARK: - 手机号验证码登录（1.1.3）

    /// POST /api/v1/auth/sms/send — 发验证码（6 位、5 分钟有效）。
    /// 服务端限流：同一手机号 60 秒一次、每天最多 10 次；失败中文错误原样透传。
    /// scenario：发码场景，不传默认 login；忘记密码时传 reset（用重置密码模板 100003）。
    func sendSmsCode(phone: String, scenario: String? = nil) async throws {
        var body: [String: Any] = ["phone": phone]
        if let scenario { body["scenario"] = scenario }
        try await requestNoData(path: "/api/v1/auth/sms/send", method: "POST",
                                jsonBody: body)
    }

    /// GET /api/v1/auth/sms/status — 短信服务是否已开通（只返回 configured，
    /// 不含任何配置内容）。强制绑手机号的门先查这个：没开通时不硬拦，配好后自动变严格。
    func fetchSmsStatus() async throws -> Bool {
        let status: SmsStatus = try await request(path: "/api/v1/auth/sms/status")
        return status.configured
    }

    /// POST /api/v1/auth/sms/login — 手机号 + 验证码登录。
    /// 返回形同密码登录（{ok, user}，新注册还会带 apiKey）；成功后服务端发 7 天 session。
    /// 没有密码，不存 Keychain；管理员账号（role=admin）也可以登录 App（2026-11-24 新规矩）。
    @discardableResult
    func loginWithSms(phone: String, code: String) async throws -> PublicUser {
        guard baseURL != nil else { throw APIError.unreachable }
        let url = try url(for: "/api/v1/auth/sms/login")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["phone": phone, "code": code, "platform": "ios"])
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
            throw APIError(message: auth.error ?? "验证码不对或已过期")
        }
        return user
    }

    /// POST /api/v1/me/phone/bind — 已登录用户绑定手机号（发码验证后绑定）。
    /// 返回 {ok, data: publicUser}，Store 侧合并进当前用户（team/paySettings 不动）。
    func bindPhone(phone: String, code: String) async throws -> UserProfile {
        try await request(path: "/api/v1/me/phone/bind", method: "POST",
                          jsonBody: ["phone": phone, "code": code])
    }

    /// POST /api/v1/me/password/change — 改密码（先绑手机号，短信验证码验证身份）。
    /// 服务端限 30 天改一次，限期内调会报 429 并给出下次可改时间，错误原样透传。
    func changePassword(phone: String, code: String, newPassword: String) async throws -> UserProfile {
        try await request(path: "/api/v1/me/password/change", method: "POST",
                          jsonBody: ["phone": phone, "code": code, "newPassword": newPassword])
    }

    /// POST /api/v1/auth/password/reset — 忘记密码（公开接口，没登录时用）。
    /// 发码时传 scenario=reset（重置密码模板）；核验通过只改密码，不发 session、
    /// 不自动登录——让用户回登录页用新密码登录。
    func resetPassword(phone: String, code: String, newPassword: String) async throws {
        try await requestNoData(path: "/api/v1/auth/password/reset", method: "POST",
                                jsonBody: ["phone": phone, "code": code, "newPassword": newPassword])
    }

    /// POST /api/v1/auth/login — App 专用登录：
    /// 普通账号与管理员账号都能登录（2026-11-24 新规矩，admin 两边都能进）。
    /// 成功后服务端 Set-Cookie: paiban_session（7 天）。
    /// 注意：不要再用 /api/v1/admin/login，那个只给管理端（网页）用。
    @discardableResult
    func login(username: String, password: String) async throws -> PublicUser {
        guard baseURL != nil else { throw APIError.unreachable }
        let url = try url(for: "/api/v1/auth/login")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["username": username, "password": password, "platform": "ios"])
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
            // 服务端返回的错误（auth.error）原样透传给用户。
            throw APIError(message: auth.error ?? "账号或密码不对")
        }
        // 登录成功：把账号密码存进 Keychain，供以后 Basic 兜底。
        KeychainHelper.save(username: username, password: password)
        return user
    }

    /// POST /api/v1/auth/register — 公开注册，成功后同样发 session cookie。
    /// 1.2.6：昵称（displayName，可空）与短信验证码（code，服务端核验）一起交；
    /// 昵称空着服务端就用手机号当显示名。
    @discardableResult
    func register(username: String, password: String, displayName: String? = nil, code: String? = nil) async throws -> PublicUser {
        guard baseURL != nil else { throw APIError.unreachable }
        let url = try url(for: "/api/v1/auth/register")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "username": username, "password": password, "confirmPassword": password,
        ]
        if let displayName, !displayName.isEmpty { body["displayName"] = displayName }
        if let code, !code.isEmpty { body["code"] = code }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
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

    /// POST /api/v1/me/device —— 设备直连登记（1.2.7.004）。
    /// App 登录后把 identifierForVendor 登记到用户名下；小组件此后带
    /// X-Device-Id 就能拉数据，不用填密钥。只认 session 登录。
    /// 静默失败（不抛）：登记不上时小组件走缓存，不打扰用户。
    func registerDevice() async {
        guard let deviceId = UIDevice.current.identifierForVendor?.uuidString else { return }
        let _: DeviceRegisterResponse? = try? await request(path: "/api/v1/me/device", method: "POST",
                                                             jsonBody: ["deviceId": deviceId, "platform": "ios"])
    }

    /// PUT /api/v1/me/profile — 只传给定的字段（合并更新）。
    /// displayName：改显示名（≤32 字，空串清回用户名）；登录用的 username 不动。
    /// rotation：倒班设置（1.2.7.001：modeId/team/baseDate/teamNames/manualShifts 的字典；
    /// 服务端校验 modeId 必须是 5 种方式之一或 "manual"，team 必须是 A/B/C/D）。
    func updateProfile(team: String? = nil, paySettings: [String: Any]? = nil, onboardingDone: Bool? = nil, displayName: String? = nil, rotation: [String: Any]? = nil, displaySettings: [String: Any]? = nil) async throws -> UserProfile {
        var body: [String: Any] = [:]
        if let team { body["team"] = team }
        if let paySettings { body["paySettings"] = paySettings }
        if let onboardingDone { body["onboardingDone"] = onboardingDone }
        if let displayName { body["displayName"] = displayName }
        if let rotation { body["rotation"] = rotation }
        if let displaySettings { body["displaySettings"] = displaySettings }
        // PUT /me/profile 返回更新后的 profile（data 包装）。
        return try await request(path: "/api/v1/me/profile", method: "PUT", jsonBody: body)
    }

    // MARK: 倒班方式目录（1.2.7.001，第 23 条）

    /// GET /api/v1/rotation-modes —— 倒班方式目录（5 种四班三倒 + 即将推出的分类）。
    /// 服务端返回的目录与 App 内置的 RotationModes.fourThree 一致；App 优先用服务端的，
    /// 服务端没给（老版本）时用内置的。
    func fetchRotationModes() async throws -> [RotationMode] {
        struct ModesResponse: Decodable { var modes: [RotationMode]? }
        let resp: ModesResponse = try await request(path: "/api/v1/rotation-modes")
        return resp.modes ?? []
    }

    // MARK: 节假日（1.2.7.001，第 23 条）

    /// GET /api/v1/holidays?year= —— 服务端缓存的节假日数据（timor.tech 拉取、归一化）。
    /// kind = legal（法定/三薪）/ rest（普通放假）/ workday（调休上班日）。
    func fetchHolidays(year: Int) async throws -> HolidaysResponse {
        try await request(path: "/api/v1/holidays", query: ["year": String(year)])
    }

    // MARK: 共享班表（1.2.7.001，第 24 条）

    /// GET /api/v1/me/shares —— 我分享出去的 + 同事分享给我的。
    func fetchShares() async throws -> SharesResponse {
        try await request(path: "/api/v1/me/shares")
    }

    /// POST /api/v1/me/shares —— 分享我的基础日历给同事（toUsername 是对方账号名/手机号）。
    /// 只分享基础日历（方式/班组/基准日/班组名），不含调班/请假/加班、不含工资。
    func shareSchedule(toUsername: String, note: String? = nil) async throws -> ScheduleShare {
        var body: [String: Any] = ["toUsername": toUsername]
        if let note, !note.isEmpty { body["note"] = note }
        return try await request(path: "/api/v1/me/shares", method: "POST", jsonBody: body)
    }

    /// GET /api/v1/me/shares/:id?year=&month= —— 看一条分享的基础日历（指定月份）。
    func fetchShareMonth(id: String, year: Int, month: Int) async throws -> [ShareMonthDay] {
        struct ShareMonthResponse: Decodable {
            var share: ScheduleShare?
            var days: [ShareMonthDay]?
        }
        let resp: ShareMonthResponse = try await request(
            path: "/api/v1/me/shares/\(id)",
            query: ["year": String(year), "month": String(month)])
        return resp.days ?? []
    }

    /// DELETE /api/v1/me/shares/:id —— 撤销我发出的分享（或拒收发给我的）。
    func deleteShare(id: String) async throws {
        try await requestNoData(path: "/api/v1/me/shares/\(id)", method: "DELETE")
    }

    /// POST /api/v1/me/shares/:id/refresh —— 分享人基础轮次变了，更新快照。
    func refreshShare(id: String) async throws -> ScheduleShare {
        try await request(path: "/api/v1/me/shares/\(id)/refresh", method: "POST")
    }

    /// POST /api/v1/me/shares/:id/link —— 生成分享链接/口令（对方点开就能看基础日历）。
    func createShareLink(id: String) async throws -> String {
        struct LinkResponse: Decodable { var url: String?; var token: String? }
        let resp: LinkResponse = try await request(path: "/api/v1/me/shares/\(id)/link", method: "POST")
        return resp.url ?? ""
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
        let device = "\(await UIDevice.current.systemName) \(await UIDevice.current.systemVersion) (\(await UIDevice.current.model))"
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

    /// GET /api/v1/me/feedback — 我的反馈列表（只返回自己的，最新在前），每条带回复 thread。
    /// 返回体是 {ok, items}，不是 {ok, data}，所以走 requestResponse（见上）。
    func fetchMyFeedback() async throws -> [FeedbackItem] {
        let resp: FeedbackListResponse = try await requestResponse(path: "/api/v1/me/feedback")
        guard resp.ok else { throw APIError(message: resp.error ?? "加载我的反馈失败") }
        return resp.items ?? []
    }

    /// POST /api/v1/me/feedback/:file/reply — 给某条反馈继续回一句话（1–2000 字，
    /// 服务端校验，失败中文错误原样透传）。成功返回新那条回复。
    func postFeedbackReply(file: String, text: String) async throws -> FeedbackReply {
        let encoded = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file
        let resp: FeedbackReplyResponse = try await requestResponse(
            path: "/api/v1/me/feedback/\(encoded)/reply", method: "POST", jsonBody: ["text": text])
        guard resp.ok, let reply = resp.reply else {
            throw APIError(message: resp.error ?? "回复发送失败")
        }
        return reply
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

    // MARK: 调班互换（/me/swap，空间那套）

    /// GET /api/v1/me/teams/range?start=YYYY-MM-DD&days=N —— 四班同取：
    /// 从 start 起连续 N 天、四个班组的日程（调班候选卡片与还班日列表用）。
    func fetchTeamsRange(start: String, days: Int) async throws -> TeamsRangeResponse {
        try await request(path: "/api/v1/me/teams/range",
                          query: ["start": start, "days": String(days)])
    }

    /// POST /api/v1/me/swap —— 调班（1.2.9.001 第 31 条：空间那套，配对互换）：
    /// 替班日我休息、partner 替我上 partnerShift（对方那天最终的班）；
    /// 只写我自己的记录，不动对方账号。myShift 保留仅作兼容（新客户端不传）。
    /// paybackDate 为空 = 待还班（以后再补填），给了就同时写还班日（我上 paybackMyShift）。
    /// 成功返回 {coverDate, paybackDate}。
    func postSwap(date: String, myShift: String?, partner: String? = nil, partnerShift: String? = nil,
                  note: String?, paybackDate: String?, paybackMyShift: String?) async throws -> SwapSaveResult {
        var body: [String: Any] = ["date": date]
        if let myShift, !myShift.isEmpty { body["myShift"] = myShift }
        if let partner, !partner.isEmpty { body["partner"] = partner }
        if let partnerShift, !partnerShift.isEmpty { body["partnerShift"] = partnerShift }
        if let note, !note.isEmpty { body["note"] = note }
        if let paybackDate, !paybackDate.isEmpty { body["paybackDate"] = paybackDate }
        if let paybackMyShift, !paybackMyShift.isEmpty { body["paybackMyShift"] = paybackMyShift }
        return try await request(path: "/api/v1/me/swap", method: "POST", jsonBody: body)
    }

    /// POST /api/v1/me/swap/payback —— 给待还班的调班补填还班日。
    func postSwapPayback(coverDate: String, paybackDate: String, myShift: String) async throws {
        let body: [String: Any] = ["coverDate": coverDate, "paybackDate": paybackDate, "myShift": myShift]
        try await requestNoData(path: "/api/v1/me/swap/payback", method: "POST", jsonBody: body)
    }

    /// POST /api/v1/me/swap/to-leave —— 待还班的调班一直不还，转为请假（对方的顶岗保留）。
    func postSwapToLeave(date: String, type: String?, note: String?) async throws {
        var body: [String: Any] = ["date": date]
        if let type, !type.isEmpty { body["type"] = type }
        if let note, !note.isEmpty { body["note"] = note }
        try await requestNoData(path: "/api/v1/me/swap/to-leave", method: "POST", jsonBody: body)
    }

    /// POST /api/v1/me/leave/cover —— 请假日安排顶岗：对方替我上我那天的班。
    func postLeaveCover(date: String, partner: String, partnerShift: String, note: String?) async throws {
        var body: [String: Any] = ["date": date, "partner": partner, "partnerShift": partnerShift]
        if let note, !note.isEmpty { body["note"] = note }
        try await requestNoData(path: "/api/v1/me/leave/cover", method: "POST", jsonBody: body)
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

    /// POST /api/v1/me/pay/month — 改自己当月录入数里的某一个字段
    ///（1.2.7 起每人改自己的：老爷改全局，老爷以外改自己账号的单月录入）
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
    /// 1.2.8 内测渠道：每次带 platform=ios；channel 传内测偏好（beta/stable，默认 stable）。
    /// 已登录时请求带 session cookie（401 时 Basic 兜底），服务端据此回 isBetaTester；
    /// 没登录或不是内测人员，服务端永远回正式版。回包的 data 里可能带 isBetaTester/hasBeta/channel。
    func fetchVersion(channel: String? = nil) async throws -> VersionInfo {
        var query: [String: String] = ["platform": "ios"]
        if let channel, !channel.isEmpty { query["channel"] = channel }
        return try await request(path: ServerConfig.versionPath, query: query)
    }
}
