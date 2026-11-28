import SwiftUI
import UIKit // 自适应色用 UIColor 动态色（1.2.8.001）
import CoreText // 字重桥接：UIFont → CTFont → SwiftUI Font

/// 全 App 设计规范（1.1.4 统一，老爷 2026-11-24 06:09 定「统一整个软件的 UI 设计」）。
///
/// 以现有视觉为底，不发明新风格，只把各处写散了的数收成一套：
/// 顶部深 navy 大卡片、班次色（日绿/中红/早紫/休淡青，语义不动，只在 ShiftStyle 里）、
/// 圆角卡片。各页共用同一套，不再各写各的。
///
/// 定死的数（全 App 一个值）：
/// - 品牌深 navy：Color(red: 0.11, green: 0.15, blue: 0.23)。AccentColor 资产浅色是这个值，
///   所以系统 .borderedProminent / Color.accentColor 天生就是 navy，不用每处手写。
///   之前 AccentColor 资产是深绿（0.067/0.141/0.106），主按钮走深绿、顶栏卡片走深蓝，
///   两个深色混着用——1.1.4 起统一成 navy。
/// - AccentColor 资产深色（1.2.8.002 深色修）：深 navy 蓝字写在黑底上对比度只有 1.3:1，
///   设置页「切换管理员后台」「检查更新」「意见反馈」「欢迎评分」「自动选路」、
///   排班页月份导航「今天」/左右箭头、Tab 栏选中态，深色下全都看不清。
///   深色改系统亮蓝（0.039/0.518/1.0），黑底上清晰可读；浅色保持原来那个深 navy，一字不差。
///   所有用 Color.accentColor 的地方（按钮标题、Picker 标签、Tab 选中态、.borderedProminent
///   按钮底色、当天详情选中描边）跟着资产一起变，不用每处手写。
/// - 卡片圆角 16、卡片内边距 16、页面左右边距 16、区块间距 16。
/// - 主/次按钮高 48、圆角 12（48 高的按钮配 12 圆角）。
/// - 字号三档：标题 .title2 加粗、区块标题 .headline、正文 .subheadline、小字 .caption；
///   次要文字统一 .foregroundColor(.secondary)。
/// - 卡片底色按页面底色选（不是全 App 一个色值）：分组底色（工资/登录页）用白卡，
///   白底页面（当天详情 sheet）用浅灰卡——底色分层，卡片才看得见。
///   阴影只在白卡上用（0.05 / radius 8 / y 2），浅灰卡不用。
enum AppStyle {
    /// 品牌深 navy。
    static let navy = Color(red: 0.11, green: 0.15, blue: 0.23)
    /// 深 navy 字（反馈页管理员名，1.2.8.001 深色修）：浅色沿用深 navy；
    /// 深色改亮钢蓝——深 navy 字写在黑底上根本看不清。
    static var navyText: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.65, green: 0.75, blue: 0.95, alpha: 1)
                : UIColor(red: 0.11, green: 0.15, blue: 0.23, alpha: 1)
        })
    }
    /// 深色提亮一档，不然卡片在黑底上没边、里面的字也糊成一片。
    static var navyAdaptive: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.18, green: 0.23, blue: 0.34, alpha: 1)
                : UIColor(red: 0.11, green: 0.15, blue: 0.23, alpha: 1)
        })
    }
    /// 半透明白字（1.2.8.001 深色修）：浅色保持原来那个透明度，深色改纯白。
    /// 深色下 75%/85%/90% 的白字发灰发虚，是「深色模式字体模糊」的头号原因。
    static func whiteText(opacity lightOpacity: Double) -> Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 1)
                : UIColor(white: 1, alpha: lightOpacity)
        })
    }
    /// 8–9pt 小灰字（阴历、脚注）（1.2.8.001 深色修）：浅色沿用系统 secondary；
    /// 深色提亮到 0.78 白——深色下系统 secondary 太暗，小字笔画细、看着发虚。
    static var tinySecondary: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 0.78, alpha: 1)
                : UIColor.secondaryLabel
        })
    }
    /// 「三薪」行底衬（1.2.8.001 深色修）：浅色黑 0.22（原来那样）；
    /// 深色改白 0.14——黑衬在深色 pill 上把那行压得更暗，白字跟着糊。
    static var tripleScrim: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.14)
                : UIColor(white: 0, alpha: 0.22)
        })
    }
    /// 当天详情连班禁令提示条（1.2.8.001 深色修）：浅色深棕字 + 浅黄底（原来那样）；
    /// 深色改浅琥珀字 + 深棕底，不然亮黄块在深色页里晃眼、字也扎眼。
    static var banHintText: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 1.0, green: 0.85, blue: 0.55, alpha: 1)
                : UIColor(red: 0.45, green: 0.33, blue: 0.05, alpha: 1)
        })
    }
    static var banHintBackground: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.25, green: 0.19, blue: 0.08, alpha: 1)
                : UIColor(red: 1.0, green: 0.95, blue: 0.80, alpha: 1)
        })
    }
    /// 开屏渐变（1.2.8.001 深色修）：浅色白到极浅（原来那样）；深色改深灰渐变，
    /// 不然深色下启动先闪一下白屏。
    static var splashTop: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)
                : UIColor(white: 1, alpha: 1)
        })
    }
    static var splashBottom: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1)
                : UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1)
        })
    }
    /// 卡片圆角。
    static let cardRadius: CGFloat = 16
    /// 卡片内边距。
    static let cardPadding: CGFloat = 16
    /// 页面左右边距。
    static let pagePadding: CGFloat = 16
    /// 区块间距（VStack 里卡片与卡片之间）。
    static let sectionSpacing: CGFloat = 16
    /// 主/次按钮高。
    static let buttonHeight: CGFloat = 48
    /// 按钮圆角。
    static let buttonRadius: CGFloat = 12

    // MARK: - 统一规范 v2（2026-11-28，老爷令：双端 UI 统一 + 视频 5 细节）

    /// 双端统一色值（浅/深各一），少写重复的 UIColor 闭包。
    static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { t in t.userInterfaceStyle == .dark ? dark : light })
    }

    /// Surface 色阶（视频细节 1）：层与层只差 1%-3%，深色绝不用纯黑 #000。
    /// surface0 页面底 / surface1 卡片 / surface2 抬高一层 / surface3 最高层。
    static var pageBackground: Color {
        adaptive(light: UIColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1),
                 dark: UIColor(red: 0.043, green: 0.043, blue: 0.059, alpha: 1)) // #F2F2F7 / #0B0B0F
    }
    static var surface1: Color {
        adaptive(light: UIColor(white: 1, alpha: 1),
                 dark: UIColor(red: 0.082, green: 0.082, blue: 0.082, alpha: 1)) // #FFFFFF / #151515
    }
    static var surface2: Color {
        adaptive(light: UIColor(red: 0.914, green: 0.914, blue: 0.933, alpha: 1),
                 dark: UIColor(red: 0.102, green: 0.102, blue: 0.106, alpha: 1)) // #E9E9EE / #1A1A1B
    }
    static var surface3: Color {
        adaptive(light: UIColor(white: 1, alpha: 1),
                 dark: UIColor(red: 0.125, green: 0.125, blue: 0.122, alpha: 1)) // #FFFFFF / #20201F
    }
    /// 分隔线（outline）：浅色 #E5E5EA / 深色 #2C2C2E。
    static var outline: Color {
        adaptive(light: UIColor(red: 0.898, green: 0.898, blue: 0.918, alpha: 1),
                 dark: UIColor(red: 0.173, green: 0.173, blue: 0.180, alpha: 1))
    }
    /// 主文字：浅色 #1C1C1E / 深色 #F5F5F7。
    static var onSurface: Color {
        adaptive(light: UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1),
                 dark: UIColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1))
    }
    /// 次文字：浅色 #6C6C70 / 深色 #A1A1A6。
    static var onSurfaceVariant: Color {
        adaptive(light: UIColor(red: 0.424, green: 0.424, blue: 0.439, alpha: 1),
                 dark: UIColor(red: 0.631, green: 0.631, blue: 0.651, alpha: 1))
    }
}

/// 内容卡片：圆角 16、内边距 16。背景由调用方按页面底色选——
/// 分组底色（工资/登录页）用 systemBackground（白卡），
/// 白底页面（当天详情 sheet）用 secondarySystemBackground（浅灰卡）。
struct AppCard: ViewModifier {
    var background: Color = AppStyle.surface1
    var shadow: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(AppStyle.cardPadding)
            .background(background)
            .cornerRadius(AppStyle.cardRadius)
            .shadow(color: shadow ? Color.black.opacity(0.05) : .clear, radius: 8, y: 2)
    }
}

extension View {
    /// 内容卡片（圆角 16、内边距 16）。shadow 只在白卡上用。
    func appCard(background: Color = AppStyle.surface1, shadow: Bool = false) -> some View {
        modifier(AppCard(background: background, shadow: shadow))
    }
}

/// 主按钮（满宽、48 高、圆角 12、navy 底白字）：登录/注册/反馈发送、表单保存。
/// 用 Label 上画背景（frame 撑满），按钮本身就是整格大小，不再是小 pill 居中。
struct AppPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: AppStyle.buttonHeight)
                .background(AppStyle.navyAdaptive)
                .foregroundColor(.white)
                .cornerRadius(AppStyle.buttonRadius)
        }
        .buttonStyle(.plain)
    }
}

/// 次按钮（满宽、48 高、圆角 12、浅灰底深字）：与主按钮并列的次要操作。
struct AppSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: AppStyle.buttonHeight)
                .background(Color(.secondarySystemBackground))
                .foregroundColor(.primary)
                .cornerRadius(AppStyle.buttonRadius)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 统一规范 v2：字号 / 字重 / 动效 / 晕入（2026-11-28）

/// 双端统一字号（两端同值）：22 titleLarge、18 title、17 headline、16 body、
/// 15 bodySmall、13 caption、12 captionSmall。
enum AppFont {
    static let titleLarge: CGFloat = 22
    static let title: CGFloat = 18
    static let headline: CGFloat = 17
    static let body: CGFloat = 16
    static let bodySmall: CGFloat = 15
    static let caption: CGFloat = 13
    static let captionSmall: CGFloat = 12

    /// CSS 字重（100–900）→ iOS 字重值（regular 0 / medium 0.23 / semibold 0.3 /
    /// bold 0.4），分段线性插值。SwiftUI Font.Weight 没有公开初始化器，不能直接
    /// 构造任意值；所以先算出 UIFont.Weight（有 rawValue 初始化器），再经 CTFont
    /// 桥接成 SwiftUI Font（见 font(size:cssWeight:scheme:)）。
    static func iosWeight(css: CGFloat) -> UIFont.Weight {
        let stops: [(CGFloat, CGFloat)] = [
            (100, -0.8), (200, -0.6), (300, -0.4), (400, 0.0),
            (500, 0.23), (600, 0.3), (700, 0.4), (800, 0.56), (900, 0.62),
        ]
        let c = min(900, max(100, css))
        for i in 0..<(stops.count - 1) {
            let (x0, y0) = stops[i]
            let (x1, y1) = stops[i + 1]
            if c >= x0 && c <= x1 {
                let t = (c - x0) / (x1 - x0)
                return UIFont.Weight(rawValue: y0 + t * (y1 - y0))
            }
        }
        return .regular
    }

    /// 统一字体：字号 + CSS 字重；深色自动 -40（视频细节 2：400→360、500→460、
    /// 600→560、700→660），浅色保持原字重。
    /// UIFont 与 CTFont 是 toll-free 桥接，先取 UIFont.systemFont 再转 CTFont，
    /// 才能把 UIFont.Weight 的任意值带进 SwiftUI Font。
    static func font(size: CGFloat, cssWeight: CGFloat, scheme: ColorScheme) -> Font {
        Font(UIFont.systemFont(
            ofSize: size,
            weight: iosWeight(css: scheme == .dark ? cssWeight - 40 : cssWeight)
        ) as CTFont)
    }
}

/// 统一字号 + 字重（深色自动 -40）。
struct AppFontModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let size: CGFloat
    let cssWeight: CGFloat
    func body(content: Content) -> some View {
        content.font(AppFont.font(size: size, cssWeight: cssWeight, scheme: scheme))
    }
}

/// 双端统一动效（视频细节 5）：时长快 150 / 中 250 / 慢 350；
/// 标准缓动 FastOutSlowIn，强调 CubicBezier(0.2, 0, 0, 1)。
enum AppMotion {
    static let fast: Double = 0.15
    static let medium: Double = 0.25
    static let slow: Double = 0.35
    /// 拖拽类（月份滑动、sheet、分段滑块）：过阻尼，雷厉风行，过程尾 0% 回弹。
    static let drag = Animation.spring(response: 0.3, dampingFraction: 1.0)
    /// 反馈类（成功对勾、Toast）：欠阻尼，Q 弹感，2.5s 自动消失。
    static let feedback = Animation.spring(response: 0.4, dampingFraction: 0.65)
    /// 反馈类自动消失时间。
    static let feedbackDismissDelay: Double = 2.5
    /// 标准缓动 FastOutSlowIn；强调 CubicBezier(0.2, 0, 0, 1)。
    static func standard(_ duration: Double = 0.25) -> Animation {
        .timingCurve(0.2, 0, 0, 1, duration: duration)
    }
    /// 平滑缓动（1.3.2.004：工资页切月、顶栏黑卡高度变化用）：慢进慢出，不抢不顿。
    /// 老爷 2026-11-28 11:34 亲口定工资页动画“改成平滑的”（不是再加一个）。
    /// 默认 0.35s；底栏切页要更快（0.25s，苹果商店那种“迅速又平滑”）。
    static func smooth(_ duration: Double = 0.35) -> Animation {
        .timingCurve(0.4, 0, 0.2, 1, duration: duration)
    }
}

/// 水墨晕染式出现（视频细节 3）：blur 6→0、120ms、cubic-bezier(.16,1,.3,1)，
/// 逐行错开 delay，前一个没晕完下一个就开始（连成波浪）。
struct BlurInModifier: ViewModifier {
    let delay: Double
    @State private var appeared = false
    func body(content: Content) -> some View {
        content
            .blur(radius: appeared ? 0 : 6)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.12).delay(delay)) {
                    appeared = true
                }
            }
    }
}

extension View {
    /// 统一字号 + 字重（深色自动 -40）。
    func appFont(size: CGFloat, weight cssWeight: CGFloat = 400) -> some View {
        modifier(AppFontModifier(size: size, cssWeight: cssWeight))
    }
    /// 水墨晕染式出现：blur 6→0、120ms；delay 逐行错开 30ms。
    func blurIn(delay: Double = 0) -> some View {
        modifier(BlurInModifier(delay: delay))
    }
    /// 行内图标下移 1/8 em（视频细节 3）：图标中心对齐文字中心，不再飘在基线上。
    func iconAligned() -> some View {
        baselineOffset(-2)
    }
    /// 最小触控热区（1.3.2.005，方案 §3.3 车间戴手套点得准）：
    /// 透明留白把点击范围扩到 48pt，视觉大小不变（图标不做大）。
    /// vertical / horizontal 分开给：横排并列的按钮只加竖向留白，不动横向间距。
    func touchTarget(vertical: CGFloat, horizontal: CGFloat = 0) -> some View {
        padding(.vertical, vertical)
            .padding(.horizontal, horizontal)
            .contentShape(Rectangle())
    }
}

/// 骨架占位块（1.3.2.005，方案 §4.4 列表加载、§5.4 弱网与离线）：
/// 加载时按真实布局排的灰色块，不转圈、不闪烁；数据到了直接换真内容。
/// 灰用 surface2（浅 #E9E9EE / 深 #1A1A1B），两端都看得见、不刺眼。
struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(AppStyle.surface2)
            .frame(width: width, height: height)
    }
}
