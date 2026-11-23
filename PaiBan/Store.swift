import Foundation
import SwiftUI

// MARK: - 本地缓存

/// App 沙盒 Documents 下、按用户 id 分文件的缓存。
/// 切月不再每次走网络：月份按 "班组-yyyy-MM" 分开存，调班/请假按 "yyyy-MM" 存，
/// 全年天数按 "yyyy" 存，工资配置与本地算好的工资按月存。
/// 启动时先读缓存立刻显示，再后台静默刷新并写回。
struct CachedData: Codable {
    var user: UserProfile?
    var month: MonthSchedule?                       // 旧版：最近一个月（兼容用）
    var pay: PayMonth?                              // 旧版：最近一个月工资（兼容用）
    var swaps: [SwapRecord]?
    var leaves: [LeaveRecord]?
    var months: [String: MonthSchedule]?            // key: "班组-yyyy-MM"
    var monthSwaps: [String: [SwapRecord]]?        // key: "yyyy-MM"
    var monthLeaves: [String: [LeaveRecord]]?      // key: "yyyy-MM"
    var yearDays: [String: [DaySchedule]]?         // key: "yyyy"，/me/range 全年天数
    var payConfig: PayConfigData?                   // GET /api/v1/config 的 pay 一节
    var payMonths: [String: PayMonth]?              // key: "yyyy-MM"，本地算好的工资
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

    // 工资（默认看上个月；本地算，服务端只给原始数据）
    @Published var payYearMonth: (year: Int, month: Int) = DateUtil.lastMonth()
    @Published var pay: PayMonth?
    @Published var isLoadingPay = false

    // 本地算工资的输入（内存里一份，磁盘缓存里也有一份）
    var payConfig: PayConfigData?
    var yearDaysCache: [String: [DaySchedule]] = [:]   // key: "yyyy"
    var payCache: [String: PayMonth] = [:]             // key: "yyyy-MM"，本地算好的工资

    // 按月缓存（内存里一份，磁盘缓存里也有一份）
    // monthCache 是 @Published：滑页时每页直接读它，数据到了页面自己刷新，不用等整页重载。
    @Published var monthCache: [String: MonthSchedule] = [:]      // key: "班组-yyyy-MM"
    var swapsCache: [String: [SwapRecord]] = [:]       // key: "yyyy-MM"
    var leavesCache: [String: [LeaveRecord]] = [:]     // key: "yyyy-MM"
    private var fetchingMonths: Set<String> = []       // 正在后台取的月份，避免重复发请求

    // App 内更新提示
    @Published var pendingUpdate: VersionInfo?
    @Published var updateNotice: String?

    @Published var errorMessage: String?

    private let lastUserIdKey = "paiban.lastUserId"

    var myTeam: String { user?.displayTeam ?? "B" }

    /// 今天的班次（供排班页顶栏显示）：优先用已加载的当月/全年天数（带调班请假），
    /// 没有就按 8 天一轮本地算基础班次。看别的月份时顶栏照样显示今天，不受切月影响。
    var todaySchedule: DaySchedule? {
        let todayString = DateUtil.string(from: Date())
        if let day = month?.day(for: todayString) { return day }
        let year = DateUtil.yearMonth(of: Date()).year
        if let day = yearDaysCache[String(year)]?.first(where: { $0.date == todayString }) { return day }
        let base = ScheduleCalculator.baseShift(team: myTeam, date: Date())
        return DaySchedule(date: todayString, team: myTeam, baseShift: base, shift: base,
                           start: nil, end: nil, timeLabel: ShiftStyle.timeRange(for: base),
                           totalHours: base == "休息" ? 0 : 8, isDouble: false,
                           isWork: base != "休息", onLeave: false, leaveType: nil,
                           leaveNote: nil, overridden: false, note: nil, partner: nil,
                           partnerShift: nil, coverDate: nil, paybackDate: nil,
                           holiday: nil, weekday: nil)
    }

    /// 是不是老爷（张晓文）：他的工资走全局录入数 + 生效表；同事走自己的设置。
    var isOwner: Bool { user?.username == "张晓文" }

    /// 月份缓存 key：班组 + 年月（看别的班也分开存，不会串月）。
    private func monthCacheKey(team: String, year: Int, month: Int) -> String {
        "\(team)-\(year)-\(String(format: "%02d", month))"
    }

    /// 工资缓存 key：年月。
    private func payCacheKey(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }

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
        swaps = []
        leaves = []
        payConfig = nil
        yearDaysCache = [:]
        payCache = [:]
        monthCache = [:]
        swapsCache = [:]
        leavesCache = [:]
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
        // 按月缓存：读进内存；只把“当前看的月份 + 当前班组”的那份放到界面上，避免月份错位。
        monthCache = cache.months ?? [:]
        swapsCache = cache.monthSwaps ?? [:]
        leavesCache = cache.monthLeaves ?? [:]
        let ym = currentYearMonth
        let key = monthCacheKey(team: viewTeam, year: ym.year, month: ym.month)
        if let cachedMonth = monthCache[key] {
            month = cachedMonth
        } else if let cachedMonth = cache.month,
                  cachedMonth.year == ym.year && cachedMonth.month == ym.month {
            month = cachedMonth // 旧版缓存兼容
        }
        let mk = payCacheKey(year: ym.year, month: ym.month)
        if let s = swapsCache[mk] { swaps = s }
        else if let s = cache.swaps { swaps = s }
        if let l = leavesCache[mk] { leaves = l }
        else if let l = cache.leaves { leaves = l }
        // 工资输入与本地算好的工资。
        payConfig = cache.payConfig
        yearDaysCache = cache.yearDays ?? [:]
        payCache = cache.payMonths ?? [:]
        if let cachedPay = payCache[payCacheKey(year: payYearMonth.year, month: payYearMonth.month)] {
            pay = cachedPay
        } else if let cachedPay = cache.pay,
                  cachedPay.year == payYearMonth.year && cachedPay.month == payYearMonth.month {
            pay = cachedPay // 旧版缓存兼容
        }
        cacheSavedAt = cache.savedAt
    }

    private func persistCache() {
        guard let id = cacheUserId() else { return }
        // 只缓存自己班组的数据：看别的班时 swaps/leaves 是空的，
        // 写回会把自己班的调班/请假记录盖掉。
        if viewTeam == myTeam {
            let ym = currentYearMonth
            monthCache[monthCacheKey(team: viewTeam, year: ym.year, month: ym.month)] = month
            swapsCache[payCacheKey(year: ym.year, month: ym.month)] = swaps
            leavesCache[payCacheKey(year: ym.year, month: ym.month)] = leaves
        }
        CacheStore.save(userId: id, cache: CachedData(
            user: user, month: month, pay: pay, swaps: swaps, leaves: leaves,
            months: monthCache, monthSwaps: swapsCache, monthLeaves: leavesCache,
            yearDays: yearDaysCache, payConfig: payConfig, payMonths: payCache,
            savedAt: Date()
        ))
        cacheSavedAt = Date()
    }

    // MARK: 刷新

    /// 读缓存后后台刷新：/me + 当月 + 工资输入（配置 + 全年天数）+ 当月工资。
    func refreshAll() async {
        guard isLoggedIn, serverReachable || api.baseURL != nil else { return }
        isOffline = false
        async let meTask: UserProfile? = try? await api.fetchMe()
        await refreshMonth()
        await refreshPayInputs()
        await refreshPay()
        if let me = await meTask {
            user = me
            viewTeam = me.displayTeam
        }
        persistCache()
    }

    /// 刷新当月：有缓存先直接显示（不转圈），再后台静默刷新；没缓存才转圈等网络。
    /// 看自己班组走服务端 /me/month；看别的班组本地算基础排班。
    /// 滑页时要哪月给哪月：有缓存直接给缓存；没缓存先按本地 8 天一轮算基础排班顶上（秒出、不闪白），
    /// 同时后台取真数据，到了就写进 monthCache，页面自己刷新。看别的班不用取数，本地算的就是最终结果。
    func monthFor(year: Int, month: Int) -> MonthSchedule {
        let key = monthCacheKey(team: viewTeam, year: year, month: month)
        if let cached = monthCache[key] { return cached }
        let local = ScheduleCalculator.localMonth(team: viewTeam, year: year, month: month)
        if viewTeam == myTeam { prefetchMonth(year: year, month: month) }
        return local
    }

    /// 后台取某月的真数据（调班/请假都带上），到了写进缓存；已缓存或正在取的直接跳过。
    func prefetchMonth(year: Int, month: Int) {
        let key = monthCacheKey(team: myTeam, year: year, month: month)
        guard monthCache[key] == nil, !fetchingMonths.contains(key) else { return }
        fetchingMonths.insert(key)
        Task {
            do {
                let m = try await api.fetchMonth(year: year, month: month)
                let swaps = (try? await api.fetchSwaps(year: year, month: month)) ?? []
                let leaves = (try? await api.fetchLeaves(year: year, month: month)) ?? []
                monthCache[key] = m
                swapsCache[payCacheKey(year: year, month: month)] = swaps
                leavesCache[payCacheKey(year: year, month: month)] = leaves
                isOffline = false
            } catch {
                AppLogger.shared.log("预取排班 \(year)-\(month) 失败：\((error as? APIError)?.message ?? error.localizedDescription)", tag: "Cache")
            }
            fetchingMonths.remove(key)
            persistCache()
        }
    }

    func refreshMonth() async {
        let ym = currentYearMonth
        let key = monthCacheKey(team: viewTeam, year: ym.year, month: ym.month)
        let monthKey = payCacheKey(year: ym.year, month: ym.month)
        if viewTeam == myTeam {
            // 先用内存缓存顶上（切月秒出），再后台静默刷新。
            applyCachedMonth()
            let hadCache = month?.year == ym.year && month?.month == ym.month
            if !hadCache { isLoadingMonth = true }
            defer { isLoadingMonth = false }
            do {
                month = try await api.fetchMonth(year: ym.year, month: ym.month)
                swaps = (try? await api.fetchSwaps(year: ym.year, month: ym.month)) ?? swaps
                leaves = (try? await api.fetchLeaves(year: ym.year, month: ym.month)) ?? leaves
                monthCache[key] = month
                swapsCache[monthKey] = swaps
                leavesCache[monthKey] = leaves
                isOffline = false
                AppLogger.shared.log("排班 \(ym.year)-\(ym.month) 联网刷新成功", tag: "Cache")
            } catch {
                AppLogger.shared.log("排班 \(ym.year)-\(ym.month) 联网刷新失败：\((error as? APIError)?.message ?? error.localizedDescription)，用缓存顶着", tag: "Cache")
                if (error as? APIError)?.message == APIError.unreachable.message {
                    isOffline = true
                } else if !hadCache {
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

    /// 刷新工资的输入：工资配置（/api/v1/config 的 pay 一节）+ 当年全年天数（/me/range）。
    /// 两者都取回来存好，后面切月、看工资都本地算，不再每次问服务端。
    func refreshPayInputs() async {
        let year = payYearMonth.year
        async let configTask: PayConfigData? = try? await api.fetchPayConfig()
        let daysInYear = DateUtil.isLeapYear(year) ? 366 : 365
        async let daysTask: [DaySchedule]? = try? await api.fetchRangeDays(
            start: String(format: "%04d-01-01", year), days: daysInYear)
        if let cfg = await configTask { payConfig = cfg }
        if let days = await daysTask, !days.isEmpty {
            yearDaysCache[String(year)] = days
            // 全年天数变了，本地算好的工资可能过时：只清当年已算的月份。
            for m in 1...12 { payCache.removeValue(forKey: payCacheKey(year: year, month: m)) }
        }
    }

    /// 本地算某月工资（不走网络）。算得出就返回，算不出（缺全年天数或配置）返回 nil。
    func computeLocalPay(year: Int, month: Int) -> PayMonth? {
        guard let cfg = payConfig?.settings,
              let days = yearDaysCache[String(year)], !days.isEmpty else { return nil }
        let recorded = isOwner ? (payConfig?.months ?? [:]) : [:]
        let effective = isOwner ? (payConfig?.effective ?? [:]) : [:]
        let offset = isOwner ? (cfg.annualLeaveUsedOffset?[String(year)] ?? 0) : 0
        return PayCalc.computePay(
            yearDays: days, global: cfg, userSettings: user?.paySettings,
            recordedMonths: recorded, effective: effective,
            annualLeaveOffset: offset, year: year, month: month
        )
    }

    /// 刷新工资：优先走本地缓存与本地算，切月秒出。
    /// 1) 本地有输入（配置 + 全年天数）就直接算、立刻显示；
    /// 2) 没输入就先取输入（配置 + 全年天数各一趟）再本地算；
    /// 3) 输入取不到才走服务端 /me/pay 兜底。
    func refreshPay() async {
        let key = payCacheKey(year: payYearMonth.year, month: payYearMonth.month)
        if let local = computeLocalPay(year: payYearMonth.year, month: payYearMonth.month) {
            pay = local
            payCache[key] = local
            persistCache()
            return
        }
        if let cached = payCache[key] {
            pay = cached
        } else {
            isLoadingPay = true
        }
        defer { isLoadingPay = false }
        // 本地算不出：先补取输入（只在缺输入时才走这两趟，取到就本地算，不用再问 /me/pay）。
        await refreshPayInputs()
        if let local = computeLocalPay(year: payYearMonth.year, month: payYearMonth.month) {
            pay = local
            payCache[key] = local
            isLoadingPay = false
            persistCache()
            return
        }
        AppLogger.shared.log("工资 \(payYearMonth.year)-\(payYearMonth.month) 本地算不出，走服务端 /me/pay 兜底", tag: "Pay")
        do {
            pay = try await api.fetchPay(year: payYearMonth.year, month: payYearMonth.month)
            isOffline = false
        } catch {
            if (error as? APIError)?.message == APIError.unreachable.message {
                isOffline = true
            } else if pay == nil {
                errorMessage = (error as? APIError)?.message ?? error.localizedDescription
            }
        }
        persistCache()
    }

    // MARK: 写操作（调班 / 请假 / 资料 / 换班）

    // 写操作后：刷新当月 + 重新取全年天数（本地算工资的输入变了）+ 本地重算工资。
    func submitOverride(date: String, shift: String, note: String?, partner: String?, partnerShift: String?) async throws {
        _ = try await api.postOverride(date: date, shift: shift, note: note, partner: partner, partnerShift: partnerShift)
        await refreshMonth()
        await refreshPayInputs()
        await refreshPay()
    }

    func cancelOverride(date: String) async throws {
        try await api.deleteOverride(date: date)
        await refreshMonth()
        await refreshPayInputs()
        await refreshPay()
    }

    func submitLeave(date: String, type: String?, note: String?) async throws {
        try await api.postLeave(date: date, type: type, note: note)
        await refreshMonth()
        await refreshPayInputs()
        await refreshPay()
    }

    func submitLeaveRange(start: String, end: String, type: String?, note: String?) async throws {
        try await api.postLeaveRange(start: start, end: end, type: type, note: note)
        await refreshMonth()
        await refreshPayInputs()
        await refreshPay()
    }

    func cancelLeave(date: String) async throws {
        try await api.deleteLeave(date: date)
        await refreshMonth()
        await refreshPayInputs()
        await refreshPay()
    }

    /// 保存资料：引导流程与设置页共用（team / paySettings / onboardingDone 只传给定的字段）。
    /// 注意：PUT /me/profile 只回 profile 字段（team / teamHistory / paySettings / onboardingDone），
    /// 没有 username / id / role；直接整包替换会把账号名丢成 nil（设置页账号显示“—”就是这么来的）。
    /// 这里合并：保留原有身份字段，只更新 profile 字段。
    func saveProfile(team: String? = nil, paySettings: [String: Any]? = nil, onboardingDone: Bool? = nil) async throws {
        let updated = try await api.updateProfile(team: team, paySettings: paySettings, onboardingDone: onboardingDone)
        var merged = user ?? updated
        merged.team = updated.team ?? merged.team
        merged.teamHistory = updated.teamHistory ?? merged.teamHistory
        merged.paySettings = updated.paySettings ?? merged.paySettings
        merged.onboardingDone = updated.onboardingDone ?? merged.onboardingDone
        user = merged
        if let team { viewTeam = team }
        persistCache()
    }

    /// 设置页显示的账号名：user.username 为主；万一缓存里是旧的缺名字版本，
    /// 用 Keychain 里登录时存的账号名兜底（登录成功就存了，一定有）。
    var displayUsername: String {
        if let name = user?.username, !name.isEmpty { return name }
        if let name = KeychainHelper.load()?.username, !name.isEmpty { return name }
        return "—"
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

    /// 同步把当前月的缓存换到界面上（标题和网格不错位），再后台静默刷新。
    private func applyCachedMonth() {
        let ym = currentYearMonth
        let key = monthCacheKey(team: viewTeam, year: ym.year, month: ym.month)
        if let cached = monthCache[key] {
            month = cached
            let mk = payCacheKey(year: ym.year, month: ym.month)
            swaps = swapsCache[mk] ?? swaps
            leaves = leavesCache[mk] ?? leaves
        }
    }

    /// 滑页时直接定到某年某月（只改 currentMonth、立刻用缓存顶上，刷新走后台，不闪白）。
    func setCurrentMonth(year: Int, month: Int) {
        guard let date = DateUtil.firstDayOfMonth(year: year, month: month) else { return }
        currentMonth = date
        applyCachedMonth()
    }

    func moveMonth(by offset: Int) {
        currentMonth = DateUtil.addingMonths(currentMonth, offset)
        applyCachedMonth()
        Task { await refreshMonth() }
    }

    func goToTodayMonth() {
        currentMonth = Date()
        applyCachedMonth()
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
