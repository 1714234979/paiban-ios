import SwiftUI

/// 设置页：账号、换班（永久换班入口）、工资设置、服务器、检查更新、关于、退出登录。
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var baseSalaryText = ""
    @State private var bonusCoefText = ""
    @State private var contributionBaseText = ""
    @State private var position = "员工"
    @State private var utilitiesText = ""
    @State private var showLogoutConfirm = false
    @State private var isSavingPay = false
    @State private var saveMessage: String?
    @State private var isCheckingUpdate = false

    private let positions = ["员工", "现场组长", "自控组长", "班长"]

    var body: some View {
        Form {
            Section("账号") {
                HStack {
                    Text("账号")
                    Spacer()
                    Text(store.user?.username ?? "—")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("班组")
                    Spacer()
                    Text("\(store.myTeam)班")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("身份")
                    Spacer()
                    Text(store.user?.isAdmin == true ? "管理员" : "同事")
                        .foregroundColor(.secondary)
                }
            }

            Section("换班") {
                NavigationLink {
                    TeamChangeView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("永久换班")
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
                    Text("社保缴费基数")
                    Spacer()
                    TextField("5938", text: $contributionBaseText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
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
        contributionBaseText = settings?.contributionBase.map { moneyText($0) } ?? "5938"
        position = settings?.position ?? "员工"
        utilitiesText = settings?.utilities.map { moneyText($0) } ?? "60"
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
        if let value = Double(contributionBaseText) { settings["contributionBase"] = value }
        settings["position"] = position
        if let value = Double(utilitiesText) { settings["utilities"] = value }
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
