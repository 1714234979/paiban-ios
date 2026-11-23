import SwiftUI

/// 登录页：账号 + 密码，错误中文原样展示；“注册账号”跳注册页。
struct LoginView: View {
    @EnvironmentObject private var store: AppStore

    @State private var username = ""
    @State private var password = ""
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
                    registerLink
                    serverLine
                }
                .padding(.horizontal, 20)
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
                    .fill(Color(red: 0.11, green: 0.15, blue: 0.23))
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

    private var formCard: some View {
        VStack(spacing: 16) {
            TextField("账号", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            SecureField("密码", text: $password)
                .textFieldStyle(.roundedBorder)
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    private var loginButton: some View {
        Button {
            Task { await doLogin() }
        } label: {
            if isBusy {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            } else {
                Text("登录")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isBusy || username.isEmpty || password.isEmpty)
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
                Text("服务器连不上：请检查网络或打开 Tailscale 后重试")
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
            try await store.login(username: username.trimmingCharacters(in: .whitespaces),
                                  password: password)
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
