import AppIntents
import WidgetKit

/// 小组件配置：API 密钥（1.2.8）。
/// App Group 不通（重签描述文件不带 group.com.paiban.app，快照读不到，
/// 小组件只显示「打开 App 登录后显示」占位）时，小组件改走服务端直拉，
/// 密钥填一次存在小组件自己的配置里，不管怎么重签都能通。
/// 密钥在 App 设置页「小组件」里复制（POST /api/v1/me/api-key 自助生成）。
/// 没填密钥时走老路：App Group 快照（通的机器上照常用）。
struct WidgetAPIKeyIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "小组件设置" }
    static var description: LocalizedStringResource { "填入小组件密钥，小组件直接从服务器拉数据；不填则用 App 共享的快照。" }

    @Parameter(title: "小组件密钥", description: "App 设置页「小组件」→ 复制小组件密钥，粘贴到这里。")
    var apiKey: String?
}
