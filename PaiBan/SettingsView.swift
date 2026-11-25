import SwiftUI
import UIKit
import StoreKit
import WidgetKit

/// 设置页（1.1.3：二级菜单）：主界面只留入口行——账号与安全、工资设置、关于
/// 各开一个二级页面改细项；换班、管理后台、服务器、更新、反馈留在主界面。
/// 服务器那节只给老爷（张晓文）看，同事看不到。
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var isCheckingUpdate = false
    @State private var showFeedback = false
    @State private var showAdminBackend = false
    /// 切渠道确认（1.2.7.002）：目标渠道 + 目标渠道最新版（先拉到再弹框）。
    @State private var pendingChannel: String?
    @State private var pendingChannelVersion: String?
    @State private var showChannelSwitchConfirm = false
    @State private var isFetchingChannelVersion = false

    // 图一新增行（1.2.7.001）：班次推送提醒 / 去除广告。
    // 1.2.7.002：日历只留月视图，「日历默认展开整月」开关已删。
    @State private var reminderOn = ShiftReminder.isEnabled
    @State private var removeAds = ShiftReminder.removeAds
    @State private var showReminderDeniedAlert = false
    @State private var isRefreshingHolidays = false

    /// 账号与安全入口的副标题：昵称 · 手机号（脱敏，未绑就写未绑定）。
    private var accountSubtitle: String {
        let phone = PhoneUtil.masked(store.user?.phone) ?? "未绑定手机号"
        return "\(store.displayUsername) · \(phone)"
    }

    /// 工资设置入口的副标题：基本工资 · 奖金系数。
    private var paySubtitle: String {
        let settings = store.user?.paySettings
        let base = settings?.baseSalary.map { PayCalc.jsNum($0) } ?? "2420"
        let coef = settings?.bonusCoef.map { String(format: "%.1f", $0) } ?? "1.0"
        return "基本工资 \(base) · 奖金系数 \(coef)"
    }

    var body: some View {
        List {
            // 账号（图一没有，但必须保留在最上面）。
            Section {
                NavigationLink {
                    AccountSecurityView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("账号与安全")
                        Text(accountSubtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // 图一列表（精美、简约：行 + 细分隔线，不堆二级标题）。
            Section {
                // 桌面&锁屏小组件。
                NavigationLink {
                    WidgetsView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("桌面&锁屏小组件")
                        Text("五个小组件 · 怎么添加 · 数据状态 · 取数实测")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 班次设置：三个班次的时段（固定）。
                NavigationLink {
                    ShiftSettingsView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("班次设置")
                        Text("日班 08–16 · 中班 16–24 · 早班 00–08")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 倒班方式设置（新增）：手动/周期、四班三倒 5 种方式、班组名。
                NavigationLink {
                    RotationSettingsView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("倒班方式设置")
                        Text(rotationSubtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 日历显示设置（新增）：周一首日 / 法定节假日 / 农历 / 上下月。
                NavigationLink {
                    CalendarDisplaySettingsView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("日历显示设置")
                        Text(displaySubtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 班次推送提醒（本地通知，默认开）。
                Toggle("班次推送提醒", isOn: reminderBinding)
                Text("班次前 30 分钟提醒，未来 7 天。关掉取消全部提醒。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // 更新日历的节假日（手动刷新 + 上次更新时间）。
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("更新日历的节假日")
                        Text(holidaySubtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("立即更新") {
                        Task { await refreshHolidaysNow() }
                    }
                    .font(.subheadline)
                    .disabled(isRefreshingHolidays)
                }

                // 去除广告（VIP 功能；广告系统还没来，只存标识，不收费、不跳转）。
                Toggle("去除广告", isOn: removeAdsBinding)
                if removeAds {
                    Text("去除广告是 VIP 功能，等广告文档到了再开。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // 换班（保留）：更换班组 + 重新走一遍引导。
            Section {
                NavigationLink {
                    TeamChangeView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("更换班组")
                        Text("换到别的班组，从生效日零点起按新班组排班")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                NavigationLink {
                    OnboardingView()
                } label: {
                    Text("重新走一遍引导设置")
                }
            }

            // 工资设置：只有有工资权限的人才显示（1.2.7.001，第 23 条）。
            // 没权限的人连工资 Tab 都没有，设置页也不出现这一行。
            if store.payAccess {
                Section {
                    NavigationLink {
                        PaySettingsView()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("工资设置")
                            Text(paySubtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // 管理后台切换：只有老爷（张晓文）能看到。
            if store.isOwner {
                Section {
                    Button {
                        showAdminBackend = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("切换管理员后台")
                                Text("用最高权限打开管理端，可管账号、发 App 更新")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // 服务器线路只给老爷看（调试用），同事不显示。
            if store.isOwner {
                Section("服务器") {
                    HStack {
                        Text("当前线路")
                        Spacer()
                        Text(store.serverKind.displayName)
                            .foregroundColor(.secondary)
                    }
                    Text(store.serverBaseURL ?? "未连接")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("手动切换线路", selection: manualSelection) {
                        Text("自动选路").tag("")
                        ForEach(ServerConfig.allCandidates, id: \.baseURL) { candidate in
                            Text("\(candidate.kind.displayName) · \(candidate.baseURL)").tag(candidate.baseURL)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section {
                Button {
                    Task { await manualUpdateCheck() }
                } label: {
                    HStack {
                        Text("检查更新")
                        Spacer()
                        if isCheckingUpdate {
                            ProgressView()
                        } else {
                            Text("当前 \(UpdateChecker.currentVersion)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                // 内测渠道（1.2.8）：只有内测人员看得到这一行。
                // 1.2.7.002：点另一个渠道先弹确认（当前版本、目标渠道最新版、切了会怎样），
                // 确认后切渠道并立刻按新渠道查一次；版本不一样就推出来（哪怕数字更低）。
                if store.user?.isBetaTester == true {
                    HStack(spacing: 0) {
                        channelButton(title: "正式版", channel: "stable")
                        channelButton(title: "内测版", channel: "beta")
                    }
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("内测版只推给内测人员；切到内测后，下次打开 App 也按内测查。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Button {
                    showFeedback = true
                } label: {
                    HStack {
                        Text("意见反馈")
                        Spacer()
                        Text("会附上最近 24 小时运行日志")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 欢迎评分：标准系统评分弹窗（上架 App 才有效；侧载时无反应、不报错）。
                Button {
                    requestReview()
                } label: {
                    Text("欢迎评分")
                }
            }

            Section {
                NavigationLink {
                    AboutView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("关于我们")
                        Text("更新日志 · 功能介绍 · 版本 \(UpdateChecker.currentVersion)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("设置")
        .alert("检查更新", isPresented: updateNoticeBinding) {
            Button("知道了", role: .cancel) {
                store.updateNotice = nil
            }
        } message: {
            Text(store.updateNotice ?? "")
        }
        .alert("切换版本渠道", isPresented: $showChannelSwitchConfirm) {
            Button("取消", role: .cancel) {
                pendingChannel = nil
                pendingChannelVersion = nil
            }
            Button(pendingChannel == "beta" ? "切换到内测版" : "切换到正式版") {
                if let channel = pendingChannel {
                    // 1.2.7.003 修：Task 标 @MainActor，确认后改 @State 才会在主线程刷新。
                    Task { @MainActor in
                        isCheckingUpdate = true
                        defer { isCheckingUpdate = false }
                        await store.checkForUpdateAfterChannelSwitch(channel: channel)
                        pendingChannel = nil
                        pendingChannelVersion = nil
                    }
                }
            }
        } message: {
            Text(channelSwitchMessage)
        }
        .alert("通知权限被拒", isPresented: $showReminderDeniedAlert) {
            Button("知道了", role: .cancel) {}
            Button("去系统设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("班次推送提醒需要通知权限。请去系统设置里打开「排班空间」的通知，再回来开提醒。")
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackView()
        }
        .fullScreenCover(isPresented: $showAdminBackend) {
            AdminBackendView()
        }
    }

    // MARK: 图一新增行的状态与绑定

    /// 倒班方式入口副标题：当前方式名 + 班组。
    private var rotationSubtitle: String {
        let r = store.rotation
        if r.isManual { return "手动排班 · \(r.teamName(for: r.team))班" }
        let name = RotationModes.mode(id: r.modeId)?.name ?? r.modeId
        return "\(name) · \(r.teamName(for: r.team))班"
    }

    /// 日历显示入口副标题：开着的选项。
    private var displaySubtitle: String {
        let d = store.calendarDisplay
        var parts: [String] = []
        if d.mondayFirst { parts.append("周一首日") }
        if d.showHolidays { parts.append("法定节假日") }
        if d.showLunar { parts.append("农历") }
        if d.showAdjacentMonths { parts.append("上下月") }
        return parts.isEmpty ? "全部关闭" : parts.joined(separator: " · ")
    }

    /// 节假日入口副标题：上次更新时间。
    private var holidaySubtitle: String {
        if let updatedAt = store.holidaysUpdatedAt, !updatedAt.isEmpty {
            return "上次更新 \(updatedAt)"
        }
        return "每年 11 月自动更新，也可手动刷新"
    }

    /// 班次推送提醒开关：开 → 请求权限 + 排未来 7 天提醒；权限被拒自动关掉并提示。
    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { reminderOn },
            set: { newValue in
                reminderOn = newValue
                ShiftReminder.isEnabled = newValue
                if newValue {
                    Task {
                        let granted = await ShiftReminder.enable(store: store)
                        if !granted {
                            reminderOn = false
                            ShiftReminder.isEnabled = false
                            showReminderDeniedAlert = true
                        }
                    }
                } else {
                    ShiftReminder.disable()
                }
            }
        )
    }


    /// 去除广告开关（只存标识；广告系统还没来，非 VIP 打开只提示、不收费、不跳转）。
    private var removeAdsBinding: Binding<Bool> {
        Binding(
            get: { removeAds },
            set: { newValue in
                removeAds = newValue
                ShiftReminder.removeAds = newValue
            }
        )
    }

    /// 手动刷新节假日（当年 + 下一年）。
    private func refreshHolidaysNow() async {
        isRefreshingHolidays = true
        defer { isRefreshingHolidays = false }
        let year = DateUtil.yearMonth(of: Date()).year
        _ = await store.refreshHolidays(year: year)
        _ = await store.refreshHolidays(year: year + 1)
    }

    /// 欢迎评分：标准系统评分弹窗。
    private func requestReview() {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }

    // MARK: 手动选线路的绑定

    private var manualSelection: Binding<String> {
        Binding(
            get: { ServerConfig.manualOverride ?? "" },
            set: { newValue in
                Task {
                    if newValue.isEmpty {
                        await store.clearServerOverride()
                    } else {
                        await store.switchServer(to: newValue)
                    }
                }
            }
        )
    }

    private var updateNoticeBinding: Binding<Bool> {
        Binding(
            get: { store.updateNotice != nil },
            set: { newValue in
                if !newValue { store.updateNotice = nil }
            }
        )
    }

    // MARK: 检查更新

    /// 渠道按钮（1.2.7.002）：当前渠道高亮；点另一个渠道先弹确认。
    /// 1.2.7.003：拉取时被点的按钮转圈 + 变灰，让人知道已经点上了。
    /// 1.2.7.007：.plain 改 .borderless——List 行里并排两个 plain 按钮，
    /// 行手势把点击吞掉，两个都点不动；borderless 才各自接得到点击。
    /// 1.2.7.009：选中态和 guard 按装的版本定，不按存的更新偏好定。
    /// 存的偏好只在确认切换时才写，从不跟装的版本同步；一旦脱节，「正式版」
    /// 会被误标成已选中，点它 guard 直接 return，看着就是点不动——003/007
    /// 修的点按 mechanics 本来就没坏，真正拦住点击的是这个 guard。
    /// 装着内测版（四段号）时内测版是已选中、正式版一定点得动；装着正式版时反过来。
    private func channelButton(title: String, channel: String) -> some View {
        let installedChannel = UpdateChecker.installedChannel
        let selected = installedChannel == channel
        let fetching = isFetchingChannelVersion && !selected
        return Button {
            guard channel != installedChannel, !isFetchingChannelVersion else { return }
            Task { await askChannelSwitch(to: channel) }
        } label: {
            HStack(spacing: 6) {
                if fetching {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(title)
                    .font(.subheadline)
                    .bold(selected)
                    .foregroundColor(selected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(selected ? Color(.systemBackground) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.borderless)
        .disabled(isFetchingChannelVersion)
        .opacity(fetching ? 0.7 : 1.0)
    }

    /// 点另一个渠道：先弹确认框（立刻有反应），目标渠道最新版后台拉到再填进去。
    /// @MainActor（1.2.7.003 修）：拉网回来后改 @State（pendingChannel、确认框）
    /// 必须在主线程。之前这个函数不是 @MainActor，Task 在后台线程续跑，
    /// @State 改了界面也不刷新，确认框永远弹不出来，看起来就是「点不动」。
    /// 1.2.7.007：确认框不等拉网——003 的做法是拉到版本号才弹，网慢时点下去
    /// 半天没反应，看着还是点不动。现在点下立刻弹，版本号到了再补进文案。
    @MainActor
    private func askChannelSwitch(to channel: String) async {
        pendingChannel = channel
        pendingChannelVersion = nil
        showChannelSwitchConfirm = true
        isFetchingChannelVersion = true
        defer { isFetchingChannelVersion = false }
        let info = await store.fetchVersionForChannel(channel)
        pendingChannelVersion = info?.latestVersion
    }

    /// 确认框文案：当前版本、目标渠道最新版、切了会怎样。
    /// 1.2.7.007：版本号还在拉时显示「正在获取…」，拉到再补，拉不到才写未知。
    private var channelSwitchMessage: String {
        let current = UpdateChecker.currentVersion
        let currentLabel = UpdateChecker.channelLabel(for: current)
        let target = pendingChannel ?? "stable"
        let targetLabel = target == "beta" ? "内测版" : "正式版"
        let targetVersion: String
        if let v = pendingChannelVersion {
            targetVersion = v
        } else if isFetchingChannelVersion {
            targetVersion = "正在获取…"
        } else {
            targetVersion = "未知（没连上服务器）"
        }
        return "当前版本：\(currentLabel) \(current)\n目标渠道最新版：\(targetLabel) \(targetVersion)\n\n切过去后，App 按\(targetLabel)查更新；\(targetLabel)有新版就推给你装，不装也可以继续用现在的版本。"
    }

    /// 手动查更新（1.2.7.003 修：同 askChannelSwitch，@MainActor，
    /// 否则 isCheckingUpdate 的转圈在后台线程改了也不显示）。
    @MainActor
    private func manualUpdateCheck() async {
        isCheckingUpdate = true
        defer { isCheckingUpdate = false }
        await store.checkForUpdateManually()
    }
}

// MARK: - 设置二级页面（1.1.3）

/// 账号与安全（二级页面）：昵称、登录账号、班组、手机号（绑定/更换）、
/// 修改昵称、修改密码、切换账号、退出登录。退出登录放最下面，切换账号在它上面；
/// 退出只清登录状态，离线缓存保留。
struct AccountSecurityView: View {
    @EnvironmentObject private var store: AppStore

    @State private var showBindPhone = false
    @State private var showChangePhone = false
    @State private var showChangeName = false
    @State private var showChangePassword = false
    @State private var showLogoutConfirm = false
    @State private var showSwitchConfirm = false

    var body: some View {
        Form {
            Section("账号") {
                HStack {
                    Text("昵称")
                    Spacer()
                    Text(store.displayUsername)
                        .foregroundColor(.secondary)
                }
                // 登录用的账号名（username）：显示名可以改，这个不动；和显示名不一样才单独列一行。
                if let username = store.user?.username, !username.isEmpty, username != store.displayUsername {
                    HStack {
                        Text("登录账号")
                        Spacer()
                        Text(username)
                            .foregroundColor(.secondary)
                    }
                }
                HStack {
                    Text("班组")
                    Spacer()
                    Text("\(store.myTeam)班")
                        .foregroundColor(.secondary)
                }
                // 手机号：没绑点进去绑；绑了点进去换（换号走新号验证码，一月一次）。
                Button {
                    if store.user?.phone?.isEmpty == false {
                        showChangePhone = true
                    } else {
                        showBindPhone = true
                    }
                } label: {
                    HStack {
                        Text("手机号")
                        Spacer()
                        Text(PhoneUtil.masked(store.user?.phone) ?? "未绑定")
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("修改") {
                Button {
                    showChangeName = true
                } label: {
                    HStack {
                        Text("修改昵称")
                        Spacer()
                        Text("改显示名，登录账号不变")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Button {
                    showChangePassword = true
                } label: {
                    HStack {
                        Text("修改密码")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
            }

            // 切换账号（1.2.6）：退出当前登录、回登录页换个账号登；离线缓存保留。
            Section {
                Button {
                    showSwitchConfirm = true
                } label: {
                    Text("切换账号")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            Section {
                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    Text("退出登录")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } footer: {
                Text("退出后只清除本机的登录状态，离线缓存保留，下次登同一账号直接用缓存顶着。")
            }
        }
        .navigationTitle("账号与安全")
        .alert("切换账号", isPresented: $showSwitchConfirm) {
            Button("取消", role: .cancel) { }
            Button("切换", role: .destructive) {
                Task { await store.logout() }
            }
        } message: {
            Text("确定要切换账号吗？将退出当前登录，返回登录页。")
        }
        .alert("退出登录", isPresented: $showLogoutConfirm) {
            Button("取消", role: .cancel) { }
            Button("退出", role: .destructive) {
                Task { await store.logout() }
            }
        } message: {
            Text("确定要退出登录吗？只清除登录状态，离线缓存会保留。")
        }
        .sheet(isPresented: $showBindPhone) {
            BindPhoneSheet()
        }
        .sheet(isPresented: $showChangePhone) {
            BindPhoneSheet(mode: .change)
        }
        .sheet(isPresented: $showChangeName) {
            ChangeNameSheet()
        }
        .sheet(isPresented: $showChangePassword) {
            ChangePasswordSheet()
        }
    }
}

/// 工资设置（二级页面）：基本工资、奖金系数、养老月扣（反推缴费基数）、
/// 岗位、水电费、科室绩效奖金。保存走服务端接口，立即落盘，管理端即是最新。
struct PaySettingsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var baseSalaryText = ""
    @State private var bonusCoefText = ""
    @State private var pensionText = ""
    @State private var position = "员工"
    @State private var education = "其他"
    @State private var shortageAmountText = "0"
    @State private var shortageStartDate = Date()
    @State private var shortageEndDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var utilitiesText = ""
    @State private var deptPerfText = ""
    @State private var hireYear = 2018
    @State private var hireMonth = 10
    @State private var annualLeaveText = "5"
    @State private var isSavingPay = false
    @State private var saveMessage: String?

    private let positions = ["员工", "现场组长", "自控组长", "班长"]
    private let educations = ["专科", "本科", "其他"]

    /// 养老月扣反推缴费基数：基数 = 养老月扣 ÷ 0.08（保留两位小数）。
    private var derivedBase: Double? {
        guard let pension = Double(pensionText.trimmingCharacters(in: .whitespaces)), pension > 0 else { return nil }
        return PayCalc.round2(pension / 0.08)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("基本工资")
                    Spacer()
                    TextField("2420", text: $baseSalaryText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
                HStack {
                    Text("奖金系数")
                    Spacer()
                    TextField("1.0", text: $bonusCoefText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
                HStack {
                    Text("养老月扣")
                    Spacer()
                    TextField("475.04", text: $pensionText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
                if let base = derivedBase {
                    HStack {
                        Text("社保缴费基数")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(PayCalc.jsNum(base))（医疗 \(MoneyUtil.money(PayCalc.round2(base * 0.02))) · 失业 \(MoneyUtil.money(PayCalc.round2(base * 0.003)))）")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                }
                Picker("岗位", selection: $position) {
                    ForEach(positions, id: \.self) { p in
                        Text(p).tag(p)
                    }
                }
                Picker("学历", selection: $education) {
                    ForEach(educations, id: \.self) { e in
                        Text(e).tag(e)
                    }
                }
                HStack {
                    Text("入职时间")
                    Spacer()
                    Picker("年份", selection: $hireYear) {
                        ForEach(1990...Calendar.current.component(.year, from: Date()), id: \.self) { y in
                            Text("\(y)").tag(y)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("年")
                    Picker("月份", selection: $hireMonth) {
                        ForEach(1...12, id: \.self) { m in
                            Text("\(m)").tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("月")
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("剩余年休假天数")
                        Text("没休完的累计到明年，不清零；休了年假会自动扣")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    TextField("5", text: $annualLeaveText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("水电费")
                        Text("填平均每月水电费，某月单独改在工资页")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    TextField("60", text: $utilitiesText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("科室绩效奖金")
                        Text("填平均科室绩效奖金，0–10000；某月单独改在工资页")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    TextField("4000", text: $deptPerfText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("缺员补贴金额")
                        Text("期限内每月计入奖金，期限到了就不计了；填 0 表示没有")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    TextField("0", text: $shortageAmountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
                DatePicker("开始日期", selection: $shortageStartDate, displayedComponents: .date)
                DatePicker("结束日期", selection: $shortageEndDate, displayedComponents: .date)
                Button {
                    Task { await savePaySettings() }
                } label: {
                    if isSavingPay {
                        ProgressView()
                    } else {
                        Text("保存工资设置")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSavingPay)
                Text("每月工资均为预估，与实际发放有出入属正常")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let saveMessage {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("工资设置")
        .onAppear(perform: fillPayFields)
        .onChange(of: store.user?.paySettings) { _ in fillPayFields() }
    }

    private func fillPayFields() {
        let settings = store.user?.paySettings
        baseSalaryText = settings?.baseSalary.map { moneyText($0) } ?? "2420"
        bonusCoefText = settings?.bonusCoef.map { String(format: "%.1f", $0) } ?? "1.0"
        // 养老月扣框里显示的是“基数 × 8%”：老爷默认基数 5938 → 475.04；
        // 同事没填过就按全局默认基数 5938 算。
        let base = settings?.contributionBase ?? 5938
        pensionText = moneyText(PayCalc.round2(base * 0.08))
        position = settings?.position ?? "员工"
        education = settings?.education ?? "其他"
        shortageAmountText = settings?.shortageSubsidy?.amount.map { moneyText($0) } ?? "0"
        if let s = settings?.shortageSubsidy?.startDate, let d = DateUtil.date(from: s) { shortageStartDate = d }
        if let e = settings?.shortageSubsidy?.endDate, let d = DateUtil.date(from: e) { shortageEndDate = d }
        utilitiesText = settings?.utilities.map { moneyText($0) } ?? "0"
        deptPerfText = settings?.deptPerf.map { moneyText($0) } ?? "4000"
        // 入职时间默认 2018-10（和全局默认一致）；剩余年休假默认 5 天。
        hireYear = settings?.hireYear ?? 2018
        hireMonth = settings?.hireMonth ?? 10
        annualLeaveText = settings?.annualLeaveRemaining.map { String($0) } ?? "5"
    }

    private func moneyText(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(value)
    }

    private func savePaySettings() async {
        saveMessage = nil
        isSavingPay = true
        defer { isSavingPay = false }
        var settings: [String: Any] = [:]
        if let value = Double(baseSalaryText) { settings["baseSalary"] = value }
        if let value = Double(bonusCoefText) { settings["bonusCoef"] = value }
        if let base = derivedBase { settings["contributionBase"] = base }
        settings["position"] = position
        settings["education"] = education
        // 入职时间（只到月份）+ 剩余年休假天数（1.2.6）：整数 0–365，超出不保存并提示。
        settings["hireYear"] = hireYear
        settings["hireMonth"] = hireMonth
        if let value = Int(annualLeaveText.trimmingCharacters(in: .whitespaces)) {
            guard value >= 0, value <= 365 else {
                saveMessage = "剩余年休假天数要在 0–365 之间"
                return
            }
            settings["annualLeaveRemaining"] = value
        }
        if let value = Double(utilitiesText) { settings["utilities"] = value }
        // 缺员补贴：金额 0–10000；金额大于 0 才需要期限，结束日期不能早于开始日期。
        if let value = Double(shortageAmountText) {
            guard value >= 0, value <= 10000 else {
                saveMessage = "缺员补贴金额要在 0–10000 之间"
                return
            }
            if value > 0 {
                guard shortageEndDate >= shortageStartDate else {
                    saveMessage = "缺员补贴结束日期不能早于开始日期"
                    return
                }
                settings["shortageSubsidy"] = [
                    "amount": value,
                    "startDate": DateUtil.string(from: shortageStartDate),
                    "endDate": DateUtil.string(from: shortageEndDate),
                ]
            } else {
                settings["shortageSubsidy"] = ["amount": 0]
            }
        }
        // 默认科室绩效奖金：0–10000，超出不保存并提示。
        if let value = Double(deptPerfText) {
            guard value >= 0, value <= 10000 else {
                saveMessage = "科室绩效奖金要在 0–10000 之间"
                return
            }
            settings["deptPerf"] = value
        }
        do {
            try await store.saveProfile(paySettings: settings)
            saveMessage = "已保存，下个月的工资按新设置算"
            await store.refreshPay()
        } catch {
            saveMessage = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

/// 关于（二级页面）：更新日志入口、功能介绍、当前版本与版权。
/// 1.1.4：更新日志改成二级菜单——原来四个版本的条目全堆在关于页里，
/// 现在关于页只留一行入口，点进去才是 ChangelogView。
struct AboutView: View {
    var body: some View {
        Form {
            Section("更新日志") {
                NavigationLink {
                    ChangelogView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("更新日志")
                        Text("查看各版本更新内容")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Section("功能介绍") {
                Text("排班空间是倒班同事的排班与工资小工具：四班 8 天一轮日历（含阴历、节气、法定假日与三薪），调班/请假、工资预估（累计预扣个税），离线缓存先顶着，没网也能看；登录支持账号密码与手机号验证码。")
            }
            Section("使用说明") {
                NavigationLink {
                    UsageGuideView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("使用说明")
                        Text("排班、调班请假、工资、反馈、更新怎么用")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Section("当前版本") {
                HStack {
                    Text("版本")
                    Spacer()
                    Text(UpdateChecker.currentVersion)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Bundle ID")
                    Spacer()
                    Text("com.paiban.app")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("名称")
                    Spacer()
                    Text("排班空间")
                        .foregroundColor(.secondary)
                }
            }
            Section {
                Text("© 2026 排班空间")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("关于")
    }
}

/// 详细使用说明（1.2.2，从关于页点进来）：按现有功能写，排班、调班请假、
/// 工资、反馈、更新、账号与安全六节；入口名字和设置页里的一致。
struct UsageGuideView: View {
    var body: some View {
        Form {
            Section("排班怎么看") {
                Text("顶部 A、B、C、D 四个班切换着看，日历按 8 天一轮排班：日班 08:00–16:00，中班 16:00–24:00，早班 00:00–08:00。班次颜色：日班绿、中班红、早班紫、休息淡青。格子里大数字是阳历，小字是阴历、节气或节日；法定节假日标绿「假」，调休上班标红「班」，三薪日多一行半透明「三薪」，当天描绿边。左右滑动切月，点某一天看当天详情。")
            }
            Section("调班 / 请假") {
                Text("点某一天进当天详情，再点调班或请假。调班：选对方班，默认两人互换，保存前能看到两边怎么变；可以先不填还班日，过几天再补；删掉调班时替班日和还班日一起恢复。请假：选一天或一段日期，只算有班的日子，休班那天不算。只能改自己班的日历（设置页里那个班），切到别的班只能看。两条连班禁令：中班接次日早班不行，早班加日班不行；能双班的组合只剩早班加中班、日班加中班；一天不能上两个相同的班；休班的人来顶岗只上一个班，不算双班。")
            }
            Section("工资页怎么看") {
                Text("工资页显示的是预估工资，仅供参考，和实际发的有出入属正常。点「可改」的行能按单月改科室绩效、绩效系数、奖金系数、加班天数、水电费，只影响当月。个税按累计预扣法算：累计应纳税所得额 = 累计总收入 − 累计五险一金 − 5000 × 已发薪月份数，当月扣税 = 本月累计税额 − 上月累计税额，税从奖金里扣。学历补贴和缺员补贴在「设置 → 工资设置」里填。")
            }
            Section("反馈问题") {
                Text("设置页点「反馈问题」，选类型和出问题的页面，写清是哪个月出了问题，可附一张截图，发送时附上最近 24 小时运行日志。发完的反馈在反馈页下方的「我的反馈」里能看到，点开一条看管理员的回复，还能继续回，像聊天一样来回说。")
            }
            Section("更新") {
                Text("有新版本时打开 App 会弹提示，点「更新」直接下载安装包安装；也可以在设置页点「检查更新」手动查。点「稍后」后当天不再弹。")
            }
            Section("账号与安全") {
                Text("改密码、改昵称、换手机号、切换账号、退出登录都在「设置 → 账号与安全」里。退出登录只清登录状态，离线缓存留着，下次登录还能看。换手机号要收新号的验证码验证，30 天内只能换一次。换班组在设置页「更换班组」里，选新班和生效日期，工资跟着新班组算。")
            }
        }
        .navigationTitle("使用说明")
    }
}

/// 更新日志（二级页面，从关于页点进来）：各版本更新内容，最新版在最上面。
struct ChangelogView: View {
    var body: some View {
        Form {
            Section {
                changelog(version: "1.2.7.009（内测）", items: [
                    "修设置页切版本渠道点不动（真根因）：选中态和点按判断之前按存的更新偏好定，偏好和装的版本一脱节，「正式版」就被误标成已选中，点它直接被拦掉；现在按装的版本号定，装着内测版点「正式版」一定进确认框，确认后按正式版查更新、正式版 1.2.7 会推出来让装",
                ])
            }
            Section {
                changelog(version: "1.2.7.008（内测）", items: [
                    "小组件 UI 优化：小号重新排版（日期一行不换行、班组改小 pill，三段上下撑满，休息日底行补明日班次）；本周加农历小字、今天加深高亮，底下加今天·明日和本周统计；本月日期旁加农历小字、今天加深高亮，底下加本月统计；设置页小组件删「怎么添加」「数据状态」两节，空位放真实小组件截图的介绍图（今日/本周/双周/月），「取数实测」留着",
                ])
            }
            Section {
                changelog(version: "1.2.7.007（内测）", items: [
                    "修设置页切版本渠道点不动：List 行里并排两个 plain 按钮会被行手势吞掉点击，改 borderless 才点得动；确认框不等拉网，点下立刻弹，目标渠道版本号到了再补进文案",
                ])
            }
            Section {
                changelog(version: "1.2.7.006（内测）", items: [
                    "小组件重写：密钥彻底拿掉，不用再填；取数只走设备直连，云和隧道并行抢答、8 秒封顶，工资拉不到也不拖垮班次；装好打开 App 就刷新，不用删掉重加；设置页小组件里加了「立即同步」，当场测取数通不通",
                ])
            }
            Section {
                changelog(version: "1.2.7.005（内测）", items: [
                    "修小组件只显示颜色、不显示文字：时间线拉数那步太慢、系统直接给了占位，现在 15 分钟内的缓存先出数，拉网只在缓存过期时才走、10 秒封顶，五个小组件都跟着好",
                ])
            }
            Section {
                changelog(version: "1.2.7.004（内测）", items: [
                    "小组件不用填密钥了：打开 App 登录一次，本机就自动登记好，小组件直接从服务器拉数据；App Group 的权限留着，以后上架商店正规签名时用它",
                ])
            }
            Section {
                changelog(version: "1.2.7.003（内测）", items: [
                    "修设置页切版本渠道点不动：点「正式版」/「内测版」没反应的问题修好了，现在点另一个渠道会先弹确认框；点完按钮会转圈，不会再让人以为没点上",
                ])
            }
            Section {
                changelog(version: "1.2.7.002（内测）", items: [
                    "倒班方式全部推出：五班三倒、四班两倒（12 小时）、三班二倒（12 小时）、两班倒、巴拿马 2-2-3、杜邦、三班三倒（带替休）、五班四倒、四班 6 小时工作制；选了方式 + 班次，日历和工资班次统计跟着算",
                    "12 小时班禁令：白班接夜班不行、不能连上两个夜班、夜班后休 48 小时、一天只能上一个班；12 小时/6 小时班的工资口径待定，工资页只显示班次统计、金额暂不算",
                    "手动排班改成参考图样式：月历 + 底部班次按钮，点某天再点班次就是给那天排班；可加自定义班次；日历里的「每周排班」整个删掉，日历只留月视图",
                    "切版本渠道先弹确认：写清当前版本、目标渠道最新版、切了会怎样；切完立刻按新渠道查一次，另一条线的版本也推出来让用户自己决定装不装",
                    "六班三倒继续留「即将推出」：两个版本的循环天数对不上、没有逐日序列表，核实不了不硬编",
                ])
            }
            Section {
                changelog(version: "1.2.7.001（内测）", items: [
                    "内测渠道：每个版本分内测版 / 正式版两条线；内测人员在设置页切内测 / 正式，管理端按人开内测权限",
                    "小组件数据修好：小组件直接从服务器拉数据（填一次小组件密钥），不再依赖全能签描述文件的 App Group；设置页「桌面&锁屏小组件」里看数据状态、生成密钥",
                    "设置页按新样式重做：桌面&锁屏小组件、班次设置、倒班方式设置、日历显示设置、班次推送提醒、日历默认展开整月、更新日历的节假日、去除广告、意见反馈、欢迎评分、关于我们",
                    "倒班方式设置：手动排班（逐日点）或周期排班；四班三倒 5 种方式（8 天连休式 / 8 天分休式 / 12 天三三制 / 12 天九三制 / 4 天循环），带循环示意；班组名可改",
                    "节假日走服务器接口：每年 11 月自动更新，管理端可手动刷新；2026 年春节、调休数据按官方通知修正",
                    "工资页权限：没有工资权限的人不显示工资 Tab，年休假也跟着隐藏；新用户引导只问排班，不问工资",
                    "共享班表：只共享基础日历，不共享调班；同事分享的班表自动进「同事分享给我的」，点开对照看班次",
                    "调班重做：调班只改自己的日历——把那天改成要换的班，备注写跟谁换的，再挑一天还班；保存前预览自己的日历",
                    "日历显示设置：周一为每周首日、显示法定节假日、显示农历、当月显示上下月，改了立刻生效，下面有实时预览",
                    "日历默认展开整月：关了打开是当周紧凑视图（7 天一行，左右切周），开了打开是整月",
                    "班次推送提醒：班次前 30 分钟提醒，未来 7 天；关了取消全部提醒",
                ])
            }
            Section {
                changelog(version: "1.2.7", items: [
                    "主屏小组件：今日班次、本周排班、本月工资、本月日历四个尺寸，点小组件直接进对应页面",
                    "锁屏小组件：圆形看今日已挣多少钱，矩形看班次、已挣和还剩多久下班",
                    "排班页今日卡片加今日预估工资和倒计时：上班前倒计时到上班，上班中工资每秒涨，下班后显示今日已挣",
                    "当天详情加预估工资一行（只看自己班时显示）",
                    "有新版本时启动或回到 App 自动提示更新，不用再去设置页手动查",
                    "工资页单月可改对所有人开放：每个人改自己的科室绩效、绩效系数、奖金系数、加班天数、水电费",
                ])
            }
            Section {
                changelog(version: "1.2.6", items: [
                    "冷启动回当天：杀掉 App 再打开，排班页和工资页都显示在当天/当月；从后台切回来保持原地",
                    "登录页重做：输入框改下划线样式，登录按钮改全圆角胶囊，底部圆形图标切换密码登录和验证码登录",
                    "注册页加昵称和手机验证码：昵称建议用真实姓名，验证码发到注册手机号、服务端核验",
                    "「名字」改成「昵称」：注册页、账号与安全页、修改昵称都叫昵称",
                    "账号与安全页加「切换账号」，退出登录移到页面最下面",
                    "新员工引导加问入职时间（只到月份）和剩余年休假天数，工资页的年假剩余按存的天数显示（年假累计、不清零）",
                    "日历 12 月 24 日节日名改成「平安」",
                ])
            }
            Section {
                changelog(version: "1.2.5", items: [
                    "删掉软件里所有车间名字样",
                    "登录页隐藏云服务器地址，底部中间显示当前版本号",
                ])
            }
            Section {
                changelog(version: "1.2.4", items: [
                    "当天详情加横向其他班次：实际班次和连班禁令之间，显示其他三个班组当天的班次",
                    "全 App 文字排版优化",
                ])
            }
            Section {
                changelog(version: "1.2.3", items: [
                    "账号改用手机号登录，不能用中文登录",
                    "管理员账号可以登录 App（用户端和管理端两边都能进）",
                    "内置 admin 删掉，张晓文就是最高权限管理者、账号是 18765766628",
                    "张晓文的 App 里能直接进管理端",
                ])
            }
            Section {
                changelog(version: "1.2.2", items: [
                    "日历日期修复：窄屏手机（如 iPhone 15）上两位数的号不再截成「…」，阳历数字按屏宽自适应",
                    "更新走服务器直链：点「更新」直接下载安装包，不用再输提取码",
                    "反馈能双向回复：反馈页下方「我的反馈」里看管理员的回复，还能继续回",
                    "关于页加详细使用说明：排班、调班请假、工资、反馈、更新、账号与安全怎么用",
                ])
            }
            Section {
                changelog(version: "1.2.1", items: [
                    "排班页滑动重叠彻底修复：每页数据拍快照、滑动中不换数据源，六行固定行距、各页对齐",
                    "日历节日名去掉「节」字：劳动节、儿童节、国庆节等只显示两个字",
                    "日历放假与请假的「假」字分色：放假白字绿底、请假红字",
                    "工资页加学历补贴：专科 50 元、本科 100 元、其他 0 元（工资设置里选学历）",
                    "工资页加缺员补贴：期限内每月计入奖金，期限到了自动停发（工资设置里填金额和期限）",
                    "新手引导加问学历和缺员补贴",
                ])
            }
            Section {
                changelog(version: "1.1.4", items: [
                    "排班页左右滑修卡顿：固定网格、不再重算、滑页刷新防抖",
                    "工资页左右滑改原生 TabView，跟着手指走",
                    "日历加载可靠：月份取不到重试 3 次、失败不写空缓存、滑页不打断在途加载",
                    "重装登录后云端数据完整恢复",
                    "账号与安全页精简：删修改密码提示、删更换手机号入口、换号提示移到换号流程里",
                    "更新日志改成二级菜单",
                    "当天详情页重做：四按钮 2×2 等宽等高、提示框重排、卡片统一样式、sheet 高度自适应",
                    "全 App UI 风格统一：主按钮/卡片/字号/间距同一套规范，主色统一成 navy",
                ])
            }
            Section {
                changelog(version: "1.1.3", items: [
                    "手机号验证码登录（账号密码登录也保留）",
                    "老账号首次打开强制绑定手机号",
                    "设置页可改密码、改名字、更换手机号（换号一月一次）",
                    "退出登录只清登录状态，离线缓存保留",
                    "调班/请假按排班空间重做：选对方班互换、预览两边、删了两边一起恢复",
                    "其他班日历只读，可改的班跟着设置页的班组走",
                    "日历：字体收小、间距收紧、假标不再压阴历、三薪标回、月统计改三薪/加班",
                    "排班页滑动修掉帧；工资页切月加动画；「可改」行滑动不再误触",
                    "设置页改成二级菜单：账号与安全、工资设置、关于",
                    "点更新自动复制提取码，提示框里也直接显示提取码",
                    "更新包改名「排班空间1.1.3.zip」",
                ])
            }
            Section {
                changelog(version: "1.1.2", items: [
                    "日历按新样式重做：阴历、节气、法定假日",
                    "工资页手势锁定、切月动画",
                    "单月可改绩效系数、奖金系数、加班天数、水电费",
                    "编辑框点外面自动收起",
                ])
            }
            Section {
                changelog(version: "1.1.1", items: [
                    "科室绩效默认值，设置页可填",
                    "切月缓存、工资页左右滑",
                    "云优先，服务器区只对老爷显示",
                    "管理员权限分层；反馈页改版",
                ])
            }
            Section {
                changelog(version: "1.1", items: [
                    "首个原生版本：排班日历、工资预估、调班请假",
                ])
            }
        }
        .navigationTitle("更新日志")
    }

    private func changelog(version: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(version).bold()
            ForEach(items, id: \.self) { item in
                Text("· \(item)")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 绑定手机号 / 改昵称 / 改密码（1.1.3）

/// 绑定手机号的两种模式：首次绑定 / 更换手机号。
enum BindPhoneMode {
    case bind
    case change
}

/// 绑定手机号：输手机号 → 发验证码（60 秒倒计时）→ 输 6 位码 → 绑定。
/// 绑完就能用手机号 + 验证码登录；服务端立即落盘，管理端即是最新。
/// 更换模式：验证码发到新号，换完旧号不能再登录；一个月只能换一次，
/// 发码前先按上次换号时间算，限期内不发码、直接报下次可换时间。
/// forced = 强制绑定（1.1.3 升级门）：没有取消按钮，绑完才走。
struct BindPhoneSheet: View {
    var mode: BindPhoneMode = .bind
    var forced: Bool = false
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var code = ""
    @State private var countdown = 0
    @State private var sending = false
    @State private var saving = false
    @State private var message: String?
    @State private var isError = false

    private var isChange: Bool { mode == .change }

    /// 上次换号时间（服务端记的 ISO 时间戳）。
    private var lastPhoneChangeDate: Date? {
        guard let last = store.user?.lastPhoneChangeAt, !last.isEmpty else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: last)
    }

    /// 上次换号 + 30 天 = 下次可换时间（与服务端算法一致）。
    private var nextChangeDate: String? {
        guard let date = lastPhoneChangeDate else { return nil }
        let out = DateFormatter()
        out.dateFormat = "yyyy-MM-dd"
        return out.string(from: date.addingTimeInterval(30 * 86400))
    }

    /// 还在 30 天换号窗口内（没到下次可换时间）。
    private var withinChangeLimit: Bool {
        guard let date = lastPhoneChangeDate else { return false }
        return Date().timeIntervalSince(date) < 30 * 86400
    }

    var body: some View {
        NavigationStack {
            Form {
                if isChange, let current = store.user?.phone, !current.isEmpty {
                    Section {
                        HStack {
                            Text("当前绑定")
                            Spacer()
                            Text(PhoneUtil.masked(current) ?? current)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Section {
                    TextField(isChange ? "新手机号（11 位大陆手机号）" : "手机号（11 位大陆手机号）", text: $phone)
                        .keyboardType(.numberPad)
                    HStack {
                        TextField("6 位验证码", text: $code)
                            .keyboardType(.numberPad)
                        Button {
                            Task { await sendCode() }
                        } label: {
                            Text(countdown > 0 ? "\(countdown) 秒后重发" : "获取验证码")
                        }
                        .disabled(sending || countdown > 0 || !PhoneUtil.isValid(phone))
                    }
                } footer: {
                    if isChange {
                        Text("验证码发到新手机号；换完旧号不能再登录。一个月只能换一次" + (nextChangeDate.map { "，下次可换时间：\($0)" } ?? "") + "。")
                    } else {
                        Text("绑完就能用手机号 + 验证码登录；一个手机号只能绑一个账号。")
                    }
                }
                if let message {
                    Section {
                        Text(message).foregroundColor(isError ? .red : .green)
                    }
                }
            }
            .navigationTitle(isChange ? "更换手机号" : "绑定手机号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !forced {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChange ? "更换" : "绑定") { Task { await bind() } }
                        .disabled(saving || !PhoneUtil.isValid(phone) || code.count != 6)
                }
            }
        }
    }

    private func sendCode() async {
        message = nil
        isError = false
        // 换号限流先在本地算：限期内不发码（省一条短信），直接报下次可换时间；
        // 服务端还会再拦一道（429），报错原样透传。
        if isChange, withinChangeLimit {
            message = "手机号一个月只能换一次" + (nextChangeDate.map { "，下次可换时间：\($0)" } ?? "")
            isError = true
            return
        }
        sending = true
        defer { sending = false }
        do {
            try await store.api.sendSmsCode(phone: phone.trimmingCharacters(in: .whitespaces))
            countdown = 60
            Task {
                while countdown > 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    countdown -= 1
                }
            }
        } catch {
            message = (error as? APIError)?.message ?? error.localizedDescription
            isError = true
        }
    }

    private func bind() async {
        message = nil
        isError = false
        saving = true
        defer { saving = false }
        do {
            try await store.bindPhone(phone: phone.trimmingCharacters(in: .whitespaces),
                                      code: code.trimmingCharacters(in: .whitespaces))
            dismiss()
        } catch {
            message = (error as? APIError)?.message ?? error.localizedDescription
            isError = true
        }
    }
}

/// 改昵称：改的是显示名（displayName），随意改、不限次数、不用验证码；
/// 登录用的账号名（username）不动。留空保存 = 清回登录账号名。
struct ChangeNameSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var saving = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("昵称（最多 32 个字）", text: $name)
                } footer: {
                    Text("改的是昵称，登录用的账号名不变；留空保存会清回账号名。")
                }
                if let message {
                    Section {
                        Text(message).foregroundColor(isError ? .red : .green)
                    }
                }
            }
            .navigationTitle("修改昵称")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(saving || name.count > 32)
                }
            }
            .onAppear {
                name = store.user?.displayName ?? ""
            }
        }
    }

    private func save() async {
        message = nil
        isError = false
        saving = true
        defer { saving = false }
        do {
            try await store.saveProfile(displayName: name.trimmingCharacters(in: .whitespaces))
            dismiss()
        } catch {
            message = (error as? APIError)?.message ?? error.localizedDescription
            isError = true
        }
    }
}

/// 改密码：必须先绑手机号，短信验证码验证身份；不限次数，随时能改
///（老爷 2026-11-24 04:54 改口：之前「一个月只能改一次」作废，改绑手机号才一月一次）。
/// 验证码发到已绑的手机号。
struct ChangePasswordSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var countdown = 0
    @State private var sending = false
    @State private var saving = false
    @State private var message: String?
    @State private var isError = false

    private var boundPhone: String? { store.user?.phone }

    var body: some View {
        NavigationStack {
            Form {
                if let phone = boundPhone {
                    Section {
                        HStack {
                            Text("验证手机号")
                            Spacer()
                            Text(PhoneUtil.masked(phone) ?? phone)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            TextField("6 位验证码", text: $code)
                                .keyboardType(.numberPad)
                            Button {
                                Task { await sendCode() }
                            } label: {
                                Text(countdown > 0 ? "\(countdown) 秒后重发" : "获取验证码")
                            }
                            .disabled(sending || countdown > 0)
                        }
                    } footer: {
                        Text("验证码发到已绑的手机号；不限次数，随时能改。")
                    }
                    Section("新密码") {
                        SecureField("新密码（至少 6 位）", text: $newPassword)
                        SecureField("再输一次新密码", text: $confirmPassword)
                    }
                } else {
                    Section {
                        Text("还没绑定手机号。改密码要先绑手机号（短信验证码验证身份）。")
                            .foregroundColor(.secondary)
                    }
                }
                if let message {
                    Section {
                        Text(message).foregroundColor(isError ? .red : .green)
                    }
                }
            }
            .navigationTitle("修改密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(saving || boundPhone == nil || code.count != 6
                                  || newPassword.count < 6 || newPassword != confirmPassword)
                }
            }
        }
    }

    private func sendCode() async {
        guard let phone = boundPhone else { return }
        message = nil
        isError = false
        sending = true
        defer { sending = false }
        do {
            try await store.api.sendSmsCode(phone: phone)
            countdown = 60
            Task {
                while countdown > 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    countdown -= 1
                }
            }
        } catch {
            message = (error as? APIError)?.message ?? error.localizedDescription
            isError = true
        }
    }

    private func save() async {
        guard let phone = boundPhone else { return }
        message = nil
        isError = false
        saving = true
        defer { saving = false }
        do {
            try await store.changePassword(phone: phone,
                                           code: code.trimmingCharacters(in: .whitespaces),
                                           newPassword: newPassword)
            dismiss()
        } catch {
            message = (error as? APIError)?.message ?? error.localizedDescription
            isError = true
        }
    }
}

/// 小组件页（1.2.7.006 重写）：五个小组件、怎么添加、真实取数状态。
/// 密钥彻底拿掉：不再生成、不再显示、不再让用户填。小组件只走设备直连。
/// 数据状态是实测的：点「立即同步小组件」就当场跑一次设备直连拉数，
/// 成功失败、当场显示，不再只让老爷去桌面看。
struct WidgetsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var syncing = false
    @State private var syncMessage: String?
    @State private var syncOK = false

    /// 本机设备号（App 登录时登记到用户名下，小组件凭它拉数据）。
    private var deviceId: String? { UIDevice.current.identifierForVendor?.uuidString }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()

    var body: some View {
        Form {
            Section("五个小组件") {
                widgetRow(name: "今日排班", size: "小", desc: "今天的班次、倒计时与今日预估工资")
                widgetRow(name: "本周排班", size: "中", desc: "本周七天班次，当天高亮")
                widgetRow(name: "本月工资", size: "中", desc: "本月应发、实发工资与实发奖金")
                widgetRow(name: "本月日历", size: "大", desc: "整月网格与班次色块，当天高亮")
                widgetRow(name: "今日已挣", size: "锁屏", desc: "锁屏上看今天已挣多少钱、还剩多久下班")
            }

            // 小组件介绍（1.2.7.008）：「怎么添加」「数据状态」两节按老爷说的删了，
            // 空出来的位置放介绍图。标题和说明用 SwiftUI 文字写，不 baked 进图。
            // 图是老爷手机上真实小组件的截图裁出来的（老爷定的：一定要和真实小组件一样），
            // 四角已磨成圆角透明底，直接用；AI 生成那 4 张不用（数据对不上），没放进 App。
            Section("小组件介绍") {
                introCard(image: "WidgetIntroToday", title: "今日排班", desc: "小号：今天的班次、倒计时与今日预估工资", imageWidth: 200)
                introCard(image: "WidgetIntroWeek", title: "本周排班", desc: "中号：本周七天班次，当天高亮")
                introCard(image: "WidgetIntroTwoWeeks", title: "双周排班", desc: "中号：两周 14 天的班次一眼看完，当天高亮")
                introCard(image: "WidgetIntroMonth", title: "本月日历", desc: "大号：整月网格与班次色块，当天高亮")
            }

            Section("取数实测") {
                Text("点一下当场跑一次小组件用的那条取数（设备直连拉今天、本周、本月和工资），成功失败当场显示；成功了还会顺手写一份快照、通知小组件刷新，不用去桌面删掉重加。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button(syncing ? "同步中…" : "立即同步小组件") {
                    Task { await syncNow() }
                }
                .disabled(syncing)
                if let syncMessage {
                    Text(syncMessage)
                        .font(.caption)
                        .foregroundColor(syncOK ? .green : .red)
                }
            }
        }
        .navigationTitle("小组件")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 介绍图卡片：图 + SwiftUI 标题/说明。方图（今日）居中限宽 200，宽图（双周）通栏。
    private func introCard(image: String, title: String, desc: String, imageWidth: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer(minLength: 0)
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: imageWidth ?? .infinity)
                    .cornerRadius(12)
                Spacer(minLength: 0)
            }
            Text(title)
                .font(.headline)
            Text(desc)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func widgetRow(name: String, size: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name)
                Spacer()
                Text(size)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(desc)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    /// 立即同步：当场跑一次小组件用的设备直连拉数，成功就写一份快照到
    /// App Group（通的机器上小组件直接读）、通知小组件刷新；失败就直说原因。
    private func syncNow() async {
        syncMessage = nil
        syncOK = false
        syncing = true
        defer { syncing = false }
        guard let deviceId else {
            syncMessage = "拿不到本机设备号，取数没法跑。"
            return
        }
        if let snap = await WidgetServerClient.fetchSnapshot(deviceId: deviceId) {
            WidgetSnapshotStore.save(snap)
            WidgetCenter.shared.reloadAllTimelines()
            syncOK = true
            syncMessage = "取数成功（\(Self.timeFormatter.string(from: Date()))），小组件已刷新，去桌面看。"
        } else {
            syncMessage = "取数失败：云和隧道都没拉到数，检查网络后重试；还不行就把这页截给我。"
        }
    }
}

// MARK: - 班次设置（1.2.7.001，图一）

/// 班次设置：三个班次的时段（固定，跟倒班方式走；8 小时三班倒）。
/// 时段不开放改——改时段要连工资一起改（日薪 = 基本工资 ÷ 21.75，跟班长有关），
/// 等以后要做 12 小时班次时再开。循环方式去「倒班方式设置」改。
struct ShiftSettingsView: View {
    private let shifts = ["日班", "中班", "早班"]

    var body: some View {
        List {
            Section {
                ForEach(shifts, id: \.self) { shift in
                    HStack {
                        Text(TeamInfo.shortName(shift))
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 26, height: 26)
                            .background(ShiftStyle.color(for: shift))
                            .clipShape(Circle())
                        Text(shift)
                        Spacer()
                        Text(ShiftStyle.timeRange(for: shift))
                            .foregroundColor(.secondary)
                    }
                }
            }
            Section {
                Text("三个班次的时段固定：日班 08:00–16:00，中班 16:00–24:00，早班 00:00–08:00。循环方式（几天一循环、怎么排）在「倒班方式设置」里改。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("班次设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}
