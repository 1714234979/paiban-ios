import SwiftUI

/// 主界面：三个 Tab（排班 / 工资 / 设置），各带自己的 NavigationStack。
/// 今日 Tab 已删；工资页标题叫「预估工资」。
///
/// 1.3.0.001（第 46 条）：底部切换栏改成自定义玻璃栏——原生 Tab 栏藏掉，
/// 底下放一条毛玻璃栏（ultraThinMaterial，透出底下内容）；点栏上的按钮切换，
/// 在栏上左右滑动也能切换（来回都行），滑动时震一下（和钉钉一样）。
/// 滑动只认栏上这一块，不动内容区，所以不跟排班页切月那套左右滑页打架。
///
/// 1.3.0.002（第 46 条修订，老爷 2026-11-26 亲口纠）：毛玻璃不是他要的玻璃，
/// 改成悬浮胶囊 + 系统 Liquid Glass——栏不贴底、不满宽、没有顶部分隔线，
/// 圆角胶囊浮在内容上面，离底边和左右都留一截空隙（像钉钉那个）。
/// 玻璃用 iOS 26+ 的 .glassEffect()（系统最新的 Liquid Glass，透明度跟系统走，
/// iOS 27 上就是它）；部署目标 iOS 16，26 以下 fallback 回 ultraThinMaterial。
///
/// 1.3.0.003（第 46 条再修，老爷 2026-11-26 亲口纠）：002 的旧底栏没藏住，
/// 底下还露着原来那条（.toolbar(.hidden, for: .tabBar) 在 iOS 27 上不生效），
/// 点旧栏会震、点胶囊不震，滑动也没震动。改法：不用 TabView 了，改手动切 Tab，
/// 三个 NavigationStack 都活着（各页导航状态不丢），只显示选中的那一个，
/// 底下只留悬浮胶囊这一条栏。震动改共享一个震动器，点按和滑动都要震。
/// 胶囊尺寸：左右留边再收窄（栏做长一点）、底部空隙再加大（往上靠一点点）。
///
/// 1.3.0.004（第 46 条再修，老爷 2026-11-26 发音乐 App 视频亲口纠）：
/// 003 的胶囊还是太宽、太高，看着像回到了以前那条。照视频（Apple Music 的
/// 悬浮胶囊底栏）改：底栏位置跟视频里一样，浮在底边上面那个高度——胶囊底离
/// 屏幕底边约 23pt（003 是 50pt，往下挪约 27pt）；三个标签，胶囊按三个标签
/// 的宽度做，适当做短一点（限宽 300pt 居中），不照视频四个标签的宽度做。
/// 震动不要了，点按和滑动都不震（003 的共享震动器整段删掉）。
///
/// 1.3.0.005（第 46 条再修，老爷 2026-11-26 发文件 App 视频 + 工资页截图亲口纠，
/// 「还不对，按照视频里的那个弄，别糊弄我了」）：004 还是不对——工资页奖金那几行
/// 透过玻璃胶囊露出来、重在一起；屏幕最底边（胶囊下面到屏幕底边那块）也被划了红线。
/// 根子是胶囊是半透明 Liquid Glass，内容滚到下面会透出来。照视频（iOS 文件 App 的
/// 悬浮胶囊底栏：最近项目/共享/浏览）重做：胶囊改成**不透明**实色（systemBackground，
/// 深浅色系统自己适配），内容滚到下面直接被挡住、不会透出来；选中那个有浅色圆角底块
/// （systemGray5 圆角矩形，matchedGeometryEffect 平滑滑动）+ 蓝色图标文字，未选中
/// 是 secondary。位置、宽度、滑动切页都不变（底离屏幕底边约 23pt，限宽 300pt 居中，
/// 栏上左右滑切换，不震动）。底部留白 100 → 120pt，三页滑到底最底下的内容离胶囊更远。
/// 底边那块再修：overlay 悬浮时滚起来内容还是会进到胶囊下面那条（屏幕最底边被截断），
/// 改成 VStack 底部固定——三页内容区在胶囊上面结束，内容永远滑不到胶囊下面，
/// 胶囊下面到屏幕底边那块只剩干净的页面底色；胶囊样子不变，还是悬浮胶囊。
/// 同版再修底栏盖内容：safeAreaInset 在 NavigationStack 里传不进去，三页
/// 滑到底最底下的内容都被胶囊盖住（排班统计卡、设置「关于」）。改成 overlay
/// 纯悬浮 + 各页自己留 100pt 底部留白，胶囊顶离内容底边约 41pt，够露出来。
///
/// 1.3.0.006（第 46 条再修，老爷 2026-11-26 在真机上试了 005 亲口纠：
/// 「ui 还是有问题，而且不能滑动，不是透明玻璃效果」；同版又加刷新率适配，第 34 条）：
/// ① 不能滑动：005 里底栏上左右滑切页在真机上滑不动。根子是手势挂法：DragGesture
/// 用普通 .gesture() 挂在装了三个 Button 的 HStack 上，Button 的点按手势会先抢
/// 住触摸、父级的拖动手势拿不到事件（SwiftUI 里子视图手势优先于父级普通手势）。
/// 改法：改成 .highPriorityGesture()，让拖动手势优先于 Button 的点按——点按
/// （没位移）时拖动认不出来、Button 照样能点；左右滑（位移超 12pt）时拖动先认
/// 出来、切页。手势阈值不变（横滑 >40pt 且大于纵向）。
/// ② 不是透明玻璃：005 的不透明实色胶囊他不要，要透明玻璃效果（像音乐 / 文件 App
/// 视频里那种 Liquid Glass，磨砂、半透明、透出底下内容的模糊影子）。但 004 被否
/// 是因为玻璃太透、工资页的字透过胶囊清清楚楚能读出来。所以这次玻璃要透、但透出
/// 来的是糊的、字读不出来：胶囊底先铺一层 .regularMaterial（中度磨砂，把底下
/// 内容糊成色块、字认不出来；.thickMaterial 太实、看着像 005 的不透明实色），
/// 上面再罩 iOS 26+ 的 .glassEffect(.regular)（Liquid Glass 的折射和亮边，
/// （.glassEffect 是 26+ API，#available 包着）。其余不动：选中底块+蓝色、未选中
/// 灰色、底离屏幕底边约 23pt、限宽 300pt 居中、不震动。底栏改回 overlay 悬浮：
/// 画廊里两种磨砂看着没区别——VStack 底部固定时内容到不了胶囊下面、底下只有一色
/// 底色，玻璃糊一色底色就跟不透明实色一个样；overlay 时内容竖滚会从胶囊底下经过，
/// 玻璃才看得见。底边干净靠三页各自的 120pt 底部留白（滑到底时内容完整露在
/// 胶囊上面、不到屏幕最底边）。
/// ③ 刷新率适配（第 34 条，老爷说刷新率太低、要 140Hz）：先说硬件事实——iPhone
/// ProMotion 自适应刷新封顶就是 120Hz（他那台 iPhone 17 Pro Max 也是），140Hz
/// 在 iOS 硬件上做不到。根因：代码里没有任何帧率设置（没 CADisplayLink、没
/// preferredFrameRateRange、没 Timer），SwiftUI 默认跟 ProMotion 走，但没有显式
/// 声明帧率范围，系统在部分场景下只给 60Hz。改法：App 启动时建一个 CADisplayLink，
/// preferredFrameRateRange 设成 10–120Hz（preferred 120），显式告诉系统这 App
/// 要用满自适应刷新；静止时系统自己会降频省电（minimum 10Hz），不用管。
/// （实现在 PaiBanApp.swift 的 RefreshRateBoost，空转、只声明范围、不干活。）
///
/// 1.3.0.007（第 46 条再修，老爷 2026-11-26 亲口定：底栏按「最开始做的那个」
/// 1.3.0.001 那版来）：002–006 的悬浮胶囊来回改了五版他都不满意，006 那版他
/// 17:31 发真机截图又纠了一次（「底层是对的，上层是错的」——胶囊底的磨砂+玻璃
/// 是对的，上面选中的那个浅色圆角底块是实色、把玻璃盖死了）；现在他直接定了：
/// 回到 001 那版——**满宽毛玻璃栏，不要悬浮胶囊、不要选中底块**。做法：底栏按
/// 001 的 GlassTabBar 原样重做（满宽一条，贴着屏幕底边，底是 .ultraThinMaterial
/// 最薄那档毛玻璃、透出底下内容，顶上一条细 Divider；三个按钮就是图标 21pt +
/// 文字 10pt，选中 AccentColor 蓝色、没选中 secondary，干净、没有选中底块）。
/// 挂法还是 001 那套：safeAreaInset(edge: .bottom) 挂在底边，内容在栏上面结束。
/// 手动切 Tab 不变（不用 TabView——原生 Tab 栏在 iOS 27 上藏不掉，003 已证实），
/// 三个 NavigationStack 都活着、只显示选中的那一个，深链与 payAccess 回跳保留。
/// 滑动手势用 006 的 .highPriorityGesture()（001 的普通 .gesture() 会被 Button
/// 点按抢走、真机上滑不动，005 已证实）；不震动（老爷亲口定，001 的震动不要加回来）。
/// 三页的 120pt 底部留白（004–006 为悬浮胶囊留的）改回 24pt——safeAreaInset 的栏
/// 本来就占位，内容在栏上面结束，不用再留 120pt；设置页 List 那 120pt safeAreaInset
/// 直接删掉。刷新率适配（006 的 RefreshRateBoost）和更新弹窗修（007 的
/// installedChannel）都在 007 里，一个包发。
///
/// 1.3.0.008（第 46 条再修，老爷 2026-11-26 18:14 发 007 实机截图亲口纠：
/// 「又回到之前了」，让直接重新编写、写成液态玻璃的）：007 那个 001 版他不认——
/// 看着像玻璃之前的老样子，不是他要的液态玻璃；001 的 ultraThinMaterial 太素了，
/// 没有液态玻璃那个味儿。这次直接按他要的写，不再绕回 001：**液态玻璃 + 全宽底栏**。
/// 做法：底栏还是满宽一条、贴着屏幕底边、顶上一条细 Divider，没有胶囊、没有选中
/// 小药丸；底先铺一层 .regularMaterial（中度磨砂，006 证实过：底下内容糊成色块、
/// 字读不出来，透亮但不透字），上面罩 iOS 26+ 的 .glassEffect(.regular, in: Rectangle())
/// （Liquid Glass 的折射和亮边，满宽矩形、不是胶囊——006 的 capsuleGlass 原样换形状）。
/// 三个按钮还是图标 21pt + 文字 10pt，选中 AccentColor 蓝色、没选中 secondary，
/// 只变颜色、没有选中底块、不盖玻璃。挂法还是 safeAreaInset(edge: .bottom)，
/// 滑动还是 006 的 .highPriorityGesture()，不震动，三页 24pt 底部留白不变。
/// 更新弹窗修（007 的 installedChannel）和刷新率适配（006 的 RefreshRateBoost）都在，
/// 008 只改底栏这一项。
///
/// 1.3.0.009（第 46 条再修，老爷 2026-11-26 18:25 亲口纠：「我要胶囊的那种啊
/// 然后加液态玻璃」）：008 理解错了——他要的是**悬浮胶囊**（不是满宽栏），上面
/// 加液态玻璃。006 那个胶囊的底层（磨砂+玻璃）他是认的（17:33 他亲口说「底层是
/// 对的」），错的是上层那个选中小药丸（浅色圆角底块、把玻璃盖死了）。这次按 006
/// 的胶囊、去掉选中小药丸：悬浮胶囊（底离屏幕底边约 23pt、限宽 300pt 居中、内容
/// 从胶囊下面滑过去的 overlay 布局），胶囊用 .regularMaterial 打底 + iOS 26+
/// .glassEffect(.regular, in: Capsule())（006 那个 capsuleGlass 原样）；选中态
/// 绝对不要选中小药丸、不要选中底块——选中就是蓝色、没选中就是灰色，只变颜色，
/// 什么都不盖在玻璃上。滑动还是 006 的 .highPriorityGesture()，不震动；三页
/// 底部留白回到 006 的 120pt（悬浮胶囊是 overlay，内容滑到底要离胶囊够远）。
/// 更新弹窗修（007 的 installedChannel）和刷新率适配（006 的 RefreshRateBoost）都在，
/// 009 只改底栏这一项。
///
/// 1.3.0.010（第 46 条再修，老爷 2026-11-26 18:34 发 009 实机截图亲口说：
/// 「没有液态玻璃，我真的要生气了」——截图上胶囊是**实心白色**，一点玻璃感都没有）：
/// 先找根因再动手。根因：009 胶囊同时挂了 .background(.regularMaterial) 和
/// .glassEffect()——磨砂底太实、把玻璃折射全盖死了，胶囊成了实心白药丸。006 他说
/// 「底层是对的」只是胶囊形状/位置对，玻璃折射从来就没透出来过（006 和 009 是同一套
/// 结构，磨砂底一直在）。修法：磨砂底整个拿掉，背景 clear，**只留
/// .glassEffect(.regular, in: Capsule())**，让玻璃直接去折射后面的内容；26 以下
/// fallback 用 .ultraThinMaterial（只在老系统上，26+ 不走这条）。其余不动：
/// 悬浮胶囊（底离屏幕底边约 23pt、限宽 300pt 居中、overlay 布局）、选中只变颜色
/// （蓝色/灰色、没有小药丸）、滑动还是 006 的 .highPriorityGesture()、不震动、
/// 三页 120pt 底部留白、更新弹窗修和刷新率适配都在，010 只改底栏玻璃这一项。
/// 发版前必须验明白：对着彩色内容（排班页日历）看，胶囊里必须能看到底下内容糊掉的
/// 影子和折射亮边，实心白就是没修好、不能发。
///
/// 1.3.0.011（第 46 条再修，老爷 2026-11-26 18:51 发 010 实机截图亲口说：
/// 「还是不行」——胶囊还是实心白，一点玻璃感都没有）：010 的修法修错了地方。
/// 这次先把根因彻底查明白（代码层面核过）：
/// ① #available(iOS 26.0, *) 分支是对的——运行时系统版本判断，老爷 iOS 27 一定走
/// glassEffect 那条，.ultraThinMaterial fallback 在他手机上物理上不可能被走，
/// fallback 不是原因；② 没有不透明祖先挡折射——MainTabView 里唯一的 .background
/// 是最外层 ZStack 背后的 Color(.systemGroupedBackground)（最底层），胶囊和页面
/// 内容之间没有任何实色层，玻璃采样的是页面本身；③ 真正的白，是 .glassEffect
/// (.regular) 自带的磨砂色调——.regular 是标准 frosted 玻璃、带白霜，采样又是
/// 设置页那种均匀浅灰底（#F2F2F7），霜 + 浅底 = 看起来就是实心白，折射无物可折。
/// 证据：010 拿掉了唯一的实色磨砂底，外观和 009 一模一样——如果磨砂底是元凶，
/// 010 早该变样了。④ 次要风险：.shadow() 挂在 .glassEffect() 之后——阴影把玻璃
/// 包进一次额外的合成，玻璃靠实时采样背后内容成像，多一次压平可能把效果闷掉；
/// 苹果自己的玻璃栏不另加阴影，玻璃自带亮边和纵深。
/// 修法：.glassEffect(.clear, in: Capsule())——.clear 是无色调、最透的那档玻璃，
/// 折射和亮边在浅底上也看得见（.regular 的霜就是那层白）；.shadow() 整段拿掉，
/// 让玻璃自己供纵深；再加一条日志标记（AppLogger，记 iOS 版本 + 走的玻璃路径，
/// 随反馈 24 小时日志可验——证明 glassEffect 路径在他真机上确实跑了）。
/// 其余不动：悬浮胶囊（底离屏幕底边约 23pt、限宽 300pt 居中、overlay 布局）、
/// 选中只变颜色（蓝色/灰色、没有小药丸）、滑动还是 006 的 .highPriorityGesture()、
/// 不震动、三页 120pt 底部留白、更新弹窗修和刷新率适配都在，011 只改底栏玻璃这一项。
/// 为什么这次一定能显出来（代码层面站得住）：.clear 和 .regular 的差别是 API
/// 文档定的——.clear 无色调、最透，.regular 带霜；同一块浅底上 .regular 显白、
/// .clear 显透 + 折射亮边；阴影那次额外合成也没了；分支正确、中间无实色遮挡都
/// 已核过。剩下唯一的变量是底色本身均匀浅灰——.clear 玻璃靠亮边和边缘折射也能
/// 在均匀底上显出液态感（文件 App 的胶囊就是这么做的）。
///
/// 1.3.0.012（第 46 条再修，老爷 2026-11-26 19:06 发视频 + 截图亲口说：
/// 「仔细看视频，还有，不弹窗，现在还是不行再改」——两件都得修）：
/// ① 不弹窗（重点）：老爷现在是 010，011 早发了，打开 App 更新弹窗一次都没弹过，
/// 只能自己去文件 App 里翻 IPA 手动装（011 的包 19:04 已下到文件 App 里）。
/// 根因（代码 + 线上实测核过）：007 的 installedChannel 只修了「问哪条线」，
/// 没修认证依赖——服务端只在「登录后带认证 + 是内测人员」时才把 latestVersion
/// 换成内测版号；版本请求一旦没带上有效 session（启动时序、切线路、7 天 session
/// 过期、短信登录没 Keychain 密码兜底），服务端照旧回正式版 1.3.0，比装的
/// 1.3.0.010 旧，isNewer 直接 false，弹窗永远不弹。线上实测：不带认证调
/// /api/v1/version?platform=ios&channel=beta 回的是 latestVersion 1.3.0、
/// channel stable，但 beta.ios.version 1.3.0.011 就在回包里公开躺着——App
/// 的 VersionInfo 从来没解 beta 这个字段。修法：内测用户直接读公开的 beta.ios
/// 版号/链接比（UpdateChecker.offeredVersion），弹窗不再依赖认证；正式用户
/// 照旧比 latestVersion。另修一个次生毛病：Store 原来拿检查结果直接覆盖
/// pendingUpdate，查失败返回 nil 就把排队等着弹的提示清了——切回前台时一次
/// 瞬断就把弹窗吞了；现在只在「确实没新版」时清，查失败保留已有的提示。
/// 触发点不变（冷启动 startup 里查 + 切回前台 scenePhase .active 再查），
/// 不加节流（「稍后」当天不弹是用户自己点的，照旧）。
/// ② 液态玻璃还是不行：视频里文件 App 底下那个悬浮胶囊（最近项目/共享/浏览）
/// 就是真正的液态玻璃胶囊——半透明、浮着、能透出后面的文件图标和文字。我们的
/// 胶囊还是实心白。011 的裸 .clear 玻璃 + 去阴影还是不显，原因看视频就明白了：
/// 真玻璃胶囊不只有一层透明玻璃，它有三样东西——淡淡的白调（跟底色拉开一点）、
/// 柔和的投影（浮起来的纵深）、发亮的细边（玻璃的边）。011 只罩了一层裸 .clear，
/// 均匀浅灰底上近乎隐形，用户看到的就是一片白。所以这次三样都补上：
/// .clear 玻璃加一点白 tint（.white.opacity(0.22)，跟底色拉开、底下内容照样
/// 透出来糊掉折射）、柔和阴影加回来（文件 App 的胶囊明明有投影，011 拿掉阴影
/// 是猜错了；只加柔和的一档，opacity 0.10 / radius 10）、再描一条发亮的细边
/// （白 0.6 / 0.5pt）。滚动时玻璃照样折射底下经过的内容。011 埋的日志标记还在，
/// onAppear 那条确认会写（胶囊常驻、主界面出现就记一次，AppLogger 追加写盘）。
/// 其余不动：悬浮胶囊（底离屏幕底边约 23pt、限宽 300pt 居中、overlay 布局）、
/// 选中只变颜色（蓝色/灰色、没有小药丸）、滑动还是 006 的 .highPriorityGesture()、
/// 不震动、三页 120pt 底部留白、刷新率适配都在，012 只改弹窗 + 底栏玻璃这两项。
struct MainTabView: View {
    @EnvironmentObject private var store: AppStore

    /// 能切到的 Tab：工资 Tab 只有有工资权限的人才有（1.2.7.001，第 23 条），
    /// 没权限的人只有排班 / 设置两个 Tab。tag 和原来一样：排班 0、工资 1、设置 2。
    private var availableTabs: [Int] {
        store.payAccess ? [0, 1, 2] : [0, 2]
    }

    private var tabItems: [(tag: Int, title: String, icon: String)] {
        [
            (0, "排班", "calendar"),
            (1, "工资", "yensign.circle"),
            (2, "设置", "gearshape"),
        ].filter { availableTabs.contains($0.tag) }
    }

    /// 每页的 NavigationStack。手动切 Tab 时三页都留在层级里（导航状态不丢），
    /// 只显示选中的那一页。
    @ViewBuilder
    private func tabPage(tag: Int) -> some View {
        switch tag {
        case 0:
            NavigationStack {
                CalendarView()
                    .navigationTitle("排班")
                    .navigationBarTitleDisplayMode(.inline)
            }
        case 1:
            // 工资 Tab：只有有工资权限的人才显示（1.2.7.001，第 23 条）。
            // 没权限的人只有排班 / 设置两个 Tab；年休假跟着工资走，也一并隐藏。
            NavigationStack {
                PayView()
                    .navigationTitle("预估工资")
                    .navigationBarTitleDisplayMode(.inline)
            }
        default:
            NavigationStack {
                SettingsView()
            }
        }
    }

    var body: some View {
        // 不用 TabView：原生 Tab 栏在 iOS 27 上藏不掉，底下会多露一条旧底栏，
        // 还会抢点按和震动。手动切 Tab：三页都活着，只显示选中的那一页。
        // 1.3.0.009：底栏改回悬浮胶囊（006 那版，去掉选中小药丸）——overlay 悬浮：
        // 玻璃要看得见，底下必须有内容滑过去；VStack 底部固定时内容永远到不了胶囊
        // 下面，胶囊底下只有一色的页面底色，磨砂+玻璃糊一色底色就跟不透明实色一个样。
        // overlay 时内容竖滚会从胶囊底下经过，玻璃把字糊成色块、看不清字，同时
        // 看上去是玻璃。底边干净靠三页各自的 120pt 底部留白（滑到底时最后的内容
        // 完整露在胶囊上面、不到屏幕最底边）。
        ZStack(alignment: .bottom) {
            ZStack {
                tabPage(tag: 0)
                    .opacity(store.selectedTab == 0 ? 1 : 0)
                    .allowsHitTesting(store.selectedTab == 0)
                if store.payAccess {
                    tabPage(tag: 1)
                        .opacity(store.selectedTab == 1 ? 1 : 0)
                        .allowsHitTesting(store.selectedTab == 1)
                }
                tabPage(tag: 2)
                    .opacity(store.selectedTab == 2 ? 1 : 0)
                    .allowsHitTesting(store.selectedTab == 2)
            }
            GlassCapsuleTabBar(
                items: tabItems,
                selectedTab: $store.selectedTab,
                onSwipeLeft: { switchTab(step: 1) },
                onSwipeRight: { switchTab(step: -1) }
            )
            .frame(maxWidth: 300)
            .padding(.bottom, 23)
        }
        .background(Color(.systemGroupedBackground))
        // 没登录时点小组件进来的深链：登录后进主界面再跳（store.handleDeepLink 先记下来）。
        .task {
            if let tab = store.pendingDeepLinkTab {
                store.pendingDeepLinkTab = nil
                store.selectedTab = tab
            }
        }
        // 工资权限没了（管理员关了）而当前正停在工资 Tab：切回排班。
        .onChange(of: store.payAccess) { newValue in
            if !newValue && store.selectedTab == 1 {
                store.selectedTab = 0
            }
        }
    }

    /// 滑动切 Tab：左滑 → 下一个，右滑 → 上一个；到头绕回另一边（来回都能滑）。
    private func switchTab(step: Int) {
        let tabs = availableTabs
        guard tabs.count > 1,
              let index = tabs.firstIndex(of: store.selectedTab) else { return }
        let next = tabs[(index + step + tabs.count) % tabs.count]
        guard next != store.selectedTab else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            store.selectedTab = next
        }
    }
}

/// 悬浮胶囊切换栏（1.3.0.012，按 006 的胶囊、去掉选中小药丸，第 46 条，老爷
/// 2026-11-26 18:25 亲口定：「我要胶囊的那种啊然后加液态玻璃」；011 根因修：
/// 010 的白不是磨砂底害的——.glassEffect(.regular) 自带白霜色调，采样均匀浅灰底
/// 就显实心白；这次改 .glassEffect(.clear, in: Capsule())（无色调、最透），
/// .shadow() 整段拿掉（阴影的额外合成可能闷掉玻璃的实时采样，玻璃自带亮边纵深）；
/// onAppear 记一条日志标记：iOS 版本 + 走的玻璃路径，随反馈日志可验；012 再修：
/// 011 的裸 .clear 还是不显——视频对照文件 App 的胶囊看明白了，真玻璃胶囊有三样
/// 东西（淡淡白调、柔和投影、发亮细边），裸 .clear 在均匀浅灰底上近乎隐形；这次
/// .clear 加一点白 tint、柔和阴影加回来、再描一条发亮细边）：
/// 透明玻璃胶囊：iOS 26+ 只罩 .glassEffect(.clear, in: Capsule())（Liquid Glass
/// 最透那档）；26 以下 fallback 用 .ultraThinMaterial 磨砂底。浮在内容
/// 上面；不贴底、不满宽、没有顶部分隔线。选中态绝对不要选中小药丸、不要选中底块——
/// 选中就是蓝色、没选中就是灰色，只变颜色，什么都不盖在玻璃上（006 错的就是上层
/// 那个浅色圆角底块、把玻璃盖死了，老爷 17:33 亲口说「底层是对的，上层是错的」）。
/// 点按钮切换；在栏上左右滑动也能切换（来回都行）。滑动手势用 .highPriorityGesture()
/// （005 的普通 .gesture() 会被 Button 的点按手势抢走、真机上滑不动）。
/// 不震动（老爷亲口定：震动不要），点按和滑动都只切页、不震。
private struct GlassCapsuleTabBar: View {
    let items: [(tag: Int, title: String, icon: String)]
    @Binding var selectedTab: Int
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tag) { item in
                Button {
                    guard item.tag != selectedTab else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = item.tag
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 21))
                        Text(item.title)
                            .font(.system(size: 10))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    // 1.3.0.009：没有选中底块——选中就是蓝色、没选中就是灰色，只变颜色，
                    // 什么都不盖在玻璃上。006 那个浅色圆角底块（跟着选中的那个走）整段删掉。
                    .foregroundColor(item.tag == selectedTab ? .blue : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        // 1.3.0.012：液态玻璃三修——011 的裸 .clear 玻璃还是不显。视频对照（文件 App
        // 的胶囊）看明白了：真玻璃胶囊不只有一层透明玻璃，它有三样东西——淡淡的白调
        // （跟底色拉开一点）、柔和的投影（浮起来的纵深）、发亮的细边（玻璃的边）。
        // 011 只罩了一层裸 .clear，均匀浅灰底上近乎隐形，用户看到的就是一片白。
        // 这次三样都补上：capsuleGlass() 里 .clear 玻璃加一点白 tint、柔和阴影加回来
        // （文件 App 的胶囊明明有投影，011 拿掉阴影是猜错了）、再描一条发亮的细边。
        // 滚动时玻璃照样折射底下经过的内容。
        .capsuleGlass()
        .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
        .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
        // 1.3.0.011：日志标记——证明 glassEffect 路径在他真机上确实跑了。
        // 记 iOS 版本 + 走的玻璃路径，随反馈 24 小时日志一起发回来可验。
        // 胶囊常驻、只在主界面出现时记一次。012 补：这条确认会写（onAppear 挂在
        // 常驻胶囊上，AppLogger.log 追加写盘；之前没验到只是老爷没发反馈）。
        .onAppear {
            let v = ProcessInfo.processInfo.operatingSystemVersion
            if #available(iOS 26.0, *) {
                AppLogger.shared.log("TabBar glass: iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion), glassEffect(.clear.tint(white 0.22), in: Capsule()) + shadow + rim", tag: "UI")
            } else {
                AppLogger.shared.log("TabBar glass: iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion), fallback ultraThinMaterial", tag: "UI")
            }
        }
        // 1.3.0.009：滑动手势用 .highPriorityGesture()（006 的修法）。005 的普通
        // .gesture() 会被三个 Button 的点按手势抢走触摸，真机上左右滑切页滑不动。
        // 高优先手势让拖动先于 Button 点按被认出来：点按（没位移）时拖动认不出来、
        // Button 照样能点；左右滑（位移超 12pt）时拖动先认出来、切页。阈值不变。
        .highPriorityGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    // 只认横滑（横向位移够大、且比纵向大）；竖滑不管。
                    guard abs(value.translation.width) > 40,
                          abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < 0 {
                        onSwipeLeft()
                    } else {
                        onSwipeRight()
                    }
                }
        )
    }
}

/// 胶囊玻璃（1.3.0.012，第 46 条）：iOS 26+ 只罩 .glassEffect(.clear.tint
/// (.white.opacity(0.22)), in: Capsule())——.clear 是最透的那档玻璃（无色调，
/// .regular 自带白霜、采样均匀浅灰底就显实心白，010 就是这么败的）；淡淡的白
/// tint 让胶囊跟 #F2F2F7 底色拉开、看得出是一颗浮着的玻璃 pill，底下内容照样
/// 透出来、糊掉、折射（011 的裸 .clear 在均匀浅灰底上近乎隐形，才看着像一片白）；
/// 背景 clear、不铺任何磨砂；26 以下 fallback 用 .ultraThinMaterial 磨砂底
/// （磨砂本身 iOS 15+ 就有，部署目标 iOS 16 能用；只在老系统上，26+ 不走这条）。
/// 阴影和细边不在这里，在调用处（.shadow + .overlay stroke）——文件 App 的胶囊
/// 就是玻璃 + 柔和投影 + 发亮细边三样齐全才看得出是玻璃。
private extension View {
    @ViewBuilder
    func capsuleGlass() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.clear.tint(.white.opacity(0.22)), in: Capsule())
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }
}
