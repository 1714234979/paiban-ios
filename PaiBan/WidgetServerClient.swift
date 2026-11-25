import Foundation

/// 小组件服务端直拉（1.2.8）：App Group 不通时的后备路。
/// 根因：重签（全能签）用的描述文件常不带 group.com.paiban.app，
/// App 写不进快照（WidgetSnapshotStore.save 静默返回）、小组件也读不到，
/// 只显示「打开 App 登录后显示」占位——登录了也没用，锁屏那个也一样。
/// 改走服务端：小组件配置里填一次 API 密钥（App 设置页「小组件」里复制），
/// 存在小组件自己的存储里，不管怎么重签都能通。
/// 拉回的数据缓存到小组件自己的 UserDefaults，离线时显示上次的数，不回占位。
/// App Group 还通的机器上，优先用快照（快、离线也能看），这条路只是兜底。
enum WidgetServerClient {
    private static let cachedSnapshotKey = "paiban.widgetServerSnapshot"
    private static let cachedAtKey = "paiban.widgetServerSnapshotAt"

    /// 读缓存（小组件自己的 UserDefaults；App 读不到，也写不进）。
    static func loadCached() -> WidgetSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: cachedSnapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    private static func saveCached(_ snap: WidgetSnapshot) {
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: cachedSnapshotKey)
            UserDefaults.standard.set(Date(), forKey: cachedAtKey)
        }
    }

    /// 本月 + 本周 + 本月工资，一次拉齐，拼成 WidgetSnapshot。
    /// 失败返回 nil（调用方回落缓存/占位）。
    static func fetchSnapshot(apiKey: String, now: Date = Date()) async -> WidgetSnapshot? {
        guard let base = await ServerConfig.resolve() else { return nil }
        let cal = DateUtil.calendar
        let ym = DateUtil.yearMonth(of: now)
        let weekday = cal.component(.weekday, from: now) // 1=周日
        let weekStart = DateUtil.addingDays(cal.startOfDay(for: now), -(weekday - 1))
        let weekStartStr = DateUtil.string(from: weekStart)
        do {
            async let me = get(path: "/api/v1/me", base: base, apiKey: apiKey, as: UserProfile.self)
            async let range = get(path: "/api/v1/me/range", base: base, apiKey: apiKey, query: ["start": weekStartStr, "days": "7"], as: RangeResponse.self)
            async let month = get(path: "/api/v1/me/month", base: base, apiKey: apiKey, query: ["year": "\(ym.year)", "month": "\(ym.month)"], as: MonthSchedule.self)
            async let pay = get(path: "/api/v1/me/pay", base: base, apiKey: apiKey, query: ["year": "\(ym.year)", "month": "\(ym.month)"], as: PayMonth.self)
            async let config = getConfig(base: base, apiKey: apiKey)
            let (profile, rangeResp, monthResp, payResp, rates) = try await (me, range, month, pay, config)
            guard let snap = buildSnapshot(profile: profile, range: rangeResp, month: monthResp, pay: payResp, rates: rates, now: now) else { return nil }
            saveCached(snap)
            return snap
        } catch {
            return nil
        }
    }

    /// 拼快照：DaySchedule → WidgetSnapshot.Day；PayMonth → WidgetSnapshot.Pay。
    private static func buildSnapshot(profile: UserProfile, range: RangeResponse, month: MonthSchedule, pay: PayMonth, rates: PayGlobalSettings, now: Date) -> WidgetSnapshot? {
        let todayStr = DateUtil.string(from: now)
        func toDay(_ d: DaySchedule) -> WidgetSnapshot.Day {
            WidgetSnapshot.Day(date: d.date, shift: d.shift, onLeave: d.onLeave ?? false, leaveType: d.leaveType, isToday: d.date == todayStr)
        }
        let week = (range.days ?? []).map(toDay)
        let monthDays = (month.days ?? []).map(toDay)
        guard let today = monthDays.first(where: { $0.date == todayStr }) ?? week.first(where: { $0.date == todayStr }) else { return nil }
        let ym = DateUtil.yearMonth(of: now)
        let paySnap = WidgetSnapshot.Pay(
            year: ym.year, month: ym.month,
            salarySubtotal: pay.salarySubtotal, salaryNet: pay.salaryNet,
            bonusAfterTax: pay.bonusAfterTax, grandTotal: pay.grandTotal,
            bonusTotal: pay.bonusTotal, incomeTax: pay.incomeTax,
            attendance: pay.attendance, tripleDays: pay.tripleDays, overtimeDays: pay.overtimeDays)
        return WidgetSnapshot(
            savedAt: Date(),
            displayName: profile.displayName,
            team: profile.displayTeam,
            teamHistory: profile.teamHistory ?? [TeamHistoryEntry(team: profile.displayTeam, effectiveFrom: "\(ym.year)-\(String(format: "%02d", ym.month))-01")],
            today: today,
            week: week,
            monthDays: monthDays,
            monthYear: ym.year,
            month: ym.month,
            pay: paySnap,
            baseSalary: pay.baseSalary ?? profile.paySettings?.baseSalary ?? 2420,
            earlyRate: rates.earlyRate ?? 70,
            midRate: rates.midRate ?? 30,
            mealRate: rates.mealRate ?? 10)
    }

    /// 工资配置只取补贴率；拉不到就用默认 70/30/10（不让整个快照失败）。
    private static func getConfig(base: String, apiKey: String) async -> PayGlobalSettings {
        if let resp = try? await get(path: "/api/v1/config", base: base, apiKey: apiKey, as: ServerConfigData.self) {
            return resp.pay?.settings ?? PayGlobalSettings()
        }
        return PayGlobalSettings()
    }

    // MARK: - 最小 HTTP 客户端（只走 X-API-Key；信封 {ok, data}）

    private struct Envelope<T: Decodable>: Decodable {
        var ok: Bool
        var data: T?
        var error: String?
    }

    private static func get<T: Decodable>(path: String, base: String, apiKey: String, query: [String: String] = [:], as type: T.Type) async throws -> T {
        var comps = URLComponents(string: base + path)
        if !query.isEmpty {
            comps?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps?.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let env = try JSONDecoder().decode(Envelope<T>.self, from: data)
        guard env.ok, let value = env.data else { throw URLError(.cannotDecodeContentData) }
        return value
    }
}
