import SwiftUI
import UIKit

/// A/B/C/D 班次切换栏（1.3.2.016，Gemini 升级版规格）：仿 iOS 26 底栏物理弹性，
/// 纯实心、无玻璃。外层不透明浅灰凹槽 + 实心滑块 + 双层微阴影；
/// 点击跨格动态拉伸、水平拖拽跟手（速度拉伸 + 橡皮筋边缘 + 触觉反馈 + 惯性吸附）；
/// 本人班组文字下方 4pt 小圆点；减弱动态效果时降级为轻量位移。
/// 轨道与滑块走 AppStyle.surface2/surface3（与 1.3.2.014 的分段选择器同款，
/// 深色下比系统底色亮一档，滑块不会在深色里变黑）。
struct ElasticTeamSegmentedBar: View {
    let items: [String]               // ["A班", "B班", "C班", "D班"]
    let myTeamIndex: Int?             // 本人班组下标，用于小圆点
    @Binding var selectedIndex: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // 交互与物理状态
    @State private var isDragging = false
    @State private var isGestureLockedHorizontal = false
    @State private var dragOriginOffset: CGFloat = 0
    @State private var currentOffset: CGFloat = 0
    @State private var velocityStretch: CGFloat = 0
    @State private var lastDragX: CGFloat = 0
    @State private var lastHapticIndex: Int = -1

    // 点击跨格弹跳拉伸状态
    @State private var tapStretchX: CGFloat = 1.0
    @State private var tapStretchY: CGFloat = 1.0
    @State private var isTapElevated = false
    @State private var bounceResetWorkItem: DispatchWorkItem?

    private let trackPadding: CGFloat = 4
    private let barHeight: CGFloat = 46
    private let haptic = UISelectionFeedbackGenerator()

    var body: some View {
        GeometryReader { geo in
            let innerWidth = max(geo.size.width - trackPadding * 2, 1)
            let segmentWidth = innerWidth / CGFloat(max(items.count, 1))
            let maxOffset = innerWidth - segmentWidth
            let restOffset = CGFloat(selectedIndex) * segmentWidth
            let pillOffset = isDragging ? currentOffset : restOffset

            // 合成物理缩放（减弱动态效果开启时固定 1.0）
            let scaleX: CGFloat = reduceMotion ? 1.0 : (isDragging ? (1.04 + velocityStretch) : tapStretchX)
            let scaleY: CGFloat = reduceMotion ? 1.0 : (isDragging ? 1.09 : tapStretchY)
            let isElevated = !reduceMotion && (isDragging || isTapElevated)

            ZStack(alignment: .leading) {
                // 1. 纯不透明浅灰凹槽（零玻璃）
                Capsule()
                    .fill(AppStyle.surface2)

                // 2. 实心滑块 + 双层实体阴影（零玻璃）
                Capsule()
                    .fill(AppStyle.surface3)
                    .frame(width: segmentWidth, height: barHeight - trackPadding * 2)
                    .scaleEffect(x: scaleX, y: scaleY, anchor: .center)
                    // 近距离轮廓影
                    .shadow(color: .black.opacity(0.05), radius: 1.5, y: 0.5)
                    // 远距离浮起影（拖动/切换时动态扩散）
                    .shadow(
                        color: .black.opacity(isElevated ? 0.14 : 0.08),
                        radius: isElevated ? 10 : 6,
                        y: isElevated ? 4 : 2.5
                    )
                    .offset(x: pillOffset)
                    .animation(
                        reduceMotion
                            ? .easeInOut(duration: 0.18)
                            : (isDragging
                                ? .interactiveSpring(response: 0.16, dampingFraction: 0.86)
                                : .spring(response: 0.34, dampingFraction: 0.72)),
                        value: pillOffset
                    )
                    .animation(.spring(response: 0.24, dampingFraction: 0.66), value: scaleX)
                    .animation(.spring(response: 0.24, dampingFraction: 0.66), value: scaleY)
                    .animation(.easeOut(duration: 0.2), value: isElevated)

                // 3. 班次文字与本人班组微型圆点
                HStack(spacing: 0) {
                    ForEach(items.indices, id: \.self) { index in
                        let liveIndex = isDragging
                            ? clampedIndex(for: pillOffset, segmentWidth: segmentWidth)
                            : selectedIndex
                        let isSelected = (index == liveIndex)
                        let isMyTeam = (index == myTeamIndex)

                        VStack(spacing: 2) {
                            Text(items[index])
                                .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? Color.primary : Color.secondary)

                            // 本人班组极轻标识点（替代原来两行冗长提示文案）
                            Circle()
                                .fill(isMyTeam ? (isSelected ? Color.primary.opacity(0.55) : Color.secondary.opacity(0.45)) : .clear)
                                .frame(width: 4, height: 4)
                        }
                        .padding(.top, 2)
                        .scaleEffect(!reduceMotion && isSelected && isElevated ? 1.035 : 1.0)
                        .frame(width: segmentWidth, height: barHeight - trackPadding * 2)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectByTap(to: index)
                        }
                        .animation(.easeOut(duration: 0.16), value: isSelected)
                    }
                }
            }
            .padding(trackPadding)
            .simultaneousGesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .local)
                    .onChanged { value in
                        // 起手方向锁：若纵向分量更大，直接让给外层 ScrollView
                        if !isGestureLockedHorizontal {
                            if abs(value.translation.height) > abs(value.translation.width) * 1.15 {
                                return
                            }
                            isGestureLockedHorizontal = true
                            isDragging = true
                            dragOriginOffset = restOffset
                            lastDragX = value.translation.width
                            lastHapticIndex = selectedIndex
                            haptic.prepare()
                        }

                        // 速度感知微拉伸（上限 +0.05）
                        let deltaX = abs(value.translation.width - lastDragX)
                        lastDragX = value.translation.width
                        velocityStretch = min(deltaX / 180.0, 0.05)

                        let rawOffset = dragOriginOffset + value.translation.width
                        currentOffset = rubberBand(rawOffset, min: 0, max: maxOffset)

                        let hoveredIndex = clampedIndex(for: currentOffset, segmentWidth: segmentWidth)
                        if hoveredIndex != lastHapticIndex {
                            haptic.selectionChanged()
                            lastHapticIndex = hoveredIndex
                        }
                    }
                    .onEnded { value in
                        defer {
                            isGestureLockedHorizontal = false
                            velocityStretch = 0
                        }
                        guard isDragging else { return }

                        let predicted = dragOriginOffset + value.predictedEndTranslation.width * 0.4
                        let target = clampedIndex(for: predicted, segmentWidth: segmentWidth)

                        withAnimation(reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.34, dampingFraction: 0.72)) {
                            selectedIndex = target
                            isDragging = false
                        }
                    }
            )
        }
        .frame(height: barHeight)
    }

    /// 点击切换：按跨越格数动态拉伸（跨格越远拉伸越灵动，落位回弹收敛）
    private func selectByTap(to target: Int) {
        guard target != selectedIndex else { return }
        haptic.selectionChanged()

        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedIndex = target
            }
            return
        }

        let span = abs(target - selectedIndex)
        let dynamicStretchX: CGFloat = span >= 2 ? 1.09 : 1.05

        bounceResetWorkItem?.cancel()

        withAnimation(.spring(response: 0.20, dampingFraction: 0.65)) {
            tapStretchX = dynamicStretchX
            tapStretchY = 1.08
            isTapElevated = true
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
            selectedIndex = target
        }

        let resetTask = DispatchWorkItem {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.74)) {
                tapStretchX = 1.0
                tapStretchY = 1.0
                isTapElevated = false
            }
        }
        bounceResetWorkItem = resetTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: resetTask)
    }

    private func clampedIndex(for offset: CGFloat, segmentWidth: CGFloat) -> Int {
        guard segmentWidth > 0 else { return 0 }
        let idx = Int(round(offset / segmentWidth))
        return min(max(idx, 0), items.count - 1)
    }

    /// 非线性苹果式边缘橡皮筋阻尼
    private func rubberBand(_ value: CGFloat, min minVal: CGFloat, max maxVal: CGFloat) -> CGFloat {
        let limit: CGFloat = 18
        if value < minVal {
            let diff = minVal - value
            return minVal - (limit * diff) / (diff + limit * 2.5)
        } else if value > maxVal {
            let diff = value - maxVal
            return maxVal + (limit * diff) / (diff + limit * 2.5)
        }
        return value
    }
}
