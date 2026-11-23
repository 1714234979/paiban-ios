# 排班空间 PaiBan（iOS 原生版）

603车间排班与工资的 iOS 应用：原生 SwiftUI，数据走 NAS 上的排班空间 API（`~/workspace/paiban-api/`，CONTRACT.md v1）。

## 用法

- 打开 App，自动选路：Cloudflare Tunnel 公网地址（见下）→ Tailscale（`http://100.66.88.28:3003`）→ 家里局域网（`http://192.168.1.101:3003`），哪个通就用哪个。
- 用账号密码登录；没有账号可以在登录页注册（只建普通同事账号）。登录后第一次走引导：选班组、填基本工资、奖金系数、社保缴费基数。
- 排班页：原生月历，按月看排班，点某天看详情、调班、请假；顶上可切 A/B/C/D 四个班看。工资页：看当月工资奖金明细（默认上个月），也有全年视图。今日页：今天的班、明天的班、睡眠窗口、本周 7 天。设置页：账号、永久换班、工资设置、服务器线路、检查更新、退出登录。
- 离线时显示本地缓存（按用户 id 分文件存在 App 沙盒 Documents 下），并显示「离线缓存」。

## 服务器地址（Config.swift，唯一配置处）

- 隧道公网地址常量在 `PaiBan/Config.swift` 第 14 行：`tunnelBaseURL`，目前是 `nil`，注释写明 **FILL IN WHEN THE TUNNEL URL IS READY — do not guess**。等隧道地址下来再填，不要猜。
- 版本清单地址也在同一文件：第 32 行 `versionPath = "/api/v1/version"`，清单地址 = 当前 baseURL + `/api/v1/version`，跟 baseURL 走，不用另写域名。

## App 内更新提示

- canonical 接口：`GET /api/v1/version`（公开，不用认证），返回 `{ok, data: {latestVersion, releaseNotes, downloadUrl}}`。
- 约定：**downloadUrl 为空表示没有更新**——即使 latestVersion 高于当前版也不弹提示；只有最新版高于当前版 **且** downloadUrl 非空时才弹「发现新版本」。
- 点「更新」只在系统浏览器里打开 downloadUrl（网盘链接），用户在网盘里下载新 IPA 安装；App 内不直接下载安装包。
- 点「稍后」当天不再弹（当天日期存 UserDefaults）。设置页有「检查更新」，手动查一次；没新版显示「已是最新版本」。检查失败（没网、服务器不通）时静默，不弹错。
- downloadUrl 在服务端改：服务端版本文件 / 管理端接口里填新版 IPA 的网盘链接。**老爷还需要提供网盘链接**（新 IPA 传上网盘后的分享链接），填进服务端的 downloadUrl，App 才会提示更新。

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
  PaiBanApp.swift          入口（@main，挂 AppStore）
  ContentView.swift        根视图：启动/登录/引导/主界面切换 + 更新提示 Alert + 离线页
  Config.swift             服务器地址唯一配置处（隧道/Tailscale/局域网 + 版本清单地址）
  APIClient.swift          URLSession 客户端：登录/注册 + 全部 /api/v1/me/* + 版本清单
  Models.swift             Codable 模型 + 班次样式/颜色 + 本地 8 天一轮基础排班计算
  Store.swift              App 状态 + 按用户 id 分文件的本地缓存 + 离线逻辑
  UpdateChecker.swift      更新检查器：语义化版本比较 + 当天不再弹
  LoginView.swift          登录页
  RegisterView.swift       注册页
  OnboardingView.swift     新用户引导（班组/基本工资/奖金系数/缴费基数）
  CalendarView.swift       原生月历（所有班次 pill 同高 28pt）
  DayDetailView.swift      某天详情 sheet：调班/请假/取消
  PayView.swift            工资奖金明细（月度 + 全年）
  TodayView.swift          今日页：今天/明天/睡眠窗口/本周
  SettingsView.swift       设置页：账号/换班/工资设置/服务器/检查更新/退出
  TeamChangeView.swift     永久换班（班组 + 生效日，多条历史）
  MainTabView.swift        四个 Tab（排班/工资/今日/设置）
  Info.plist               显示名「排班空间」，允许访问内网 http 地址
  Assets.xcassets/         图标（「班」字 + B班 8 天循环色块）
.github/workflows/ios-build.yml   云端编译工作流
CONTRACT.md                API 合同（v1，2026-11-23）
```

- 最低 iOS 16.0，Swift 5，纯 SwiftUI，无 WebView。
- 工资数字一律以服务端 `GET /me/pay` 为准，客户端不重算公式；日历看自己班组走服务端 `/me/month`，看别的班组本地按 8 天一轮算基础排班即时显示。

## 注意

- NAS 关了 App 也打不开（除非公网隧道已通）。
- 隧道地址还没下来：`Config.swift` 第 14 行还是 `nil`，填好之前 App 只走 Tailscale 和局域网。
- 新版 IPA 的网盘链接还没填：服务端的 `downloadUrl` 为空时 App 不会弹更新提示（按约定）。
