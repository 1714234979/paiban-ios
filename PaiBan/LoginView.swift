import SwiftUI

/// 登录页：两种方式都能进——账号密码登录 / 手机号验证码登录（1.1.3）。
/// 验证码登录：输手机号 → 点获取验证码（60 秒倒计时）→ 输 6 位码 → 登录；
/// 新手机号会自动建账号（用户名是「手机+后 4 位」），显示名在设置页改。错误中文原样展示。
struct LoginView: View {
    @EnvironmentObject private var store: AppStore

    /// 登录方式：password = 账号密码，sms = 手机号验证码。
    @State private var loginMode: LoginMode = .password
    private enum LoginMode: String, CaseIterable {
        case password = "账号密码"
        case sms = "手机号验证码"
    }

    @State private var username = ""
    @State private var password = ""
    // 短信登录
    @State private var phone = ""
    @State private var smsCode = ""
    @State private var smsCountdown = 0
    @State private var smsSending = false
    @State private var errorText: String?
    @State private var isBusy = false
    @State private var showRegister = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppStyle.sectionSpacing) {
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
                    if loginMode == .password {
                        registerLink
                    }
                    serverLine
                }
                .padding(.horizontal, AppStyle.pagePadding)
                .padding(.top, 32)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
            .sheet(isPresented: $showRegister) {
                RegisterView()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(AppStyle.navy)
                    .frame(width: 84, height: 84)
                Text("班")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.white)
            }
            Text("排班空间")
                .font(.title)
                .bold()
            Text("603车间 · 8天一轮倒班")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    /// 两种登录方式切换（分段选择器）。
    private var modePicker: some View {
        Picker("登录方式", selection: $loginMode) {
            ForEach(LoginMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
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

    private var passwordForm: some View {
        VStack(spacing: 16) {
            TextField("手机号", text: $username)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            SecureField("密码", text: $password)
                .textFieldStyle(.roundedBorder)
        }
        .padding(AppStyle.cardPadding)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    /// 短信登录：手机号 + 获取验证码（60 秒倒计时）+ 6 位码。
    private var smsForm: some View {
        VStack(spacing: 16) {
            TextField("手机号（11 位大陆手机号）", text: $phone)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 12) {
                TextField("6 位验证码", text: $smsCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await sendSmsCode() }
                } label: {
                    Text(smsCountdown > 0 ? "\(smsCountdown) 秒后重发" : "获取验证码")
                        .font(.subheadline)
                        .frame(minWidth: 104)
                }
                .buttonStyle(.bordered)
                .disabled(smsSending || smsCountdown > 0 || !isValidPhone(phone))
            }
            Text("新手机号登录会自动建账号；已有账号先在设置页绑手机号，绑完就能用验证码登录。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(AppStyle.cardPadding)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

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
            .background(AppStyle.navy)
            .foregroundColor(.white)
            .cornerRadius(AppStyle.buttonRadius)
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

    private var serverLine: some View {
        Group {
            if let base = store.serverBaseURL {
                Text("服务器：\(store.serverKind.displayName) · \(base)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else if store.isStarting {
                Text("正在连接服务器…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("服务器连不上：请检查网络后重试")
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func doLogin() async {
        errorText = nil
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
