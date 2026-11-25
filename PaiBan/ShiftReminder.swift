import Foundation
import UserNotifications

/// 班次推送提醒（1.2.7.001，第 23 条）：本地通知，不走推送服务、不常驻后台。
/// 开：请求权限后，把未来 7 天每个班次前 30 分钟排一条通知；
/// 排班变了（调班/请假/切方式/换班组）重新排；关：取消全部；
/// 权限被拒：开关自动关掉并提示去系统设置里开。
/// UserDefaults key：shiftReminderEnabled（默认开）。
enum ShiftReminder {
    static let enabledKey = "shiftReminderEnabled"
    static let calendarExpandKey = "calendarDefaultExpandMonth"
    static let removeAdsKey = "vipRemoveAds"

    /// 开关当前值（默认开）。
    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// 日历默认展开整月（默认关：打开是当周紧凑视图）。
    static var defaultExpandMonth: Bool {
        get { UserDefaults.standard.bool(forKey: calendarExpandKey) }
        set { UserDefaults.standard.set(newValue, forKey: calendarExpandKey) }
    }

    /// 去除广告（VIP 功能；广告系统还没来，只存标识。非 VIP 打开只存标识，不收费、不跳转）。
    static var removeAds: Bool {
        get { UserDefaults.standard.bool(forKey: removeAdsKey) }
        set { UserDefaults.standard.set(newValue, forKey: removeAdsKey) }
    }

    /// 请求通知权限（返回是否拿到）。
    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// 当前通知权限状态（.authorized / .denied / .notDetermined）。
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// 打开提醒：请求权限 → 排未来 7 天的班前 30 分钟通知。
    /// 权限被拒返回 false（调用方把开关关掉并提示去系统设置）。
    static func enable(store: AppStore) async -> Bool {
        let granted = await requestPermission()
        guard granted else { return false }
        await reschedule(store: store)
        return true
    }

    /// 关闭提醒：取消全部已排的班次通知。
    static func disable() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// 重新排未来 7 天的班前提醒（排班变了调用）。
    static func reschedule(store: AppStore) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard isEnabled else { return }
        let status = await authorizationStatus()
        guard status == .authorized else { return }

        let team = store.myTeam
        let rotation = store.rotation
        let now = Date()
        for offset in 0..<7 {
            let date = DateUtil.addingDays(now, offset)
            let dateString = DateUtil.string(from: date)
            // 当天的班次（基础轮次 + 调班/请假后的实际班次，取自本地月缓存）。
            let shift = store.shiftForDate(dateString, team: team, rotation: rotation)
            guard shift == "日班" || shift == "中班" || shift == "早班" else { continue }
            let start = shiftStart(date: date, shift: shift)
            let fire = start.addingTimeInterval(-30 * 60)
            guard fire > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "上班提醒"
            content.body = "还有 30 分钟上\(shift)（\(ShiftStyle.timeRange(for: shift)））"
            content.sound = .default
            var comps = DateUtil.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            comps.second = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: "shift-\(dateString)-\(shift)",
                                                content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// 班次开始时间（当天）：早班 00:00、日班 08:00、中班 16:00。
    private static func shiftStart(date: Date, shift: String) -> Date {
        let hour: Int
        switch shift {
        case "日班": hour = 8
        case "中班": hour = 16
        default: hour = 0
        }
        var comps = DateUtil.calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        comps.minute = 0
        comps.second = 0
        return DateUtil.calendar.date(from: comps) ?? date
    }
}
