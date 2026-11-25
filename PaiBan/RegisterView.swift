import SwiftUI

/// 注册页：昵称 + 手机号 + 手机验证码 + 密码 + 确认密码，校验提示中文；成功后直接登录并进引导。
/// 用户名就是手机号（11 位大陆手机号，1 开头）；昵称是显示名，可空，空着就用手机号当显示名；
/// 验证码发到注册的手机号，服务端核验通过才建账号（1.2.6）。
struct RegisterView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var nickname = ""
    @State private var username = ""
    @State private var smsCode = ""
    @State private var smsCountdown = 0
    @State private var smsSending = false
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorText: String?
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("注册账号")
                            .font(.title2)
                            .bold()
                        Text("注册后按引导填好班组和工资设置就能用")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 16)

                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("昵称", text: $nickname)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            Text("建议使用真实姓名，以便管理员管理")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        TextField("手机号（11 位大陆手机号）", text: $username)
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
                            .disabled(smsSending || smsCountdown > 0 || !PhoneUtil.isValid(username))
                        }
                        SecureField("密码（至少 6 位，不能含冒号）", text: $password)
                            .textFieldStyle(.roundedBorder)
                        SecureField("再输一次密码", text: $confirmPassword)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(AppStyle.cardPadding)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)

                    if let errorText {
                        Text(errorText)
                            .font(.subheadline)
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
                                Text("注册并登录").font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: AppStyle.buttonHeight)
                        .background(AppStyle.navyAdaptive)
                        .foregroundColor(.white)
                        .cornerRadius(AppStyle.buttonRadius)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)

                    Text("注册只建普通同事账号；你的排班、请假、工资只归你自己，不会动别人的数据。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, AppStyle.pagePadding)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func doRegister() async {
        let name = username.trimmingCharacters(in: .whitespaces)
        // 用户名就是手机号：11 位数字、1 开头（共用 PhoneUtil），不对不让提交。
        if !PhoneUtil.isValid(name) {
            errorText = "请输入 11 位大陆手机号（1 开头）"
            return
        }
        if smsCode.count != 6 {
            errorText = "请输入 6 位验证码"
            return
        }
        if password.count < 6 {
            errorText = "密码至少 6 位"
            return
        }
        if password.contains(":") {
            errorText = "密码不能含冒号（会影响登录）"
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
