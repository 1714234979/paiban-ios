import SwiftUI

/// 开发者选项（1.3.2.013：仅管理员可见）：主设置页只留一行入口，点进来才是这三组。
/// 收纳：管理员后台、服务器线路、更新通道（正式/内测）。
/// 普通用户看不到这一行，也看不到渠道切换——主设置页的「检查更新」只剩版号 + 小红点。
struct DeveloperOptionsView: View {
    @Environment(AppStore.self) private var store: AppStore

    @State private var isCheckingUpdate = false
    /// 切渠道确认（1.2.7.002）：目标渠道 + 目标渠道最新版（先拉到再弹框）。
    @State private var pendingChannel: String?
    @State private var pendingChannelVersion: String?
    @State private var showChannelSwitchConfirm = false
    @State private var isFetchingChannelVersion = false
    /// 渠道胶囊滑动（1.3.2.012）：和班组胶囊一样，选中底色用 matchedGeometryEffect 在两个选项间滑动。
    @Namespace private var channelCapsuleNamespace
    /// 两渠道最新版号（1.3.2.012）：进这页时后台各拉一次，挂在选项下面；拉不到就不显示，不报错。
    @State private var channelVersions: [String: String] = [:]
    /// 减弱动态效果（1.3.2.012）：胶囊不滑动，直接跳。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        List {
            // 管理员后台：原生 push 进去（系统自带“‹ 设置”返回 + 隐藏底栏），
            // 不再用 fullScreenCover + 自定义“‹ 返回”按钮（Gemini 整改模块 1b/1c）。
            Section("管理员后台") {
                NavigationLink {
                    AdminBackendView()
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        // 深色模式下 Button 标题会走 AccentColor（深色亮蓝），
                        // 这里显式 primary，和其他菜单项配色一致（模块 4a）。
                        Text("切换管理员后台")
                            .foregroundColor(.primary)
                        Text("用最高权限打开管理端，可管账号、发 App 更新")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // 服务器线路（调试用）。
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

            // 更新通道：点另一个渠道先弹确认（当前版本、目标渠道最新版、切了会怎样），
            // 确认后切渠道并立刻按新渠道查一次；版本不一样就推出来（哪怕数字更低）。
            Section("更新通道") {
                HStack(spacing: 0) {
                    channelButton(title: "正式版", channel: "stable")
                    channelButton(title: "内测版", channel: "beta")
                }
                .background(AppStyle.surface1)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                // 1.3.2.012：胶囊滑动只绑在装的渠道这个状态上；减弱动态效果时不滑动。
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: UpdateChecker.installedChannel)
                Text("内测版只推给内测人员；切到内测后，下次打开 App 也按内测查。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("开发者选项")
        .navigationBarTitleDisplayMode(.inline)
        .alert("切换版本渠道", isPresented: $showChannelSwitchConfirm) {
            Button("取消", role: .cancel) {
                pendingChannel = nil
                pendingChannelVersion = nil
            }
            Button(pendingChannel == "beta" ? "切换到内测版" : "切换到正式版") {
                if let channel = pendingChannel {
                    // 1.2.7.003 修：Task 标 @MainActor，确认后改 @State 才会在主线程刷新。
                    Task { @MainActor in
                        isCheckingUpdate = true
                        defer { isCheckingUpdate = false }
                        await store.checkForUpdateAfterChannelSwitch(channel: channel)
                        pendingChannel = nil
                        pendingChannelVersion = nil
                    }
                }
            }
        } message: {
            Text(channelSwitchMessage)
        }
        .task {
            // 1.3.2.012：两渠道最新版号各拉一次，挂在切换选项下面；拉不到就不显示。
            async let stableInfo = store.fetchVersionForChannel("stable")
            async let betaInfo = store.fetchVersionForChannel("beta")
            var versions: [String: String] = [:]
            if let info = await stableInfo { versions["stable"] = info.latestVersion }
            if let info = await betaInfo { versions["beta"] = info.latestVersion }
            channelVersions = versions
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

    // MARK: 渠道切换

    /// 渠道按钮（1.2.7.002）：当前渠道高亮；点另一个渠道先弹确认。
    /// 1.2.7.003：拉取时被点的按钮转圈 + 变灰，让人知道已经点上了。
    /// 1.2.7.007：.plain 改 .borderless——List 行里并排两个 plain 按钮，
    /// 行手势把点击吞掉，两个都点不动；borderless 才各自接得到点击。
    /// 1.2.7.009：选中态和 guard 按装的版本定，不按存的更新偏好定。
    /// 存的偏好只在确认切换时才写，从不跟装的版本同步；一旦脱节，「正式版」
    /// 会被误标成已选中，点它 guard 直接 return，看着就是点不动——003/007
    /// 修的点按 mechanics 本来就没坏，真正拦住点击的是这个 guard。
    /// 装着内测版（四段号）时内测版是已选中、正式版一定点得动；装着正式版时反过来。
    /// 1.3.2.012（老爷 2026-11-28 亲口令：切换 UI 再优化 + 加切换动画）：
    /// 选中态改成和班组胶囊一样的深色滑动胶囊（matchedGeometryEffect，装的渠道
    /// 变了就滑过去）；每个选项下面挂该渠道最新版号（进设置页时后台拉一次），
    /// 点下去先给轻冲击触感，再弹确认框。选中态仍按装的版本定（009 的规矩不动，
    /// 胶囊不会指到没装的渠道上）；.borderless 也不能动（007 的教训，List 行里
    /// 别的 ButtonStyle 接不到点击）。
    private func channelButton(title: String, channel: String) -> some View {
        let installedChannel = UpdateChecker.installedChannel
        let selected = installedChannel == channel
        let fetching = isFetchingChannelVersion && !selected
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            guard channel != installedChannel, !isFetchingChannelVersion else { return }
            Task { await askChannelSwitch(to: channel) }
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    if fetching {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(title)
                        .font(.subheadline)
                        .bold(selected)
                }
                if let version = channelVersions[channel] {
                    Text(version)
                        .font(.caption2)
                        .foregroundColor(selected ? .white.opacity(0.75) : .secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                Group {
                    if selected {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppStyle.navyAdaptive)
                            .matchedGeometryEffect(id: "channelCapsule", in: channelCapsuleNamespace)
                    } else {
                        Color.clear
                    }
                }
            )
            .foregroundColor(selected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            // 两行按钮本身已有约 50pt 高，1.3.2.005 的 touchTarget 透明留白不用再加。
        }
        .buttonStyle(.borderless)
        .disabled(isFetchingChannelVersion)
        .opacity(fetching ? 0.7 : 1.0)
    }

    /// 点另一个渠道：先弹确认框（立刻有反应），目标渠道最新版后台拉到再填进去。
    /// @MainActor（1.2.7.003 修）：拉网回来后改 @State（pendingChannel、确认框）
    /// 必须在主线程。之前这个函数不是 @MainActor，Task 在后台线程续跑，
    /// @State 改了界面也不刷新，确认框永远弹不出来，看起来就是「点不动」。
    /// 1.2.7.007：确认框不等拉网——003 的做法是拉到版本号才弹，网慢时点下去
    /// 半天没反应，看着还是点不动。现在点下立刻弹，版本号到了再补进文案。
    @MainActor
    private func askChannelSwitch(to channel: String) async {
        pendingChannel = channel
        pendingChannelVersion = nil
        showChannelSwitchConfirm = true
        isFetchingChannelVersion = true
        defer { isFetchingChannelVersion = false }
        let info = await store.fetchVersionForChannel(channel)
        pendingChannelVersion = info?.latestVersion
    }

    /// 确认框文案：当前版本、目标渠道最新版、切了会怎样。
    /// 1.2.7.007：版本号还在拉时显示「正在获取…」，拉到再补，拉不到才写未知。
    private var channelSwitchMessage: String {
        let current = UpdateChecker.currentVersion
        let currentLabel = UpdateChecker.channelLabel(for: current)
        let target = pendingChannel ?? "stable"
        let targetLabel = target == "beta" ? "内测版" : "正式版"
        let targetVersion: String
        if let v = pendingChannelVersion {
            targetVersion = v
        } else if isFetchingChannelVersion {
            targetVersion = "正在获取…"
        } else {
            targetVersion = "未知（没连上服务器）"
        }
        return "当前版本：\(currentLabel) \(current)\n目标渠道最新版：\(targetLabel) \(targetVersion)\n\n切过去后，App 按\(targetLabel)查更新；\(targetLabel)有新版就推给你装，不装也可以继续用现在的版本。"
    }
}
