import SwiftUI

/// 登录页（1.2.6 重做，模仿考试宝、换成我们自己的藏青「班」图标）：
/// 两种方式都能进——账号密码登录 / 手机号验证码登录；没有一键登录（阿里云一键登录
/// 免费次数只有 100 次，不够用，1.2.6 不做、不留入口）。
/// 输入框是下划线样式（只有底部细线，不要方框直角），登录按钮是全圆角胶囊；
/// 两种方式在底部「其他登录方式」用圆形图标切换。验证码登录：输手机号 → 点获取
/// 验证码（60 秒倒计时）→ 输 6 位码 → 登录；新手机号会自动建账号（用户名是
/// 「手机+后 4 位」），昵称在设置页改。错误中文原样展示。
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
    @State private var showPassword = false
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
                VStack(spacing: 24) {
                    header
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
                    Spacer(minLength: 24)
                    otherMethods
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
            Text("8天一轮倒班")
                .font(.subheadline)
                .foregroundColor(.secondary)
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
    private func underlineField<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
                .padding(.vertical, 12)
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 1)
        }
    }

    private var passwordForm: some View {
        VStack(spacing: 8) {
            underlineField {
                TextField("请输入手机号", text: $username)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            underlineField {
                HStack(spacing: 8) {
                    Group {
                        if showPassword {
                            TextField("请输入密码", text: $password)
                        } else {
                            SecureField("请输入密码", text: $password)
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
            underlineField {
                TextField("请输入手机号", text: $phone)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            underlineField {
                HStack(spacing: 12) {
                    TextField("请输入验证码", text: $smsCode)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task { await sendSmsCode() }
                    } label: {
                        Text(smsCountdown > 0 ? "\(smsCountdown) 秒后重发" : "获取验证码")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .disabled(smsSending || smsCountdown > 0 || !isValidPhone(phone))
                }
            }
            Text("新手机号登录会自动建账号；已有账号先在设置页绑手机号，绑完就能用验证码登录。")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
    }

    /// 全圆角胶囊登录按钮（1.2.6）。
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

    /// 底部「其他登录方式」：圆形图标切换两种登录方式（1.2.6；只有密码和验证码两种）。
    private var otherMethods: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 1)
                Text("其他登录方式")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 1)
            }
            HStack(spacing: 56) {
                methodButton(mode: .password, icon: "lock.fill", label: "密码登录")
                methodButton(mode: .sms, icon: "message.fill", label: "验证码登录")
            }
        }
    }

    private func methodButton(mode: LoginMode, icon: String, label: String) -> some View {
        let isActive = loginMode == mode
        return Button {
            loginMode = mode
            errorText = nil
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isActive ? AppStyle.navy : Color(.systemBackground))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .stroke(isActive ? Color.clear : Color(.separator), lineWidth: 1)
                        )
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(isActive ? .white : .secondary)
                }
                Text(label)
                    .font(.caption)
                    .foregroundColor(isActive ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
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
