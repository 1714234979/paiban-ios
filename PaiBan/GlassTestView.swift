import SwiftUI

/// 液态玻璃测试页（1.3.0.013，第 46 条）：
/// 老爷真机上连续五版（006/009/010/011/012）底栏玻璃都显不出来，全是实心白。
/// 这页是诊断用的对照试验，不动主流程：同一块彩色底（红黄蓝绿紫橙大色块，
/// 上下滚）上面，并排两颗胶囊——A 是 SwiftUI .glassEffect(.clear)（012 那套），
/// B 是 UIKit UIVisualEffectView 磨砂玻璃。两颗胶囊悬浮不动，彩色底从下面滚过，
/// 看哪颗透出后面彩色的模糊影子、哪颗是实心白。B 是系统磨砂玻璃，一定看得出来；
/// A 显不出来，就证明 SwiftUI 玻璃这条路在咱这个工程里不通，底栏就用 B 的做法。
/// 入口：设置 → 关于 → 液态玻璃测试。
struct GlassTestView: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    Text("上下滚彩色块，看 A、B 两颗胶囊：透出后面彩色模糊影子的是玻璃，实心白的是没显出来。B 是系统磨砂玻璃。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemBackground))
                    colorBlock(.red, "红色块")
                    colorBlock(.yellow, "黄色块")
                    colorBlock(.blue, "蓝色块")
                    colorBlock(.green, "绿色块")
                    colorBlock(.purple, "紫色块")
                    colorBlock(.orange, "橙色块")
                }
                .padding(.bottom, 240)
            }
            .modifier(AlwaysVisibleScrollIndicator())

            VStack(spacing: 18) {
                VStack(spacing: 4) {
                    Text("A · SwiftUI glassEffect(.clear)")
                        .font(.caption).bold()
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .foregroundColor(.white)
                    capsuleA
                }
                VStack(spacing: 4) {
                    Text("B · UIKit UIVisualEffectView")
                        .font(.caption).bold()
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .foregroundColor(.white)
                    capsuleB
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 23)
        }
        .navigationTitle("液态玻璃测试")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            AppLogger.shared.log("GlassTest: A glassEffect(.clear.tint white 0.22), B UIVisualEffectView(.systemThinMaterial)", tag: "UI")
        }
    }

    /// A 胶囊：012 那套 SwiftUI 玻璃原样（裸 .clear + 白 tint + 阴影 + 细边）。
    @ViewBuilder
    private var capsuleA: some View {
        if #available(iOS 26.0, *) {
            capsuleItems
                .padding(.horizontal, 10)
                .glassEffect(.clear.tint(.white.opacity(0.22)), in: Capsule())
                .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
                .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
        } else {
            capsuleItems
                .padding(.horizontal, 10)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    /// B 胶囊：UIKit 磨砂玻璃（和 013 底栏同一套做法）。
    private var capsuleB: some View {
        capsuleItems
            .padding(.horizontal, 10)
            .background(
                ZStack {
                    BlurView(style: .systemThinMaterial)
                    Color.white.opacity(0.12)
                }
                .clipShape(Capsule())
            )
            .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
            .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
    }

    /// 胶囊里的三个标签（跟真底栏一样：排班/工资/设置，选中蓝色、没选中灰色）。
    private var capsuleItems: some View {
        HStack(spacing: 0) {
            testTabItem(icon: "calendar", title: "排班", selected: false)
            testTabItem(icon: "yensign.circle", title: "工资", selected: true)
            testTabItem(icon: "gearshape", title: "设置", selected: false)
        }
    }

    private func testTabItem(icon: String, title: String, selected: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 21))
            Text(title)
                .font(.system(size: 10))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .foregroundColor(selected ? .blue : .secondary)
    }

    private func colorBlock(_ color: Color, _ text: String) -> some View {
        ZStack {
            color
            Text(text)
                .font(.title).bold()
                .foregroundColor(.white)
        }
        .frame(height: 220)
    }
}
