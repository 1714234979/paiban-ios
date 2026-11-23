# 排班空间 Native App — API 合同 (v1, 2026-11-23)

本文档是本次原生 App 重构的 API 合同。API 子代理按此实现 server.js/core.js；
iOS 子代理按此写 Swift 客户端；两者都以此为准，不要自行改接口形状。

## 现状（不要破坏）
- API 在 NAS `/vol2/1000/paiban-api/app/`，VM 副本 `~/workspace/paiban-api/`。
  server.js（818 行，Node 内置 http，无依赖），core.js（纯函数：排班+工资）。
- 数据在 data/ 下：config.json（四班 + 全局工资设置）、users.json、sessions.json。
- 认证：session cookie（7 天，`paiban_session`）、X-API-Key / Bearer、Basic。
- 注册 `POST /api/v1/auth/register`（公开）建普通同事账号 role=user、canWrite=true。
- 现有接口全部保留、行为不变：GET /health、/api/v1/config、/teams、/day、/month、
  /range、/teams/range、/quiet、/pay、/pay/year、/swaps、/leaves；写接口
  /api/v1/override、/swap、/leave、/leave/range、/swap/payback、/swap/to-leave、
  /pay/month、/pay/settings、/pay/effective、/pay/contribution-base、/pay/utilities、
  /pay/annual-leave-total；管理端 /api/v1/admin/*。
- core.js 里 `monthPay` / `computePay` / `countBaseWork` 目前写死 'B' 班，
  工资设置取全局 `config.pay.settings`，出勤/科室绩效取全局 `config.pay.months`。
  这些全局接口（/api/v1/pay 等）保持原样——它们是 Space（空间）同步的口径。
- 班次规则：8 天一轮。B [日,日,中,中,休,早,早,休] 基准 2026-11-02=日班；
  A [早,早,休,日,日,中,中,休]、C [日,中,中,休,早,早,休,日]、
  D [中,休,早,早,休,日,日,中]，基准都是 2026-11-01。
  白班=日班 08–16，夜班=早班 00–08，中班 16–24。
  班次值：日班 / 中班 / 早班 / 休息 / 早中班 / 日中班。
  连班禁令：中班接次日早班不行；早班+日班不行；一天不能上两个相同的班。
- 工资公式（与空间一致）：基本工资 2420；早班补贴 70/个，中班 30/个，日班 0；
  高温费仅 6–9 月每月 250 按出勤比例；工龄津贴 20×(当年年份−入职年份+1)，
  入职 2018 年 10 月；社保基数 5938（养老 8%、医疗 2%、失业 0.3%），公积金 403；
  奖金=(科室绩效+其他奖罚)×绩效系数×奖金系数+加班费（含三薪）；
  三薪规则：法定节假日上班只有超出基本天数的部分算三薪；
  个税累计预扣法，税从奖金里扣。

## 账号规矩（2026-11-23 老爷亲口定）
- **老爷本人的用户端账号是「张晓文」（username `张晓文`，role=user，B 班）。**
  他在 App 里用的就是这个号，不是普通同事。他的数据和排班空间同步：
  App 里登录张晓文，看到的就是他自己的那份数据（班次、工资设置和空间里一致）。
  服务端：以用户名 `张晓文` 为 owner 标识（server.js 里一个清楚标明的常量
  `OWNER_USERNAME = '张晓文'`），他的 /me/* 一律按全局 config 解析
  （班组、调班/请假、工资设置、出勤录入都走全局，和空间同步）。
  他的 paySettings 为空、teamHistory 为 B 时，/me/pay 必须等于全局 /api/v1/pay。
- **管理账号 `admin`（role=admin）只进管理端，不能登录 App。**
  App 专用登录接口 `POST /api/v1/auth/login`（见下），只允许普通用户账号
  （role=user）；role=admin 调它返回 403，错误信息固定为
  「管理账号不能登录 App，请使用用户账号登录」。
  管理端登录 `POST /api/v1/admin/login` 不受影响（admin 照常进管理端）。
  App 客户端也要做一道拦截：登录返回的 user.role 是 admin 时拒绝进 App，
  显示同一句提示（纵深防御）。
- App 登录一律走 `POST /api/v1/auth/login`，不要再用 `/api/v1/admin/login`
  （那个只给管理端用）。`POST /api/v1/auth/login` body `{username, password}`，
  成功返回 `{ok, user}` 并发 7 天 session cookie（与 admin/login 同形）；
  账号密码不对 401；账号停用 403；role=admin 403（上句提示）。

## 身份模型
- 管理员账号（role=admin）= 老爷本人 = 与空间同步的那份数据。
  他的排班/请假/工资写操作继续走全局 config（/api/v1/* 写接口和 /pay/*），
  空间读同一份 config，所以自动同步。
- 普通同事账号（role=user）= 每人一份独立数据，存在 NAS（users.json 的 profile），
  手机上也存一份本地副本。他们的写操作走下面的 /api/v1/me/*，不写全局 config。
- 因此：全局写接口（/api/v1/override、/swap、/leave、/leave/range、/swap/payback、
  /swap/to-leave、/pay/*）改为仅管理员可用；普通同事调这些接口返回 403，
  并提示改用 /api/v1/me/*。同时更新 app.html（手机端网页），让非管理员用户
  的调班/请假走 /me/*，不要把网页端弄坏。

## 用户 profile（存在 users.json 的用户对象上）
```json
{
  "team": "B",
  "teamHistory": [
    {"team": "B", "effectiveFrom": "2026-11-02"},
    {"team": "A", "effectiveFrom": "2026-12-01"}
  ],
  "paySettings": {
    "baseSalary": 2420, "bonusCoef": 1.0, "contributionBase": 5938,
    "position": "员工", "utilities": 60, "hireYear": 2018, "hireMonth": 10,
    "deptPerfDefault": 4000, "perfCoefDefault": 1
  },
  "onboardingDone": true,
  "overrides": [{"date": "2026-12-05", "shift": "日班", "note": "调班", "partner": "A", "partnerShift": "中班"}],
  "leaves": [{"date": "2026-12-10", "type": "年假", "note": ""}]
}
```
- `team`：当前班组。没有 teamHistory 时直接用它；默认 "B"。
- `teamHistory`：按 effectiveFrom 升序、effectiveFrom 唯一。某天的班组 =
  最后一个 effectiveFrom <= 该天的条目；如果没有 <= 该天的条目，用第一条的班组。
  允许多次改班（多条记录）。新增时 effectiveFrom 已存在则替换该条。
- `paySettings`：只存用户改过/填过的字段；缺失的字段回落到全局
  config.pay.settings。bonusCoef 是奖金系数；position 是岗位；hireYear/hireMonth
  用于工龄津贴；utilities 是水电费；deptPerfDefault / perfCoefDefault 是
  科室绩效默认值 / 绩效系数默认值。
- `overrides` / `leaves`：该用户自己的调班/请假记录（普通用户专用）。
  管理员（老爷）的不存在这里——他的在全局 config.teams 里。
- 新用户（刚注册、没走完引导）没有 profile 字段时：team 默认 "B"，
  paySettings 为空（全回落全局），onboardingDone=false。

## 新增接口（/api/v1/me/*，session 或 API-Key/Basic 认证，取当前登录用户）
- `GET /api/v1/me` → `{ok, data: {id, username, role, enabled, canWrite,
  passwordViewable, team, teamHistory, paySettings, onboardingDone}}`
  （publicUser 字段 + profile 字段；没有 profile 时给默认值。）
- `PUT /api/v1/me/profile` body `{team?, paySettings?, onboardingDone?}`。
  team 必须是 A/B/C/D；paySettings 是对象，只更新传来的字段（合并，不覆盖整包）。
  返回更新后的 profile。用于引导流程和设置页。
- `GET /api/v1/me/team-history` → `{ok, data: [ {team, effectiveFrom}, ... ]}`（升序）。
- `POST /api/v1/me/team-history` body `{team, effectiveFrom}`。
  校验 team 合法、effectiveFrom 是 YYYY-MM-DD；已存在同一天则替换；保持升序。
  返回完整 teamHistory。用于永久换班。
- `DELETE /api/v1/me/team-history?effectiveFrom=YYYY-MM-DD` → 删除一条换班记录，
  返回完整 teamHistory。至少保留一条时才能删（删到 0 条时报错）。
- `GET /api/v1/me/day?date=YYYY-MM-DD` → 该用户当天的班次（与 /api/v1/day 同形，
  多一个 `team` 字段表示当天实际班组）。班组按 teamHistory 取，调班/请假
  取用户自己的 overrides/leaves（普通用户）；管理员取全局 config（与 /api/v1/day?team=他的班组 一致）。
- `GET /api/v1/me/month?year=2026&month=11` → `{ok, data: {team, year, month,
  days: [同 /api/v1/month 的 day 对象，每天的 team 是当天实际班组], stats}}`。
  stats 与 /api/v1/month 的 stats 同形（totalDays、basicDays、actualWork、
  actualShifts、doubleDays、leaveDays、counts{day,early,mid} 等）。
- `GET /api/v1/me/range?start=YYYY-MM-DD&days=30` → 该用户连续若干天（同 /api/v1/range 同形）。
- `GET /api/v1/me/pay?year=2026&month=11` → 该用户某月工资奖金，
  与 /api/v1/pay 返回的 month 对象同形（含 incomeTax、bonusAfterTax、grandTotal、
  累计字段等）。计算口径：班次按 teamHistory；设置 = 全局 settings + 用户 paySettings；
  出勤/科室绩效按用户自己的班次算，**不用**全局 config.pay.months（那是老爷的录入数）；
  科室绩效默认取用户 paySettings.deptPerfDefault 或全局 deptPerfDefault；
  绩效系数默认取用户 paySettings.perfCoefDefault 或全局；年假按用户自己的 leaves
  （type 年假/年休假）+ 用户 paySettings.annualLeaveTotal（默认 5）算。
  管理员调这个接口时，结果应与全局 /api/v1/pay 一致（他的 paySettings 为空、
  teamHistory 为 B、且全局 months 录入数要参与——即管理员走老口径）。
  换言之：管理员的 /me/pay = 全局 computePay；普通用户的 /me/pay = 按本节口径算。
- `GET /api/v1/me/pay/year?year=2026` → 该用户全年 12 个月（同 /api/v1/pay/year 同形）。
- `GET /api/v1/me/swaps?year=2026&month=12` → 该用户自己的调班记录（overrides 列表，
  按月过滤可选）。管理员调这个接口返回全局他所在班组的 overrides（与 /api/v1/swaps 一致）。
- `GET /api/v1/me/leaves?year=2026&month=11` → 该用户自己的请假记录。
  管理员返回全局他所在班组的 leaves。
- `POST /api/v1/me/override` body `{date, shift, note?, partner?, partnerShift?}`。
  只改自己的 overrides；用 core.validateDayShift 按用户当天班组校验
  （含邻日禁令，按用户自己的排班算）；通过后保存并返回当天 day 对象。
  管理员调这个接口时走全局 upsertOverride（与 /api/v1/override 一致）。
- `DELETE /api/v1/me/override?date=YYYY-MM-DD` → 删自己的单日调班。
  管理员走全局 deleteOverride。
- `POST /api/v1/me/leave` body `{date, type?, note?}` → 自己单日请假。
  管理员走全局 upsertLeave。
- `POST /api/v1/me/leave/range` body `{start, end, type?, note?}` → 自己一段日期请假，
  只算有班的日子（休班跳过），最多 62 天。管理员走全局。
- `DELETE /api/v1/me/leave?date=YYYY-MM-DD` → 删自己单日请假。管理员走全局。
- `GET /api/v1/me/quiet?at=YYYY-MM-DDTHH:MM` → 该用户的睡眠窗口
  （按用户当天/次日班次算，规则同 core.getQuiet 但 team 按用户当天班组；
  管理员固定 B 班，与现有一致）。
- 所有 /me/* 写接口：普通用户要求 canWrite=true（注册默认 true）；
  管理员永远可写。错误用中文返回 `{ok:false, error:"..."}`。

## core.js 改动（保持向后兼容）
- 新增按"每天班组解析函数"算排班的版本：`getDayForUser(cfg, teamForDate, date)`、
  `monthStatsForUser(cfg, teamForDate, y, m)`、`monthDaysForUser(cfg, teamForDate, y, m)`，
  其中 teamForDate 是 `(dateStr) => team`。班组那天的 override/leave：
  普通用户只查用户自己的 overrides/leaves（由 server 层把用户记录拼成
  一个"虚拟 teamCfg"传进去，或给 core 加可选参数——实现方式自定，
  但不要改现有 getDay/monthStats 的签名和行为）。
- 新增 `monthPayForUser(cfg, y, m, teamForDate, settingsOverride, userMonthsOverride)`、
  `computePayForUser(cfg, y, m, teamForDate, settingsOverride)`：
  settings = 全局 settings + settingsOverride；出勤/绩效按用户自己的班次算；
  不读全局 pay.months（除非调用方是管理员，那时直接用老的 computePay）。
- 现有 `monthPay` / `computePay` / `countBaseWork` / `getDay` / `monthStats`
  保持原样，不要改签名。

## 客户端（iOS）需要的数据
- 登录：App 用 POST /api/v1/auth/login（只允许 role=user；admin 调它返回 403
  「管理账号不能登录 App，请使用用户账号登录」），成功发 7 天 session cookie；
  或用 Basic（账号密码存钥匙串）。管理端登录 POST /api/v1/admin/login 只给网页管理端用，
  App 不再调它。
- 启动流程：读本地缓存立刻显示 → 后台调 GET /api/v1/me + /me/month + /me/pay
  刷新 → 写回本地缓存。
- 本地缓存：App 沙盒 Documents 下一个 JSON 文件（按用户 id 分文件），
  存 profile + 最近一个月的 month/pay + swaps/leaves。离线时直接读缓存。
- 服务器地址：一个常量（见 iOS 任务），不要写死单个地址；按可达性依次试：
  Cloudflare Tunnel 公网地址（占位，等隧道 agent 给）→ Tailscale
  http://100.66.88.28:3003 → 局域网 http://192.168.1.101:3003。

## 验收（API 子代理）
- NAS 与 VM 两份 server.js/core.js 内容一致（diff 核对）。
- clean restart 后：/health 200；注册测试账号 → PUT /me/profile（设 A 班、
  基本工资 3000、奖金系数 1.2、基数 6000）→ POST /me/team-history 两条
  （2026-12-01 切 A、2027-03-01 切 C）→ GET /me/day 在 2026-11-23 应为 B 班、
  2026-12-05 应为 A 班、2027-03-05 应为 C 班 → GET /me/month 与 /me/pay
  正常返回且奖金系数/基数生效 → /me/override、/me/leave 写后读回一致 →
  管理员全局接口仍正常、Space 的全局数据未变 → 测试账号删干净。
- 更新接口文档（~/workspace/your_files/排班空间-API-接口文档.md 与 NAS app/README.md）
  与 GET /api/v1/docs。
