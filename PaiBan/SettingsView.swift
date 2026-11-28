import SwiftUI
import UIKit
import StoreKit
import WidgetKit

/// 设置页（1.3.2.013：按普通用户视图重排）：标准分组列表，分组 1 账号卡片置顶，
/// 分组 2 排班与工资，分组 3 显示与组件，分组 4 帮助与关于；全页图标统一单色深炭灰。
/// 管理员的东西收进底部「开发者选项」单行（仅管理员可见），点进子页才是管理后台、
/// 服务器线路、更新通道；普通用户看不到渠道切换。
struct SettingsView: View {
    @Environment(AppStore.self) private var store: AppStore

    @State private var isCheckingUpdate = false
    @State private var showFeedback = false

    // 班次提醒（1.2.7.001）。
    // 1.2.7.002：日历只留月视图，「日历默认展开整月」开关已删。
    @State private var reminderOn = ShiftReminder.isEnabled
    @State private var showReminderDeniedAlert = false
    @State private var isRefreshingHolidays = false

    /// 账号与安全入口的副标题：昵称 · 手机号（脱敏，未绑就写未绑定）。
    private var accountSubtitle: String {
        let phone = PhoneUtil.masked(store.user?.phone) ?? "未绑定手机号"
        return "\(store.displayUsername) · \(phone)"
    }

    /// 工资设置入口的副标题：基本工资 · 系数。
    private var paySubtitle: String {
        let settings = store.user?.paySettings
        let base = settings?.baseSalary.map { PayCalc.jsNum($0) } ?? "2420"
        let coef = settings?.bonusCoef.map { String(format: "%.1f", $0) } ?? "1.0"
        return "基本工资 \(base) · 系数 \(coef)"
    }

    var body: some View {
        List {
            // 分组 1：账号卡片（无组标题，置顶）。
            Section {
                NavigationLink {
                    AccountSecurityView().toolbar(.hidden, for: .tabBar)
                } label: {
                    HStack(spacing: 12) {
                        SurnameAvatarView(name: store.displayUsername, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("账号与安全")
                            Text(accountSubtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // 分组 2：排班与工资。
            Section {
                // 倒班与班次（只读的「班次设置」已合并进这页顶部卡片，不再单列一行）。
                NavigationLink {
                    RotationSettingsView().toolbar(.hidden, for: .tabBar)
                } label: {
                    settingsRow(icon: "calendar.badge.clock", title: "倒班与班次", subtitle: rotationSubtitle)
                }

                // 更换班组。
                NavigationLink {
                    TeamChangeView().toolbar(.hidden, for: .tabBar)
                } label: {
                    settingsRow(icon: "person.2", title: "更换班组", subtitle: "调整所属班组与生效日期")
                }

                // 工资设置：只有有工资权限的人才显示（1.2.7.001，第 23 条）。
                // 没权限的人连工资 Tab 都没有，设置页也不出现这一行。
                if store.payAccess {
                    NavigationLink {
                        PaySettingsView().toolbar(.hidden, for: .tabBar)
                    } label: {
                        settingsRow(icon: "yensign.circle", title: "工资设置", subtitle: paySubtitle)
                    }
                }

                // 班次提醒（本地通知，默认开）。
                Toggle(isOn: reminderBinding) {
                    HStack(spacing: 12) {
                        settingsIcon("bell.badge")
                        Text("班次提醒")
                    }
                }
            } header: {
                Text("排班与工资")
            }

            // 分组 3：显示与组件。
            Section("显示与组件") {
                // 外观：点开菜单选跟随系统 / 浅色 / 深色；说明文字已删（系统常识不写）。
                HStack(spacing: 12) {
                    settingsIcon("circle.lefthalf.filled")
                    Text("外观")
                    Spacer()
                    Picker("", selection: appearanceBinding) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // 日历显示。
                NavigationLink {
                    CalendarDisplaySettingsView().toolbar(.hidden, for: .tabBar)
                } label: {
                    settingsRow(icon: "calendar", title: "日历显示", subtitle: displaySubtitle)
                }

                // 桌面与锁屏小组件。
                NavigationLink {
                    WidgetsView().toolbar(.hidden, for: .tabBar)
                } label: {
                    settingsRow(icon: "square.grid.2x2", title: "桌面与锁屏小组件", subtitle: "5 款组件 · 支持桌面与锁屏")
                }

                // 节假日数据：右侧轻量「更新」文字按钮，点后转圈。
                HStack(spacing: 12) {
                    settingsIcon("calendar.circle")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("节假日数据")
                        Text(holidaySubtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if isRefreshingHolidays {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("更新") {
                            Task { await refreshHolidaysNow() }
                        }
                        .font(.subheadline)
                    }
                }
            }

            // 分组 4：帮助与关于。
            Section("帮助与关于") {
                // 使用帮助（从「关于」二级页提至一级，方便新用户查找）。
                NavigationLink {
                    UsageGuideView().toolbar(.hidden, for: .tabBar)
                } label: {
                    settingsRow(icon: "questionmark.circle", title: "使用帮助")
                }

                // 新手引导。
                NavigationLink {
                    OnboardingView().toolbar(.hidden, for: .tabBar)
                } label: {
                    settingsRow(icon: "sparkles", title: "新手引导", subtitle: "重新配置班次与基础信息")
                }

                // 意见反馈（日志提示已移入反馈页内，主列表不再写）。
                Button {
                    showFeedback = true
                } label: {
                    HStack(spacing: 12) {
                        settingsIcon("exclamationmark.bubble")
                        Text("意见反馈")
                        Spacer()
                    }
                }
                .foregroundColor(.primary)

                // 给个好评（1.3.2.019 先隐藏：没上商店，SKStoreReviewController 点了没用；
                // 等上架了再放出来。requestReview() 函数本身保留，别删）。
                // Button {
                //     requestReview()
                // } label: {
                //     HStack(spacing: 12) {
                //         settingsIcon("star")
                //         Text("给个好评")
                //         Spacer()
                //     }
                // }
                // .foregroundColor(.primary)

                // 检查更新：右侧浅灰当前版号；有新版时前面多一个小红点。
                // 正式/内测切换栏普通用户不再显示，收进底部的「开发者选项」。
                Button {
                    Task { await manualUpdateCheck() }
                } label: {
                    HStack(spacing: 12) {
                        settingsIcon("arrow.down.circle")
                        Text("检查更新")
                        Spacer()
                        if isCheckingUpdate {
                            ProgressView()
                        } else {
                            if store.pendingUpdate != nil {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                            }
                            Text("v\(UpdateChecker.currentVersion)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .foregroundColor(.primary)

                // 关于排班空间（版本号已放在「检查更新」行，这里不再重复）。
                NavigationLink {
                    AboutView().toolbar(.hidden, for: .tabBar)
                } label: {
                    settingsRow(icon: "info.circle", title: "关于排班空间")
                }
            }

            // 开发者选项（仅管理员）：单行入口，点进子页；普通用户看不到这一行。
            // 里面收着管理员后台、服务器线路、更新通道（正式/内测）。
            if store.isOwner {
                Section {
                    NavigationLink {
                        DeveloperOptionsView().toolbar(.hidden, for: .tabBar)
                    } label: {
                        settingsRow(icon: "wrench.and.screwdriver", title: "开发者选项")
                    }
                }
            }
        }
        // 底部安全留白（1.3.2.013）：列表滑到底时，最后一行「关于排班空间」完整露在
        // 液态玻璃 TabBar 上方，不被底栏压住。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 20)
        }
        .modifier(AlwaysVisibleScrollIndicator())
        // 工资权限获批弹窗的「去填写」落点（1.3.2.017）：MainTabView 的 alert 里
        // 置 store.navigateToPaySettings = true，这里推工资设置页；返回时自动清掉。
        .navigationDestination(isPresented: Bindable(store).navigateToPaySettings) {
            PaySettingsView().toolbar(.hidden, for: .tabBar)
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
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
        .alert("通知权限被拒", isPresented: $showReminderDeniedAlert) {
            Button("知道了", role: .cancel) {}
            Button("去系统设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("班次提醒需要通知权限。请去系统设置里打开「排班空间」的通知，再回来开提醒。")
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
        }
    }

    // MARK: 设置行样式（1.3.2.013）

    /// 行图标：全页统一单色深炭灰（.primary），18–20pt、常规字重，
    /// 和日历页顶部黑卡、液态玻璃的克制调性一致。
    private func settingsIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 19, weight: .regular))
            .foregroundStyle(.primary)
            .frame(width: 24, alignment: .center)
    }

    /// 标准入口行：图标 + 标题 + 可选副标题（单行精炼）。
    private func settingsRow(icon: String, title: String, subtitle: String? = nil) -> some View {
        HStack(spacing: 12) {
            settingsIcon(icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    /// 外观绑定：跟随系统 / 浅色 / 深色，改完立刻生效。
    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(
            get: { store.appearance },
            set: { store.appearance = $0 }
        )
    }

    /// 倒班与班次入口副标题：当前方式名 + 班组（方式名里的「·」统一成「 · 」）。
    private var rotationSubtitle: String {
        let r = store.rotation
        if r.isManual { return "手动排班 · \(r.teamName(for: r.team))班" }
        let name = RotationModes.mode(id: r.modeId)?.name ?? r.modeId
        let pretty = name.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " · ")
        return "\(pretty) · \(r.teamName(for: r.team))班"
    }

    /// 日历显示入口副标题：开着的选项（周一首日不列，只列法定节假日 · 农历 · 上下月）。
    private var displaySubtitle: String {
        let d = store.calendarDisplay
        var parts: [String] = []
        if d.showHolidays { parts.append("法定节假日") }
        if d.showLunar { parts.append("农历") }
        if d.showAdjacentMonths { parts.append("上下月") }
        return parts.isEmpty ? "全部关闭" : parts.joined(separator: " · ")
    }

    /// 节假日入口副标题：只到日期（更新频率是年度级，精确到分秒显得噪杂）。
    private var holidaySubtitle: String {
        if let updatedAt = store.holidaysUpdatedAt, !updatedAt.isEmpty {
            return "更新于 \(String(DateUtil.localDateTime(fromISO: updatedAt).prefix(10)))"
        }
        return "每年 11 月自动更新"
    }

    /// 班次提醒开关：开 → 请求权限 + 排未来 7 天提醒；权限被拒自动关掉并提示。
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


    /// 手动刷新节假日（当年 + 下一年）。
    private func refreshHolidaysNow() async {
        isRefreshingHolidays = true
        defer { isRefreshingHolidays = false }
        let year = DateUtil.yearMonth(of: Date()).year
        _ = await store.refreshHolidays(year: year)
        _ = await store.refreshHolidays(year: year + 1)
    }

    /// 给个好评：标准系统评分弹窗。
    private func requestReview() {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
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

    /// 手动查更新（1.2.7.003 修：Task 标 @MainActor，
    /// 否则 isCheckingUpdate 的转圈在后台线程改了也不显示）。
    @MainActor
    private func manualUpdateCheck() async {
        isCheckingUpdate = true
        defer { isCheckingUpdate = false }
        await store.checkForUpdateManually()
    }
}

// MARK: - 设置二级页面（1.1.3）

/// 姓氏首字头像（1.3.2.020，老爷 22:47 发头像制作截图定稿）：圆形、灰色渐变底
/// （上浅下深）、姓氏首字白色粗体居中放大。所有人统一这个样式，不随机、不按人变色。
/// 账号与安全页顶部与设置页「账号与安全」入口共用。
private struct SurnameAvatarView: View {
    let name: String
    let size: CGFloat

    private var initial: String {
        String(name.prefix(1))
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.70), Color(white: 0.36)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Text(initial)
                .font(.system(size: size * 0.44, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

/// 账号与安全（二级页面）：昵称、登录账号、班组、手机号（绑定/更换）、
/// 账号与安全（1.3.2.018 按微信/支付宝改）：信息行本身可点进编辑（昵称/密码/手机号行），
/// 退出登录与注销账号并到底部一组；退出只清登录状态，离线缓存保留。
struct AccountSecurityView: View {
    @Environment(AppStore.self) private var store: AppStore

    @State private var showBindPhone = false
    @State private var showChangePhone = false
    @State private var showChangeName = false
    @State private var showChangePassword = false
    @State private var showLogoutConfirm = false
    /// 注销账号两步确认（1.3.2.018）：先弹提醒（30 天后删数据、30 天内可找回），
    /// 确认后再弹一次最终确认；两次都确认才调服务端注销接口。
    @State private var showCancelNotice = false
    @State private var showCancelConfirm = false
    @State private var cancelError: String?
    @State private var cancelling = false

    var body: some View {
        Form {
            // 头像区（1.3.3，老爷 2026-11-28 23:34 亲口令，图一参考）：头像居中放
            // 顶部，下面居中放打码手机号；名字删掉（只在「个人信息」昵称行里留
            // 着）。头像还是灰渐变圆 + 白色粗体姓，80pt（图一那个约 180pt 太大，不用）。
            Section {
                VStack(spacing: 10) {
                    SurnameAvatarView(name: store.displayUsername, size: 80)
                    Text(PhoneUtil.masked(store.user?.phone) ?? "未绑定手机号")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // 1.3.2.018（参考微信/支付宝）：信息行本身可点进编辑——点昵称行改昵称、
            // 点密码行改密码、点手机号行绑号/换号，不再单设一个「修改」区（少点一下）。
            Section("个人信息") {
                Button {
                    showChangeName = true
                } label: {
                    HStack {
                        Text("昵称")
                        Spacer()
                        Text(store.displayUsername)
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
                HStack {
                    Text("班组")
                    Spacer()
                    Text("\(store.myTeam)班")
                        .foregroundColor(.secondary)
                }
            }

            Section("登录与安全") {
                // 手机号：没绑点进去绑；绑了点进去换（换号走新号验证码，一月一次）。
                Button {
                    if store.user?.phone?.isEmpty == false {
                        showChangePhone = true
                    } else {
                        showBindPhone = true
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("登录手机号")
                            Text("用于登录和接收验证码")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(PhoneUtil.masked(store.user?.phone) ?? "未绑定")
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
                Button {
                    showChangePassword = true
                } label: {
                    HStack {
                        Text("登录密码")
                        Spacer()
                        Text("修改密码")
                            .foregroundColor(.blue)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
            }

        }
        // 退出登录与注销账号挪到页底（1.3.2.019）：不再是 Form 里的中间卡片，
        // 改放底部 safeAreaInset，上面留空。样式按老爷 22:36 发的设计图
        // （1.3.2.022 重做）：退出登录是白色圆角按钮、深色文字；注销账号是按钮
        // 下方一行红色文字、居中、直接放灰底上，不套白卡、不要分隔线。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                if let cancelError {
                    Text(cancelError)
                        .appFont(size: AppFont.bodySmall)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                Button {
                    showLogoutConfirm = true
                } label: {
                    Text("退出登录")
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .background(AppStyle.surface1)
                .cornerRadius(AppStyle.cardRadius)
                // 注销账号（1.3.2.018）：点开先弹提醒（30 天后删全部数据，30 天内重新注册可找回），
                // 确认后调服务端注销接口，成功后清本地登录态、回登录页。
                Button {
                    showCancelNotice = true
                } label: {
                    Text("注销账号")
                        .appFont(size: AppFont.bodySmall)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.plain)
                .disabled(cancelling)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .navigationTitle("账号与安全")
        .navigationBarTitleDisplayMode(.inline)
        .alert("注销账号", isPresented: $showCancelNotice) {
            Button("取消", role: .cancel) { }
            Button("继续注销", role: .destructive) {
                showCancelConfirm = true
            }
        } message: {
            Text("注销后，你的排班、请假与工资数据将在 30 天后全部删除。30 天内用同一手机号重新注册，可以找回旧账号数据；超过 30 天就找不回来了。")
        }
        .alert("确认注销吗？", isPresented: $showCancelConfirm) {
            Button("取消", role: .cancel) { }
            Button("确认注销", role: .destructive) {
                Task { await doCancelAccount() }
            }
        } message: {
            Text("注销后立即退出登录。30 天后全部数据删除，且无法恢复。")
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

    /// 注销账号：调服务端注销接口，成功后 Store 清登录态、回登录页；
    /// 失败（如服务端还没接这个接口）留在本页显示中文错误，不退出。
    private func doCancelAccount() async {
        cancelError = nil
        cancelling = true
        defer { cancelling = false }
        do {
            _ = try await store.cancelAccount()
        } catch {
            cancelError = (error as? APIError)?.message ?? error.localizedDescription
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
    // 1.3.2.018（老爷 2026-11-28 21:23/21:25 亲口令）：数值默认改空白，让用户自己输；
    // 缺员补贴期限改 1 年（开始当天、结束一年后，不再是 3 个月）；
    // 首次工资默认改非首次（不是，之前拿过）。
    @State private var shortageAmountText = ""
    @State private var shortageStartDate = Date()
    @State private var shortageEndDate = Calendar.current.date(byAdding: .month, value: 12, to: Date()) ?? Date()
    @State private var utilitiesText = ""
    @State private var deptPerfText = ""
    @State private var hireYear = Calendar.current.component(.year, from: Date())
    @State private var hireMonth = Calendar.current.component(.month, from: Date())
    /// 今年是不是第一次拿工资（2026-11-27 修订版，第 4.4 条）：默认 false（非首次）。
    @State private var firstEmploymentInYear = false
    @State private var annualLeaveText = ""
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
                    TextField("输入金额", text: $baseSalaryText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .fieldBackground()
                }
                HStack {
                    Text("奖金系数")
                    Spacer()
                    TextField("输入系数", text: $bonusCoefText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .fieldBackground()
                }
                HStack {
                    Text("养老月扣")
                    Spacer()
                    TextField("输入金额", text: $pensionText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .fieldBackground()
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
                    TextField("输入金额", text: $housingFundText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .fieldBackground()
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
                    TextField("输入天数", text: $annualLeaveText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .fieldBackground()
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("水电费")
                        Text("填平均每月水电费，某月单独改在工资页")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    TextField("输入金额", text: $utilitiesText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .fieldBackground()
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("科室绩效奖金")
                        Text("填平均科室绩效奖金，0–10000；某月单独改在工资页")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    TextField("输入金额", text: $deptPerfText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .fieldBackground()
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("缺员补贴金额")
                        Text("期限内每月计入奖金，期限到了就不计了；填 0 表示没有")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    TextField("输入金额", text: $shortageAmountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .fieldBackground()
                }
                // 缺员补贴期限（1.3.2.018，老爷 2026-11-28 21:25 亲口定）：开始/结束两个日期
                // UI 改成一样宽——日期字数不同（11月两位数、2月一位数）会让默认的紧凑
                // DatePicker 一宽一窄；这里把日期按钮定宽 150pt，两边一样宽。
                // 期限默认 1 年（开始当天、结束一年后）。
                HStack {
                    Text("开始日期")
                    Spacer()
                    DatePicker("", selection: $shortageStartDate, displayedComponents: .date)
                        .labelsHidden()
                        .frame(width: 150)
                }
                HStack {
                    Text("结束日期")
                    Spacer()
                    DatePicker("", selection: $shortageEndDate, displayedComponents: .date)
                        .labelsHidden()
                        .frame(width: 150)
                }
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
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: fillPayFields)
        .onChange(of: store.user?.paySettings) { _ in fillPayFields() }
    }

    private func fillPayFields() {
        let settings = store.user?.paySettings
        // 1.3.2.018（老爷 2026-11-28 21:23/21:25 亲口令）：数值默认改空白，没填过
        // 就留空、让用户自己输，不再预填 2420 / 1.0 / 475.04 / 0 / 4000 / 5 这些数；
        // 入职时间默认当天（当年当月，往前翻着改）；首次工资默认非首次。
        baseSalaryText = settings?.baseSalary.map { moneyText($0) } ?? ""
        bonusCoefText = settings?.bonusCoef.map { String(format: "%.1f", $0) } ?? ""
        // 养老月扣框里显示的是“基数 × 8%”；没填过缴费基数就留空，不按全局默认基数 5938 预填。
        pensionText = settings?.contributionBase.map { moneyText(PayCalc.round2($0 * 0.08)) } ?? ""
        // 公积金（1.3.0.001，第 47 条）：没填过就留空，不预填算出来的数。
        housingFundText = settings?.housingFund.map { moneyText($0) } ?? ""
        position = settings?.position ?? "员工"
        education = settings?.education ?? "其他"
        shortageAmountText = settings?.shortageSubsidy?.amount.map { moneyText($0) } ?? ""
        if let s = settings?.shortageSubsidy?.startDate, let d = DateUtil.date(from: s) { shortageStartDate = d }
        if let e = settings?.shortageSubsidy?.endDate, let d = DateUtil.date(from: e) { shortageEndDate = d }
        utilitiesText = settings?.utilities.map { moneyText($0) } ?? ""
        deptPerfText = settings?.deptPerf.map { moneyText($0) } ?? ""
        // 入职时间默认当天（当年当月）；剩余年休假默认空白；首次工资默认非首次。
        let now = Date()
        hireYear = settings?.hireYear ?? Calendar.current.component(.year, from: now)
        hireMonth = settings?.hireMonth ?? Calendar.current.component(.month, from: now)
        firstEmploymentInYear = settings?.firstEmploymentInYear ?? false
        annualLeaveText = settings?.annualLeaveRemaining.map { String($0) } ?? ""
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
                            .fieldBackground()
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
                        .fieldBackground()
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
                        .fieldBackground()
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
                        .fieldBackground()
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
        .navigationBarTitleDisplayMode(.inline)
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
            // 1.3.2.017：保存成功轻震一下确认（再加绿字提示，双重确认）。
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            saveMessage = "已保存，下个月的工资按新设置算" + (certWarning.map { "；\($0)" } ?? "")
            await store.refreshPay()
        } catch {
            saveMessage = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

/// 关于（二级页面）：顶部 App 图标 + 名称 + 版本居中展示，下方只放更新日志和功能介绍。
/// 1.1.4：更新日志改成二级菜单——原来四个版本的条目全堆在关于页里，
/// 现在关于页只留一行入口，点进去才是 ChangelogView。
/// 1.3.2.013：使用说明已提到主设置页一级（「使用帮助」），这里不再重复；
/// Bundle ID 行已删，只留图标 + 名称 + 版本。
struct AboutView: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image("SplashLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    Text("排班空间")
                        .font(.headline)
                    Text("版本 \(UpdateChecker.currentVersion)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
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
                Text("排班空间是一款专为倒班人群打造的排班与薪资助手。支持多种倒班周期、灵活调班请假、法定节假日标注及税后工资预估，并内置离线缓存，无网环境下也能随时查阅排班。")
            }
            // 法律文件（1.3.2.019：从设置页底部挪过来，老爷令放关于里）。
            Section("法律文件") {
                NavigationLink {
                    LegalDocumentView(document: .privacyPolicy).toolbar(.hidden, for: .tabBar)
                } label: {
                    Text(LegalDocument.privacyPolicy.title)
                }
                NavigationLink {
                    LegalDocumentView(document: .collectionList).toolbar(.hidden, for: .tabBar)
                } label: {
                    Text(LegalDocument.collectionList.title)
                }
                NavigationLink {
                    LegalDocumentView(document: .thirdPartyList).toolbar(.hidden, for: .tabBar)
                } label: {
                    Text(LegalDocument.thirdPartyList.title)
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
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 使用帮助（1.3.2.013：从长段纯文本墙改成折叠式 FAQ 手风琴）：
/// 点问题展开答案；个税计算公式拆成缩进清单。入口在主设置页一级（「使用帮助」）。
struct UsageGuideView: View {
    var body: some View {
        Form {
            DisclosureGroup("如何查看与切换排班") {
                Text("顶部 A、B、C、D 四个班切换着看，日历按 8 天一轮排班：日班 08:00–16:00，中班 16:00–24:00，早班 00:00–08:00。班次颜色：日班绿、中班红、早班紫、休息淡青。格子里大数字是阳历，小字是阴历、节气或节日；法定节假日标绿「假」，调休上班标红「班」，三薪日多一行半透明「三薪」，当天描绿边。左右滑动切月，点某一天看当天详情。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            DisclosureGroup("如何记录调班与请假") {
                Text("点某一天进当天详情，再点调班或请假。调班：选对方班，默认两人互换，保存前能看到两边怎么变；可以先不填还班日，过几天再补；删掉调班时替班日和还班日一起恢复。请假：选一天或一段日期，只算有班的日子，休班那天不算。只能改自己班的日历（设置页里那个班），切到别的班只能看。两条连班禁令：中班接次日早班不行，早班加日班不行；能双班的组合只剩早班加中班、日班加中班；一天不能上两个相同的班；休班的人来顶岗只上一个班，不算双班。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            DisclosureGroup("预估工资是如何计算的") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("工资页显示的是预估工资，仅供参考，和实际发的有出入属正常。点「可改」的行能按单月改科室绩效、绩效系数、奖金系数、加班天数、水电费，只影响当月。")
                    Text("个税按累计预扣法算：")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("· 累计应纳税所得额 = 累计总收入 − 累计五险一金 − 5000 × 已发薪月份数 − 累计专项附加扣除")
                        Text("· 当月扣税 = 本月累计税额 − 上月累计税额")
                        Text("· 税从奖金里扣")
                    }
                    .padding(.leading, 8)
                    Text("学历补贴、缺员补贴和专项附加扣除在「设置 → 工资设置」里填。")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            DisclosureGroup("如何反馈问题") {
                Text("设置页点「意见反馈」，选类型和出问题的页面，写清是哪个点出了问题，可附一张截图，发送时附上最近 24 小时运行日志。发完的反馈在反馈页下方的「我的反馈」里能看到，点开一条看管理员的回复，还能继续回。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            DisclosureGroup("如何更新 App") {
                Text("有新版本时打开 App 会弹提示，点「更新」直接下载安装包安装；也可以在设置页点「检查更新」手动查。点「稍后」后这个版本不再弹，出了新版本照样弹。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            DisclosureGroup("账号与安全说明") {
                Text("改密码、改昵称、换手机号、注销账号、退出登录都在「设置 → 账号与安全」里。退出登录只清登录状态，离线缓存留着，下次登录还能看。注销账号后 30 天删除全部数据，30 天内用同一手机号重新注册可以找回。换手机号要收新号的验证码验证，30 天内只能换一次。换班组在设置页「更换班组」里，选新班和生效日期，工资跟着新班组算。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("使用帮助")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 更新日志（二级页面，从关于页点进来）：各版本更新内容，最新版在最上面。
struct ChangelogView: View {
    var body: some View {
        Form {
            // 1.3.2.017（老爷 2026-11-28 20:43 亲口令）：更新日志分两组——「正式版」
            // 只放正式版号，「内测版」只放内测版号，各组最新在上；版本号不再带
            // 「（内测）/（正式版）」后缀（组标题就是渠道）。只放 iOS 自己的版本，
            // 不放安卓的；以后发新版，内测条目进内测组、正式条目进正式组。
            // 1.3.2.020（老爷 2026-11-28 22:51 亲口令）：只显示当前安装渠道那组——
            // 内测版（四段版号）只看「内测版」，正式版（三段版号）只看「正式版」；
            // 另一组直接不显示。按 UpdateChecker.installedChannel 定。
            if UpdateChecker.installedChannel != "beta" {
                Section("正式版") {
                    changelog(version: "1.3.3", items: [
                        "排班页和工资页滑动更顺了，月份左右滑跟手，标题不再错位、跳月，切月更快",
                        "界面统一翻新，深色模式分层更清楚，卡片和分隔线更干净，深色下字重自动降一档，金额、日期用等宽数字",
                        "排班能前后滑 10 年",
                        "2027 年节假日改准了，端午 6 月 9 日、中秋 9 月 15 日",
                        "排班页和工资页顶卡改成白框、更紧凑，高度固定，工资页默认看上个月",
                        "登录/注册页统一了，底划线输入框、胶囊按钮、密码框带眼睛，登录方式是双 Tab，加了协议勾选，协议全文都能在 App 里看",
                        "密码规则改成 8-16 位、须同时含字母和数字",
                        "当天详情页大改，调班/请假/记加班/改排班单行四列，当前开的那个唯一高亮，请假单日/多日一个卡片里切换，连班禁令收进「? 规则」",
                        "全站输入框改成底线样式，昵称最多 10 个字",
                        "账号与安全页改成头像版，灰色渐变圆头像加姓名和手机号，下面分「个人信息」「登录与安全」两组，退出登录是白色圆角按钮，注销账号是按钮下面一行红字",
                        "账号可以注销了，注销后 30 天删数据，30 天内重新注册可以找回旧账号",
                        "已经调班的日子再点「调班」，会轻震一下并提示一行字",
                        "更新日志只显示当前渠道，内测版只看内测版的，正式版只看正式版的",
                    ])
                    changelog(version: "1.3.2", items: [
                        "个税加专项附加扣除",
                        "负个税按 0 算",
                        "工资页首次进页改成空状态",
                        "登录页加忘记密码",
                        "切月更快",
                        "点某天能直接改班次",
                    ])
                    changelog(version: "1.3.0", items: [
                        "每日预估改按实发算",
                        "排班页统计行加上基本天数",
                        "应出勤改按排班算（基础轮班天数）",
                        "小组件介绍图换成真实截图",
                        "小号今日小组件钱那行不再截断",
                        "入职时间年份纯数字且横着一行显示",
                    ])
                    changelog(version: "1.2.9", items: [
                        "修深色模式蓝色字看不清：深色下强调色改亮蓝，设置页、排班页、底部 Tab 栏、引导页深色下都清晰可读",
                    ])
                    changelog(version: "1.2.8", items: [
                        "修小号小组件显示不全：顶行日期和底行明日班次完整显示，不截断",
                        "启动加开屏：全屏品牌闪屏（大 logo + 班次色小圆点），盖住启动时的加载/过渡，不再闪白屏",
                    ])
                    changelog(version: "1.2.7", items: [
                        "主屏小组件：今日班次、本周排班、本月工资、本月日历四个尺寸，点小组件直接进对应页面",
                        "锁屏小组件：圆形看今日已挣多少钱，矩形看班次、已挣和还剩多久下班",
                        "排班页今日卡片加今日预估工资和倒计时：上班前倒计时到上班，上班中工资每秒涨，下班后显示今日已挣",
                        "当天详情加预估工资一行（只看自己班时显示）",
                        "有新版本时启动或回到 App 自动提示更新，不用再去设置页手动查",
                        "工资页单月可改对所有人开放：每个人改自己的科室绩效、绩效系数、奖金系数、加班天数、水电费",
                    ])
                    changelog(version: "1.2.6", items: [
                        "冷启动回当天：杀掉 App 再打开，排班页和工资页都显示在当天/当月；从后台切回来保持原地",
                        "登录页重做：输入框改下划线样式，登录按钮改全圆角胶囊，底部圆形图标切换密码登录和验证码登录",
                        "注册页加昵称和手机验证码：昵称建议用真实姓名，验证码发到注册手机号、服务端核验",
                        "「名字」改成「昵称」：注册页、账号与安全页、修改昵称都叫昵称",
                        "账号与安全页加「切换账号」，退出登录移到页面最下面",
                        "新员工引导加问入职时间（只到月份）和剩余年休假天数，工资页的年假剩余按存的天数显示（年假累计、不清零）",
                        "日历 12 月 24 日节日名改成「平安」",
                    ])
                    changelog(version: "1.2.5", items: [
                        "删掉软件里所有车间名字样",
                        "登录页底部中间显示当前版本号",
                    ])
                    changelog(version: "1.2.4", items: [
                        "当天详情加横向其他班次：实际班次和连班禁令之间，显示其他三个班组当天的班次",
                        "全 App 文字排版优化",
                    ])
                    changelog(version: "1.2.3", items: [
                        "账号改用手机号登录，不能用中文登录",
                    ])
                    changelog(version: "1.2.2", items: [
                        "日历日期修复：窄屏手机上两位数的号不再截成「…」",
                        "更新不用再输提取码：点「更新」直接下载安装包",
                        "反馈能双向回复：反馈页下方「我的反馈」里看回复，还能继续回",
                        "关于页加详细使用说明：排班、调班请假、工资、反馈、更新、账号与安全怎么用",
                    ])
                    changelog(version: "1.2.1", items: [
                        "排班页滑动重叠修复：滑动时各页对齐，不重叠",
                        "日历节日名去掉「节」字：劳动节、儿童节、国庆节等只显示两个字",
                        "日历放假与请假的「假」字分色：放假白字绿底、请假红字",
                        "工资页加学历补贴：专科 50 元、本科 100 元、其他 0 元（工资设置里选学历）",
                        "工资页加缺员补贴：期限内每月计入奖金，期限到了自动停发（工资设置里填金额和期限）",
                        "新手引导加问学历和缺员补贴",
                    ])
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
                    changelog(version: "1.1.2", items: [
                        "日历按新样式重做：阴历、节气、法定假日",
                        "工资页手势锁定、切月动画",
                        "单月可改绩效系数、奖金系数、加班天数、水电费",
                        "编辑框点外面自动收起",
                    ])
                    changelog(version: "1.1.1", items: [
                        "科室绩效默认值，设置页可填",
                        "切月更快、工资页左右滑",
                        "反馈页改版",
                    ])
                    changelog(version: "1.1", items: [
                        "首个原生版本：排班日历、工资预估、调班请假",
                    ])
                }
            }
            if UpdateChecker.installedChannel == "beta" {
                Section("内测版") {
                    changelog(version: "1.3.3.002", items: [
                        "排班页顶卡「预估今日工资」那块删掉了，顶卡只剩日期、班次和倒计时",
                        "注册页多余提示删掉了",
                    ])
                    changelog(version: "1.3.3.001", items: [
                        "账号与安全页头像改成居中布局，头像居中放顶部，下面带打码手机号，头像旁的名字删掉",
                    ])
                    changelog(version: "1.3.2.022", items: [
                        "当天详情页里，已经调班了再点「调班」的那行提示，挪到 sheet 最下面了（「已调班」那张卡下面）",
                        "账号与安全页顶部的姓氏头像再大了一点",
                        "账号与安全页底部的退出登录改成白色圆角按钮了，注销账号改成按钮下面一行红色文字了",
                    ])
                    changelog(version: "1.3.2.021", items: [
                        "当天详情页里，这天已经调班了再点「调班」，会轻震一下并提示一行字：已经进行调班了，如果需要再次更改，请删除此次调班，或者直接更改排班",
                    ])
                    changelog(version: "1.3.2.020", items: [
                        "工资页切月左右滑时，竖向拖动条不再跟着左右跑了",
                        "隐私政策和用户协议里，工资估算加上了「仅对获得工资权限的用户提供」的限定——工资估算只给有权限的人用",
                        "账号与安全页改成头像版了：顶部灰色渐变圆头像加姓名和手机号，下面分「个人信息」「登录与安全」两组；设置页入口的头像也换成同一个姓氏头像了",
                        "排班页「本月调班 / 请假」列表里每行前面的小圆点改成跟文字垂直居中了",
                        "当天详情页调班、请假、记加班、改排班四个按钮的底色换成纯白了，之前浅灰在灰底上看不清",
                        "更新日志只显示当前渠道了：内测版只看内测版的日志，正式版只看正式版的日志",
                        "更新日志里只留功能更新和 bug 修复：1.3.2、1.3.0 那两条「内容与某某内测版相同」拆成一条条功能，1.2.9、1.2.8.002 里「深色模式全面排查、各页逐页过了一遍」这种过程描述删了",
                    ])
                    changelog(version: "1.3.2.019", items: [
                        "隐私政策、个人信息收集清单、第三方合作清单三条链接从设置页底挪进「关于」页里了",
                        "账号与安全页退出登录和注销账号之间的分隔横杠修成通栏不断的了",
                        "工资页「当月」按钮加上了和排班页「回到今天」一样的显隐动画（淡入+缩放）",
                        "账号与安全页的退出登录和注销账号挪到那一页的最下边了",
                        "「给个好评」先隐藏了——没上商店，点了没用，等上架再放出来",
                        "当天详情页「其他班次」里「休」改回浅青，跟主日历的休统一了",
                    ])
                    changelog(version: "1.3.2.018", items: [
                        "排班页顶卡「预估 ¥XXX」小字加回来了；金额标签改成「预估今日工资」",
                        "工资页顶卡标题行重排：小眼睛紧挨「本月实发合计」，「当月」按钮挪到最右边，标题和金额之间更紧凑",
                        "设置页底部三条协议链接都点得开了，各进各的全文页",
                        "日历选中格的框描边改均匀了，粗细一致、完整可见，形状还是圆角矩形",
                        "当天详情页大改：操作栏改成调班/请假/记加班/改排班单行四列，当前开的那个唯一高亮；请假和请一段假并成一个卡片，里面单日/多日切换；顶部两张卡并成一张紧凑头部卡；连班禁令收进右上角「? 规则」按钮；其他班次压成一行轻量色标，休息改回浅灰；色块降饱和；提交按钮都改成通栏主按钮",
                        "「年假」和「年休假」合并了，只留「年休假」",
                        "全站输入框改成底线样式，不要灰底了",
                        "昵称最多 10 个字，改昵称和注册页都限 10 字，带 x/10 计数",
                        "工资设置默认值改空白、日期默认当天；缺员补贴期限改成 1 年，开始/结束日期一样宽；首次工资默认改成非首次",
                        "「切换账号」删了；账号与安全页加了「注销账号」，注销后 30 天删数据，30 天内重新注册可以找回旧账号",
                        "账号与安全页按微信/支付宝改：昵称、密码、手机号行直接点进去改，不再单设「修改」区；退出登录和注销账号并到底部一组",
                    ])
                    changelog(version: "1.3.2.017", items: [
                        "登录/注册页统一成一个样式：底划线输入框、胶囊主按钮、密码框带眼睛；登录方式改成输入框上方的双 Tab，版面不再跳",
                        "登录/注册加了协议勾选：没勾选点登录会被拦住；《用户使用协议》《隐私政策》《个人信息收集清单》都能在 App 里直接看全文",
                        "设置页底部加了《隐私政策》《个人信息收集清单》《第三方合作清单》三个入口",
                        "手动排班重新排版：白卡 + 藏青选中，底部班次条统一成选择器风格，多余的文字删了",
                        "倒班方式改成可折叠分组，默认只展开当前选中的那组",
                        "新人引导：点卡片只选中，点「下一步」才进下一步；周期排班在同页展开方式列表，不跳页",
                        "公积金输入框看得见了，全站输入框都统一成带底色的样式",
                        "全站删了一批多余的提示文字",
                        "密码规则改成 8-16 位、须同时含字母和数字，注册、忘记密码、改密码三处都有提醒",
                        "管理员给了工资权限会弹一次窗，问要不要去填工资设置",
                        "工资页顶卡变紧凑了：「当月」按钮挪进标题行；顶卡跟着内容一起滑，不再冻结在顶端",
                        "排班页顶卡徽标改成「回到本班」；分享按钮图标重新居中了；两页月份箭头对齐了",
                        "更新日志拆成「正式版」和「内测版」两组，不再混成一条",
                        "保存按钮都有反应了：该关页面的关页面，该提示的提示，不再点了没动静",
                    ])
                    changelog(version: "1.3.2.016", items: [
                        "排班页顶卡换成两区紧凑布局：日期、班次状态和今日已挣并成一行，倒计时还在，卡片矮了一截",
                        "排班页和工资页的顶卡高度都固定了，不再一会儿大一会儿小",
                        "「看的是X班的排班」那段提示删掉了",
                        "班组切换改成弹性分段条，拖着走、带回弹，滑到哪个班震一下",
                        "工资页默认看上个月（工资压一个月发），标题写明是几月",
                        "切 Tab 回来自动回位：排班回本月，工资回上个月；设置页也一样",
                        "看别班的日子不能改，只读提示下面加了「切回 B 班」按钮",
                    ])
                    changelog(version: "1.3.2.015", items: [
                        "更新弹窗改成按版本记：点「稍后」只对这个版本不再弹，出了新版本照样弹，一天更新好几次也能收到",
                    ])
                    changelog(version: "1.3.2.014", items: [
                        "排班页和工资页的顶卡改成白框，跟着浅色深色走；排班页日期放顶行，今日已挣挪到底下",
                        "工资页顶卡多了三段进度条和三列小字，实发工资、实发奖金、餐贴一眼看清",
                        "切换班组不再闪屏，点一下直接换，胶囊滑过去就行",
                        "选中那天的蓝色框改成藏青，跟全站选中态一个颜色，不扎眼了",
                        "班组切换改成分段选择器，底部统计改成四列大数字",
                        "工资页「工资明细」「奖金明细」标题挪到白卡外面，卡片里只留行",
                        "左上角「本月」和右下角悬浮「今天」都不要了，回到今天改成顶卡右下角的小按钮，两页一样",
                        "「龙抬头」全改成「龙头」，详情页也一样",
                    ])
                    changelog(version: "1.3.2.013", items: [
                        "设置页重新分组：排班与工资、显示与组件、帮助与关于，找入口更快了",
                        "管理员入口收进「开发者选项」，普通用户设置页更干净；检查更新有新版时多一个小红点",
                        "小组件页直接展示 5 张预览卡片，数据同步改成轻提示「已刷新」",
                        "使用说明改成问答式，点问题展开答案；个税算法拆成清单更好读",
                        "倒班与班次页改成白底卡片 + 细描边选中态，班次时段直接放在页顶",
                        "全站标题统一居中，切页时头部不再跳；点月份标题可直接选年月，不用连点箭头",
                        "黑卡右上角加了眼睛，点一下金额全部藏起来，再点恢复；黑卡上还标了「B班 · 我的今日」",
                        "工资单更好读：扣款项带负号、0 元的行变浅、公积金补上费率",
                        "更换班组页的保存按钮改成独立大按钮，轮次预览改成彩色小标签",
                    ])
                    changelog(version: "1.3.2.012", items: [
                        "排班页黑卡重新排版：日期与班次在左，今日已挣放大在右，一眼看清",
                        "排班页与工资页顺序对齐，切换不再跳动；班组切换更顺滑，胶囊不再变形",
                        "日期格里的「龙抬头」改成「龙头」，不再竖排三行顶到班次",
                        "工资页返回按钮移到右上角，叫「本月」，不再挡住「可改」；金额全部右对齐",
                        "设置页版本切换改成滑动胶囊，两个渠道的最新版号直接显示在选项下",
                    ])
                    changelog(version: "1.3.2.011", items: [
                        "优化排班与工资页切换流畅度，滑动切换更跟手",
                        "修复跨月滑动时顶部标题与日期显示异常的问题",
                        "优化工资明细加载机制，切换月份响应更快",
                    ])
                    changelog(version: "1.3.2.010", items: [
                        "工资页黑卡不再被切断，标签与金额完整显示，跟着月份翻页",
                        "工资页切换月份更快，算数挪到后台，滑到新月不用等",
                        "排班页快速滑动更顺滑，标题不再糊成一团",
                    ])
                    changelog(version: "1.3.2.009", items: [
                        "卡顿根治了：状态改成细粒度观察，一个地方变了不再牵着整页重画；月份和工资只算一次记下来，滑过去直接显示",
                        "标题拖过一半就换，不用等滑停了才变；底栏不再缩成左下角小圆球盖字",
                        "日历白卡整张跟着月份滑，星期栏和日期永远对齐，不再错位、切边",
                        "工资黑卡跟着月份一起翻页、一起滚动，不再上面停在 11 月、下面已经滑到 12 月",
                        "「今天」按钮改成右下角悬浮按钮，标题行只剩箭头和月份；调班/请假那张卡改成通栏长条",
                        "三薪改成日期数字旁边的小橙点，不再往上凸压农历字；排班页、工资页、设置页向上滚时导航栏不再透字",
                    ])
                    changelog(version: "1.3.2.008", items: [
                        "排班页重做了：月份滑动是系统原生的分页，标题只跟着落定的那一页走，不再错位、重叠、跳月；「今天」按钮只在非当月出现",
                        "底栏改回系统原生：iOS 26 上是液态玻璃，低版本是标准底栏；所有二级页面都藏起底栏，倒班方式设置的保存按钮和关于页的版权信息不再被压住；管理后台也从设置页点进去，左上角是系统返回",
                        "节假日更新时间改成本地时间；倒班方式的周均小时不再带一串小数",
                        "排班页往上滚时导航栏不再透字；三薪改成右上角的「三薪」小角标",
                        "工资页黑卡回来了，里面是当月实发合计的大数字",
                    ])
                    changelog(version: "1.3.2.007", items: [
                        "动画按文档重做了：月份滑动跟手、松手轻轻落定；点箭头切月只轻轻移一点、淡过去，不再整页横甩；班组切换底色滑过去，标签跟着换；点某一天格子会暗一下，点「今天」那格闪一下",
                        "底栏切换不再自己加淡入淡出：恢复系统原生的切换，干净利落",
                        "砍掉了几处多余的提示文字：工资页「本地计算，仅供参考」和底部那段说明、手动排班页「点击下方班次排班」都没了，字少了、页面更干净",
                    ])
                    changelog(version: "1.3.2.006", items: [
                        "日历固定 6 行：不管哪个月都是 6 行、行距一样，慢拖时两页的行严丝合缝，不再错位；5 行的月底下多出一行下月开头的暗色日期",
                        "底栏切换改成淡入淡出：点排班/工资/设置，页面 0.2 秒轻轻淡过去，不再一下子硬切",
                        "排班页和工资页最底下不再被底栏压住：底部多留了白，「当月应出勤」和奖金卡片都能完整看到",
                        "月份箭头、今天按钮、班组按钮点下去有反应了：轻轻缩一下、暗一下，0.1 秒就回来",
                        "骨架屏晚 150 毫秒再出来：数据回来得快就不闪一下灰条",
                    ])
                    changelog(version: "1.3.2.005", items: [
                        "戴手套也点得中：月份箭头、今天按钮、班组按钮、保存取消和验证码按钮，点击范围都扩到 48，样子没变",
                        "加载时不再转圈：排班页的调班/请假卡、工资页加载中显示灰色骨架占位，数据来了直接换上",
                        "排班页和工资页底下多了一行「数据更新于几点」，一眼能看出数据是不是最新的",
                        "调班、请假、工资设置保存成功时手机轻震一下，确认收到了",
                    ])
                    changelog(version: "1.3.2.004", items: [
                        "排班页预加载 21 页：每翻一页，前后 10 个月的格子都提前算好，滑过来直接显示，慢拖不再一顿一顿",
                        "调班/请假那张卡一直都在：本月没有就显示“本月没有调班请假”，不再忽有忽无、页面不再往上跳；当月出勤和这张卡跟排班页一起预加载",
                        "工资页切月动画改成平滑的：左右滑、点箭头都顺滑地过去；邻月的工资提前算好，滑到新月不用现算",
                        "顶上黑卡高度变化也顺滑了：休息那天没有预计工资，黑卡缩小时是慢慢缩的，不再一下子跳",
                        "底栏切页迅速又平滑：点排班/工资/设置，页面 0.25 秒平滑淡入淡出，胶囊指示条跟着滑过去；工资提前算好，第一次点过去也不用等",
                    ])
                    changelog(version: "1.3.2.003", items: [
                        "月份左右滑动更跟手了：慢拖也不一顿一顿的了——日历格改成整页一次画好再滑，倒计时那行每秒重画时不再多走一次模糊，窄屏字号只算一次",
                        "10 年滑页窗口改成前后各 10 年：排班页和工资页都能往前翻 10 年、往后翻 10 年，一共 20 年，滑到头也不怕",
                        "界面统一翻新：深色模式分层更清楚，不再是一片黑；卡片和分隔线改成淡淡的明暗色阶，整体更干净高级",
                        "深色下字不再发粗：字重自动降一档，看着和浅色一样舒服；倒计时、金额、日期都用等宽数字，数字跳动时不再左右抖",
                        "动效分了性格：月份滑动干脆利落不回弹，保存成功的提示带一点回弹、2.5 秒自己消失；动态出现的文字像水墨一样晕开",
                        "2027 年节假日按官方数据改准了：端午是 6 月 9 日、中秋是 9 月 15 日，之前推算的日期是错的",
                    ])
                    changelog(version: "1.3.2.002", items: [
                        "10 年滑页窗口改成前后各 10 年：排班页和工资页都能往前翻 10 年、往后翻 10 年，一共 20 年，滑到头也不怕",
                        "界面统一翻新：深色模式分层更清楚，不再是一片黑；卡片和分隔线改成淡淡的明暗色阶，整体更干净高级",
                        "深色下字不再发粗：字重自动降一档，看着和浅色一样舒服；倒计时、金额、日期都用等宽数字，数字跳动时不再左右抖",
                        "动效分了性格：月份滑动干脆利落不回弹，保存成功的提示带一点回弹、2.5 秒自己消失；动态出现的文字像水墨一样晕开",
                        "2027 年节假日按官方数据改准了：端午是 6 月 9 日、中秋是 9 月 15 日，之前推算的日期是错的",
                    ])
                    changelog(version: "1.3.2.001", items: [
                        "界面统一翻新：深色模式分层更清楚，不再是一片黑；卡片和分隔线改成淡淡的明暗色阶，整体更干净高级",
                        "深色下字不再发粗：字重自动降一档，看着和浅色一样舒服；倒计时、金额、日期都用等宽数字，数字跳动时不再左右抖",
                        "动效分了性格：月份滑动干脆利落不回弹，保存成功的提示带一点回弹、2.5 秒自己消失；动态出现的文字像水墨一样晕开",
                        "排班取消上下一年的限制，改成 10 年：排班页和工资页都能前后滑 10 年（前后各 10 年），滑到头也不怕",
                        "2027 年节假日按官方数据改准了：端午是 6 月 9 日、中秋是 9 月 15 日，之前推算的日期是错的",
                    ])
                    changelog(version: "1.3.1.001", items: [
                        "个税加专项附加扣除：子女教育、赡养老人按自己填的每月金额扣，婴幼儿照护每孩自己填每月金额（每孩最多 2000），学历教育 400/月，职业资格取证当年一次性扣 3600（要填取证年月），大病医疗只在次年汇算时扣、不影响每月工资，房贷 1000/月或租金三档（二选一）；设置 → 工资设置 → 专项附加扣除里填；有工资权限的人第一次进工资页会问一次有没有专项扣除，只问一次；工资页奖金区多了一行「专项附加扣除」",
                        "个税算出来是负数时不再倒扣：按 0 算，多的留到以后月份再抵，不会从实发奖金里扣钱。",
                        "工资页首次进页改成空状态：还没填工资设置时，工资页只显示一个「填写工资设置」按钮，点进去走一遍引导，填完才显示数据",
                        "登录页加「忘记密码？」：没登录时用短信验证码重置密码（输手机号 → 收验证码 → 设新密码），不用再找管理员",
                        "切月更快、更省流量；小组件只在内容变化时刷新",
                        "点某天能直接改这天的班：日班/中班/早班/早中班/日中班，改完计入当月总班数算工资。",
                    ])
                    changelog(version: "1.3.0.015", items: [
                        "底栏恢复系统默认样式；修复更新提醒不弹出的问题；滚动指示条常显；支持 120Hz 刷新率；公积金可以自己填。",
                    ])
                    changelog(version: "1.3.0.014", items: [
                        "底栏改为满宽毛玻璃样式；修复更新提醒不弹出的问题。",
                    ])
                    changelog(version: "1.3.0.013", items: [
                        "底栏玻璃效果优化；栏上滑动切页更灵敏；滚动指示条常显。",
                    ])
                    changelog(version: "1.3.0.012", items: [
                        "修复更新提醒不弹出的问题；底栏玻璃效果优化。",
                    ])
                    changelog(version: "1.3.0.011", items: [
                        "底栏玻璃效果优化。",
                    ])
                    changelog(version: "1.3.0.010", items: [
                        "底栏玻璃效果优化。",
                    ])
                    changelog(version: "1.3.0.009", items: [
                        "底栏改成悬浮胶囊样式，加玻璃效果。",
                    ])
                    changelog(version: "1.3.0.008", items: [
                        "底栏玻璃效果重做。",
                    ])
                    changelog(version: "1.3.0.007", items: [
                        "修复更新提醒不弹出的问题；底栏恢复满宽毛玻璃样式。",
                    ])
                    changelog(version: "1.3.0.006", items: [
                        "底栏改回透明玻璃悬浮样式；栏上滑动切页修复；支持 120Hz 刷新率。",
                    ])
                    changelog(version: "1.3.0.005", items: [
                        "底栏悬浮胶囊改成不透明。",
                    ])
                    changelog(version: "1.3.0.004", items: [
                        "底栏悬浮胶囊位置和宽度调整。",
                    ])
                    changelog(version: "1.3.0.003", items: [
                        "底栏只留悬浮胶囊。",
                    ])
                    changelog(version: "1.3.0.002", items: [
                        "底栏改成悬浮胶囊，加系统液态玻璃效果；在栏上左右滑动可以切页。",
                    ])
                    changelog(version: "1.3.0.001", items: [
                        "底栏加毛玻璃效果，在栏上左右滑动可以切页；公积金改成自己填。",
                    ])
                    changelog(version: "1.2.9.004", items: [
                        "排班页统计行应出勤改按排班算：以前应出勤那格显示的是基本天数（10 月 18 天、11 月 21 天），和基本天数撞成两个一样的数；现在应出勤按基础轮班天数算（10 月 24 天、11 月 22 天、12 月 24 天），基本天数还是法定口径（10 月 18 天、11 月 21 天、12 月 23 天），两个数不一样了",
                    ])
                    changelog(version: "1.2.9.003", items: [
                        "每日预估改按实发算：按当天班次类型算，扣五险一金和个税；水电费不扣，餐补不算。当月每天预估加起来等于工资页那个月实发 + 水电费。",
                        "排班页统计行加上基本天数：以前应出勤和基本天数共用一个数（11 月碰巧都是 21 看不出，10 月会错成 24）；现在基本天数按法定放假口径算（10 月 18 天、11 月 21 天、12 月 23 天）",
                        "小组件介绍图换成真实截图；新加本月工资和锁屏今日已挣两张介绍卡，只有开了工资权限才显示；没权限的人小号今日小组件只显示班次和倒计时，不显示钱",
                        "小号今日小组件钱那行不再截断：已挣和预估整行完整显示",
                        "入职时间年份不再带逗号：工资设置 → 入职时间的年份滚轮以前显示 2,012、2,018（带千分位逗号），现在显示 2012、2018 这种纯数字；日历显示设置预览和分享班表里的年份也一起改了。金额里的千分位逗号不受影响",
                        "入职时间年份不再折行：工资设置 → 入职时间的年份以前窄得折成两行竖着显示，现在横着一行显示；工资引导里入职时间那一行也一起改了",
                    ])
                    changelog(version: "1.2.9.002", items: [
                        "入职时间年份不再带逗号：工资设置 → 入职时间的年份滚轮以前显示 2,012、2,018（带千分位逗号），现在显示 2012、2018 这种纯数字；日历显示设置预览和分享班表里的年份也一起改了。金额里的千分位逗号不受影响",
                    ])
                    changelog(version: "1.2.9.001", items: [
                        "每日预估工资改成工资加奖金总共的：按天算、按当天班次类型算，普通上班日、加班日、三薪日各按各的；双班两个班都算。",
                        "开通工资功能后，再次进软件会弹窗走一遍工资引导：把基本工资、奖金系数、缴费基数、岗位、入职时间、剩余年休假填好，再进工资页；已有权限、设定填好了的不弹。引导可以点「以后再说」跳过，跳过后下次进软件还会再弹，直到走完为止",
                        "钱跟着工资权限走：排班页「已挣 · 预估」那行、当天详情「预估工资」行、小号今日小组件和锁屏小组件里的钱数、本月工资小组件，都只有开了工资权限才能看到；没权限只显示班次和倒计时，不显示钱。倒计时（距下班）不是钱，不管开关都显示",
                        "调班/请假重做（配对互换）：以前调班只能改自己这边、没有和哪个班调的选项；现在点一天看四个班、选一个班替你上这天（你这天休息，对方那天变成组合班），再挑一天还班（也可以先不填，待还班），保存前两边一起预览；删一边两边一起恢复；还班日可以后补，一直不还就转为请假。请假也可以安排别的班顶岗。只改你自己的记录，不动对方的日历；看别的班日历时，你和那个班调过的日子按调班后显示",
                        "新用户引导的倒班方式补全：以前引导里选四班三倒只有 8 天一轮一种；现在和设置页一样——手动/周期两张大卡 + 按分类列出的全部方式（四班三倒 5 种、五班三倒、四班两倒、三班二倒、两班倒、巴拿马、杜邦、三班三倒、五班四倒、四班 6 小时），每种带循环示意，选完就生效",
                        "法定节假日三薪标记：只要那天在法定节假日表里，日历格就标「三薪」，不管当天是上班还是休息（比如 2027 年 1 月 1 日元旦 B 班休息，也标三薪）；工资计算不变，三薪天数和金额只算实际上了法定节假日班次的",
                        "班次推送提醒修好：以前开关看着开着，但提醒从没响过。现在打开软件就弹一次系统通知权限弹窗（只弹一次，被拒后去系统设置里开）；被拒就把开关关掉，不再假装开着。",
                    ])
                    changelog(version: "1.2.8.002", items: [
                        "修深色模式蓝色字看不清：深色下强调色改亮蓝，设置页、排班页、底部 Tab 栏、引导页深色下都清晰可读",
                    ])
                    changelog(version: "1.2.8.001", items: [
                        "设置里加深色模式：跟随系统 / 浅色 / 深色三个选项，改完立刻生效，不用重启 App",
                        "修深色模式字体模糊：深色下文字改纯白、提亮，开屏深色改深灰渐变，不闪白屏",
                    ])
                    changelog(version: "1.2.7.010", items: [
                        "修小号小组件显示不全：顶行日期和底行明日班次完整显示，不截断",
                        "启动加开屏：全屏品牌闪屏（大 logo + 班次色小圆点），盖住启动时的加载/过渡，不再闪白屏",
                    ])
                    changelog(version: "1.2.7.009", items: [
                        "修设置页切版本渠道点不动：点「正式版」/「内测版」会先弹确认框，确认后按新渠道查更新",
                    ])
                    changelog(version: "1.2.7.008", items: [
                        "小组件 UI 优化：小号重新排版，本周/本月加农历小字、今天高亮、底下加统计；设置页小组件改放真实小组件截图的介绍图",
                    ])
                    changelog(version: "1.2.7.007", items: [
                        "修设置页切版本渠道点不动：点「正式版」/「内测版」立刻弹确认框",
                    ])
                    changelog(version: "1.2.7.006", items: [
                        "小组件重写：不用再填密钥；装好打开 App 就刷新，不用删掉重加；设置页小组件里加了「立即同步」",
                    ])
                    changelog(version: "1.2.7.005", items: [
                        "修小组件只显示颜色、不显示文字：小组件现在直接出数",
                    ])
                    changelog(version: "1.2.7.004", items: [
                        "小组件不用填密钥了：打开 App 登录一次，小组件直接从服务器拉数据",
                    ])
                    changelog(version: "1.2.7.003", items: [
                        "修设置页切版本渠道点不动：点「正式版」/「内测版」没反应的问题修好了，现在点另一个渠道会先弹确认框；点完按钮会转圈，不会再让人以为没点上",
                    ])
                    changelog(version: "1.2.7.002", items: [
                        "倒班方式全部推出：五班三倒、四班两倒（12 小时）、三班二倒（12 小时）、两班倒、巴拿马 2-2-3、杜邦、三班三倒（带替休）、五班四倒、四班 6 小时工作制；选了方式 + 班次，日历和工资班次统计跟着算",
                        "12 小时班禁令：白班接夜班不行、不能连上两个夜班、夜班后休 48 小时、一天只能上一个班；12 小时/6 小时班的工资口径待定，工资页只显示班次统计、金额暂不算",
                        "手动排班改成月历 + 底部班次按钮：点某天再点班次就是给那天排班；可加自定义班次；日历只留月视图",
                        "切版本渠道先弹确认：写清当前版本、目标渠道最新版、切了会怎样；切完立刻按新渠道查一次，另一条线的版本也推出来让用户自己决定装不装",
                        "六班三倒继续留「即将推出」",
                    ])
                    changelog(version: "1.2.7.001", items: [
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
            }
        }
        .navigationTitle("更新日志")
        .navigationBarTitleDisplayMode(.inline)
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
                        .fieldBackground()
                    HStack {
                        TextField("6 位验证码", text: $code)
                            .keyboardType(.numberPad)
                            .fieldBackground()
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
            // 1.3.2.017：保存成功轻震一下 + 关页面。
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                    HStack(spacing: 8) {
                        TextField("昵称（最多 10 个字）", text: $name)
                            .fieldBackground()
                            .onChange(of: name) { _, new in
                                if new.count > 10 { name = String(new.prefix(10)) }
                            }
                        Text("\(name.count)/10")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
                        .disabled(saving || name.count > 10)
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
            // 1.3.2.017：保存成功轻震一下 + 关页面。
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                                .fieldBackground()
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
                        SecureField(PasswordUtil.placeholder, text: $newPassword)
                        .fieldBackground()
                        SecureField("再输一次新密码", text: $confirmPassword)
                        .fieldBackground()
                        // 1.3.2.017：密码规则提醒（小字、次要色）；冒号限制已去掉，不再提冒号。
                        Text(PasswordUtil.ruleHint)
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                                  || !PasswordUtil.isValid(newPassword) || newPassword != confirmPassword)
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
        // 1.3.2.017：客户端先校验新规（8-16 位、字母+数字），不合规就地提示，不等服务端报错。
        guard PasswordUtil.isValid(newPassword) else {
            message = PasswordUtil.ruleHint
            isError = true
            return
        }
        saving = true
        defer { saving = false }
        do {
            try await store.changePassword(phone: phone,
                                           code: code.trimmingCharacters(in: .whitespaces),
                                           newPassword: newPassword)
            // 1.3.2.017：保存成功轻震一下 + 关页面。
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismiss()
        } catch {
            message = (error as? APIError)?.message ?? error.localizedDescription
            isError = true
        }
    }
}

/// 小组件页（1.2.7.006 重写）：五张带预览图的介绍卡片 + 数据同步。
/// 密钥彻底拿掉：不再生成、不再显示、不再让用户填。小组件只走设备直连。
/// 数据同步是实测的：点「刷新小组件数据」就当场跑一次设备直连拉数，
/// 成功只弹轻量 Toast「已刷新」，失败才在页面里直说原因，不再只让老爷去桌面看。
struct WidgetsView: View {
    @Environment(AppStore.self) private var store: AppStore
    @State private var syncing = false
    @State private var syncMessage: String?
    /// 轻量 Toast（1.3.2.013）：同步成功只弹一句「已刷新」，1.5 秒自己消失，不再弹大绿框。
    @State private var showSyncToast = false

    /// 本机设备号（App 登录时登记到用户名下，小组件凭它拉数据）。
    private var deviceId: String? { UIDevice.current.identifierForVendor?.uuidString }

    var body: some View {
        Form {
            // 小组件介绍（1.2.7.008）：进页面直接展示带预览图的 5 张卡片，
            // 顶部的纯文字目录已删（和下面的卡片重复）。
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

            Section("数据同步") {
                Text("若桌面或锁屏小组件显示延迟，可点击下方按钮手动刷新数据。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button(syncing ? "同步中…" : "刷新小组件数据") {
                    Task { await syncNow() }
                }
                .disabled(syncing)
                if let syncMessage {
                    Text(syncMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("桌面与锁屏小组件")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if showSyncToast {
                Text("已刷新")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.label))
                    .foregroundColor(Color(.systemBackground))
                    .clipShape(Capsule())
                    .padding(.bottom, 24)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSyncToast)
    }

    /// 介绍图卡片：图 + SwiftUI 标题/说明。方图（今日）居中限宽 200，宽图通栏。
    /// 预览图是静态截图（11 月 26 日那天裁的），日期不是当天；右上角加极淡的
    /// 「示例」标签，免得误以为小组件不会自动刷新（1.3.2.013）。
    private func introCard(image: String, title: String, desc: String, imageWidth: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer(minLength: 0)
                ZStack(alignment: .topTrailing) {
                    Image(image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: imageWidth ?? .infinity)
                        .cornerRadius(12)
                    Text("示例")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemBackground).opacity(0.85))
                        .clipShape(Capsule())
                        .padding(6)
                }
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

    /// 刷新小组件数据：当场跑一次小组件用的设备直连拉数，成功就写一份快照到
    /// App Group（通的机器上小组件直接读）、通知小组件刷新；失败就直说原因。
    /// 成功只弹轻量 Toast「已刷新」（1.3.2.013），不再在页面里留大绿框。
    private func syncNow() async {
        syncMessage = nil
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
            showSyncToast = true
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                showSyncToast = false
            }
        } else {
            syncMessage = "取数失败：云和隧道都没拉到数，检查网络后重试；还不行就把这页截给我。"
        }
    }
}

