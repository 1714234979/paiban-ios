import SwiftUI
import UIKit
import StoreKit
import WidgetKit

/// 设置页（1.1.3：二级菜单）：主界面只留入口行——账号与安全、工资设置、关于
/// 各开一个二级页面改细项；换班、管理后台、服务器、更新、反馈留在主界面。
/// 服务器那节只给老爷（张晓文）看，同事看不到。
struct SettingsView: View {
    @Environment(AppStore.self) private var store: AppStore

    @State private var isCheckingUpdate = false
    @State private var showFeedback = false
    /// 切渠道确认（1.2.7.002）：目标渠道 + 目标渠道最新版（先拉到再弹框）。
    @State private var pendingChannel: String?
    @State private var pendingChannelVersion: String?
    @State private var showChannelSwitchConfirm = false
    @State private var isFetchingChannelVersion = false
    /// 渠道胶囊滑动（1.3.2.012）：和班组胶囊一样，选中底色用 matchedGeometryEffect 在两个选项间滑动。
    @Namespace private var channelCapsuleNamespace
    /// 两渠道最新版号（1.3.2.012）：进设置页时后台各拉一次，挂在选项下面；拉不到就不显示，不报错。
    @State private var channelVersions: [String: String] = [:]
    /// 减弱动态效果（1.3.2.012）：胶囊不滑动，直接跳。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    AccountSecurityView().toolbar(.hidden, for: .tabBar)
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
                    WidgetsView().toolbar(.hidden, for: .tabBar)
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
                    ShiftSettingsView().toolbar(.hidden, for: .tabBar)
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
                    RotationSettingsView().toolbar(.hidden, for: .tabBar)
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
                    CalendarDisplaySettingsView().toolbar(.hidden, for: .tabBar)
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
                    TeamChangeView().toolbar(.hidden, for: .tabBar)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("更换班组")
                        Text("换到别的班组，从生效日零点起按新班组排班")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                NavigationLink {
                    OnboardingView().toolbar(.hidden, for: .tabBar)
                } label: {
                    Text("重新走一遍引导设置")
                }
            }

            // 外观（1.2.8.001）：深色模式。跟随系统 / 浅色 / 深色，改完立刻生效，不用重启。
            Section("外观") {
                Picker("深色模式", selection: Binding(
                    get: { store.appearance },
                    set: { store.appearance = $0 }
                )) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text("跟随系统按手机的深色模式走；选深色就是一直深色，选浅色就是一直浅色。改完立刻生效。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 工资设置：只有有工资权限的人才显示（1.2.7.001，第 23 条）。
            // 没权限的人连工资 Tab 都没有，设置页也不出现这一行。
            if store.payAccess {
                Section {
                    NavigationLink {
                        PaySettingsView().toolbar(.hidden, for: .tabBar)
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
            // 原生 push 进去（系统自带“‹ 设置”返回 + 隐藏底栏），不再用 fullScreenCover
            // + 自定义“‹ 返回”按钮（Gemini 整改模块 1b/1c）。
            if store.isOwner {
                Section {
                    NavigationLink {
                        AdminBackendView()
                            .toolbar(.hidden, for: .tabBar)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                // 深色模式下 Button 标题会走 AccentColor（深色亮蓝），
                                // 这里显式 primary，和其他菜单项配色一致（模块 4a）。
                                Text("切换管理员后台")
                                    .foregroundColor(.primary)
                                Text("用最高权限打开管理端，可管账号、发 App 更新")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
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
                    .background(AppStyle.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    // 1.3.2.012：胶囊滑动只绑在装的渠道这个状态上；减弱动态效果时不滑动。
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: UpdateChecker.installedChannel)
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
                    AboutView().toolbar(.hidden, for: .tabBar)
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
        .modifier(AlwaysVisibleScrollIndicator())
        .navigationTitle("设置")
        // 导航栏毛玻璃隔离（2026-11-28，和排班页同一毛病）：向上滚时卡片文字透过导航栏、
        // 和「设置」标题打架；设置页之前没写 toolbarBackground，走系统默认就是 .automatic，
        // 这里显式写出来，和排班页/工资页保持一致。
        .toolbarBackground(.automatic, for: .navigationBar)
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
        .task {
            // 1.2.9.001（第 35 条）：进设置页检查一次提醒权限——开着但还没定，
            // 弹系统权限请求；被拒就把开关关掉并提示去系统设置开。
            let wasOn = reminderOn
            let ok = await ShiftReminder.ensurePermissionAndSchedule(store: store)
            reminderOn = ShiftReminder.isEnabled
            // 只有真正被拒才弹提示：画廊模式跳过请求时状态还是未决定，
            // 另有弹窗在等用户点时也一样，别当成被拒。
            if wasOn && !ok {
                let status = await ShiftReminder.authorizationStatus()
                if status == .denied { showReminderDeniedAlert = true }
            }
            // 1.3.2.012：两渠道最新版号各拉一次，挂在切换选项下面；拉不到就不显示。
            async let stableInfo = store.fetchVersionForChannel("stable")
            async let betaInfo = store.fetchVersionForChannel("beta")
            var versions: [String: String] = [:]
            if let info = await stableInfo { versions["stable"] = info.latestVersion }
            if let info = await betaInfo { versions["beta"] = info.latestVersion }
            channelVersions = versions
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

    /// 节假日入口副标题：上次更新时间（ISO 时间戳转本地 yyyy-MM-dd HH:mm，
    /// 如 2026-11-27T07:36:10.262Z → 2026-11-27 15:36；模块 2a）。
    private var holidaySubtitle: String {
        if let updatedAt = store.holidaysUpdatedAt, !updatedAt.isEmpty {
            return "上次更新 \(DateUtil.localDateTime(fromISO: updatedAt))"
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
    /// 1.3.2.012（老爷 2026-11-28 亲口令：切换 UI 再优化 + 加切换动画）：
    /// 选中态改成和班组胶囊一样的深色滑动胶囊（matchedGeometryEffect，装的渠道
    /// 变了就滑过去）；每个选项下面挂该渠道最新版号（进设置页时后台拉一次），
    /// 点下去先给轻冲击触感，再弹确认框。选中态仍按装的版本定（009 的规矩不动，
    /// 胶囊不会指到没装的渠道上）；.borderless 也不能动（007 的教训，List 行里
    /// 别的 ButtonStyle 接不到点击）。
    private func channelButton(title: String, channel: String) -> some View {
        let installedChannel = UpdateChecker.installedChannel
        let selected = installedChannel == channel
        let fetching = isFetchingChannelVersion && !selected
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            guard channel != installedChannel, !isFetchingChannelVersion else { return }
            Task { await askChannelSwitch(to: channel) }
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    if fetching {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(title)
                        .font(.subheadline)
                        .bold(selected)
                }
                if let version = channelVersions[channel] {
                    Text(version)
                        .font(.caption2)
                        .foregroundColor(selected ? .white.opacity(0.75) : .secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                Group {
                    if selected {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppStyle.navyAdaptive)
                            .matchedGeometryEffect(id: "channelCapsule", in: channelCapsuleNamespace)
                    } else {
                        Color.clear
                    }
                }
            )
            .foregroundColor(selected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            // 两行按钮本身已有约 50pt 高，1.3.2.005 的 touchTarget 透明留白不用再加。
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
    @Environment(AppStore.self) private var store: AppStore

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
    @Environment(AppStore.self) private var store: AppStore

    @State private var baseSalaryText = ""
    @State private var bonusCoefText = ""
    @State private var pensionText = ""
    /// 公积金（1.3.0.001，第 47 条）：用户直接填的月扣金额；留空 = 没填，算工资时按 0 算。
    @State private var housingFundText = ""
    @State private var position = "员工"
    @State private var education = "其他"
    @State private var shortageAmountText = "0"
    @State private var shortageStartDate = Date()
    @State private var shortageEndDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var utilitiesText = ""
    @State private var deptPerfText = ""
    @State private var hireYear = 2018
    @State private var hireMonth = 10
    /// 今年是不是第一次拿工资（2026-11-27 修订版，第 4.4 条）：默认 true。
    @State private var firstEmploymentInYear = true
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
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("公积金")
                        Text("月扣金额，照工资条上的实际数填；不填按 0 算（不扣公积金）")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    TextField("", text: $housingFundText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
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
                    // 38 条：这行太挤（入职时间 + 年份 Picker + 年 + 月份 Picker + 月），
                    // 年份的值被压到只剩两位数宽、折成「20」/「18」两行。Picker 的「年份」/
                    // 「月份」标签和后面的「年」/「月」重复，藏掉标签、只留值（2018 年 10 月），
                    // 再加 fixedSize 让按钮按理想宽度显示、不参与压缩，年份就横着一行了。
                    Picker("年份", selection: $hireYear) {
                        ForEach(1990...Calendar.current.component(.year, from: Date()), id: \.self) { y in
                            // 36 条：Text("\(y)") 是 LocalizedStringKey，整数按本地格式分组，
                            // 2018 会显示成 2,018；verbatim 才拼纯数字。
                            Text(verbatim: "\(y)").tag(y)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize(horizontal: true, vertical: false)
                    Text("年")
                    Picker("月份", selection: $hireMonth) {
                        ForEach(1...12, id: \.self) { m in
                            Text(verbatim: "\(m)").tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize(horizontal: true, vertical: false)
                    Text("月")
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("今年是第一次拿工资吗？")
                        Text("第一次拿工资：累计减除费用按 5000 × 当年月份数；之前在别处拿过工资、今年年中才入职：按在本单位任职月数算")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $firstEmploymentInYear) {
                        Text("是，第一次").tag(true)
                        Text("不是，之前拿过").tag(false)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize(horizontal: true, vertical: false)
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
                // 专项附加扣除（第 52 条，2026-11-27）：多选 + 数量/档位，存 paySettings.specialDeductions。
                NavigationLink {
                    SpecialDeductionsView()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("专项附加扣除")
                            Text("子女教育、房贷利息、赡养老人这些，每月从应纳税所得额里扣，个税会少交")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(specialDeductionSummary)
                            .foregroundColor(.secondary)
                    }
                }
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
        // 公积金（1.3.0.001，第 47 条）：没填过就留空，不预填算出来的数。
        housingFundText = settings?.housingFund.map { moneyText($0) } ?? ""
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
        firstEmploymentInYear = settings?.firstEmploymentInYear ?? true
        annualLeaveText = settings?.annualLeaveRemaining.map { String($0) } ?? "5"
    }

    private func moneyText(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(value)
    }

    /// 专项附加扣除摘要（第 52 条）：每月扣多少，没填就显示「未填写」。
    private var specialDeductionSummary: String {
        let monthly = PayCalc.specialDeductionMonthly(store.user?.paySettings?.specialDeductions)
        return monthly > 0 ? "每月扣 \(MoneyUtil.money(monthly))" : "未填写"
    }

    private func savePaySettings() async {
        saveMessage = nil
        isSavingPay = true
        defer { isSavingPay = false }
        var settings: [String: Any] = [:]
        if let value = Double(baseSalaryText) { settings["baseSalary"] = value }
        if let value = Double(bonusCoefText) { settings["bonusCoef"] = value }
        if let base = derivedBase { settings["contributionBase"] = base }
        // 公积金（1.3.0.001，第 47 条）：填了就用填的数；空着 = 清掉（没填按 0 算）。
        // 0–10000，超出不保存并提示。
        let trimmedHF = housingFundText.trimmingCharacters(in: .whitespaces)
        if trimmedHF.isEmpty {
            if store.user?.paySettings?.housingFund != nil { settings["housingFund"] = NSNull() }
        } else if let value = Double(trimmedHF) {
            guard value >= 0, value <= 10000 else {
                saveMessage = "公积金要在 0–10000 之间"
                return
            }
            settings["housingFund"] = value
        }
        settings["position"] = position
        settings["education"] = education
        // 入职时间（只到月份）+ 剩余年休假天数（1.2.6）：整数 0–365，超出不保存并提示。
        settings["hireYear"] = hireYear
        settings["hireMonth"] = hireMonth
        settings["firstEmploymentInYear"] = firstEmploymentInYear
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
            // 1.3.2.005（方案 §6 车间噪音环境）：工资设置保存成功，轻震一下确认。
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            saveMessage = "已保存，下个月的工资按新设置算"
            await store.refreshPay()
        } catch {
            saveMessage = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

/// 专项附加扣除编辑页（第 52 条，2026-11-27；2026-11-27 修订版：DeepSeek 修订）：
/// 多选 + 数量/档位，填完保存到服务端 paySettings.specialDeductions，工资页个税立刻按新数算。
/// 房贷利息与住房租金互斥（服务端校验会拦，这里选了一边就自动清掉另一边，不让用户填出
/// 服务端会报错的组合）。大病医疗填年度自付总额，月度不扣，只汇算时扣。
/// 职业资格取证当年一次性扣 3600（取证当月才计）；婴幼儿照护每孩分别填每月金额。
/// 从设置 → 工资设置 → 专项附加扣除进来，也从工资页「有没有专项附加扣除」弹窗的
/// 「有，去填写」进来；第一次打开且还没问过时，onAppear 里触发一次询问弹窗（见 Store）。
struct SpecialDeductionsView: View {
    @Environment(AppStore.self) private var store: AppStore

    @State private var infantCareAmounts: [String] = []
    @State private var childEduText = ""
    @State private var continuingEdu = ""
    @State private var certYear = Calendar.current.component(.year, from: Date())
    @State private var certMonth = Calendar.current.component(.month, from: Date())
    @State private var certYearMonthSet = false
    @State private var medicalSelfPayText = ""
    @State private var mortgage = false
    @State private var rent: Double = 0
    @State private var elderlyText = ""
    @State private var isSaving = false
    @State private var saveMessage: String?

    private let rentOptions: [Double] = [0, 800, 1100, 1500]

    /// 当前填的每月扣除总额（实时预览，和工资页用的同一口径；取证当月才含那 3600）。
    private var monthlyTotal: Double {
        PayCalc.specialDeductionMonthly(SpecialDeductions(
            infantCare: infantCareAmounts.map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 },
            childEdu: Int(childEduText.trimmingCharacters(in: .whitespaces)),
            continuingEdu: continuingEdu,
            certYearMonth: continuingEdu == "vocational" && certYearMonthSet
                ? String(format: "%04d-%02d", certYear, certMonth) : nil,
            medicalSelfPayAnnual: Double(medicalSelfPayText.trimmingCharacters(in: .whitespaces)),
            mortgage: mortgage, rent: rent,
            elderly: Double(elderlyText.trimmingCharacters(in: .whitespaces))
        ))
    }

    /// 取证年月 Picker 的绑定：用户动手选才记为“已填”，fillFields 程序回填不算。
    private var certYearBinding: Binding<Int> {
        Binding(get: { certYear }, set: { certYear = $0; certYearMonthSet = true })
    }
    private var certMonthBinding: Binding<Int> {
        Binding(get: { certMonth }, set: { certMonth = $0; certYearMonthSet = true })
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("每月共扣")
                    Spacer()
                    Text(MoneyUtil.money(monthlyTotal))
                        .bold()
                }
                Text("个税按累计预扣法算：累计应纳税所得额 = 累计总收入 − 累计五险一金 − 5000 × 已发薪月份数 − 累计专项附加扣除。填的越多，当月扣的税越少。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section("孩子") {
                // 3岁以下婴幼儿照护（修订版）：每孩分别填每月金额，每孩 0–2000；
                // 夫妻分摊的填自己那份（一人全额填 2000，平分各填 1000）。
                ForEach(infantCareAmounts.indices, id: \.self) { i in
                    HStack {
                        Text("婴幼儿照护 · 孩子 \(i + 1) 每月金额")
                        Spacer()
                        TextField("0", text: $infantCareAmounts[i])
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Button(role: .destructive) {
                            infantCareAmounts.remove(at: i)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                    }
                }
                if infantCareAmounts.count < 5 {
                    Button("添加孩子") { infantCareAmounts.append("") }
                }
                Text("3岁以下婴幼儿照护：每孩每月最多扣 2000；夫妻分摊的填自己那份（一人全额填 2000，平分各填 1000）。没孩子就不用填。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("子女教育每月金额")
                        Text("每个孩子 ¥2000/月；夫妻分摊的填自己那份（一人全额填 2000，平分各填 1000）")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    TextField("0", text: $childEduText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
            }
            Section("继续教育") {
                Picker("继续教育", selection: $continuingEdu) {
                    Text("没有").tag("")
                    Text("学历教育（¥400/月）").tag("degree")
                    Text("职业资格（取证当年一次性 ¥3600）").tag("vocational")
                }
                .pickerStyle(.menu)
                if continuingEdu == "vocational" {
                    // 取证年月（修订版）：取证当月一次性扣 3600，其余月 0；没填按 0 算。
                    HStack {
                        Text("取证年月")
                        Spacer()
                        Picker("年份", selection: certYearBinding) {
                            ForEach(2020...Calendar.current.component(.year, from: Date()) + 1, id: \.self) { y in
                                Text(verbatim: "\(y)").tag(y)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                        Text("年")
                        Picker("月份", selection: certMonthBinding) {
                            ForEach(1...12, id: \.self) { m in
                                Text(verbatim: "\(m)").tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                        Text("月")
                    }
                    Text("取证当年一次性扣 ¥3600：只在取证那个月扣，其他月 0；没填取证年月按 0 算。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Section("大病医疗") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("年度自付总额")
                        Text("医保目录范围内年度自付总额；汇算时按（自付−15000）扣，上限 80000；仅汇算使用，不影响每月工资")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    TextField("0", text: $medicalSelfPayText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
                let deductible = PayCalc.medicalAnnualDeduction(SpecialDeductions(
                    medicalSelfPayAnnual: Double(medicalSelfPayText.trimmingCharacters(in: .whitespaces))))
                if deductible > 0 {
                    Text("预计汇算可扣 \(MoneyUtil.money(deductible))（次年汇算时一次性扣）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Section("住房") {
                Toggle("首套房贷利息（¥1000/月）", isOn: $mortgage)
                    .onChange(of: mortgage) { on in
                        // 房贷与租金互斥：勾了房贷，租金清零。
                        if on { rent = 0 }
                    }
                Picker("住房租金", selection: $rent) {
                    ForEach(rentOptions, id: \.self) { v in
                        Text(v == 0 ? "没有" : "¥\(Int(v))/月").tag(v)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: rent) { v in
                    // 房贷与租金互斥：选了租金，房贷取消。
                    if v > 0 { mortgage = false }
                }
                Text("房贷利息和住房租金只能选一个：有房贷就勾房贷，租房就选租金那档。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section("赡养老人") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("每月金额")
                        Text("独生填 3000；和兄弟姐妹分摊的填自己那份，每人每月不超过 1500")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    TextField("0", text: $elderlyText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("保存专项扣除")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
                if let saveMessage {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("专项附加扣除")
        .onAppear(perform: fillFields)
        .onChange(of: store.user?.paySettings?.specialDeductions) { _ in fillFields() }
        // 第一次打开专项扣除且还没问过：弹窗问一次「有没有专项附加扣除」。
        // （工资页第一次进页时也会问，两边共用同一个“问过”标记，先问到的算数。）
        // dispatch 到下一轮 runloop 再改 @Published，避免“视图更新中改状态”的警告。
        .onAppear {
            if !store.specialDeductionAsked
                && PayCalc.specialDeductionMonthly(store.user?.paySettings?.specialDeductions) == 0 {
                DispatchQueue.main.async { store.needsSpecialDeductionAsk = true }
            }
        }
        .alert("有没有专项附加扣除？", isPresented: Bindable(store).needsSpecialDeductionAsk) {
            Button("有，去填写") { store.markSpecialDeductionAsked() }
            Button("没有", role: .cancel) { store.markSpecialDeductionAsked() }
        } message: {
            Text("子女教育、房贷利息、赡养老人这些，每月能从应纳税所得额里扣，个税会少交。有的话填一下，没有就跳过，只问一次。")
        }
    }

    private func fillFields() {
        let sd = store.user?.paySettings?.specialDeductions
        infantCareAmounts = (sd?.infantCare ?? []).map { String($0) }
        childEduText = sd?.childEdu.map { String($0) } ?? ""
        continuingEdu = sd?.continuingEdu ?? ""
        if let ym = sd?.certYearMonth, ym.count == 7,
           let y = Int(ym.prefix(4)), let m = Int(ym.suffix(2)) {
            certYear = y
            certMonth = m
            certYearMonthSet = true
        } else {
            certYearMonthSet = false
        }
        medicalSelfPayText = sd?.medicalSelfPayAnnual.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } ?? ""
        mortgage = sd?.mortgage ?? false
        rent = sd?.rent ?? 0
        elderlyText = sd?.elderly.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } ?? ""
    }

    private func save() async {
        saveMessage = nil
        isSaving = true
        defer { isSaving = false }
        // 婴幼儿照护（修订版）：每孩分别填每月金额，每孩 0–2000。
        var infantCare: [Int] = []
        for (i, t) in infantCareAmounts.enumerated() {
            let trimmed = t.trimmingCharacters(in: .whitespaces)
            let v = trimmed.isEmpty ? 0 : Int(trimmed)
            guard let v, v >= 0, v <= 2000 else {
                saveMessage = "婴幼儿照护：孩子 \(i + 1) 每月金额要在 0–2000 之间"
                return
            }
            infantCare.append(v)
        }
        let trimmedChildEdu = childEduText.trimmingCharacters(in: .whitespaces)
        let childEdu = trimmedChildEdu.isEmpty ? 0 : Int(trimmedChildEdu)
        guard let childEdu, childEdu >= 0, childEdu <= 10000 else {
            saveMessage = "子女教育每月金额要在 0–10000 之间"
            return
        }
        let trimmedElderly = elderlyText.trimmingCharacters(in: .whitespaces)
        let elderly = trimmedElderly.isEmpty ? 0 : Double(trimmedElderly)
        guard let elderly, elderly >= 0, elderly <= 3000 else {
            saveMessage = "赡养老人每月金额要在 0–3000 之间"
            return
        }
        // 大病医疗（修订版）：填年度自付总额；月度不扣，只汇算用。
        let trimmedSelfPay = medicalSelfPayText.trimmingCharacters(in: .whitespaces)
        let medicalSelfPay = trimmedSelfPay.isEmpty ? 0 : Double(trimmedSelfPay)
        guard let medicalSelfPay, medicalSelfPay >= 0, medicalSelfPay <= 1000000 else {
            saveMessage = "大病医疗年度自付总额要在 0–1000000 之间"
            return
        }
        // 房贷与租金互斥：界面上已经互斥清掉了，这里再兜底一次，房贷优先。
        let finalRent: Double = mortgage ? 0 : rent
        // 职业资格没填取证年月：按 0 处理，保存照常，只提示一句。
        let certWarning: String? = (continuingEdu == "vocational" && !certYearMonthSet)
            ? "取证年月没填，职业资格这个月按 0 算；填上取证年月后，取证当月一次性扣 3600" : nil
        var dict: [String: Any] = [
            "infantCare": infantCare,
            "childEdu": childEdu,
            "continuingEdu": continuingEdu,
            "medicalSelfPayAnnual": medicalSelfPay,
            "mortgage": mortgage,
            "rent": finalRent,
            "elderly": elderly,
        ]
        if continuingEdu == "vocational" && certYearMonthSet {
            dict["certYearMonth"] = String(format: "%04d-%02d", certYear, certMonth)
        }
        do {
            try await store.saveProfile(paySettings: ["specialDeductions": dict])
            saveMessage = "已保存，下个月的工资按新设置算" + (certWarning.map { "；\($0)" } ?? "")
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
                        .monospacedDigit()
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
                Text("工资页显示的是预估工资，仅供参考，和实际发的有出入属正常。点「可改」的行能按单月改科室绩效、绩效系数、奖金系数、加班天数、水电费，只影响当月。个税按累计预扣法算：累计应纳税所得额 = 累计总收入 − 累计五险一金 − 5000 × 已发薪月份数 − 累计专项附加扣除，当月扣税 = 本月累计税额 − 上月累计税额，税从奖金里扣。学历补贴、缺员补贴和专项附加扣除在「设置 → 工资设置」里填。")
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
                changelog(version: "1.3.2.012（内测）", items: [
                    "排班页黑卡改成左右分栏：左边日期班次倒计时，右边今日已挣放大当主角；休息天高度也不变了",
                    "排班页顺序改成标题→黑卡→日历→班组选择，和工资页同款顺序，切 Tab 标题和黑卡不再跳；班组切换加了淡出淡入，胶囊滑过去不再变形",
                    "龙抬头在日期格里改成「龙头」，不再竖排三行顶到班次；排班页底部留了白，统计行不再贴着底栏",
                    "工资页返回按钮挪到导航栏右上角，叫「本月」，不再挡「科室绩效」的「可改」；「可改」挪到金额左边，金额全部贴右沿对齐",
                    "设置页内测/正式版切换改成深色滑动胶囊，两个选项下面挂着各自最新版号，点下去有轻震动",
                ])
                changelog(version: "1.3.2.011（内测）", items: [
                    "黑卡被切的根因修了：分页器改按实际高度排版，「今天」按钮改成悬浮、不再挤压页面；黑卡标签和数字完整显示",
                    "工资页切月不卡了：只读本地缓存，算数和写盘都挪到后台；进 App 就把前后 10 个月工资先预热好",
                    "排班页快滑不抽帧了：标题只在小范围里刷新，格子一次算好；慢点箭头还留着数字滚动，快滑时不再糊成一团",
                ])
                changelog(version: "1.3.2.010（内测）", items: [
                    "工资页黑卡不再被切：改成每页固定页眉，标签和大数字完整显示，跟着月份翻页、不跟竖滚走",
                    "工资页切月不卡了：工资改到后台算，当前月先算好；切月那一刻主线程上不再同步算工资",
                    "排班页快滑不抽帧了：邻月格子后台预热、中心先算；标题改成淡入，快滑时数字不再糊成一团",
                ])
                changelog(version: "1.3.2.009（内测）", items: [
                    "卡顿根治了：状态改成细粒度观察，一个地方变了不再牵着整页重画；月份和工资只算一次记下来，滑过去直接显示",
                    "标题拖过一半就换，不用等滑停了才变；底栏不再缩成左下角小圆球盖字",
                    "日历白卡整张跟着月份滑，星期栏和日期永远对齐，不再错位、切边",
                    "工资黑卡跟着月份一起翻页、一起滚动，不再上面停在 11 月、下面已经滑到 12 月",
                    "「今天」按钮改成右下角悬浮按钮，标题行只剩箭头和月份；调班/请假那张卡改成通栏长条",
                    "三薪改成日期数字旁边的小橙点，不再往上凸压农历字；排班页、工资页、设置页向上滚时导航栏不再透字",
                ])
                changelog(version: "1.3.2.008（内测）", items: [
                    "排班页重做了：月份滑动是系统原生的分页，标题只跟着落定的那一页走，不再错位、重叠、跳月；「今天」按钮只在非当月出现",
                    "底栏改回系统原生：iOS 26 上是液态玻璃，低版本是标准底栏；所有二级页面都藏起底栏，倒班方式设置的保存按钮和关于页的版权信息不再被压住；管理后台也从设置页点进去，左上角是系统返回",
                    "节假日更新时间改成本地时间；倒班方式的周均小时不再带一串小数",
                    "排班页往上滚时导航栏不再透字；三薪改成右上角的「三薪」小角标",
                    "工资页黑卡回来了，里面是当月实发合计的大数字",
                ])
                changelog(version: "1.3.2.007（内测）", items: [
                    "动画按文档重做了：月份滑动跟手、松手轻轻落定；点箭头切月只轻轻移一点、淡过去，不再整页横甩；班组切换底色滑过去，标签跟着换；点某一天格子会暗一下，点「今天」那格闪一下",
                    "底栏切换不再自己加淡入淡出：恢复系统原生的切换，干净利落",
                    "砍掉了几处多余的提示文字：工资页「本地计算，仅供参考」和底部那段说明、手动排班页「点击下方班次排班」都没了，字少了、页面更干净",
                ])
                changelog(version: "1.3.2.006（内测）", items: [
                    "日历固定 6 行：不管哪个月都是 6 行、行距一样，慢拖时两页的行严丝合缝，不再错位；5 行的月底下多出一行下月开头的暗色日期",
                    "底栏切换改成淡入淡出：点排班/工资/设置，页面 0.2 秒轻轻淡过去，不再一下子硬切",
                    "排班页和工资页最底下不再被底栏压住：底部多留了白，「当月应出勤」和奖金卡片都能完整看到",
                    "月份箭头、今天按钮、班组按钮点下去有反应了：轻轻缩一下、暗一下，0.1 秒就回来",
                    "骨架屏晚 150 毫秒再出来：数据回来得快就不闪一下灰条",
                ])
                changelog(version: "1.3.2.005（内测）", items: [
                    "戴手套也点得中：月份箭头、今天按钮、班组按钮、保存取消和验证码按钮，点击范围都扩到 48，样子没变",
                    "加载时不再转圈：排班页的调班/请假卡、工资页加载中显示灰色骨架占位，数据来了直接换上",
                    "排班页和工资页底下多了一行「数据更新于几点」，一眼能看出数据是不是最新的",
                    "调班、请假、工资设置保存成功时手机轻震一下，确认收到了",
                ])
                changelog(version: "1.3.2.004（内测）", items: [
                    "排班页预加载 21 页：每翻一页，前后 10 个月的格子都提前算好，滑过来直接显示，慢拖不再一顿一顿",
                    "调班/请假那张卡一直都在：本月没有就显示“本月没有调班请假”，不再忽有忽无、页面不再往上跳；当月出勤和这张卡跟排班页一起预加载",
                    "工资页切月动画改成平滑的：左右滑、点箭头都顺滑地过去；邻月的工资提前算好，滑到新月不用现算",
                    "顶上黑卡高度变化也顺滑了：休息那天没有预计工资，黑卡缩小时是慢慢缩的，不再一下子跳",
                    "底栏切页迅速又平滑：点排班/工资/设置，页面 0.25 秒平滑淡入淡出，胶囊指示条跟着滑过去；工资提前算好，第一次点过去也不用等",
                ])
                changelog(version: "1.3.2.003（内测）", items: [
                    "月份左右滑动更跟手了：慢拖也不一顿一顿的了——日历格改成整页一次画好再滑，倒计时那行每秒重画时不再多走一次模糊，窄屏字号只算一次",
                    "10 年滑页窗口改成前后各 10 年：排班页和工资页都能往前翻 10 年、往后翻 10 年，一共 20 年，滑到头也不怕",
                    "界面统一翻新：深色模式分层更清楚，不再是一片黑；卡片和分隔线改成淡淡的明暗色阶，整体更干净高级",
                    "深色下字不再发粗：字重自动降一档，看着和浅色一样舒服；倒计时、金额、日期都用等宽数字，数字跳动时不再左右抖",
                    "动效分了性格：月份滑动干脆利落不回弹，保存成功的提示带一点回弹、2.5 秒自己消失；动态出现的文字像水墨一样晕开",
                    "2027 年节假日按官方数据改准了：端午是 6 月 9 日、中秋是 9 月 15 日，之前推算的日期是错的",
                ])
                changelog(version: "1.3.2.002（内测）", items: [
                    "10 年滑页窗口改成前后各 10 年：排班页和工资页都能往前翻 10 年、往后翻 10 年，一共 20 年，滑到头也不怕",
                    "界面统一翻新：深色模式分层更清楚，不再是一片黑；卡片和分隔线改成淡淡的明暗色阶，整体更干净高级",
                    "深色下字不再发粗：字重自动降一档，看着和浅色一样舒服；倒计时、金额、日期都用等宽数字，数字跳动时不再左右抖",
                    "动效分了性格：月份滑动干脆利落不回弹，保存成功的提示带一点回弹、2.5 秒自己消失；动态出现的文字像水墨一样晕开",
                    "2027 年节假日按官方数据改准了：端午是 6 月 9 日、中秋是 9 月 15 日，之前推算的日期是错的",
                ])
                changelog(version: "1.3.2.001（内测）", items: [
                    "界面统一翻新：深色模式分层更清楚，不再是一片黑；卡片和分隔线改成淡淡的明暗色阶，整体更干净高级",
                    "深色下字不再发粗：字重自动降一档，看着和浅色一样舒服；倒计时、金额、日期都用等宽数字，数字跳动时不再左右抖",
                    "动效分了性格：月份滑动干脆利落不回弹，保存成功的提示带一点回弹、2.5 秒自己消失；动态出现的文字像水墨一样晕开",
                    "排班取消上下一年的限制，改成 10 年：排班页和工资页都能前后滑 10 年（前后各 10 年），滑到头也不怕",
                    "2027 年节假日按官方数据改准了：端午是 6 月 9 日、中秋是 9 月 15 日，之前推算的日期是错的",
                ])
                changelog(version: "1.3.2（正式版）", items: [
                    "内容与 1.3.1.001 内测版相同：个税加专项附加扣除、负个税按 0 算、工资页首次进页改成空状态、登录页加忘记密码、切月更快、点某天能直接改班次。",
                ])
                changelog(version: "1.3.1.001（内测）", items: [
                    "个税加专项附加扣除：子女教育、赡养老人按自己填的每月金额扣，婴幼儿照护每孩自己填每月金额（每孩最多 2000），学历教育 400/月，职业资格取证当年一次性扣 3600（要填取证年月），大病医疗只在次年汇算时扣、不影响每月工资，房贷 1000/月或租金三档（二选一）；设置 → 工资设置 → 专项附加扣除里填；有工资权限的人第一次进工资页会问一次有没有专项扣除，只问一次；工资页奖金区多了一行「专项附加扣除」",
                    "个税算出来是负数时不再倒扣：按 0 算，多的留到以后月份再抵，不会从实发奖金里扣钱。",
                    "工资页首次进页改成空状态：还没填工资设置时，工资页只显示一个「填写工资设置」按钮，点进去走一遍引导，填完才显示数据",
                    "登录页加「忘记密码？」：没登录时用短信验证码重置密码（输手机号 → 收验证码 → 设新密码），不用再找管理员",
                    "切月更快、更省流量；小组件只在内容变化时刷新",
                    "点某天能直接改这天的班：日班/中班/早班/早中班/日中班，改完计入当月总班数算工资。",
                ])
                changelog(version: "1.3.0.015（内测）", items: [
                    "底栏恢复系统默认样式；修复更新提醒不弹出的问题；滚动指示条常显；支持 120Hz 刷新率；公积金可以自己填。",
                ])
                changelog(version: "1.3.0.014（内测）", items: [
                    "底栏改为满宽毛玻璃样式；修复更新提醒不弹出的问题。",
                ])
                changelog(version: "1.3.0.013（内测）", items: [
                    "底栏玻璃效果优化；栏上滑动切页更灵敏；滚动指示条常显。",
                ])
                changelog(version: "1.3.0.012（内测）", items: [
                    "修复更新提醒不弹出的问题；底栏玻璃效果优化。",
                ])
                changelog(version: "1.3.0.011（内测）", items: [
                    "底栏玻璃效果优化。",
                ])
                changelog(version: "1.3.0.010（内测）", items: [
                    "底栏玻璃效果优化。",
                ])
                changelog(version: "1.3.0.009（内测）", items: [
                    "底栏改成悬浮胶囊样式，加玻璃效果。",
                ])
                changelog(version: "1.3.0.008（内测）", items: [
                    "底栏玻璃效果重做。",
                ])
                changelog(version: "1.3.0.007（内测）", items: [
                    "修复更新提醒不弹出的问题；底栏恢复满宽毛玻璃样式。",
                ])
                changelog(version: "1.3.0.006（内测）", items: [
                    "底栏改回透明玻璃悬浮样式；栏上滑动切页修复；支持 120Hz 刷新率。",
                ])
                changelog(version: "1.3.0.005（内测）", items: [
                    "底栏悬浮胶囊改成不透明。",
                ])
                changelog(version: "1.3.0.004（内测）", items: [
                    "底栏悬浮胶囊位置和宽度调整。",
                ])
                changelog(version: "1.3.0.003（内测）", items: [
                    "底栏只留悬浮胶囊。",
                ])
                changelog(version: "1.3.0.002（内测）", items: [
                    "底栏改成悬浮胶囊，加系统液态玻璃效果；在栏上左右滑动可以切页。",
                ])
                changelog(version: "1.3.0.001（内测）", items: [
                    "底栏加毛玻璃效果，在栏上左右滑动可以切页；公积金改成自己填。",
                ])
                changelog(version: "1.3.0（正式版）", items: [
                    "内容与 1.2.9.004 内测版相同：每日预估改按实发算、排班页统计行加上基本天数、应出勤改按排班算（基础轮班天数）、小组件介绍图换成真实截图、小号今日小组件钱那行不再截断、入职时间年份纯数字且横着一行显示",
                ])
                changelog(version: "1.2.9.004（内测）", items: [
                    "排班页统计行应出勤改按排班算：以前应出勤那格显示的是基本天数（10 月 18 天、11 月 21 天），和基本天数撞成两个一样的数；现在应出勤按基础轮班天数算（10 月 24 天、11 月 22 天、12 月 24 天），基本天数还是法定口径（10 月 18 天、11 月 21 天、12 月 23 天），两个数不一样了",
                ])
            }
            Section {
                changelog(version: "1.2.9.003（内测）", items: [
                    "每日预估改按实发算：按当天班次类型算，扣五险一金和个税；水电费不扣，餐补不算。当月每天预估加起来等于工资页那个月实发 + 水电费。",
                    "排班页统计行加上基本天数：以前应出勤和基本天数共用一个数（11 月碰巧都是 21 看不出，10 月会错成 24）；现在基本天数按法定放假口径算（10 月 18 天、11 月 21 天、12 月 23 天）",
                    "小组件介绍图换成真实截图；新加本月工资和锁屏今日已挣两张介绍卡，只有开了工资权限才显示；没权限的人小号今日小组件只显示班次和倒计时，不显示钱",
                    "小号今日小组件钱那行不再截断：已挣和预估整行完整显示",
                    "入职时间年份不再带逗号：工资设置 → 入职时间的年份滚轮以前显示 2,012、2,018（带千分位逗号），现在显示 2012、2018 这种纯数字；日历显示设置预览和分享班表里的年份也一起改了。金额里的千分位逗号不受影响",
                    "入职时间年份不再折行：工资设置 → 入职时间的年份以前窄得折成两行竖着显示，现在横着一行显示；工资引导里入职时间那一行也一起改了",
                ])
            }
            Section {
                changelog(version: "1.2.9.002（内测）", items: [
                    "入职时间年份不再带逗号：工资设置 → 入职时间的年份滚轮以前显示 2,012、2,018（带千分位逗号），现在显示 2012、2018 这种纯数字；日历显示设置预览和分享班表里的年份也一起改了。金额里的千分位逗号不受影响",
                ])
            }
            Section {
                changelog(version: "1.2.9.001（内测）", items: [
                    "每日预估工资改成工资加奖金总共的：按天算、按当天班次类型算，普通上班日、加班日、三薪日各按各的；双班两个班都算。",
                    "开通工资功能后，再次进软件会弹窗走一遍工资引导：把基本工资、奖金系数、缴费基数、岗位、入职时间、剩余年休假填好，再进工资页；已有权限、设定填好了的不弹。引导可以点「以后再说」跳过，跳过后下次进软件还会再弹，直到走完为止",
                    "钱跟着工资权限走：排班页「已挣 · 预估」那行、当天详情「预估工资」行、小号今日小组件和锁屏小组件里的钱数、本月工资小组件，都只有开了工资权限才能看到；没权限只显示班次和倒计时，不显示钱。倒计时（距下班）不是钱，不管开关都显示",
                    "调班/请假重做（配对互换）：以前调班只能改自己这边、没有和哪个班调的选项；现在点一天看四个班、选一个班替你上这天（你这天休息，对方那天变成组合班），再挑一天还班（也可以先不填，待还班），保存前两边一起预览；删一边两边一起恢复；还班日可以后补，一直不还就转为请假。请假也可以安排别的班顶岗。只改你自己的记录，不动对方的日历；看别的班日历时，你和那个班调过的日子按调班后显示",
                    "新用户引导的倒班方式补全：以前引导里选四班三倒只有 8 天一轮一种；现在和设置页一样——手动/周期两张大卡 + 按分类列出的全部方式（四班三倒 5 种、五班三倒、四班两倒、三班二倒、两班倒、巴拿马、杜邦、三班三倒、五班四倒、四班 6 小时），每种带循环示意，选完就生效",
                    "法定节假日三薪标记：只要那天在法定节假日表里，日历格就标「三薪」，不管当天是上班还是休息（比如 2027 年 1 月 1 日元旦 B 班休息，也标三薪）；工资计算不变，三薪天数和金额只算实际上了法定节假日班次的",
                    "班次推送提醒修好：以前开关看着开着，但提醒从没响过。现在打开软件就弹一次系统通知权限弹窗（只弹一次，被拒后去系统设置里开）；被拒就把开关关掉，不再假装开着。",
                ])
            }
            Section {
                changelog(version: "1.2.9", items: [
                    "修深色模式蓝色字看不清：深色下强调色改亮蓝，设置页、排班页、底部 Tab 栏、引导页深色下都清晰可读",
                    "深色模式全面排查：排班、工资、设置、登录/注册、引导、反馈、关于各页逐页过了一遍，标题、正文、次要文字、链接、按钮、Tab 栏深色下都清楚；系统次要灰字在深色下对比度够，没动",
                ])
            }
            Section {
                changelog(version: "1.2.8.002（内测）", items: [
                    "修深色模式蓝色字看不清：深色下强调色改亮蓝，设置页、排班页、底部 Tab 栏、引导页深色下都清晰可读",
                    "深色模式全面排查：排班、工资、设置、登录/注册、引导、反馈、关于各页逐页过了一遍，标题、正文、次要文字、链接、按钮、Tab 栏深色下都清楚；系统次要灰字在深色下对比度够，没动",
                ])
            }
            Section {
                changelog(version: "1.2.8.001（内测）", items: [
                    "设置里加深色模式：跟随系统 / 浅色 / 深色三个选项，改完立刻生效，不用重启 App",
                    "修深色模式字体模糊：深色下文字改纯白、提亮，开屏深色改深灰渐变，不闪白屏",
                ])
            }
            Section {
                changelog(version: "1.2.8", items: [
                    "修小号小组件显示不全：顶行日期和底行明日班次完整显示，不截断",
                    "启动加开屏：全屏品牌闪屏（大 logo + 班次色小圆点），盖住启动时的加载/过渡，不再闪白屏",
                ])
            }
            Section {
                changelog(version: "1.2.7.010（内测）", items: [
                    "修小号小组件显示不全：顶行日期和底行明日班次完整显示，不截断",
                    "启动加开屏：全屏品牌闪屏（大 logo + 班次色小圆点），盖住启动时的加载/过渡，不再闪白屏",
                ])
            }
            Section {
                changelog(version: "1.2.7.009（内测）", items: [
                    "修设置页切版本渠道点不动：点「正式版」/「内测版」会先弹确认框，确认后按新渠道查更新",
                ])
            }
            Section {
                changelog(version: "1.2.7.008（内测）", items: [
                    "小组件 UI 优化：小号重新排版，本周/本月加农历小字、今天高亮、底下加统计；设置页小组件改放真实小组件截图的介绍图",
                ])
            }
            Section {
                changelog(version: "1.2.7.007（内测）", items: [
                    "修设置页切版本渠道点不动：点「正式版」/「内测版」立刻弹确认框",
                ])
            }
            Section {
                changelog(version: "1.2.7.006（内测）", items: [
                    "小组件重写：不用再填密钥；装好打开 App 就刷新，不用删掉重加；设置页小组件里加了「立即同步」",
                ])
            }
            Section {
                changelog(version: "1.2.7.005（内测）", items: [
                    "修小组件只显示颜色、不显示文字：小组件现在直接出数",
                ])
            }
            Section {
                changelog(version: "1.2.7.004（内测）", items: [
                    "小组件不用填密钥了：打开 App 登录一次，小组件直接从服务器拉数据",
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
                    "手动排班改成月历 + 底部班次按钮：点某天再点班次就是给那天排班；可加自定义班次；日历只留月视图",
                    "切版本渠道先弹确认：写清当前版本、目标渠道最新版、切了会怎样；切完立刻按新渠道查一次，另一条线的版本也推出来让用户自己决定装不装",
                    "六班三倒继续留「即将推出」",
                ])
            }
            Section {
                changelog(version: "1.2.7.001（内测）", items: [
                    "内测渠道：每个版本分内测版 / 正式版两条线；内测人员在设置页切内测 / 正式",
                    "小组件数据修好：小组件直接从服务器拉数据（填一次小组件密钥）；设置页「桌面&锁屏小组件」里看数据状态、生成密钥",
                    "设置页按新样式重做：桌面&锁屏小组件、班次设置、倒班方式设置、日历显示设置、班次推送提醒、日历默认展开整月、更新日历的节假日、去除广告、意见反馈、欢迎评分、关于我们",
                    "倒班方式设置：手动排班（逐日点）或周期排班；四班三倒 5 种方式（8 天连休式 / 8 天分休式 / 12 天三三制 / 12 天九三制 / 4 天循环），带循环示意；班组名可改",
                    "节假日每年 11 月自动更新；2026 年春节、调休数据按官方通知修正",
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
                    "登录页底部中间显示当前版本号",
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
                ])
            }
            Section {
                changelog(version: "1.2.2", items: [
                    "日历日期修复：窄屏手机上两位数的号不再截成「…」",
                    "更新不用再输提取码：点「更新」直接下载安装包",
                    "反馈能双向回复：反馈页下方「我的反馈」里看回复，还能继续回",
                    "关于页加详细使用说明：排班、调班请假、工资、反馈、更新、账号与安全怎么用",
                ])
            }
            Section {
                changelog(version: "1.2.1", items: [
                    "排班页滑动重叠修复：滑动时各页对齐，不重叠",
                    "日历节日名去掉「节」字：劳动节、儿童节、国庆节等只显示两个字",
                    "日历放假与请假的「假」字分色：放假白字绿底、请假红字",
                    "工资页加学历补贴：专科 50 元、本科 100 元、其他 0 元（工资设置里选学历）",
                    "工资页加缺员补贴：期限内每月计入奖金，期限到了自动停发（工资设置里填金额和期限）",
                    "新手引导加问学历和缺员补贴",
                ])
            }
            Section {
                changelog(version: "1.1.4", items: [
                    "排班页左右滑修卡顿",
                    "工资页左右滑跟着手指走",
                    "日历加载更可靠：滑页不打断加载，加载失败会重试",
                    "重装登录后云端数据完整恢复",
                    "账号与安全页精简：删修改密码提示、删更换手机号入口、换号提示移到换号流程里",
                    "更新日志改成二级菜单",
                    "当天详情页重做：按钮和卡片样式统一",
                    "全 App UI 风格统一：主按钮、卡片、字号、间距同一套规范",
                ])
            }
            Section {
                changelog(version: "1.1.3", items: [
                    "手机号验证码登录（账号密码登录也保留）",
                    "老账号首次打开强制绑定手机号",
                    "设置页可改密码、改名字、更换手机号（换号一月一次）",
                    "退出登录只清登录状态",
                    "调班/请假重做：选对方班互换、预览两边、删了两边一起恢复",
                    "其他班日历只读，可改的班跟着设置页的班组走",
                    "日历：字体收小、间距收紧、假标不再压阴历、三薪标回、月统计改三薪/加班",
                    "排班页滑动更顺滑；工资页切月加动画；「可改」行滑动不再误触",
                    "设置页改成二级菜单：账号与安全、工资设置、关于",
                    "点更新自动复制提取码，提示框里也直接显示提取码",
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
                    "切月更快、工资页左右滑",
                    "反馈页改版",
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
    @Environment(AppStore.self) private var store: AppStore
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
                        // 1.3.2.005（方案 §3.3）：验证码按钮只有一行字高，透明留白扩到 48pt。
                        .touchTarget(vertical: 14)
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
    @Environment(AppStore.self) private var store: AppStore
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
    @Environment(AppStore.self) private var store: AppStore
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
                            // 1.3.2.005（方案 §3.3）：验证码按钮只有一行字高，透明留白扩到 48pt。
                            .touchTarget(vertical: 14)
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
    @Environment(AppStore.self) private var store: AppStore
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
            // 1.2.9.003：五张全是真实裁图（今日/本周/本月/工资/锁屏）；没有双周这个小组件，
            // 双周那张拿掉；本月工资和锁屏今日已挣两张只有开了工资权限才显示（钱跟着 payAccess 走）。
            Section("小组件介绍") {
                introCard(image: "WidgetIntroToday", title: "今日排班", desc: "小号：今天的班次、倒计时与今日预估工资", imageWidth: 200)
                introCard(image: "WidgetIntroWeek", title: "本周排班", desc: "中号：本周七天班次，当天高亮")
                introCard(image: "WidgetIntroMonth", title: "本月日历", desc: "大号：整月网格与班次色块，当天高亮")
                if store.payAccess {
                    introCard(image: "WidgetIntroPay", title: "本月工资", desc: "中号：本月应发、实发工资与实发奖金")
                    introCard(image: "WidgetIntroLock", title: "今日已挣", desc: "锁屏：今天已挣多少钱、还剩多久下班")
                }
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

    /// 介绍图卡片：图 + SwiftUI 标题/说明。方图（今日）居中限宽 200，宽图通栏。
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
            // 只在快照内容真的变化时才写、才刷（和 Store.publishWidgetSnapshot 同一个规矩，
            // WidgetCenter 刷新有系统预算，别浪费）；没变就只报成功，不重复刷。
            if snap != WidgetSnapshotStore.load() {
                WidgetSnapshotStore.save(snap)
                WidgetKinds.reloadTimelines()
            }
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
