import Foundation

/// 小组件服务端直拉（1.2.8）：App Group 不通时的后备路。
/// 根因：重签（全能签）用的描述文件常不带 group.com.paiban.app，
/// App 写不进快照（WidgetSnapshotStore.save 静默返回）、小组件也读不到，
/// 只显示「打开 App 登录后显示」占位——登录了也没用，锁屏那个也一样。
/// 改走服务端：小组件直接从服务器拉数据，不管怎么重签都能通。
/// 两条认领路（1.2.7.004）：① 设备直连（默认）——App 登录时把
/// identifierForVendor 登记到用户名下，小组件带 X-Device-Id 拉，不用填密钥；
/// ② 密钥直拉（手动后备）——小组件配置里填一次 API 密钥（App 设置页「小组件」里复制）。
/// 拉回的数据缓存到小组件自己的 UserDefaults，离线时显示上次的数，不回占位。
/// App Group 还通的机器上，优先用快照（快、离线也能看），这条路只是兜底；
/// App Group 代码与权限原样保留，后期上架商店（正规签名）时再用它。
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

    /// 密钥直拉（原有）：小组件配置里填了 API 密钥。
    static func fetchSnapshot(apiKey: String, now: Date = Date()) async -> WidgetSnapshot? {
        await fetchSnapshot(authHeader: ("X-API-Key", apiKey), now: now)
    }

    /// 设备直拉（1.2.7.004）：App 登录时登记过 identifierForVendor，
    /// 小组件带 X-Device-Id 拉数据，不用填密钥。
    static func fetchSnapshot(deviceId: String, now: Date = Date()) async -> WidgetSnapshot? {
        await fetchSnapshot(authHeader: ("X-Device-Id", deviceId), now: now)
    }

    /// 新鲜缓存（15 分钟内）：时间线关键路径上先用它立刻出数，不等网络；
    /// 缓存过期时才拉网，拉回后刷新缓存供下一次用。班次一天内不变，
    /// 15 分钟的旧数对小组件足够新鲜。
    static func loadFreshCached(maxAge: TimeInterval = 900) -> WidgetSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: cachedSnapshotKey),
              let at = UserDefaults.standard.object(forKey: cachedAtKey) as? Date,
              Date().timeIntervalSince(at) < maxAge,
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return nil }
        return snap
    }

    /// 本月 + 本周 + 本月工资，一次拉齐，拼成 WidgetSnapshot。
    /// 失败返回 nil（调用方回落缓存/占位）。
    /// 1.2.7.005：不走 ServerConfig.resolve() 的 /health 探活——探活在小组件时间线
    /// 关键路径上最慢可拖 20 秒（云 10 秒 + 隧道 10 秒），WidgetKit 预算一到就杀
    /// 扩展、改显示系统占位（灰条 + 色块）。改成直连云拉数，失败再试 NAS 隧道；
    /// 单个地址 10 秒封顶，超时即回落缓存。
    private static func fetchSnapshot(authHeader: (name: String, value: String), now: Date) async -> WidgetSnapshot? {
        var bases = [ServerConfig.cloudBaseURL]
        if let tunnel = ServerConfig.nasTunnelBaseURL, !tunnel.isEmpty {
            bases.append(tunnel)
        }
        for base in bases {
            if let snap = await fetchFrom(base: base, authHeader: authHeader, now: now) {
                return snap
            }
        }
        return nil
    }

    /// 单个地址拉一次，10 秒封顶（超时即 nil，调用方回落缓存）。
    private static func fetchFrom(base: String, authHeader: (name: String, value: String), now: Date) async -> WidgetSnapshot? {
        await withTimeout(seconds: 10) {
            let cal = DateUtil.calendar
            let ym = DateUtil.yearMonth(of: now)
            let weekday = cal.component(.weekday, from: now) // 1=周日
            let weekStart = DateUtil.addingDays(cal.startOfDay(for: now), -(weekday - 1))
            let weekStartStr = DateUtil.string(from: weekStart)
            do {
                async let me = get(path: "/api/v1/me", base: base, authHeader: authHeader, as: UserProfile.self)
                async let range = get(path: "/api/v1/me/range", base: base, authHeader: authHeader, query: ["start": weekStartStr, "days": "7"], as: RangeResponse.self)
                async let month = get(path: "/api/v1/me/month", base: base, authHeader: authHeader, query: ["year": "\(ym.year)", "month": "\(ym.month)"], as: MonthSchedule.self)
                async let pay = get(path: "/api/v1/me/pay", base: base, authHeader: authHeader, query: ["year": "\(ym.year)", "month": "\(ym.month)"], as: PayMonth.self)
                async let config = getConfig(base: base, authHeader: authHeader)
                let (profile, rangeResp, monthResp, payResp, rates) = try await (me, range, month, pay, config)
                guard let snap = buildSnapshot(profile: profile, range: rangeResp, month: monthResp, pay: payResp, rates: rates, now: now) else { return nil }
                saveCached(snap)
                return snap
            } catch {
                return nil
            }
        }
    }

    /// 给一次异步活加时限：活先完成就取它的结果，时限先到就回 nil 并取消活。
    private static func withTimeout<T>(seconds: TimeInterval, _ work: @escaping () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            for await result in group {
                group.cancelAll()
                return result
            }
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
    private static func getConfig(base: String, authHeader: (name: String, value: String)) async -> PayGlobalSettings {
        if let resp = try? await get(path: "/api/v1/config", base: base, authHeader: authHeader, as: ServerConfigData.self) {
            return resp.pay?.settings ?? PayGlobalSettings()
        }
        return PayGlobalSettings()
    }

    // MARK: - 最小 HTTP 客户端（只走一条认证头：X-API-Key 或 X-Device-Id；信封 {ok, data}）

    private struct Envelope<T: Decodable>: Decodable {
        var ok: Bool
        var data: T?
        var error: String?
    }

    private static func get<T: Decodable>(path: String, base: String, authHeader: (name: String, value: String), query: [String: String] = [:], as type: T.Type) async throws -> T {
        var comps = URLComponents(string: base + path)
        if !query.isEmpty {
            comps?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps?.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue(authHeader.value, forHTTPHeaderField: authHeader.name)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let env = try JSONDecoder().decode(Envelope<T>.self, from: data)
        guard env.ok, let value = env.data else { throw URLError(.cannotDecodeContentData) }
        return value
    }
}
