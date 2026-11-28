import SwiftUI

/// 注册页（1.3.2.017 向登录页看齐）：昵称 + 手机号 + 手机验证码 + 密码 + 确认密码，
/// 校验提示中文；成功后直接登录并进引导。用户名就是手机号（11 位大陆手机号，1 开头）；
/// 昵称是显示名，可空，空着就用手机号当显示名；验证码发到注册的手机号，
/// 服务端核验通过才建账号（1.2.6）。
/// 样式和登录页同一套：下划线输入框 + 藏青全圆角胶囊按钮 + 协议勾选行；
/// 大标题不再单独占一行（navigationTitle inline），副标题只剩一行说明。
struct RegisterView: View {
    @Environment(AppStore.self) private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var nickname = ""
    @State private var username = ""
    @State private var smsCode = ""
    @State private var smsCountdown = 0
    @State private var smsSending = false
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    /// 协议勾选（1.3.2.017）：默认未勾选；未勾选点注册拦住并提示。
    @State private var agreedToTerms = false
    @State private var errorText: String?
    @State private var isBusy = false
    @FocusState private var focusedField: RegField?
    /// 输入框聚焦态（统一规范 v2：聚焦变暗 + 阴影，不用亮色描边）。
    private enum RegField { case nickname, username, smsCode, password, confirmPassword }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("完成注册后，按引导配置班组与薪资即可使用")
                        .appFont(size: AppFont.bodySmall)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    VStack(spacing: 8) {
                        underlineField(focused: focusedField == .nickname) {
                            TextField("昵称", text: $nickname)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .nickname)
                        }
                        Text("用于班表展示，建议填写常用姓名")
                            .appFont(size: AppFont.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                        underlineField(focused: focusedField == .username) {
                            TextField("手机号（11 位大陆手机号）", text: $username)
                                .keyboardType(.numberPad)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .username)
                        }
                        underlineField(focused: focusedField == .smsCode) {
                            HStack(spacing: 12) {
                                TextField("6 位验证码", text: $smsCode)
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
                                .disabled(smsSending || smsCountdown > 0 || !PhoneUtil.isValid(username))
                            }
                        }
                        underlineField(focused: focusedField == .password) {
                            HStack(spacing: 8) {
                                Group {
                                    if showPassword {
                                        TextField(PasswordUtil.placeholder, text: $password)
                                            .focused($focusedField, equals: .password)
                                    } else {
                                        SecureField(PasswordUtil.placeholder, text: $password)
                                            .focused($focusedField, equals: .password)
                                    }
                                }
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                Button { showPassword.toggle() } label: {
                                    Image(systemName: showPassword ? "eye" : "eye.slash")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        underlineField(focused: focusedField == .confirmPassword) {
                            HStack(spacing: 8) {
                                Group {
                                    if showConfirmPassword {
                                        TextField("请再输一次密码", text: $confirmPassword)
                                            .focused($focusedField, equals: .confirmPassword)
                                    } else {
                                        SecureField("请再输一次密码", text: $confirmPassword)
                                            .focused($focusedField, equals: .confirmPassword)
                                    }
                                }
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                Button { showConfirmPassword.toggle() } label: {
                                    Image(systemName: showConfirmPassword ? "eye" : "eye.slash")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        // 1.3.2.017：密码规则提醒（小字、次要色）；冒号限制已去掉，不再提冒号。
                        Text(PasswordUtil.ruleHint)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                    }
                    if let errorText {
                        Text(errorText)
                            .appFont(size: AppFont.bodySmall)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Button {
                        Task { await doRegister() }
                    } label: {
                        Group {
                            if isBusy {
                                ProgressView().tint(.white)
                            } else {
                                Text("注册并登录").appFont(size: AppFont.headline, weight: 600)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: AppStyle.buttonHeight)
                        .background(canRegister ? AppStyle.navyAdaptive : Color(.systemGray3))
                        .foregroundColor(.white)
                        .cornerRadius(AppStyle.buttonHeight / 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy || !canRegister)
                    AgreementConsentRow(agreed: $agreedToTerms)
                    Text("你的排班、请假与工资数据仅本人可见，系统将严格保护个人隐私。")
                        .appFont(size: AppFont.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.top, 32)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("注册账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    /// 注册按钮能不能点：手机号合法 + 6 位码 + 密码合规 + 两次一致（昵称可空）。
    private var canRegister: Bool {
        PhoneUtil.isValid(username) && smsCode.count == 6
            && PasswordUtil.isValid(password) && password == confirmPassword
    }

    /// 下划线输入框：和登录页同一套（只有底部一条细线）。
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

    private func doRegister() async {
        let name = username.trimmingCharacters(in: .whitespaces)
        // 1.3.2.017：未勾选协议先拦住并提示（别静默失败）。
        guard agreedToTerms else {
            errorText = "请先阅读并同意《用户使用协议》和《隐私协议》"
            return
        }
        // 用户名就是手机号：11 位数字、1 开头（共用 PhoneUtil），不对不让提交。
        if !PhoneUtil.isValid(name) {
            errorText = "请输入 11 位大陆手机号（1 开头）"
            return
        }
        if smsCode.count != 6 {
            errorText = "请输入 6 位验证码"
            return
        }
        if !PasswordUtil.isValid(password) {
            errorText = PasswordUtil.ruleHint
            return
        }
        if password != confirmPassword {
            errorText = "两次输入的密码不一致"
            return
        }
        errorText = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let nick = nickname.trimmingCharacters(in: .whitespaces)
            try await store.register(username: name, password: password,
                                     displayName: nick.isEmpty ? nil : nick,
                                     code: smsCode.trimmingCharacters(in: .whitespaces))
            dismiss()
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
            try await store.api.sendSmsCode(phone: username.trimmingCharacters(in: .whitespaces))
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
}
