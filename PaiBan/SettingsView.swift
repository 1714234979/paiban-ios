import SwiftUI

/// 设置页：账号、换班（更换班组入口）、工资设置、检查更新、关于、退出登录。
/// 服务器那节只给老爷（张晓文）看，同事看不到。
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var baseSalaryText = ""
    @State private var bonusCoefText = ""
    @State private var pensionText = ""
    @State private var position = "员工"
    @State private var utilitiesText = ""
    @State private var deptPerfText = ""
    @State private var showLogoutConfirm = false
    @State private var isSavingPay = false
    @State private var saveMessage: String?
    @State private var isCheckingUpdate = false
    @State private var showFeedback = false
    @State private var showAdminBackend = false

    private let positions = ["员工", "现场组长", "自控组长", "班长"]

    /// 养老月扣反推缴费基数：基数 = 养老月扣 ÷ 0.08（保留两位小数）。
    private var derivedBase: Double? {
        guard let pension = Double(pensionText.trimmingCharacters(in: .whitespaces)), pension > 0 else { return nil }
        return PayCalc.round2(pension / 0.08)
    }

    var body: some View {
        Form {
            Section("账号") {
                HStack {
                    Text("账号")
                    Spacer()
                    Text(store.displayUsername)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("班组")
                    Spacer()
                    Text("\(store.myTeam)班")
                        .foregroundColor(.secondary)
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
                HStack {
                    Text("水电费")
                    Spacer()
                    TextField("60", text: $utilitiesText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("科室绩效奖金")
                        Text("默认科室绩效，0–10000；某月单独改在工资页")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    TextField("4000", text: $deptPerfText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
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
                .disabled(isSavingPay)
                if let saveMessage {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    Text("退出登录")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } footer: {
                Text("退出后会清除本机的登录状态和该账号的离线缓存。")
            }
        }
        .navigationTitle("设置")
        .onAppear(perform: fillPayFields)
        .onChange(of: store.user?.paySettings) { _ in fillPayFields() }
        .alert("退出登录", isPresented: $showLogoutConfirm) {
            Button("取消", role: .cancel) { }
            Button("退出", role: .destructive) {
                Task { await store.logout() }
            }
        } message: {
            Text("确定要退出登录吗？本机的离线缓存会一起清除。")
        }
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

    // MARK: 工资设置

    private func fillPayFields() {
        let settings = store.user?.paySettings
        baseSalaryText = settings?.baseSalary.map { moneyText($0) } ?? "2420"
        bonusCoefText = settings?.bonusCoef.map { String(format: "%.1f", $0) } ?? "1.0"
        // 养老月扣框里显示的是“基数 × 8%”：老爷默认基数 5938 → 475.04；
        // 同事没填过就按全局默认基数 5938 算。
        let base = settings?.contributionBase ?? 5938
        pensionText = moneyText(PayCalc.round2(base * 0.08))
        position = settings?.position ?? "员工"
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
        if let value = Double(utilitiesText) { settings["utilities"] = value }
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

    // MARK: 检查更新

    private func manualUpdateCheck() async {
        isCheckingUpdate = true
        defer { isCheckingUpdate = false }
        await store.checkForUpdateManually()
    }
}
