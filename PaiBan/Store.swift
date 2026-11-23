import Foundation
import SwiftUI

// MARK: - 本地缓存

/// App 沙盒 Documents 下、按用户 id 分文件的缓存：
/// 存 profile + 最近一个月的 month/pay + swaps/leaves。
/// 启动时先读缓存立刻显示，再后台刷新并写回。
struct CachedData: Codable {
    var user: UserProfile?
    var month: MonthSchedule?
    var pay: PayMonth?
    var swaps: [SwapRecord]?
    var leaves: [LeaveRecord]?
    var savedAt: Date?
}

enum CacheStore {
    private static func fileURL(userId: String) -> URL? {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent("paiban-cache-\(userId).json")
    }

    static func load(userId: String) -> CachedData? {
        guard let url = fileURL(userId: userId),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CachedData.self, from: data)
    }

    static func save(userId: String, cache: CachedData) {
        guard let url = fileURL(userId: userId) else { return }
        var copy = cache
        copy.savedAt = Date()
        if let data = try? JSONEncoder().encode(copy) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func delete(userId: String) {
        guard let url = fileURL(userId: userId) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - App 状态

/// 全 App 唯一的状态容器：当前用户、月份、缓存的月排班/工资/调班/请假、登录态。
@MainActor
final class AppStore: ObservableObject {

    let api = APIClient.shared

    // 登录态
    @Published var isLoggedIn = false
    @Published var user: UserProfile?
    @Published var isStarting = true          // 启动中（正在选路 / 试登录）
    @Published var startupError: String?

    // 服务器
    @Published var serverBaseURL: String?
    @Published var serverKind: ServerKind = .tailscale
    @Published var serverReachable = false

    // 离线：服务器连不上时用缓存顶着，界面上显示“离线缓存”。
    @Published var isOffline = false
    @Published var cacheSavedAt: Date?

    // 排班
    @Published var currentMonth = Date()              // 当前看的月份（Date 取当月 1 号即可）
    @Published var viewTeam: String = "B"             // 日历顶部的班组切换（可看别的班）
    @Published var month: MonthSchedule?
    @Published var swaps: [SwapRecord] = []
    @Published var leaves: [LeaveRecord] = []
    @Published var isLoadingMonth = false

    // 工资（默认看上个月）
    @Published var payYearMonth: (year: Int, month: Int) = DateUtil.lastMonth()
    @Published var pay: PayMonth?
    @Published var payYearData: PayYear?
    @Published var isLoadingPay = false

    // 今日
    @Published var todayDay: DaySchedule?
    @Published var tomorrowDay: DaySchedule?
    @Published var weekDays: [DaySchedule] = []
    @Published var quiet: QuietInfo?

    // App 内更新提示
    @Published var pendingUpdate: VersionInfo?
    @Published var updateNotice: String?

    @Published var errorMessage: String?

    private let lastUserIdKey = "paiban.lastUserId"

    var myTeam: String { user?.displayTeam ?? "B" }

    var currentYearMonth: (year: Int, month: Int) {
        DateUtil.yearMonth(of: currentMonth)
    }

    // MARK: 启动

    /// 启动流程：选路 → 试 session 登录（cookie 还在就直接进）→ 读缓存立刻显示 → 后台刷新。
    func startup() async {
        isStarting = true
        startupError = nil
        let reachable = await api.resolveServer()
        serverReachable = reachable
        serverBaseURL = api.baseURL
        serverKind = api.serverKind
        guard reachable else {
            // 连不上服务器：有缓存就离线进，没有就报连不上。
            isStarting = false
            if let lastId = UserDefaults.standard.string(forKey: lastUserIdKey),
               let cache = CacheStore.load(userId: lastId), cache.user != nil {
                applyCache(cache)
                isLoggedIn = true
                isOffline = true
            } else {
                startupError = "连不上服务器（隧道 / Tailscale / 局域网都试过了），请检查网络后再试。"
            }
            return
        }
        do {
            let me = try await api.fetchMe()
            // 纵深防御：旧版 App 用 admin/login 留下的 session 若还是 admin，
            // 不进 App，清掉 session 并报同一句提示。
            if me.isAdmin {
                await api.logout()
                isStarting = false
                isLoggedIn = false
                startupError = APIError.adminBlocked.message
                return
            }
            user = me
            isLoggedIn = true
            viewTeam = me.displayTeam
            UserDefaults.standard.set(me.id ?? me.username ?? "", forKey: lastUserIdKey)
            loadCacheForCurrentUser()
            isStarting = false
            await refreshAll()
            await checkForUpdateAfterLaunch()
        } catch {
            isStarting = false
            // session 失效或未登录：有缓存也不自动进（账号可能换了），回登录页。
            // 但如果是纯网络问题且有缓存，仍可离线看。
            if let apiError = error as? APIError, apiError.message == APIError.unreachable.message,
               let lastId = UserDefaults.standard.string(forKey: lastUserIdKey),
               let cache = CacheStore.load(userId: lastId), cache.user != nil {
                applyCache(cache)
                isLoggedIn = true
                isOffline = true
            } else {
                isLoggedIn = false
            }
        }
    }

    // MARK: 登录 / 注册 / 退出

    func login(username: String, password: String) async throws {
        if !serverReachable, !(await api.resolveServer()) {
            throw APIError.unreachable
        }
        serverBaseURL = api.baseURL
        serverKind = api.serverKind
        serverReachable = true
        _ = try await api.login(username: username, password: password)
        let me = try await api.fetchMe()
        // 客户端纵深防御（第二道）：登录返回的 role 是 admin 时拒绝进 App，
        // 清掉刚建的 session 与 Keychain，显示同一句提示。
        // 张晓文与普通同事的 role 都是 "user"，不会触发这一支。
        if me.isAdmin {
            await api.logout()
            throw APIError.adminBlocked
        }
        user = me
        isLoggedIn = true
        isOffline = false
        viewTeam = me.displayTeam
        UserDefaults.standard.set(me.id ?? me.username ?? "", forKey: lastUserIdKey)
        loadCacheForCurrentUser()
        await refreshAll()
        await checkForUpdateAfterLaunch()
    }

    func register(username: String, password: String) async throws {
        if !serverReachable, !(await api.resolveServer()) {
            throw APIError.unreachable
        }
        serverBaseURL = api.baseURL
        serverKind = api.serverKind
        serverReachable = true
        _ = try await api.register(username: username, password: password)
        let me = try await api.fetchMe()
        user = me
        isLoggedIn = true
        isOffline = false
        viewTeam = me.displayTeam
        UserDefaults.standard.set(me.id ?? me.username ?? "", forKey: lastUserIdKey)
        loadCacheForCurrentUser()
        await refreshAll()
        await checkForUpdateAfterLaunch()
    }

    /// 退出登录：清服务端 session + 本地该用户的缓存 + Keychain 里的账号密码。
    func logout() async {
        let userId = user?.id ?? user?.username
        await api.logout()
        if let userId { CacheStore.delete(userId: userId) }
        UserDefaults.standard.removeObject(forKey: lastUserIdKey)
        user = nil
        isLoggedIn = false
        isOffline = false
        month = nil
        pay = nil
        payYearData = nil
        swaps = []
        leaves = []
        todayDay = nil
        tomorrowDay = nil
        weekDays = []
        quiet = nil
        cacheSavedAt = nil
    }

    // MARK: 缓存

    private func cacheUserId() -> String? {
        user?.id ?? user?.username ?? UserDefaults.standard.string(forKey: lastUserIdKey)
    }

    private func loadCacheForCurrentUser() {
        guard let id = cacheUserId(),
              let cache = CacheStore.load(userId: id) else { return }
        applyCache(cache)
    }

    private func applyCache(_ cache: CachedData) {
        if let cachedUser = cache.user, user == nil {
            user = cachedUser
            viewTeam = cachedUser.displayTeam
        }
        if let cachedMonth = cache.month {
            // 只用缓存里“当前看的月份”的那份，避免月份错位。
            let ym = currentYearMonth
            if cachedMonth.year == ym.year && cachedMonth.month == ym.month {
                month = cachedMonth
            }
        }
        if let cachedPay = cache.pay {
            if cachedPay.year == payYearMonth.year && cachedPay.month == payYearMonth.month {
                pay = cachedPay
            }
        }
        swaps = cache.swaps ?? swaps
        leaves = cache.leaves ?? leaves
        cacheSavedAt = cache.savedAt
    }

    private func persistCache() {
        guard let id = cacheUserId() else { return }
        CacheStore.save(userId: id, cache: CachedData(
            user: user, month: month, pay: pay, swaps: swaps, leaves: leaves, savedAt: Date()
        ))
        cacheSavedAt = Date()
    }

    // MARK: 刷新

    /// 读缓存后后台刷新：/me + 当月 + 当月工资 + 调班/请假 + 今日。
    func refreshAll() async {
        guard isLoggedIn, serverReachable || api.baseURL != nil else { return }
        isOffline = false
        async let meTask: UserProfile? = try? await api.fetchMe()
        await refreshMonth()
        await refreshPay()
        await refreshToday()
        if let me = await meTask {
            user = me
            viewTeam = me.displayTeam
        }
        persistCache()
    }

    /// 刷新当月：看自己班组走服务端 /me/month；看别的班组本地算基础排班。
    func refreshMonth() async {
        let ym = currentYearMonth
        isLoadingMonth = true
        defer { isLoadingMonth = false }
        if viewTeam == myTeam {
            do {
                month = try await api.fetchMonth(year: ym.year, month: ym.month)
                swaps = (try? await api.fetchSwaps(year: ym.year, month: ym.month)) ?? swaps
                leaves = (try? await api.fetchLeaves(year: ym.year, month: ym.month)) ?? leaves
                isOffline = false
            } catch {
                if (error as? APIError)?.message == APIError.unreachable.message {
                    isOffline = true
                } else {
                    errorMessage = (error as? APIError)?.message ?? error.localizedDescription
                }
            }
        } else {
            // 看别的班：本地按 8 天一轮算基础排班（无调班/请假），即时显示。
            month = ScheduleCalculator.localMonth(team: viewTeam, year: ym.year, month: ym.month)
            swaps = []
            leaves = []
        }
        persistCache()
    }

    /// 刷新工资：永远以服务端 /me/pay 为准，客户端不重算公式。
    func refreshPay() async {
        isLoadingPay = true
        defer { isLoadingPay = false }
        do {
            pay = try await api.fetchPay(year: payYearMonth.year, month: payYearMonth.month)
            isOffline = false
        } catch {
            if (error as? APIError)?.message == APIError.unreachable.message {
                isOffline = true
            } else {
                errorMessage = (error as? APIError)?.message ?? error.localizedDescription
            }
        }
        persistCache()
    }

    func refreshPayYear() async {
        do {
            payYearData = try await api.fetchPayYear(year: payYearMonth.year)
        } catch {
            errorMessage = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    /// 刷新今日：今天、明天、本周 7 天、睡眠窗口。
    func refreshToday() async {
        let todayString = DateUtil.string(from: Date())
        do {
            let range = try await api.fetchRange(start: todayString, days: 7)
            weekDays = range
            todayDay = range.first
            tomorrowDay = range.count > 1 ? range[1] : nil
            let nowString = DateUtil.timeFormatter.string(from: Date())
            quiet = try? await api.fetchQuiet(at: nowString)
        } catch {
            // 今日页失败不阻塞主流程；离线时用当月缓存里的今天顶一下。
            if let today = month?.day(for: todayString) {
                todayDay = today
            } else {
                let base = ScheduleCalculator.baseShift(team: myTeam, date: Date())
                todayDay = DaySchedule(date: todayString, team: myTeam, baseShift: base, shift: base,
                                       start: nil, end: nil, timeLabel: ShiftStyle.timeRange(for: base),
                                       totalHours: base == "休息" ? 0 : 8, isDouble: false,
                                       isWork: base != "休息", onLeave: false, leaveType: nil,
                                       leaveNote: nil, overridden: false, note: nil, partner: nil,
                                       partnerShift: nil, coverDate: nil, paybackDate: nil,
                                       holiday: nil, weekday: nil)
            }
        }
    }

    // MARK: 写操作（调班 / 请假 / 资料 / 换班）

    func submitOverride(date: String, shift: String, note: String?, partner: String?, partnerShift: String?) async throws {
        _ = try await api.postOverride(date: date, shift: shift, note: note, partner: partner, partnerShift: partnerShift)
        await refreshMonth()
        await refreshPay()
    }

    func cancelOverride(date: String) async throws {
        try await api.deleteOverride(date: date)
        await refreshMonth()
        await refreshPay()
    }

    func submitLeave(date: String, type: String?, note: String?) async throws {
        try await api.postLeave(date: date, type: type, note: note)
        await refreshMonth()
        await refreshPay()
    }

    func submitLeaveRange(start: String, end: String, type: String?, note: String?) async throws {
        try await api.postLeaveRange(start: start, end: end, type: type, note: note)
        await refreshMonth()
        await refreshPay()
    }

    func cancelLeave(date: String) async throws {
        try await api.deleteLeave(date: date)
        await refreshMonth()
        await refreshPay()
    }

    /// 保存资料：引导流程与设置页共用（team / paySettings / onboardingDone 只传给定的字段）。
    func saveProfile(team: String? = nil, paySettings: [String: Any]? = nil, onboardingDone: Bool? = nil) async throws {
        let updated = try await api.updateProfile(team: team, paySettings: paySettings, onboardingDone: onboardingDone)
        user = updated
        if let team { viewTeam = team }
        persistCache()
    }

    func refreshTeamHistory() async throws -> [TeamHistoryEntry] {
        let history = try await api.fetchTeamHistory()
        var updatedUser = user
        updatedUser?.teamHistory = history
        if let last = history.sorted(by: { $0.effectiveFrom < $1.effectiveFrom }).last {
            updatedUser?.team = last.team
        }
        user = updatedUser
        persistCache()
        return history
    }

    // MARK: 月份切换

    func moveMonth(by offset: Int) {
        currentMonth = DateUtil.addingMonths(currentMonth, offset)
        Task { await refreshMonth() }
    }

    func goToTodayMonth() {
        currentMonth = Date()
        Task { await refreshMonth() }
    }

    /// 手动切换服务器地址后重连并刷新。
    func switchServer(to baseURL: String) async {
        ServerConfig.manualOverride = baseURL
        api.baseURL = baseURL
        api.serverKind = ServerConfig.kind(for: baseURL)
        serverBaseURL = baseURL
        serverKind = api.serverKind
        serverReachable = await ServerConfig.probe(baseURL: baseURL)
        if serverReachable {
            await refreshAll()
        }
    }

    func clearServerOverride() async {
        ServerConfig.manualOverride = nil
        await startup()
    }

    // MARK: App 内更新提示

    /// 启动后（服务器连通时）调一次版本清单；有新版就 pendingUpdate，界面弹提示。
    /// 检查失败静默，不弹错。
    func checkForUpdateAfterLaunch() async {
        guard serverReachable || api.baseURL != nil else { return }
        pendingUpdate = await UpdateChecker.checkAfterLaunch(api: api)
    }

    /// 设置页「检查更新」手动查：有新版弹提示，没新版显示“已是最新版本”。
    func checkForUpdateManually() async {
        guard serverReachable || api.baseURL != nil else {
            updateNotice = "现在连不上服务器，稍后再试"
            return
        }
        switch await UpdateChecker.checkManually(api: api) {
        case .updateAvailable(let info):
            pendingUpdate = info
        case .upToDate:
            updateNotice = "已是最新版本（当前 \(UpdateChecker.currentVersion)）"
        }
    }

    /// 点「稍后」：当天不再弹。
    func dismissUpdateForToday() {
        UpdateChecker.markDismissedToday()
        pendingUpdate = nil
    }
}
