import SwiftUI

/// 登录页（1.2.6 重做，模仿考试宝、换成我们自己的藏青「班」图标）：
/// 两种方式都能进——账号密码登录 / 手机号验证码登录；没有一键登录（阿里云一键登录
/// 免费次数只有 100 次，不够用，1.2.6 不做、不留入口）。
/// 输入框是下划线样式（只有底部细线，不要方框直角），登录按钮是全圆角胶囊；
/// 两种方式用输入框上方的双 Tab（分段选择器）切换，版面不跳动。
/// 验证码登录：输手机号 → 点获取验证码（60 秒倒计时）→ 输 6 位码 → 登录；新手机号会自动建账号（用户名是
/// 「手机+后 4 位」），昵称在设置页改。错误中文原样展示。
/// 1.3.2.017：主按钮下方加协议勾选行（默认未勾选），未勾选点登录拦住并提示；
/// 品牌副标题「8天一轮倒班」已删；登录页验证码提示已删（砍提示规矩）。
struct LoginView: View {
    @Environment(AppStore.self) private var store: AppStore

    /// 登录方式：password = 账号密码，sms = 手机号验证码。
    @State private var loginMode: LoginMode = .password
    private enum LoginMode: String, CaseIterable {
        case password = "账号密码"
        case sms = "手机号验证码"
    }

    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @FocusState private var focusedField: LoginField?
    /// 输入框聚焦态（统一规范 v2：聚焦变暗 + 阴影，不用亮色描边）。
    private enum LoginField { case username, password, phone, smsCode }
    // 短信登录
    @State private var phone = ""
    @State private var smsCode = ""
    @State private var smsCountdown = 0
    @State private var smsSending = false
    @State private var errorText: String?
    @State private var isBusy = false
    @State private var showRegister = false
    @State private var showForgotPassword = false
    /// 协议勾选（1.3.2.017）：默认未勾选；未勾选点登录拦住并提示。
    @State private var agreedToTerms = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    modePicker
                    formCard
                    if let errorText {
                        Text(errorText)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    loginButton
                    AgreementConsentRow(agreed: $agreedToTerms)
                    if loginMode == .password {
                        HStack {
                            registerLink
                            Spacer()
                            Button("忘记密码？") {
                                showForgotPassword = true
                            }
                            .font(.subheadline)
                        }
                    }
                    Spacer(minLength: 24)
                    versionLine
                }
                .padding(.horizontal, 32)
                .padding(.top, 48)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
            .sheet(isPresented: $showRegister) {
                RegisterView()
            }
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordView(onDone: { phone in
                    // 重置成功回登录页：账号框直接填好这个手机号，用户只输新密码就行。
                    username = phone
                    loginMode = .password
                })
            }
        }
    }

    /// 登录方式双 Tab（1.3.2.017）：输入框上方分段选择器，替代底部两个大圆按钮；
    /// 切方式时版面不跳动、错误提示清掉。
    private var modePicker: some View {
        Picker("登录方式", selection: $loginMode) {
            Text(LoginMode.password.rawValue).tag(LoginMode.password)
            Text(LoginMode.sms.rawValue).tag(LoginMode.sms)
        }
        .pickerStyle(.segmented)
        .onChange(of: loginMode) { _ in errorText = nil }
    }

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(AppStyle.navyAdaptive)
                    .frame(width: 84, height: 84)
                Text("班")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.white)
            }
            Text("排班空间")
                .font(.title)
                .bold()
        }
    }

    private var formCard: some View {
        Group {
            if loginMode == .password {
                passwordForm
            } else {
                smsForm
            }
        }
    }

    /// 下划线输入框：只有底部一条细线，不要方框直角（1.2.6）。
    private func underlineField<Content: View>(focused: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 1)
        }
        .background(focused ? AppStyle.surface2 : Color.clear)
        .cornerRadius(10)
        .shadow(color: focused ? Color.black.opacity(0.12) : .clear, radius: 4, y: 1)
    }

    private var passwordForm: some View {
        VStack(spacing: 8) {
            underlineField(focused: focusedField == .username) {
                TextField("请输入手机号", text: $username)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .username)
            }
            underlineField(focused: focusedField == .password) {
                HStack(spacing: 8) {
                    Group {
                        if showPassword {
                            TextField("请输入密码", text: $password)
                                .focused($focusedField, equals: .password)
                        } else {
                            SecureField("请输入密码", text: $password)
                                .focused($focusedField, equals: .password)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye" : "eye.slash")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    /// 短信登录：手机号 + 获取验证码（60 秒倒计时）+ 6 位码。
    private var smsForm: some View {
        VStack(spacing: 8) {
            underlineField(focused: focusedField == .phone) {
                TextField("请输入手机号", text: $phone)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .phone)
            }
            underlineField(focused: focusedField == .smsCode) {
                HStack(spacing: 12) {
                    TextField("请输入验证码", text: $smsCode)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .smsCode)
                    Button {
                        Task { await sendSmsCode() }
                    } label: {
                        Text(smsCountdown > 0 ? "\(smsCountdown) 秒后重发" : "获取验证码")
                            .appFont(size: AppFont.bodySmall)
                            .monospacedDigit()
                            .foregroundColor(.blue)
                    }
                    .disabled(smsSending || smsCountdown > 0 || !isValidPhone(phone))
                }
            }
        }
    }

    /// 全圆角胶囊登录按钮（1.2.6）。未填内容时置灰禁用（1.3.2.017，和注册页统一）。
    private var loginButton: some View {
        Button {
            Task { await doLogin() }
        } label: {
            Group {
                if isBusy {
                    ProgressView().tint(.white)
                } else {
                    Text("登录").font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: AppStyle.buttonHeight)
            .background(canLogin ? AppStyle.navyAdaptive : Color(.systemGray3))
            .foregroundColor(.white)
            .cornerRadius(AppStyle.buttonHeight / 2)
        }
        .buttonStyle(.plain)
        .disabled(isBusy || !canLogin)
    }

    /// 登录按钮能不能点：密码模式要账号+密码；短信模式要合法手机号+6 位码。
    private var canLogin: Bool {
        if loginMode == .password {
            return !username.isEmpty && !password.isEmpty
        }
        return isValidPhone(phone) && smsCode.count == 6
    }

    private var registerLink: some View {
        Button("没有账号？注册账号") {
            showRegister = true
        }
        .font(.subheadline)
    }

    /// 底部当前版本号：从 bundle 读，升版自动跟着变。
    private var versionLine: some View {
        Text("当前版本 \(appVersion)")
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private func doLogin() async {
        errorText = nil
        // 1.3.2.017：未勾选协议先拦住并提示（别静默失败）。
        guard agreedToTerms else {
            errorText = "请先阅读并同意《用户使用协议》和《隐私协议》"
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            if loginMode == .password {
                try await store.login(username: username.trimmingCharacters(in: .whitespaces),
                                      password: password)
            } else {
                try await store.loginWithSms(phone: phone.trimmingCharacters(in: .whitespaces),
                                             code: smsCode.trimmingCharacters(in: .whitespaces))
            }
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    /// 发验证码：成功后开始 60 秒倒计时（每秒 -1）；失败把服务端中文错误显示出来。
    private func sendSmsCode() async {
        errorText = nil
        smsSending = true
        defer { smsSending = false }
        do {
            try await store.api.sendSmsCode(phone: phone.trimmingCharacters(in: .whitespaces))
            smsCountdown = 60
            Task {
                while smsCountdown > 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    smsCountdown -= 1
                }
            }
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    /// 大陆手机号校验（共用 PhoneUtil）。
    private func isValidPhone(_ s: String) -> Bool { PhoneUtil.isValid(s) }
}

/// 忘记密码（登录页「忘记密码？」入口，1.3.3.004 按 115 干净白卡重写）：没登录时用短信验证码重置密码。
/// 流程：输手机号 → 点获取验证码（走重置密码模板）→ 输 6 位码 → 设新密码 → 提交。
/// 成功后只改密码，不自动登录；回登录页时账号框已填好这个手机号，用户只输新密码就行。
/// 第一张卡：手机号（+86 前缀）+ 新密码 + 再输一次；第二张卡：短信验证码 + 描边「获取验证码」；
/// 下面大号「提交」按钮。不要多余提示，不抄参考图的文案（规则是 8-16 位不是 8-20；
/// 咱们没有数字账号，「若你只知道数字账号，请点此找回」那句不要）。
/// 只有手机找回，没有邮箱找回，点「忘记密码」直接进这个表单，不用选方式。
struct ForgotPasswordView: View {
    @Environment(AppStore.self) private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    /// 重置成功后回登录页：把手机号带回去填进账号框。
    var onDone: (String) -> Void = { _ in }

    @State private var phone = ""
    @State private var smsCode = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var smsCountdown = 0
    @State private var smsSending = false
    @State private var errorText: String?
    @State private var isBusy = false
    @State private var resetDone = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if resetDone {
                        successBody
                    } else {
                        formBody
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 32)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("忘记密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private var formBody: some View {
        VStack(spacing: 20) {
            WhiteCard {
                HStack(spacing: 10) {
                    Text("+86")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 1, height: 20)
                    TextField("请输入手机号", text: $phone)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                WhiteCardDivider()
                PasswordFieldRow(placeholder: PasswordUtil.placeholder, text: $newPassword, show: $showPassword)
                WhiteCardDivider()
                PasswordFieldRow(placeholder: "请再输一次新密码", text: $confirmPassword, show: $showConfirmPassword)
            }
            // 1.3.2.017：密码规则提醒（小字、次要色）；冒号限制已去掉，不再提冒号。
            // 规则是 8-16 位（参考图里的 8-20 不对，不抄）。
            Text(PasswordUtil.ruleHint)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            WhiteCard {
                HStack(spacing: 12) {
                    TextField("请输入验证码", text: $smsCode)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    OutlinedCodeButton(title: smsCountdown > 0 ? "\(smsCountdown) 秒后重发" : "获取验证码",
                                       disabled: smsSending || smsCountdown > 0 || !PhoneUtil.isValid(phone)) {
                        Task { await sendSmsCode() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            if let errorText {
                Text(errorText)
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
            Button {
                Task { await doReset() }
            } label: {
                Group {
                    if isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Text("提交").font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: AppStyle.buttonHeight)
                .background((canReset || isBusy) ? AppStyle.navyAdaptive : Color(.systemGray3))
                .foregroundColor(.white)
                .cornerRadius(AppStyle.buttonHeight / 2)
            }
            .buttonStyle(.plain)
            .disabled(isBusy || !canReset)
        }
    }

    private var successBody: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)
            Text("密码已重置")
                .font(.headline)
            Text("请用新密码登录。")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button {
                onDone(phone.trimmingCharacters(in: .whitespaces))
                dismiss()
            } label: {
                Text("去登录").font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppStyle.buttonHeight)
                    .background(AppStyle.navyAdaptive)
                    .foregroundColor(.white)
                    .cornerRadius(AppStyle.buttonHeight / 2)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 48)
    }

    private var canReset: Bool {
        PhoneUtil.isValid(phone) && smsCode.count == 6
            && PasswordUtil.isValid(newPassword)
            && confirmPassword == newPassword
    }

    /// 发验证码（重置密码场景）：成功后开始 60 秒倒计时；失败把服务端中文错误显示出来。
    private func sendSmsCode() async {
        errorText = nil
        smsSending = true
        defer { smsSending = false }
        do {
            try await store.api.sendSmsCode(phone: phone.trimmingCharacters(in: .whitespaces), scenario: "reset")
            smsCountdown = 60
            Task {
                while smsCountdown > 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    smsCountdown -= 1
                }
            }
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func doReset() async {
        errorText = nil
        guard confirmPassword == newPassword else {
            errorText = "两次输入的新密码不一致"
            return
        }
        guard PasswordUtil.isValid(newPassword) else {
            errorText = PasswordUtil.ruleHint
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await store.api.resetPassword(
                phone: phone.trimmingCharacters(in: .whitespaces),
                code: smsCode.trimmingCharacters(in: .whitespaces),
                newPassword: newPassword)
            resetDone = true
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
