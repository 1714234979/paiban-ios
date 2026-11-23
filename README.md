# 排班空间 PaiBan（iOS 套壳版）

603车间排班与工资的 iOS 应用：壳是 WKWebView，里面加载 NAS 上跑的手机端页面（`/app`），数据走 NAS 上的排班空间 API。

## 用法

- 打开 App，先试家里局域网（`http://192.168.1.101:3003`），不行再试 Tailscale（`http://100.66.88.28:3003`），两个都连不上会显示“连不上 NAS”，按提示检查 Wi-Fi 或 Tailscale。
- 用管理员给你的同事账号登录（账号和密码都由管理员在管理端定）。
- 排班页：按月看四班排班，点某天看详情；工资页：看 B班当月工资奖金；今日页：今天的班、明天、能不能吵老爷、未来 7 天。

## 编译（不用买 Mac，GitHub Actions 云端编）

推到 GitHub 私有仓库后，Actions 自动编出**未签名**的 `PaiBan.ipa`（Artifacts 里下载，保留 30 天）。也可以在 Actions 里点 Run workflow 手动编一次。

GitHub 免费额度：公开仓库无限，私有仓库每月 2000 分钟，macOS 按 10 倍计费，一次编译约 5 分钟 ≈ 50 分钟额度，一个月够跑几十次。

## 企业签安装（一年有效）

编出来的是未签名包，需要用自己的企业证书重签再装：

1. 准备企业证书（.p12）和对应的 mobileprovision 文件（企业账号里下）。
2. 用重签工具（如电脑上的爱思助手、3uTools，或 Mac 上的 `codesign`）把 `PaiBan.ipa` 重签成企业签包。
3. 把重签后的包发到手机上安装，有效期一年，到期重新签一次即可。

工程里的 Bundle ID 是 `com.paiban.app`，重签时可按自己的企业账号改。

## 工程结构

```
PaiBan.xcodeproj/          Xcode 工程
PaiBan/
  PaiBanApp.swift          入口
  ContentView.swift        主界面（WKWebView + 局域网/Tailscale 自动选路 + 断网提示）
  Info.plist               显示名「排班空间」，允许访问内网 http 地址
  Assets.xcassets/         图标（「班」字 + B班 8 天循环色块）
.github/workflows/ios-build.yml   云端编译工作流
```

- 最低 iOS 16.0，Swift 5，SwiftUI + WKWebView。
- 只在 NAS 内网能用（家里 Wi-Fi / Tailscale），外网打不开。

## 注意

- 手机端页面跑在 NAS 上（`http://192.168.1.101:3003/app`），NAS 关了 App 也打不开。
- 空间和 API 是两份数据：空间里改了排班，要在管理端（`/admin` → 排班配置 → 导入配置）把最新配置导进 API，App 里才会变。
