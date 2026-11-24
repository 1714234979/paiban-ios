import SwiftUI

/// 设置页（1.1.3：二级菜单）：主界面只留入口行——账号与安全、工资设置、关于
/// 各开一个二级页面改细项；换班、管理后台、服务器、更新、反馈留在主界面。
/// 服务器那节只给老爷（张晓文）看，同事看不到。
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var isCheckingUpdate = false
    @State private var showFeedback = false
    @State private var showAdminBackend = false

    /// 账号与安全入口的副标题：名字 · 手机号（脱敏，未绑就写未绑定）。
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
        Form {
            Section("账号") {
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

            // 管理后台切换：只有老爷（张晓文）能看到。点一下进管理后台（WebView），
            // 返回后排班/工资页的状态、登录态、本地缓存都在，不用重新登录。
            if store.isOwner {
                Section("管理后台") {
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

            Section("换班") {
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

            Section("工资设置") {
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

            Section("更新") {
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
            }

            Section("反馈") {
                Button {
                    showFeedback = true
                } label: {
                    HStack {
                        Text("反馈问题")
                        Spacer()
                        Text("会附上最近 24 小时运行日志")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("关于") {
                NavigationLink {
                    AboutView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("关于")
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
        .sheet(isPresented: $showFeedback) {
            FeedbackView()
        }
        .fullScreenCover(isPresented: $showAdminBackend) {
            AdminBackendView()
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

    private func manualUpdateCheck() async {
        isCheckingUpdate = true
        defer { isCheckingUpdate = false }
        await store.checkForUpdateManually()
    }
}

// MARK: - 设置二级页面（1.1.3）

/// 账号与安全（二级页面）：名字、登录账号、班组、手机号（绑定/更换）、
/// 修改名字、修改密码、退出登录。退出登录放这里，不留在设置页主界面；
/// 退出只清登录状态，离线缓存保留。
struct AccountSecurityView: View {
    @EnvironmentObject private var store: AppStore

    @State private var showBindPhone = false
    @State private var showChangePhone = false
    @State private var showChangeName = false
    @State private var showChangePassword = false
    @State private var showLogoutConfirm = false

    var body: some View {
        Form {
            Section("账号") {
                HStack {
                    Text("名字")
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
                        Text("修改名字")
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
                Text("改密码、改名字、换手机号、退出登录都在「设置 → 账号与安全」里。退出登录只清登录状态，离线缓存留着，下次登录还能看。换手机号要收新号的验证码验证，30 天内只能换一次。换班组在设置页「更换班组」里，选新班和生效日期，工资跟着新班组算。")
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

// MARK: - 绑定手机号 / 改名字 / 改密码（1.1.3）

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

/// 改名字：改的是显示名（displayName），随意改、不限次数、不用验证码；
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
                    TextField("显示名（最多 32 个字）", text: $name)
                } footer: {
                    Text("改的是显示名，登录用的账号名不变；留空保存会清回账号名。")
                }
                if let message {
                    Section {
                        Text(message).foregroundColor(isError ? .red : .green)
                    }
                }
            }
            .navigationTitle("修改名字")
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
