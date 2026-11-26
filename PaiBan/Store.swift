import Foundation
import SwiftUI
import WidgetKit

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
    var monthOvertime: [String: [OvertimeRecord]]? // key: "yyyy-MM"
    var yearDays: [String: [DaySchedule]]?         // key: "yyyy"，/me/range 全年天数
    var payConfig: PayConfigData?                   // GET /api/v1/config 的 pay 一节
    var payMonths: [String: PayMonth]?              // key: "yyyy-MM"，本地算好的工资
    var userMonths: [String: PayMonthRecord]?       // 1.2.7：同事自己的单月录入（各改各的，服务端存 user.payMonths）
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
    @Published var user: UserProfile? {
        didSet {
            // 服务端 profile 里的显示设置是跨设备同步的源：有就采用（本地也存一份）。
            if let ds = user?.displaySettings, ds != calendarDisplay {
                calendarDisplay = ds
                ds.saveLocal()
            }
            // 换账号/退出：清掉旧账号的引导弹窗状态，免得串到新账号上。
            if Self.userKey(for: oldValue) != Self.userKey(for: user) {
                needsPayGuide = false
            }
            // 第 30 条：工资权限刚开通（false→true）时，弹工资引导。
            checkPayGuide()
        }
    }
    @Published var isStarting = true          // 启动中（正在选路 / 试登录）
    @Published var startupError: String?

    // 1.2.7.001：倒班设置（方式 + 班组 + 基准日 + 班组名 + 手动逐日班次），来自 profile；
    // 没拿到时按现有分休式（mode 4-3-b、基准日 2026-11-01）算，与旧数据逐日一致。
    var rotation: RotationSetting { user?.rotation ?? .default }
    /// 1.2.7.001：工资页权限（服务端回的；字段缺失时默认开，避免老服务端把老爷的工资页藏掉）。
    var payAccess: Bool { user?.payAccess ?? true }
    /// 1.2.7.001：日历显示设置（本地 UserDefaults + 服务端 profile 同步）。
    @Published var calendarDisplay: CalendarDisplaySettings = CalendarDisplaySettings.loadLocal()
    /// 1.2.8.001：外观（跟随系统/浅色/深色，本地 UserDefaults；改完立刻生效，不用重启）。
    @Published var appearance: AppearanceMode = AppearanceMode.loadLocal() {
        didSet { appearance.saveLocal() }
    }
    /// 1.2.7.001：节假日缓存（key 日期，value 节假日一天；服务端拉取，挂了用内置表）。
    @Published var holidays: [String: HolidayDay] = [:]
    @Published var holidaysUpdatedAt: String?
    /// 1.2.7.001：共享班表（我分享的 + 同事分享给我的）。
    @Published var sharesSent: [ScheduleShare] = []
    @Published var sharesReceived: [ScheduleShare] = []

    // 服务器
    @Published var serverBaseURL: String?
    @Published var serverKind: ServerKind = .cloud
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
    @Published var overtime: [OvertimeRecord] = []
    @Published var isLoadingMonth = false

    // 工资（1.2.6 冷启动回当天：默认看当月；本地算，服务端只给原始数据）
    @Published var payYearMonth: (year: Int, month: Int) = DateUtil.yearMonth(of: Date())
    @Published var pay: PayMonth?
    @Published var isLoadingPay = false

    // 本地算工资的输入（内存里一份，磁盘缓存里也有一份）
    var payConfig: PayConfigData?
    var yearDaysCache: [String: [DaySchedule]] = [:]   // key: "yyyy"
    var payCache: [String: PayMonth] = [:]             // key: "yyyy-MM"，本地算好的工资
    /// 1.2.7：同事自己的单月录入（各改各的；老爷的仍走全局 payConfig.months）。
    /// 服务端存 user.payMonths，GET /me 回传；离线时走磁盘缓存里的 userMonths。
    var userMonths: [String: PayMonthRecord] = [:]
    /// 小组件深链要跳的 Tab（0 排班 / 1 工资）：MainTabView 跟着它切。
    @Published var selectedTab = 0
    /// 没登录时点小组件进来的深链：先记下来，登录后进主界面再跳。
    var pendingDeepLinkTab: Int?
    /// 上次发给小组件的快照（内容不变时不重复写、不重复刷新，WidgetCenter 刷新有系统预算）。
    private var lastPublishedSnapshot: WidgetSnapshot?

    // 按月缓存（内存里一份，磁盘缓存里也有一份）
    // monthCache 是 @Published：滑页时每页直接读它，数据到了页面自己刷新，不用等整页重载。
    @Published var monthCache: [String: MonthSchedule] = [:]      // key: "班组-yyyy-MM"
    var swapsCache: [String: [SwapRecord]] = [:]       // key: "yyyy-MM"
    var leavesCache: [String: [LeaveRecord]] = [:]     // key: "yyyy-MM"
    var overtimeCache: [String: [OvertimeRecord]] = [:] // key: "yyyy-MM"
    // 本地算好的月排班（8 天一轮）备忘：monthFor 每调一次就重算一次是 1.1.2 掉帧的主因，
    // 这里按班组+年月记下来，只算一次；真数据到了走 monthCache 覆盖，不影响预取。
    var localMonthCache: [String: MonthSchedule] = [:]  // key 同 monthCacheKey
    /// 工资输入（payConfig / 全年天数）版本号：日历要靠它重画三薪标与底部统计，
    /// 输入到齐就 +1 触发重画（yearDaysCache / payConfig 本身不是 @Published）。
    @Published var payInputsVersion = 0
    /// 日历数据版本号（1.1.5）：日历每页只存一份数据快照，滑动中不读 store；
    /// 只有真正的数据变更才 +1 让各页重拍快照——调班/请假保存、刷新成功、换班组。
    /// 滑页中的 prefetch / setCurrentMonth 不碰它，滑稳之前快照一动不动。
    @Published var calendarVersion = 0
    private var fetchingMonths: Set<String> = []       // 正在后台取的月份，避免重复发请求

    // App 内更新提示
    @Published var pendingUpdate: VersionInfo?
    @Published var updateNotice: String?

    @Published var errorMessage: String?

    private let lastUserIdKey = "paiban.lastUserId"

    var myTeam: String { user?.displayTeam ?? "B" }

    /// 当前看的日历能不能改：只有正在看的班组 = 用户当前在设置页设定的班组时才能改。
    /// （老爷 2026-11-24 04:49/04:50 定：切到别的班看日历是纯只读；能改的班跟着设置走，
    /// 换班组后权限跟着变，不是写死 B 班。）
    var canEditCurrentCalendar: Bool { viewTeam == myTeam }

    /// 今天的班次（供排班页顶栏显示）：优先用已加载的当月/全年天数（带调班请假），
    /// 没有就按 8 天一轮本地算基础班次。看别的月份时顶栏照样显示今天，不受切月影响。
    var todaySchedule: DaySchedule? {
        let todayString = DateUtil.string(from: Date())
        if let day = month?.day(for: todayString) { return day }
        let year = DateUtil.yearMonth(of: Date()).year
        if let day = yearDaysCache[String(year)]?.first(where: { $0.date == todayString }) { return day }
        let base = ScheduleCalculator.baseShift(team: myTeam, date: Date(), rotation: rotation)
        return DaySchedule(date: todayString, team: myTeam, baseShift: base, shift: base,
                           start: nil, end: nil, timeLabel: ShiftStyle.timeRange(for: base),
                           totalHours: base == "休息" ? 0 : 8, isDouble: false,
                           isWork: base != "休息", onLeave: false, leaveType: nil,
                           leaveNote: nil, overridden: false, note: nil, partner: nil,
                           partnerShift: nil, coverDate: nil, paybackDate: nil,
                           holiday: nil, weekday: nil)
    }

    /// 是不是老爷（张晓文，账号是手机号 18765766628）：他的工资走全局录入数 + 生效表；同事走自己的设置。
    /// 2026-11-24 起账号改用手机号，isOwner 改认手机号，不再认中文名「张晓文」。
    var isOwner: Bool { user?.username == "18765766628" }

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

    /// 启动流程（本地优先）：Keychain 里有账号密码 + 本地有缓存，就直接进，
    /// 不等服务器；进去之后后台静默同步（服务器、数据、更新检查）。
    /// 没账号或没缓存才走原来那套（连服务器、登录页）。
    func startup() async {
        isStarting = true
        startupError = nil
        reloadWidgetsOnVersionChange()
        if let lastId = UserDefaults.standard.string(forKey: lastUserIdKey),
           KeychainHelper.load() != nil,
           let cache = CacheStore.load(userId: lastId), cache.user != nil {
            applyCache(cache)
            isLoggedIn = true
            isStarting = false
            // 1.2.9.001（第 35 条）：打开软件就检查提醒权限——开着但还没定，
            // 直接弹系统原生权限弹窗（只弹一次）；拿到了就按缓存的排班把未来 7 天排上。
            // 不等后台同步（网络慢/断网时也不耽误弹）；后台同步的 refreshAll 里还会再调一次，
            // 权限已定就只重排，不重复弹。
            Task { _ = await ShiftReminder.ensurePermissionAndSchedule(store: self) }
            Task { await backgroundSyncAfterLaunch() }
            return
        }
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
                startupError = "连不上服务器（云服务器与 NAS 备份都试过了），请检查网络后再试。"
            }
            return
        }
        do {
            let me = try await api.fetchMe()
            user = me
            isLoggedIn = true
            viewTeam = me.displayTeam
            UserDefaults.standard.set(me.id ?? me.username ?? "", forKey: lastUserIdKey)
            loadCacheForCurrentUser()
            isStarting = false
            registerThisDevice()
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

    /// 进去之后后台静默同步：选路 → 验 session → 刷新数据 → 查更新。
    /// 联不上就离线用着，不打扰；只有 session 明确失效（不是网络问题）才回登录页。
    private func backgroundSyncAfterLaunch() async {
        reloadWidgetsOnVersionChange()
        let reachable = await api.resolveServer()
        serverReachable = reachable
        serverBaseURL = api.baseURL
        serverKind = api.serverKind
        guard reachable else {
            isOffline = true
            return
        }
        do {
            let me = try await api.fetchMe()
            user = me
            isLoggedIn = true
            isOffline = false
            viewTeam = me.displayTeam
            UserDefaults.standard.set(me.id ?? me.username ?? "", forKey: lastUserIdKey)
            registerThisDevice()
            await refreshAll()
            await checkForUpdateAfterLaunch()
        } catch {
            if let apiError = error as? APIError, apiError.message == APIError.unreachable.message {
                isOffline = true
            } else {
                // 不是网络问题，是 session/账号问题：回登录页。
                isLoggedIn = false
            }
        }
    }

    /// 设备直连登记（1.2.7.004）：登录成功后、启动同步成功后，把本机
    /// identifierForVendor 登记到用户名下；小组件凭设备号拉数据，不用填密钥。
    /// 后台静默做，失败不打扰用户（小组件走缓存）。
    /// 重装后设备号会变，启动时重登记能自己接上。
    private func registerThisDevice() {
        Task { await api.registerDevice() }
    }

    /// 版本变了就强制刷新小组件时间线（1.2.7.006）：App 更新后小组件扩展也换了
    /// 新代码，但快照内容没变时 publishWidgetSnapshot 不会触发刷新，小组件会
    /// 一直跑旧扩展、看着像「只改了版号」。每个版本只刷一次，不浪费系统预算；
    /// 装好打开 App 就生效，不用删掉重加。离线也刷（刷的是扩展代码，不用联网）。
    private func reloadWidgetsOnVersionChange() {
        let key = "paiban.widgetReloadedVersion"
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard !current.isEmpty else { return }
        if UserDefaults.standard.string(forKey: key) != current {
            UserDefaults.standard.set(current, forKey: key)
            WidgetCenter.shared.reloadAllTimelines()
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
        user = me
        isLoggedIn = true
        isOffline = false
        viewTeam = me.displayTeam
        UserDefaults.standard.set(me.id ?? me.username ?? "", forKey: lastUserIdKey)
        loadCacheForCurrentUser()
        registerThisDevice()
        await refreshAll()
        await checkForUpdateAfterLaunch()
    }

    /// 手机号 + 验证码登录（1.1.3）：与账号密码登录同一套后续流程（fetchMe → 设用户 → 读缓存 → 刷新）。
    /// 没有密码，不存 Keychain；下次启动走 session（7 天）或缓存离线进。
    /// 新手机号会自动建账号（用户名是「手机+后 4 位」），显示名可在设置页改。
    func loginWithSms(phone: String, code: String) async throws {
        if !serverReachable, !(await api.resolveServer()) {
            throw APIError.unreachable
        }
        serverBaseURL = api.baseURL
        serverKind = api.serverKind
        serverReachable = true
        _ = try await api.loginWithSms(phone: phone, code: code)
        let me = try await api.fetchMe()
        user = me
        isLoggedIn = true
        isOffline = false
        viewTeam = me.displayTeam
        UserDefaults.standard.set(me.id ?? me.username ?? "", forKey: lastUserIdKey)
        loadCacheForCurrentUser()
        registerThisDevice()
        await refreshAll()
        await checkForUpdateAfterLaunch()
    }

    /// 注册（1.2.6）：昵称（displayName，可空）与短信验证码（code，服务端核验）一起交；
    /// 昵称空着就用手机号当显示名（服务端默认同用户名）。
    func register(username: String, password: String, displayName: String? = nil, code: String? = nil) async throws {
        if !serverReachable, !(await api.resolveServer()) {
            throw APIError.unreachable
        }
        serverBaseURL = api.baseURL
        serverKind = api.serverKind
        serverReachable = true
        _ = try await api.register(username: username, password: password, displayName: displayName, code: code)
        let me = try await api.fetchMe()
        user = me
        isLoggedIn = true
        isOffline = false
        viewTeam = me.displayTeam
        UserDefaults.standard.set(me.id ?? me.username ?? "", forKey: lastUserIdKey)
        loadCacheForCurrentUser()
        registerThisDevice()
        await refreshAll()
        await checkForUpdateAfterLaunch()
    }

    /// 绑定/更换手机号（1.1.3）：发码验证后绑定，服务端立即落盘并返回最新用户信息；
    /// 这里合并进当前用户（team/paySettings 不动），管理端读服务端即是最新。
    /// 首次绑定不限；换绑（已绑过再换另一个号）一个月只能换一次，
    /// 服务端限 30 天，限期内会报 429 并给出下次可换时间（错误原样透传）。
    func bindPhone(phone: String, code: String) async throws {
        let updated = try await api.bindPhone(phone: phone, code: code)
        var merged = user ?? updated
        merged.phone = updated.phone ?? merged.phone
        merged.displayName = updated.displayName ?? merged.displayName
        merged.lastPhoneChangeAt = updated.lastPhoneChangeAt ?? merged.lastPhoneChangeAt
        user = merged
        persistCache()
    }

    /// 改密码（1.1.3）：必须先绑手机号，短信验证码验证身份；不限次数、随时能改
    /// （老爷 2026-11-24 04:54 改口：之前「一个月只能改一次」作废，改绑手机号才一月一次）。
    /// 改完服务端立即落盘；原来有密码登录记录的，Keychain 也同步换成新密码，
    /// 否则下次启动本地验旧密码会对不上；原来只用短信登录的（没 Keychain）不动。
    func changePassword(phone: String, code: String, newPassword: String) async throws {
        let updated = try await api.changePassword(phone: phone, code: code, newPassword: newPassword)
        var merged = user ?? updated
        merged.phone = updated.phone ?? merged.phone
        merged.displayName = updated.displayName ?? merged.displayName
        merged.lastPhoneChangeAt = updated.lastPhoneChangeAt ?? merged.lastPhoneChangeAt
        user = merged
        if KeychainHelper.load() != nil, let username = user?.username {
            KeychainHelper.save(username: username, password: newPassword)
        }
        persistCache()
    }

    /// 退出登录：只清登录状态/session（服务端 session + 本地 cookie + Keychain 密码）。
    /// 1.1.3：离线缓存保留（不删文件、不清 lastUserId），下次登同一账号直接用缓存顶着。
    /// 内存里的当月数据清掉，避免登出后界面还留着上一个人的数。
    func logout() async {
        await api.logout()
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
        localMonthCache = [:]
        userMonths = [:]
        cacheSavedAt = nil
        selectedTab = 0
        pendingDeepLinkTab = nil
        // 退出后小组件没数据可显示：清掉共享区的快照，让它显示占位。
        lastPublishedSnapshot = nil
        WidgetSnapshotStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
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
        // 1.2.7：同事自己的单月录入（缓存里的优先，其次是缓存用户对象里带的）。
        if let um = cache.userMonths {
            userMonths = um
        } else if let um = user?.payMonths {
            userMonths = um
        }
        // 按月缓存：读进内存；只把“当前看的月份 + 当前班组”的那份放到界面上，避免月份错位。
        monthCache = cache.months ?? [:]
        swapsCache = cache.monthSwaps ?? [:]
        leavesCache = cache.monthLeaves ?? [:]
        overtimeCache = cache.monthOvertime ?? [:]
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
            overtimeCache[payCacheKey(year: ym.year, month: ym.month)] = overtime
        }
        CacheStore.save(userId: id, cache: CachedData(
            user: user, month: month, pay: pay, swaps: swaps, leaves: leaves,
            months: monthCache, monthSwaps: swapsCache, monthLeaves: leavesCache,
            monthOvertime: overtimeCache,
            yearDays: yearDaysCache, payConfig: payConfig, payMonths: payCache,
            userMonths: userMonths,
            savedAt: Date()
        ))
        cacheSavedAt = Date()
        // 数据写盘后顺手给小组件发一份快照（内容不变时不重复发，见 publishWidgetSnapshot）。
        publishWidgetSnapshot()
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
            if let pm = me.payMonths { userMonths = pm }
        }
        persistCache()
        // 1.2.7.001：节假日同步（服务端更新时间变了就拉新数据，只刷新日历标注）。
        await checkHolidaysUpdate()
        // 1.2.9.001（第 35 条）：排班变了，班次推送提醒重新排（未来 7 天）。
        // 提醒开着但权限还是未决定，就先弹系统权限请求（只弹一次），拿到了再排；
        // 被拒就把开关关掉——开关不能看着开、实际一条都没排。
        _ = await ShiftReminder.ensurePermissionAndSchedule(store: self)
        // 1.1.4：重装恢复——登录后把账号的完整数据从云端拉回来（后台静默，不拖登录）。
        restoreFullDataFromCloud()
    }

    /// 登录后从云端把账号的完整数据拉回来（重装恢复）：除了 refreshAll 取的当月 +
    /// 工资配置，再把 teamHistory 与当年各月的调班/请假/加班都补进缓存。
    /// 1.1.4：原来 refreshAll 只取当月，其他月份只在滑到时才 prefetch——重装后
    /// 登录，滑到 12 月（有调班对子）那一刻会先看到 8 天一轮的基础排班、等网络
    /// 回来才变出调班，看着像丢了（数据其实都在服务端）。现在登录后后台静默补：
    /// 当年 1–12 月逐月 prefetch（有记录的月份写进缓存，没记录的返回空数组也记下，
    /// 下次滑到直接就是真数据、不闪基础排班）。登录本身不被拖住（后台 Task，
    /// 当月与关键资料先出，其余慢慢补）；服务端是唯一真源，本地缓存只供离线。
    /// teamHistory：fetchMe 的 profile 里已经带了（服务端 getProfile 返回），
    /// 这里再兜底一次——如果是 nil（旧数据/异常），调 refreshTeamHistory 补取。
    /// prefetchMonth 自带去重（已缓存/正在取的跳过），重复调也不会重复发请求。
    private func restoreFullDataFromCloud() {
        Task {
            if user?.teamHistory == nil {
                _ = try? await refreshTeamHistory()
            }
            let year = DateUtil.yearMonth(of: Date()).year
            for month in 1...12 {
                prefetchMonth(year: year, month: month)
                // 让出一点时间，别 12 个月同时冲出去。
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    /// 刷新当月：有缓存先直接显示（不转圈），再后台静默刷新；没缓存才转圈等网络。
    /// 看自己班组走服务端 /me/month；看别的班组本地算基础排班。
    /// 滑页时要哪月给哪月：有缓存直接给缓存；没缓存先按本地 8 天一轮算顶上（秒出、不闪白），
    /// 但只算一次、记进 localMonthCache——1.1.2 每调一次就重算一次（每格 ~30 天 × DateFormatter），
    /// 滑页时每页调 3 次、每次重绘全调，是掉帧的主因。真数据到了走 monthCache 覆盖，
    /// 预取照常发（localMonthCache 不影响 monthCache 的预取判断）。
    /// 看别的班：本地月上再叠我自己的调班记录里 partner==这个班的那几条
    /// （overlayPartnerRecords），对方那天按调班后显示；叠加每次现算、不进缓存，
    /// 我的调班记录到了（prefetch 成功、日历重拍快照）就自动带上。
    func monthFor(year: Int, month: Int) -> MonthSchedule {
        let key = monthCacheKey(team: viewTeam, year: year, month: month)
        if let cached = monthCache[key] { return cached }
        if let local = localMonthCache[key] {
            prefetchMonth(year: year, month: month)
            return viewTeam == myTeam ? local : overlayPartnerRecords(local, year: year, month: month)
        }
        let local = ScheduleCalculator.localMonth(team: viewTeam, year: year, month: month, rotation: rotation)
        localMonthCache[key] = local
        prefetchMonth(year: year, month: month)
        return viewTeam == myTeam ? local : overlayPartnerRecords(local, year: year, month: month)
    }

    /// 看别的班的日历：本地 8 天一轮的基础上，叠上我自己的调班记录里 partner==这个班的那几条
    /// （对方那天最终上的班 = 记录里的 partnerShift；对方那天是替我上的，记 partner=我这边的班、
    /// partnerShift=我这天最终的班）。请假顶岗的记录也在同一份 overrides 里，一起叠上。
    /// 只读我自己的数据，不动对方账号（老爷 2026-11-26 08:59 定）。
    private func overlayPartnerRecords(_ month: MonthSchedule, year: Int, month monthNum: Int) -> MonthSchedule {
        guard viewTeam != myTeam, var days = month.days else { return month }
        let records = (swapsCache[payCacheKey(year: year, month: monthNum)] ?? [])
            .filter { $0.partner == viewTeam && $0.partnerShift != nil }
        guard !records.isEmpty else { return month }
        for rec in records {
            guard let i = days.firstIndex(where: { $0.date == rec.date }) else { continue }
            var d = days[i]
            let newShift = rec.partnerShift ?? d.shift
            let parts = newShift == "休息" ? [] : ShiftStyle.parts(of: newShift)
            d.shift = newShift
            d.overridden = true
            d.partner = myTeam
            d.partnerShift = rec.shift
            d.coverDate = rec.coverDate
            d.paybackDate = rec.paybackDate
            d.note = rec.note
            d.isDouble = parts.count == 2
            d.isWork = !parts.isEmpty
            d.totalHours = parts.count * 8
            d.timeLabel = parts.isEmpty ? nil : parts.map { ShiftStyle.timeRange(for: $0) }.joined(separator: " + ")
            d.start = parts.isEmpty ? nil : Self.shiftStart(of: parts.first!)
            d.end = parts.isEmpty ? nil : Self.shiftEnd(of: parts.last!)
            days[i] = d
        }
        var m = month
        m.days = days
        return m
    }

    /// 单班的上班时间（与 ScheduleCalculator.timeStart/timeEnd 同表，overlay 用）。
    private static func shiftStart(of shift: String) -> String? {
        switch shift {
        case "日班": return "08:00"
        case "中班": return "16:00"
        case "早班": return "00:00"
        default: return nil
        }
    }

    /// 单班的下班时间（与 ScheduleCalculator.timeStart/timeEnd 同表，overlay 用）。
    private static func shiftEnd(of shift: String) -> String? {
        switch shift {
        case "日班": return "16:00"
        case "中班": return "24:00"
        case "早班": return "08:00"
        default: return nil
        }
    }

    /// 取某月真数据，失败重试 3 次（退避 0.5/1 秒）。取消（滑走了）不重试，直接抛。
    /// prefetchMonth 与 refreshMonth 共用；1.1.4 加载可靠。
    private func fetchMonthWithRetry(year: Int, month: Int) async throws -> MonthSchedule {
        var lastError: Error?
        for attempt in 0..<3 {
            if Task.isCancelled { throw CancellationError() }
            do {
                return try await api.fetchMonth(year: year, month: month)
            } catch {
                lastError = error
                if Task.isCancelled { throw CancellationError() }
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(500_000_000 * (attempt + 1)))
                }
            }
        }
        throw lastError ?? APIError.unreachable
    }

    /// 后台取某月的真数据（调班/请假都带上），到了写进缓存；月缓存与调班/请假
    /// 缓存都齐了才跳过（缺任何一项都补取，免得记录一直空白），正在取的直接跳过。
    /// 1.1.4（加载可靠，老爷 06:04 定性「不是没画全，是加载失败」）：
    /// 原来 fetchMonth 失败只记一条日志、不重试，滑页时网络抖一下那月就一直是
    /// 本地 fallback；fetchSwaps/fetchLeaves 失败还默认 [] 写进缓存，守卫一看
    /// “有值”就再也不补取，记录永久空白。现在 fetchMonth 失败重试 3 次
    /// （fetchMonthWithRetry）；调班/请假/加班哪路失败就不写那路的缓存（留 nil，
    /// 下次 prefetch 再补），不把失败当成“没有记录”固化下来。
    /// prefetch 的 Task 不随滑页取消（滑页只取消 refreshMonth 的防抖任务），
    /// 在途的加载一定跑完写进缓存，滑走再滑回来数据还在。
    func prefetchMonth(year: Int, month: Int) {
        let key = monthCacheKey(team: myTeam, year: year, month: month)
        let mk = payCacheKey(year: year, month: month)
        guard monthCache[key] == nil || swapsCache[mk] == nil || leavesCache[mk] == nil, !fetchingMonths.contains(key) else { return }
        fetchingMonths.insert(key)
        Task {
            defer {
                fetchingMonths.remove(key)
                persistCache()
            }
            // fetchMonth 失败重试 3 次（fetchMonthWithRetry）；3 次都失败就不写缓存，
            // 下次滑到/预取时守卫还会再试，不静默留空。
            let m: MonthSchedule
            do {
                m = try await fetchMonthWithRetry(year: year, month: month)
            } catch {
                AppLogger.shared.log("预取排班 \(year)-\(month) 失败（已重试 3 次）：\((error as? APIError)?.message ?? error.localizedDescription)", tag: "Cache")
                return
            }
            // 调班/请假/加班各取各的：哪路失败就不写那路（留 nil，下次再补），
            // 不把 [] 当成“没有记录”写死进缓存。
            let swaps = try? await api.fetchSwaps(year: year, month: month)
            let leaves = try? await api.fetchLeaves(year: year, month: month)
            let ot = try? await api.fetchOvertime(year: year, month: month)
            monthCache[key] = m
            if let swaps { swapsCache[mk] = swaps }
            if let leaves { leavesCache[mk] = leaves }
            if let ot { overtimeCache[mk] = ot }
            isOffline = false
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
                // 先把四趟取完（各在自己的 await 里），再一次性把结果写进 @Published：
                // 1.1.2 是取一趟写一次，每次写都触发一次整页重绘，滑页时连着重绘好几次才卡。
                // 同步连续写多个 @Published，SwiftUI 只算一次重绘。
                // 1.1.4：fetchMonth 失败重试 3 次（fetchMonthWithRetry），别让一次网络
                // 抖动就让落定那月的 store.month 一直是旧数；取消（滑走了）不重试。
                let fetchedMonth = try await fetchMonthWithRetry(year: ym.year, month: ym.month)
                let fetchedSwaps = (try? await api.fetchSwaps(year: ym.year, month: ym.month)) ?? swaps
                let fetchedLeaves = (try? await api.fetchLeaves(year: ym.year, month: ym.month)) ?? leaves
                let fetchedOvertime = (try? await api.fetchOvertime(year: ym.year, month: ym.month)) ?? overtime
                month = fetchedMonth
                swaps = fetchedSwaps
                leaves = fetchedLeaves
                overtime = fetchedOvertime
                monthCache[key] = fetchedMonth
                swapsCache[monthKey] = fetchedSwaps
                leavesCache[monthKey] = fetchedLeaves
                overtimeCache[monthKey] = fetchedOvertime
                isOffline = false
                // 1.1.5：刷新成功才让日历各页重拍快照（滑页防抖保证这时已经落定）。
                calendarVersion += 1
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
            // 看别的班：本地按 8 天一轮算基础排班（无调班/请假），即时显示（走 monthFor 的备忘，不重算）。
            month = monthFor(year: ym.year, month: ym.month)
            swaps = []
            leaves = []
            overtime = []
        }
        persistCache()
    }

    /// 把服务端单日数据直接补进日历缓存：调班/请假/取消保存成功后立刻调，
    /// 日历网格读的就是 monthCache，不用等整月刷新回来；整月刷新随后仍会跑一遍对账。
    /// 1.1.2 的教训：只改 month 不写 monthCache（取消请假那路），网格就一直是老的，
    /// 后台整月刷新一慢，用户看到的就是“保存成功了，日历没变”。
    private func patchDayIntoCaches(_ day: DaySchedule) {
        let comps = DateUtil.yearMonth(of: DateUtil.date(from: day.date) ?? Date())
        let key = monthCacheKey(team: viewTeam, year: comps.year, month: comps.month)
        if var cached = monthCache[key], var days = cached.days,
           let i = days.firstIndex(where: { $0.date == day.date }) {
            days[i] = day
            cached.days = days
            monthCache[key] = cached
        }
        if var m = month, m.year == comps.year, m.month == comps.month,
           var days = m.days, let i = days.firstIndex(where: { $0.date == day.date }) {
            days[i] = day
            m.days = days
            month = m
        }
        persistCache()
    }

    /// 从服务端取某天最新状态，补进日历缓存（失败静默，整月刷新会兜底）。
    private func refreshDayOnCalendar(date: String) async {
        if let day = try? await api.fetchDay(date: date) {
            patchDayIntoCaches(day)
        }
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
        let recorded = isOwner ? (payConfig?.months ?? [:]) : userMonths
        let effective = isOwner ? (payConfig?.effective ?? [:]) : [:]
        let offset = isOwner ? (cfg.annualLeaveUsedOffset?[String(year)] ?? 0) : 0
        return PayCalc.computePay(
            yearDays: days, global: cfg, userSettings: user?.paySettings,
            recordedMonths: recorded, effective: effective,
            annualLeaveOffset: offset, year: year, month: month
        )
    }

    /// 取某月工资（本地算，带缓存）：先看 payCache，没有就本地算并记进缓存。
    /// 1.1.4：triplePayInfo 原来每次渲染都调 computeLocalPay 跑完整 PayCalc
    ///（日历每页、底部统计、工资页都调），滑页时几页一起算、主线程被占满就掉帧。
    /// 现在走 payCache 备忘，同一月只算一次；输入变了（refreshPayInputs 清年缓存、
    /// updatePayMonthField 走 refreshPay 重算）缓存跟着失效，不会拿旧数。
    /// 注意 payCache 不是 @Published，写缓存本身不触发重绘；真正要重画时靠
    /// pay / monthCache / payInputsVersion 这些 @Published 驱动。
    func payFor(year: Int, month: Int) -> PayMonth? {
        let key = payCacheKey(year: year, month: month)
        if let cached = payCache[key] { return cached }
        if let local = computeLocalPay(year: year, month: month) {
            payCache[key] = local
            return local
        }
        return nil
    }

    /// 切月（工资页）：同步改月份并立刻用本地算好的工资顶上（有输入时秒出），
    /// 让调用方的 withAnimation 能把「月份 + 内容」包在同一个动画事务里，
    /// 工资页切月才有真正的左右滑动动画；本地算不出时照旧走异步 refreshPay（onChange 兜底）。
    func setPayMonth(year: Int, month: Int) {
        payYearMonth = (year, month)
        if let local = computeLocalPay(year: year, month: month) {
            pay = local
            payCache[payCacheKey(year: year, month: month)] = local
            persistCache()
        }
    }

    /// 补齐指定年份的全年天数 + 工资配置（日历的三薪标与底部统计要用，本地算的输入）。
    /// 只补没缓存的年份；到齐后 payInputsVersion +1，让日历重画。
    func ensureYearDays(years: [Int]) async {
        if payConfig == nil {
            if let cfg = try? await api.fetchPayConfig() {
                payConfig = cfg
            }
        }
        for year in years {
            if yearDaysCache[String(year)] != nil { continue }
            let daysInYear = DateUtil.isLeapYear(year) ? 366 : 365
            if let days = try? await api.fetchRangeDays(
                start: String(format: "%04d-01-01", year), days: daysInYear), !days.isEmpty {
                yearDaysCache[String(year)] = days
            }
        }
        payInputsVersion += 1
    }

    /// 某月工资里的三薪日期与加班天数（日历用）：三薪日 = 法定节假日上班的天里、
    /// 超出基本天数的那几天（按日期顺序取前 tripleDays 天，与工资页 tripleDates 一致）；
    /// 加班天数 = 工资算法的 overtimeDays。只在看自己班时用（别人的班没有我的工资）。
    /// 本地算（computeLocalPay，带缓存）；输入没到齐算不出时返回 nil（日历先不标，等输入到了重画）。
    func triplePayInfo(year: Int, month: Int) -> (tripleDates: Set<String>, tripleDays: Double, overtimeDays: Double)? {
        guard viewTeam == myTeam else { return nil }
        // 1.1.4：走 payFor（带 payCache 备忘），不再每次调 computeLocalPay 现算。
        guard let pay = payFor(year: year, month: month) else { return nil }
        // 三薪按班次标：按时间顺序累加每一天的班次数，累计班次还没达到三薪数那几天都标
        // （双班那天 2 个班次，一天就占满 2 个三薪；只有部分班次算三薪那天也标）。
        let dates = pay.tripleDates ?? []
        let target = pay.tripleDays ?? 0
        var tripleSet = Set<String>()
        var used = 0.0
        for td in dates {
            if used < target, let d = td.date { tripleSet.insert(d) }
            used += Double(ShiftStyle.parts(of: td.shift ?? "").count)
        }
        return (tripleSet, pay.tripleDays ?? 0, pay.overtimeDays ?? 0)
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

    // MARK: 写操作（调班 / 请假 / 加班）——乐观更新 + 后台静默同步

    /// 本地先改当天的班次（界面立刻变），再后台同步到服务端；
    /// 同步成功后从服务端刷新一次（权威数据），失败则刷回来（回滚）并把错误写进 errorMessage。
    private func applyLeaveLocally(date: String, type: String?, note: String?) {
        guard var m = month, var days = m.days,
              let i = days.firstIndex(where: { $0.date == date }) else { return }
        var d = days[i]
        d.onLeave = true
        d.leaveType = type
        d.leaveNote = note
        days[i] = d
        m.days = days
        month = m
        let mk = payCacheKey(year: currentYearMonth.year, month: currentYearMonth.month)
        monthCache[monthCacheKey(team: viewTeam, year: currentYearMonth.year, month: currentYearMonth.month)] = m
        // 1.1.5：请假乐观更新也要让日历各页重拍快照（日历立刻变，不等后台刷新）。
        calendarVersion += 1
        var rec = leaves.first { $0.date == date } ?? LeaveRecord(date: date)
        rec.type = type; rec.note = note
        if let j = leaves.firstIndex(where: { $0.date == date }) { leaves[j] = rec } else { leaves.append(rec) }
        leavesCache[mk] = leaves
    }

    /// 后台同步一趟：成功后刷新权威数据，失败刷回来回滚并记错（不抛给界面，界面已经显示“已保存”）。
    private func syncInBackground(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
                await refreshMonth()
                await refreshPayInputs()
                await refreshPay()
            } catch {
                await refreshMonth()
                errorMessage = (error as? APIError)?.message ?? error.localizedDescription
                AppLogger.shared.log("同步失败：\(errorMessage ?? "")", tag: "Sync")
            }
        }
    }

    func submitLeave(date: String, type: String?, note: String?) async {
        applyLeaveLocally(date: date, type: type, note: note)
        persistCache()
        syncInBackground {
            try await self.api.postLeave(date: date, type: type, note: note)
        }
    }

    // MARK: 调班互换（空间那套，1.2.9.001 第 31 条）

    /// 四班同取：从 start 起连续 N 天、四个班组的日程（调班候选卡片与还班日列表用）。
    /// 当天详情打开调班/请假流程时现取（数据小、一次取够当月窗口），不做长期缓存。
    func fetchTeamsRange(start: String, days: Int) async throws -> TeamsRangeResponse {
        try await api.fetchTeamsRange(start: start, days: days)
    }

    /// 提交调班（1.2.9.001 第 31 条：空间那套，配对互换）：
    /// 替班日我休息、partner 替我上 partnerShift（对方那天最终的班）；
    /// paybackDate 为空 = 待还班，给了就同时写还班日（我上 paybackMyShift，对方休息）。
    /// 只写我自己的记录，不动对方账号。
    /// 与乐观更新的那几路不同，这里等服务端回话再报成功——连班禁令由服务端最终裁定，
    /// 失败要把服务端的中文错误原样显示出来，不能先报“已保存”再悄悄回滚。
    func submitSwap(date: String, partner: String, partnerShift: String, note: String?,
                    paybackDate: String?, paybackMyShift: String?) async throws -> SwapSaveResult {
        let result = try await api.postSwap(date: date, myShift: nil, partner: partner, partnerShift: partnerShift,
                                            note: note, paybackDate: paybackDate, paybackMyShift: paybackMyShift)
        // 先把替班日（+还班日）的服务端最新状态直接补进日历缓存，日历立刻变；
        // 整月刷新随后跑一遍，把统计和记录列表也对上。
        await refreshDayOnCalendar(date: date)
        if let payback = result.paybackDate { await refreshDayOnCalendar(date: payback) }
        await refreshMonth()
        await refreshPayInputs()
        await refreshPay()
        return result
    }

    /// 给待还班的调班补填还班日（1.2.9.001 第 31 条）：
    /// myShift = 还班日那天我最终上的班（我自己那天的班 + 那次调班里我被替掉的班并成的组合班）。
    func fillSwapPayback(coverDate: String, paybackDate: String, myShift: String) async throws {
        try await api.postSwapPayback(coverDate: coverDate, paybackDate: paybackDate, myShift: myShift)
        await refreshDayOnCalendar(date: coverDate)
        await refreshDayOnCalendar(date: paybackDate)
        await refreshMonth()
        await refreshPayInputs()
        await refreshPay()
    }

    /// 待还班的调班一直不还，转为请假（对方的顶岗保留）。
    func convertSwapToLeave(date: String, type: String?, note: String?) async throws {
        try await api.postSwapToLeave(date: date, type: type, note: note)
        await refreshDayOnCalendar(date: date)
        await refreshMonth()
        await refreshPayInputs()
        await refreshPay()
    }

    /// 请假日安排顶岗：对方替我上我那天的班。
    func submitLeaveCover(date: String, partner: String, partnerShift: String, note: String?) async throws {
        try await api.postLeaveCover(date: date, partner: partner, partnerShift: partnerShift, note: note)
        await refreshDayOnCalendar(date: date)
        await refreshMonth()
        await refreshPayInputs()
        await refreshPay()
    }

    /// 删一次调班（两边一起删）：删替班日连还班日一起恢复；删还班日则替班日变回待还班。
    /// 同样等服务端回话再报成功。
    func cancelSwap(date: String) async throws {
        // 先记下还班日：删完替班日，还班日那天也要一起恢复，事后就查不到了。
        let paybackDate = month?.day(for: date)?.paybackDate
        try await api.deleteOverride(date: date)
        await refreshDayOnCalendar(date: date)
        if let payback = paybackDate { await refreshDayOnCalendar(date: payback) }
        await refreshMonth()
        await refreshPayInputs()
        await refreshPay()
    }

    func submitLeaveRange(start: String, end: String, type: String?, note: String?) async {
        // 请一段假：本地先把范围内有班的日子都标上请假，后台再同步。
        if let s = DateUtil.date(from: start), let e = DateUtil.date(from: end) {
            let n = max(0, Int(e.timeIntervalSince(s) / 86400))
            for i in 0...min(n, 62) {
                if let d = Calendar.current.date(byAdding: .day, value: i, to: s) {
                    applyLeaveLocally(date: DateUtil.string(from: d), type: type, note: note)
                }
            }
        }
        persistCache()
        syncInBackground {
            try await self.api.postLeaveRange(start: start, end: end, type: type, note: note)
        }
    }

    func cancelLeave(date: String) async {
        if var m = month, var days = m.days, let i = days.firstIndex(where: { $0.date == date }) {
            var d = days[i]
            d.onLeave = false; d.leaveType = nil; d.leaveNote = nil
            days[i] = d
            m.days = days
            month = m
            // 日历网格读 monthCache：只改 month 不写缓存，网格要等后台刷新才变（1.1.2 的 bug）。
            let comps = DateUtil.yearMonth(of: DateUtil.date(from: date) ?? Date())
            monthCache[monthCacheKey(team: viewTeam, year: comps.year, month: comps.month)] = m
            // 1.1.5：取消请假也要让日历各页重拍快照（日历立刻变，不等后台刷新）。
            calendarVersion += 1
            leaves.removeAll { $0.date == date }
            leavesCache[payCacheKey(year: comps.year, month: comps.month)] = leaves
        }
        persistCache()
        syncInBackground { try await self.api.deleteLeave(date: date) }
    }

    /// 记加班：几点到几点，服务端算时长（跨夜自动加 24 小时）。一天一条，改了就覆盖。
    /// 本地先记一条（时长当场算），后台再同步；失败刷回来回滚。
    func submitOvertime(date: String, start: String, end: String, note: String?) async {
        let minutes = OvertimeCalc.minutes(start: start, end: end)
        let rec = OvertimeRecord(date: date, start: start, end: end, minutes: minutes, note: note)
        if let i = overtime.firstIndex(where: { $0.date == date }) { overtime[i] = rec } else { overtime.append(rec) }
        let mk = payCacheKey(year: currentYearMonth.year, month: currentYearMonth.month)
        overtimeCache[mk] = overtime
        persistCache()
        syncInBackground {
            _ = try await self.api.postOvertime(date: date, start: start, end: end, note: note)
        }
    }

    func deleteOvertime(date: String) async {
        overtime.removeAll { $0.date == date }
        let mk = payCacheKey(year: currentYearMonth.year, month: currentYearMonth.month)
        overtimeCache[mk] = overtime
        persistCache()
        syncInBackground { try await self.api.deleteOvertime(date: date) }
    }

    /// 改当月录入数里的某一个字段（1.2.7 起每人改自己的）：
    /// 老爷改全局 config.pay.months；同事改自己账号的单月录入（服务端存 user.payMonths，不碰全局）。
    /// 本地先改掉当月录入数、立刻重算，后台再同步到服务端。
    /// value 传 nil 表示清掉该覆盖值（恢复公式计算）。
    func updatePayMonthField(monthKey: String, field: PayRecordField, value: Double?) async {
        // 先算出改完的那条记录（两边同一段 switch，只写一次）。
        func applying(_ rec: PayMonthRecord) -> PayMonthRecord {
            var r = rec
            switch field {
            case .deptPerf: r.deptPerf = value
            case .perfCoef: r.perfCoef = value
            case .bonusCoef: r.bonusCoef = value
            case .overtimeDays: r.overtimeDays = value
            case .utilities: r.utilities = value
            }
            return r
        }
        if isOwner {
            var cfg = payConfig ?? PayConfigData()
            var months = cfg.months ?? [:]
            months[monthKey] = applying(months[monthKey] ?? PayMonthRecord())
            cfg.months = months
            payConfig = cfg
        } else {
            userMonths[monthKey] = applying(userMonths[monthKey] ?? PayMonthRecord())
        }
        await refreshPay()
        persistCache()
        Task {
            do {
                _ = try await api.postPayMonthField(monthKey: monthKey, field: field, value: value)
            } catch {
                errorMessage = (error as? APIError)?.message ?? error.localizedDescription
                AppLogger.shared.log("单月录入同步失败：\(errorMessage ?? "")", tag: "Sync")
                // 同步失败要把本地乐观改动刷回来：老爷重取全局配置，同事重取自己的 profile（payMonths）。
                if isOwner {
                    await refreshPayInputs()
                } else if let me = try? await api.fetchMe() {
                    user = me
                    if let pm = me.payMonths { userMonths = pm }
                }
                await refreshPay()
            }
        }
    }

    // MARK: - 今日预估与小组件

    /// 今日预估用的基本工资与补贴率（与 monthPay 同链）：生效表（当月）> 个人设置 > 全局 > 默认。
    /// 排班页今日卡片、当天详情、小组件快照共用。
    var todayPayInputs: (baseSalary: Double, earlyRate: Double, midRate: Double, mealRate: Double) {
        let ym = DateUtil.yearMonth(of: Date())
        let key = payCacheKey(year: ym.year, month: ym.month)
        let global = payConfig?.settings ?? PayGlobalSettings()
        let base = PayCalc.resolvedBaseSalary(effective: payConfig?.effective ?? [:], userSettings: user?.paySettings, global: global, monthKey: key)
        return (base, global.earlyRate ?? 70, global.midRate ?? 30, global.mealRate ?? 10)
    }

    /// 某天预估用的全套输入（第 40 条）：基本工资/补贴率/日工资（与 monthPay 同链）
    /// + PayCalc.dayEstimateInputs 算好的当日分摊与加成。排班页今日卡片（传今天）、
    /// 当天详情（传那天）、小组件快照（传今天）共用。本地算不出当月工资
    /// （缺全年天数或配置）时输入全 0——预估显示 ¥0.00，不崩；新口径没有只算工资的
    /// 退路（分摊要当月工资），等工资刷出来就正常了。
    func estimateInputs(for dateString: String) -> (baseSalary: Double, earlyRate: Double, midRate: Double, dailyRate: Double, inputs: PayCalc.DayEstimateInputs) {
        let date = DateUtil.date(from: dateString) ?? Date()
        let ym = DateUtil.yearMonth(of: date)
        let key = payCacheKey(year: ym.year, month: ym.month)
        let global = payConfig?.settings ?? PayGlobalSettings()
        let base = PayCalc.resolvedBaseSalary(effective: payConfig?.effective ?? [:], userSettings: user?.paySettings, global: global, monthKey: key)
        var inputs = PayCalc.DayEstimateInputs()
        if let pay = payFor(year: ym.year, month: ym.month) {
            let monthDays = (yearDaysCache[String(ym.year)] ?? []).filter { $0.date.hasPrefix(key) }.map { (date: $0.date, shift: $0.shift, onLeave: $0.onLeave ?? false) }
            inputs = PayCalc.dayEstimateInputs(dateString: dateString, monthDays: monthDays, pay: pay, baseSalary: base, dailyRate: base / 21.75, basicDays: PayCalc.basicDays(year: ym.year, month: ym.month))
        }
        return (base, global.earlyRate ?? 70, global.midRate ?? 30, base / 21.75, inputs)
    }

    /// 今日预估用的全套输入（estimateInputs 传今天）。
    var todayEstimateInputs: (baseSalary: Double, earlyRate: Double, midRate: Double, dailyRate: Double, inputs: PayCalc.DayEstimateInputs) {
        estimateInputs(for: DateUtil.string(from: Date()))
    }

    // MARK: - 工资引导（第 30 条，2026-11-26）

    /// 工资引导弹窗（第 30 条）：管理端给用户开了工资权限后，下次进软件弹出来走一遍工资引导。
    /// 触发：启动/同步时发现 payAccess 从 false 变成 true、且还没走过这遍引导。
    /// 已有权限、设定填好了的老用户不弹（他们的 payAccess 一直是 true，没经过 false→true 的翻转）。
    @Published var needsPayGuide = false

    private static func userKey(for profile: UserProfile?) -> String {
        profile?.id ?? profile?.username ?? ""
    }

    private var payGuideDoneKey: String { "paiban.payGuideDone." + Self.userKey(for: user) }
    private var lastPayAccessKey: String { "paiban.lastPayAccess." + Self.userKey(for: user) }

    private var payGuideDone: Bool {
        get { UserDefaults.standard.bool(forKey: payGuideDoneKey) }
        set { UserDefaults.standard.set(newValue, forKey: payGuideDoneKey) }
    }

    /// 每次服务端 profile 刷新（user 被赋值）后调：看 payAccess 是不是刚从 false 翻成 true。
    /// 只在主界面已就绪（引导已过）时才弹；引导页里不弹。
    /// 跳过（以后再说）不记完成、不更新上次权限——下次启动还会再弹，直到走完为止。
    private func checkPayGuide() {
        guard let u = user, u.onboardingDone == true else { return }
        guard !payGuideDone else { return }
        let currentAccess = u.payAccess ?? true
        guard currentAccess else {
            // 还没开通：记下当前状态（false），等以后翻成 true 再弹。
            UserDefaults.standard.set(false, forKey: lastPayAccessKey)
            return
        }
        let last = UserDefaults.standard.object(forKey: lastPayAccessKey) as? Bool
        let flipped = (last == false)
        // 首跑这版：以前没记过权限，且用户一条工资设定都没填过——当成刚开通，弹一次。
        // 已有权限的老用户都有 paySettings（哪怕只填了一项），不会误弹。
        let firstRunUnsetUp = (last == nil && u.paySettings == nil)
        if flipped || firstRunUnsetUp {
            needsPayGuide = true
            // 先不更新 lastPayAccess：跳过的话下次启动还会再弹；走完引导时再记。
        } else {
            UserDefaults.standard.set(true, forKey: lastPayAccessKey)
        }
    }

    /// 工资引导走完了：记完成、记下当前权限，下次不再弹。
    func completePayGuide() {
        payGuideDone = true
        UserDefaults.standard.set(true, forKey: lastPayAccessKey)
        needsPayGuide = false
    }

    /// 工资引导点「以后再说」：这次不弹了，但不记完成——下次进软件还会再弹，直到走完为止。
    func skipPayGuide() {
        needsPayGuide = false
    }

    /// 小组件深链：paiban://schedule 进排班页，paiban://pay 进工资页。
    /// 没登录时先记下来，登录后进主界面再跳（MainTabView 的 .task 里应用）。
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "paiban" else { return }
        let tab: Int?
        switch url.host {
        case "schedule": tab = 0
        case "pay": tab = 1
        default: tab = nil
        }
        guard let tab else { return }
        if isLoggedIn {
            selectedTab = tab
        } else {
            pendingDeepLinkTab = tab
        }
    }

    /// 小组件快照：App 数据变了就写一份到 App Group 共享区，并通知小组件刷新。
    /// 内容不变时不重复写（WidgetCenter 刷新有系统预算，别浪费）。
    func publishWidgetSnapshot() {
        guard isLoggedIn else { return }
        let snap = buildWidgetSnapshot()
        guard snap != lastPublishedSnapshot else { return }
        lastPublishedSnapshot = snap
        WidgetSnapshotStore.save(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 小组件快照：今天 + 本周 7 天 + 本月每天（带调班/请假）+ 本月工资 + 解析好的工资口径。
    /// 本周从周日开头；本月天数优先用已加载的全年天数/当月数据，缺的按换班记录解析后的班组 + 8 天一轮基础班次补。
    private func buildWidgetSnapshot() -> WidgetSnapshot {
        let now = Date()
        let todayString = DateUtil.string(from: now)
        let ym = DateUtil.yearMonth(of: now)
        let history = user?.teamHistory ?? []
        let inputs = todayPayInputs
        // 某天的数据：优先全年天数/当月数据（带调班请假），没有就按班组 + 8 天一轮基础班次算。
        func dayFor(_ date: Date) -> WidgetSnapshot.Day {
            let ds = DateUtil.string(from: date)
            let y = DateUtil.yearMonth(of: date).year
            if let d = yearDaysCache[String(y)]?.first(where: { $0.date == ds }) {
                return WidgetSnapshot.Day(date: ds, shift: d.shift, onLeave: d.onLeave == true, leaveType: d.leaveType, isToday: ds == todayString)
            }
            if let d = month?.day(for: ds) {
                return WidgetSnapshot.Day(date: ds, shift: d.shift, onLeave: d.onLeave == true, leaveType: d.leaveType, isToday: ds == todayString)
            }
            let team = ScheduleCalculator.teamForDate(ds, history: history, fallbackTeam: myTeam)
            let base = ScheduleCalculator.baseShift(team: team, date: date, rotation: rotation)
            return WidgetSnapshot.Day(date: ds, shift: base, onLeave: false, leaveType: nil, isToday: ds == todayString)
        }
        // 本周（周日开头）。
        let weekday = DateUtil.calendar.component(.weekday, from: now) - 1 // 0=周日
        let weekStart = DateUtil.addingDays(now, -weekday)
        let week = (0..<7).map { dayFor(DateUtil.addingDays(weekStart, $0)) }
        // 本月每天。
        let dim = DateUtil.daysInMonth(year: ym.year, month: ym.month)
        var monthDays: [WidgetSnapshot.Day] = []
        for d in 1...dim {
            if let date = DateUtil.calendar.date(from: DateComponents(year: ym.year, month: ym.month, day: d)) {
                monthDays.append(dayFor(date))
            }
        }
        // 本月工资（本地算好的那份）。没工资权限不放工资数（第 29 条补充规矩：钱跟着 payAccess 走）。
        let hasPayAccess = payAccess
        let payMonth = hasPayAccess ? payFor(year: ym.year, month: ym.month) : nil
        let pay = payMonth.map { WidgetSnapshot.Pay(year: ym.year, month: ym.month, salarySubtotal: $0.salarySubtotal, salaryNet: $0.salaryNet, bonusAfterTax: $0.bonusAfterTax, grandTotal: $0.grandTotal, bonusTotal: $0.bonusTotal, incomeTax: $0.incomeTax, attendance: $0.attendance, tripleDays: $0.tripleDays, overtimeDays: $0.overtimeDays) }
        // 今日预估输入（第 40 条）：当日分摊与加成（dayEstimateInputs 算好的整份）；
        // 没权限时归 0（小组件不显示钱）。
        let estInputs = estimateInputs(for: todayString)
        return WidgetSnapshot(
            savedAt: now,
            displayName: user?.displayName ?? user?.username,
            team: myTeam,
            teamHistory: history,
            today: dayFor(now),
            week: week,
            monthDays: monthDays,
            monthYear: ym.year,
            month: ym.month,
            pay: pay,
            baseSalary: inputs.baseSalary,
            earlyRate: inputs.earlyRate,
            midRate: inputs.midRate,
            mealRate: inputs.mealRate,
            payAccess: hasPayAccess,
            todayInputs: hasPayAccess ? estInputs.inputs : PayCalc.DayEstimateInputs()
        )
    }

    /// 保存资料：引导流程与设置页共用（team / paySettings / onboardingDone / displayName 只传给定的字段）。
    /// 注意：PUT /me/profile 只回 profile 字段（team / teamHistory / paySettings / onboardingDone / displayName），
    /// 没有 username / id / role；直接整包替换会把账号名丢成 nil（设置页账号显示“—”就是这么来的）。
    /// 这里合并：保留原有身份字段，只更新 profile 字段。
    /// 1.2.7.001：rotation 与 displaySettings 也走同一合并（服务端回了就更新，没回保留本地）。
    func saveProfile(team: String? = nil, paySettings: [String: Any]? = nil, onboardingDone: Bool? = nil, displayName: String? = nil, rotation: RotationSetting? = nil, displaySettings: CalendarDisplaySettings? = nil) async throws {
        let updated = try await api.updateProfile(team: team, paySettings: paySettings, onboardingDone: onboardingDone, displayName: displayName, rotation: rotation?.asDict(), displaySettings: displaySettings?.asDict())
        var merged = user ?? updated
        merged.team = updated.team ?? merged.team
        merged.teamHistory = updated.teamHistory ?? merged.teamHistory
        merged.paySettings = updated.paySettings ?? merged.paySettings
        merged.onboardingDone = updated.onboardingDone ?? merged.onboardingDone
        merged.displayName = updated.displayName ?? merged.displayName
        merged.payMonths = updated.payMonths ?? merged.payMonths
        merged.payAccess = updated.payAccess ?? merged.payAccess
        merged.rotation = updated.rotation ?? merged.rotation
        merged.displaySettings = updated.displaySettings ?? merged.displaySettings
        merged.isBetaTester = updated.isBetaTester ?? merged.isBetaTester
        user = merged
        if let pm = merged.payMonths { userMonths = pm }
        if let ds = merged.displaySettings {
            calendarDisplay = ds
            ds.saveLocal()
        }
        if let team { viewTeam = team }
        persistCache()
    }

    /// 保存倒班设置（方式 / 班次 / 基准日 / 班组名 / 手动逐日班次）。
    /// 切方式时调用方先弹提示（切换后现有调班/请假记录按新循环重算，只重算基础轮次、不删记录）。
    func saveRotation(_ newRotation: RotationSetting) async throws {
        try await saveProfile(team: newRotation.team, rotation: newRotation)
        // 基础轮次变了：本地月缓存失效，重新拉当月（服务端按新方式算）。
        monthCache.removeAll()
        await refreshMonth()
    }

    /// 保存日历显示设置（本地 + 服务端同步）。
    func saveDisplaySettings(_ settings: CalendarDisplaySettings) async throws {
        calendarDisplay = settings
        settings.saveLocal()
        do {
            try await saveProfile(displaySettings: settings)
        } catch {
            // 服务端同步失败不报错：本地设置已生效，下次启动再同步。
            AppLogger.shared.log("显示设置服务端同步失败：\(error.localizedDescription)", tag: "Store")
        }
    }

    /// 手动模式：设某天的班次（shift = 班次名，如日班/中班/早班/白班/夜班/休息，
    /// 或自定义班次码 X1…）。名字按 RotationModes.shiftCode 转码；自定义码直接存。
    func setManualShift(date: String, shift: String) async throws {
        var r = rotation
        let code: String
        if shift.hasPrefix("X"), rotation.customShifts[shift] != nil {
            code = shift
        } else if shift == "休息" {
            code = "-"
        } else {
            code = RotationModes.shiftCode(for: shift)
        }
        r.manualShifts[date] = code
        try await saveRotation(r)
    }

    /// 手动模式：清除某天的手动排班（「无」按钮：删掉当天的手动记录，那天算休息）。
    func clearManualShift(date: String) async throws {
        var r = rotation
        r.manualShifts.removeValue(forKey: date)
        try await saveRotation(r)
    }

    /// 手动排班页：加一个自定义班次（名字 + 颜色），返回新码（X1/X2…）。
    func addCustomShift(name: String, colorHex: String) async throws -> String {
        var r = rotation
        var n = 1
        while r.customShifts["X\(n)"] != nil { n += 1 }
        let code = "X\(n)"
        r.customShifts[code] = CustomShift(name: name, color: colorHex)
        try await saveRotation(r)
        return code
    }

    /// 按日期取某天（周视图用）：先找月缓存（含调班/请假），没有就本地按轮次算一条。
    func dayFor(dateString: String) -> DaySchedule? {
        guard let date = DateUtil.date(from: dateString) else { return nil }
        let ym = DateUtil.yearMonth(of: date)
        let month = monthFor(year: ym.year, month: ym.month)
        if let day = (month.days ?? []).first(where: { $0.date == dateString }) { return day }
        // 本地算：基础轮次 + 当天日期。
        let base = rotation.baseShift(team: viewTeam, date: date)
        return DaySchedule(date: dateString, team: viewTeam, baseShift: base, shift: base,
                           weekday: DateUtil.calendar.component(.weekday, from: date) - 1)
    }

    /// 某天的实际班次（基础轮次 + 调班/请假后的结果；双班返回第一个班次）。
    /// 推送提醒用：只关心当天第一个班次几点开始。
    func shiftForDate(_ dateString: String, team: String, rotation: RotationSetting) -> String {
        guard let date = DateUtil.date(from: dateString) else { return "休息" }
        let ym = DateUtil.yearMonth(of: date)
        let month = monthFor(year: ym.year, month: ym.month)
        if let day = (month.days ?? []).first(where: { $0.date == dateString }) {
            let shift = day.shift
            if shift == "早中班" { return "早班" }
            if shift == "日中班" { return "日班" }
            return shift
        }
        return rotation.baseShift(team: team, date: date)
    }

    // MARK: 节假日（1.2.7.001，第 23 条）

    /// 拉取某年节假日（服务端缓存；失败时用内置表兜底，不报错）。
    /// 返回该年的节假日字典（key 日期）。
    func refreshHolidays(year: Int) async -> [String: HolidayDay] {
        do {
            let resp = try await api.fetchHolidays(year: year)
            var map: [String: HolidayDay] = [:]
            for d in resp.days ?? [] { map[d.date] = d }
            if !map.isEmpty {
                holidays.merge(map) { _, new in new }
                if let updatedAt = resp.updatedAt { holidaysUpdatedAt = updatedAt }
                return map
            }
        } catch {
            AppLogger.shared.log("节假日拉取失败，用内置表：\(error.localizedDescription)", tag: "Store")
        }
        // 兜底：内置表（2026 年已按官方通知修正；其他年份暂无内置数据）。
        var map: [String: HolidayDay] = [:]
        for d in BuiltinHolidays.days(for: year) { map[d.date] = d }
        holidays.merge(map) { _, new in new }
        return map
    }

    /// 启动时检查节假日更新：服务端 version 回的 holidaysUpdatedAt 变了就拉取新数据并刷新日历。
    /// 只刷新节假日标注，不动排班数据。失败静默（用内置表顶着）。
    func checkHolidaysUpdate() async {
        do {
            let info = try await api.fetchVersion(channel: UpdateChecker.channel)
            if let serverUpdatedAt = info.holidaysUpdatedAt,
               serverUpdatedAt != holidaysUpdatedAt {
                holidaysUpdatedAt = serverUpdatedAt
                let year = info.holidaysYear?.first ?? DateUtil.yearMonth(of: Date()).year
                _ = await refreshHolidays(year: year)
                return
            }
            // 服务端没给时间戳（老版本）或没变：只保证当年数据在本地。
            let year = DateUtil.yearMonth(of: Date()).year
            if holidays[DateUtil.string(from: Date())] == nil {
                _ = await refreshHolidays(year: year)
            }
        } catch { return }
        // 12 月进入 1 月时自动拉下一年。
        if DateUtil.yearMonth(of: Date()).month == 12 {
            _ = await refreshHolidays(year: DateUtil.yearMonth(of: Date()).year + 1)
        }
    }

    /// 某天的节假日（服务端数据优先，没有用内置表）。
    func holiday(for dateString: String) -> HolidayDay? {
        if let h = holidays[dateString] { return h }
        if let year = Int(dateString.prefix(4)) {
            return BuiltinHolidays.days(for: year).first { $0.date == dateString }
        }
        return nil
    }

    // MARK: 共享班表（1.2.7.001，第 24 条）

    /// 拉取共享列表（我分享的 + 同事分享给我的）。
    func fetchShares() async {
        do {
            let resp = try await api.fetchShares()
            sharesSent = resp.sent ?? []
            sharesReceived = resp.received ?? []
        } catch {
            AppLogger.shared.log("共享列表拉取失败：\(error.localizedDescription)", tag: "Store")
        }
    }

    /// 分享我的基础日历给同事（对方账号名/手机号 + 可选备注）。
    func shareSchedule(toUsername: String, note: String? = nil) async throws -> ScheduleShare {
        let share = try await api.shareSchedule(toUsername: toUsername, note: note)
        await fetchShares()
        return share
    }

    /// 撤销我发出的分享（或拒收发给我的）。
    func deleteShare(id: String) async throws {
        try await api.deleteShare(id: id)
        await fetchShares()
    }

    /// 分享人基础轮次变了，更新快照。
    func refreshShare(id: String) async throws {
        _ = try await api.refreshShare(id: id)
        await fetchShares()
    }

    /// 设置页显示的名字：优先显示名（displayName，自己改的），没有显示名显示账号名；
    /// 万一缓存里是旧的缺名字版本，用 Keychain 里登录时存的账号名兜底。
    /// 注意：显示名只是显示，登录用的账号名（username）不动。
    var displayUsername: String {
        if let name = user?.displayName, !name.isEmpty { return name }
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
    /// 调班/请假/加班先读本地缓存立刻显示，没缓存就清空（绝不留上个月的记录）；
    /// 网格没缓存先按本地 8 天一轮算顶上。后台刷新成功才更新缓存，失败保留旧缓存不弹错。
    private func applyCachedMonth() {
        let ym = currentYearMonth
        let mk = payCacheKey(year: ym.year, month: ym.month)
        swaps = swapsCache[mk] ?? []
        leaves = leavesCache[mk] ?? []
        overtime = overtimeCache[mk] ?? []
        // 网格走 monthFor：有真数据用真数据，没有本地算顶上（只算一次，记缓存里）。
        month = monthFor(year: ym.year, month: ym.month)
    }

    /// 某天的加班记录（没有就是 nil）。
    func overtime(for date: String) -> OvertimeRecord? {
        overtime.first { $0.date == date }
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

    /// 切渠道后立刻按新渠道查一次（1.2.7.002）：版本不一样就推出来（哪怕数字上更低），
    /// 只有版本完全一样才说已是最新版本。
    func checkForUpdateAfterChannelSwitch(channel: String) async {
        guard serverReachable || api.baseURL != nil else {
            updateNotice = "现在连不上服务器，稍后再试"
            return
        }
        UpdateChecker.channel = channel
        switch await UpdateChecker.checkAfterChannelSwitch(api: api, channel: channel) {
        case .updateAvailable(let info):
            pendingUpdate = info
        case .upToDate:
            updateNotice = "已是最新版本（当前 \(UpdateChecker.currentVersion)）"
        }
    }

    /// 取某渠道的最新版本（切渠道确认框里显示目标渠道最新版用）。
    func fetchVersionForChannel(_ channel: String) async -> VersionInfo? {
        try? await api.fetchVersion(channel: channel)
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
