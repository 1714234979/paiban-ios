import Foundation

/// 小组件服务端直拉（1.2.7.006 重写）：只走设备直连，密钥那条路整个删掉。
/// 链路：App Group 快照 → 15 分钟内新鲜缓存 → 设备直连（X-Device-Id）→ 旧缓存。
/// App Group 还通的机器上，优先用快照（快、离线也能看），这条路只是兜底；
/// App Group 代码与权限原样保留，后期上架商店（正规签名）时再用它。
///
/// 之前为什么坏（别再犯）：设备拉取串行云 10 秒 + 隧道 10 秒，失败后密钥
/// 再拉 20 秒，两段加起来 40 秒，WidgetKit 预算一到就杀扩展、显示占位。
/// 这次云和隧道并行抢答、先到先得，总共 8 秒封顶；班次是核心必须拿到，
/// 工资和配置拉不到也不拖垮整个快照（班次照常显示）。
/// 拉回的数据缓存到小组件自己的 UserDefaults，离线时显示上次的数，不回占位。
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

    /// 设备直拉（唯一取数路）：云和 NAS 隧道并行抢答，先到先得，8 秒封顶。
    /// 以前串行云 10 秒 + 隧道 10 秒，再叠密钥 20 秒，WidgetKit 预算耗光才占位。
    static func fetchSnapshot(deviceId: String, now: Date = Date()) async -> WidgetSnapshot? {
        await withTimeout(seconds: 8) {
            await withTaskGroup(of: WidgetSnapshot?.self) { group in
                group.addTask { await fetchFrom(base: ServerConfig.cloudBaseURL, deviceId: deviceId, now: now) }
                if let tunnel = ServerConfig.nasTunnelBaseURL, !tunnel.isEmpty {
                    group.addTask { await fetchFrom(base: tunnel, deviceId: deviceId, now: now) }
                }
                for await snap in group {
                    if let snap {
                        group.cancelAll()
                        return snap
                    }
                }
                return nil
            }
        }
    }

    /// 单个地址拉一次：班次（range + month）是核心，必须拿到一个才有今天；
    /// me、工资、配置是添头，单个拉不到就用缓存里的值或默认值，不拖垮整个快照。
    /// 以前五个接口 async let 一票否决，任何一个失败整个小组件就空白。
    private static func fetchFrom(base: String, deviceId: String, now: Date) async -> WidgetSnapshot? {
        let cal = DateUtil.calendar
        let ym = DateUtil.yearMonth(of: now)
        let weekday = cal.component(.weekday, from: now) // 1=周日
        let weekStart = DateUtil.addingDays(cal.startOfDay(for: now), -(weekday - 1))
        let weekStartStr = DateUtil.string(from: weekStart)
        let header = ("X-Device-Id", deviceId)
        async let rangeTask = get(path: "/api/v1/me/range", base: base, authHeader: header, query: ["start": weekStartStr, "days": "7"], as: RangeResponse.self)
        async let monthTask = get(path: "/api/v1/me/month", base: base, authHeader: header, query: ["year": "\(ym.year)", "month": "\(ym.month)"], as: MonthSchedule.self)
        async let meTask = get(path: "/api/v1/me", base: base, authHeader: header, as: UserProfile.self)
        async let payTask = get(path: "/api/v1/me/pay", base: base, authHeader: header, query: ["year": "\(ym.year)", "month": "\(ym.month)"], as: PayMonth.self)
        async let configTask = getConfig(base: base, authHeader: header)
        // 逐个 try?，一个失败不连累其他（async let 并行，互不取消）。
        let range = try? await rangeTask
        let month = try? await monthTask
        let profile = try? await meTask
        let pay = try? await payTask
        let rates = await configTask
        guard let snap = buildSnapshot(profile: profile, range: range, month: month, pay: pay, rates: rates, now: now) else { return nil }
        saveCached(snap)
        return snap
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
    /// range/month 至少要有一个拿到今天，否则拼不出今天、回 nil；
    /// me 拿不到就用上次缓存里的班组/名字；工资拿不到就空着（工资组件显示
    /// 「打开 App 同步一下」，班次组件不受影响）。
    private static func buildSnapshot(profile: UserProfile?, range: RangeResponse?, month: MonthSchedule?, pay: PayMonth?, rates: PayGlobalSettings, now: Date) -> WidgetSnapshot? {
        let todayStr = DateUtil.string(from: now)
        func toDay(_ d: DaySchedule) -> WidgetSnapshot.Day {
            WidgetSnapshot.Day(date: d.date, shift: d.shift, onLeave: d.onLeave ?? false, leaveType: d.leaveType, isToday: d.date == todayStr)
        }
        let week = (range?.days ?? []).map(toDay)
        let monthDays = (month?.days ?? []).map(toDay)
        guard let today = monthDays.first(where: { $0.date == todayStr }) ?? week.first(where: { $0.date == todayStr }) else { return nil }
        let ym = DateUtil.yearMonth(of: now)
        let cached = loadCached()
        let team = profile?.displayTeam ?? cached?.team ?? ""
        let teamHistory = profile?.teamHistory ?? cached?.teamHistory ?? [TeamHistoryEntry(team: team, effectiveFrom: "\(ym.year)-\(String(format: "%02d", ym.month))-01")]
        let paySnap: WidgetSnapshot.Pay? = pay.map { p in
            WidgetSnapshot.Pay(
                year: ym.year, month: ym.month,
                salarySubtotal: p.salarySubtotal, salaryNet: p.salaryNet,
                bonusAfterTax: p.bonusAfterTax, grandTotal: p.grandTotal,
                bonusTotal: p.bonusTotal, incomeTax: p.incomeTax,
                attendance: p.attendance, tripleDays: p.tripleDays, overtimeDays: p.overtimeDays)
        }
        return WidgetSnapshot(
            savedAt: Date(),
            displayName: profile?.displayName ?? cached?.displayName,
            team: team,
            teamHistory: teamHistory,
            today: today,
            week: week,
            monthDays: monthDays,
            monthYear: ym.year,
            month: ym.month,
            pay: paySnap,
            baseSalary: pay?.baseSalary ?? profile?.paySettings?.baseSalary ?? cached?.baseSalary ?? 2420,
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

    // MARK: - 最小 HTTP 客户端（只走一条认证头 X-Device-Id；信封 {ok, data}）

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
        req.timeoutInterval = 8
        req.setValue(authHeader.value, forHTTPHeaderField: authHeader.name)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let env = try JSONDecoder().decode(Envelope<T>.self, from: data)
        guard env.ok, let value = env.data else { throw URLError(.cannotDecodeContentData) }
        return value
    }
}
