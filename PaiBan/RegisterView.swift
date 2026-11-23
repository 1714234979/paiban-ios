import SwiftUI

/// 注册页：账号 + 密码 + 确认密码，校验提示中文；成功后直接登录并进引导。
struct RegisterView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
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
                        TextField("账号（不能含空格或冒号，最多 32 字）", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        SecureField("密码（至少 6 位，不能含冒号）", text: $password)
                            .textFieldStyle(.roundedBorder)
                        SecureField("再输一次密码", text: $confirmPassword)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(20)
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
                        if isBusy {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        } else {
                            Text("注册并登录")
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isBusy)

                    Text("注册只建普通同事账号；你的排班、请假、工资只归你自己，不会动别人的数据。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
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
        if name.isEmpty {
            errorText = "账号名不能为空"
            return
        }
        if name.count > 32 {
            errorText = "账号名最多 32 个字符"
            return
        }
        if name.contains(" ") || name.contains(":") {
            errorText = "账号名不能含空格或冒号"
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
            try await store.register(username: name, password: password)
            dismiss()
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
