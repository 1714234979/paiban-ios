# 排班空间 PaiBan（iOS 原生版）

排班与工资的 iOS 应用：原生 SwiftUI。

## 功能

- 排班页：原生月历，按月看排班，点某天看详情、调班、请假；顶上可切 A/B/C/D 四个班看。
- 工资页：看当月工资奖金明细（默认上个月），也有全年视图。
- 今日页：今天的班、明天的班、睡眠窗口、本周 7 天。
- 设置页：账号、永久换班、工资设置、检查更新、退出登录。
- 用账号密码登录；没有账号可以在登录页注册。登录后第一次走引导：选班组、填基本工资、奖金系数、社保缴费基数。
- 离线时显示本地缓存，并显示「离线缓存」。

## 编译（GitHub Actions 云端编）

推到 GitHub 后，Actions 自动编出**未签名**的 `PaiBan.ipa`（Artifacts 里下载，保留 30 天）。也可以在 Actions 里点 Run workflow 手动编一次。

## 企业签安装（一年有效）

编出来的是未签名包，需要用自己的企业证书重签再装：

1. 准备企业证书（.p12）和对应的 mobileprovision 文件（企业账号里下）。
2. 用重签工具（如爱思助手、3uTools，或 Mac 上的 `codesign`）把 `PaiBan.ipa` 重签成企业签包。
3. 把重签后的包发到手机上安装，有效期一年，到期重新签一次即可。

工程里的 Bundle ID 是 `com.paiban.app`，重签时可按自己的企业账号改。

## 工程结构

```
PaiBan.xcodeproj/          Xcode 工程
PaiBan/
  PaiBanApp.swift          入口（@main，挂 AppStore）
  ContentView.swift        根视图：启动/登录/引导/主界面切换 + 更新提示 Alert + 离线页
  Config.swift             服务器地址配置
  APIClient.swift          URLSession 客户端
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
  SettingsView.swift       设置页：账号/换班/工资设置/检查更新/退出
  TeamChangeView.swift     永久换班（班组 + 生效日，多条历史）
  MainTabView.swift        底部切换栏（排班/工资/设置）
  Info.plist               显示名「排班空间」
  Assets.xcassets/         图标（「班」字 + B班 8 天循环色块）
.github/workflows/ios-build.yml   云端编译工作流
```

- 最低 iOS 16.0，Swift 5，纯 SwiftUI，无 WebView。
