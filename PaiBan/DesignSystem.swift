import SwiftUI

/// 全 App 设计规范（1.1.4 统一，老爷 2026-11-24 06:09 定「统一整个软件的 UI 设计」）。
///
/// 以现有视觉为底，不发明新风格，只把各处写散了的数收成一套：
/// 顶部深 navy 大卡片、班次色（日绿/中红/早紫/休淡青，语义不动，只在 ShiftStyle 里）、
/// 圆角卡片。各页共用同一套，不再各写各的。
///
/// 定死的数（全 App 一个值）：
/// - 品牌深 navy：Color(red: 0.11, green: 0.15, blue: 0.23)。AccentColor 资产也是这个值，
///   所以系统 .borderedProminent / Color.accentColor 天生就是 navy，不用每处手写。
///   之前 AccentColor 资产是深绿（0.067/0.141/0.106），主按钮走深绿、顶栏卡片走深蓝，
///   两个深色混着用——1.1.4 起统一成 navy。
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
}

/// 内容卡片：圆角 16、内边距 16。背景由调用方按页面底色选——
/// 分组底色（工资/登录页）用 systemBackground（白卡），
/// 白底页面（当天详情 sheet）用 secondarySystemBackground（浅灰卡）。
struct AppCard: ViewModifier {
    var background: Color = Color(.systemBackground)
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
    func appCard(background: Color = Color(.systemBackground), shadow: Bool = false) -> some View {
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
                .background(AppStyle.navy)
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
