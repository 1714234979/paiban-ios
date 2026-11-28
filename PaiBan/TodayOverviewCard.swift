import SwiftUI
import UIKit

/// 顶部「今日排班」卡片（1.3.2.016，Gemini 升级版规格 + 老爷令重构）：
/// 上下两区紧凑结构——上行「日期 + 我的班组徽标 | 按需显示的今天按钮」，
/// 下行「左：班次与状态（实时倒计时） | 右：今日已挣 + 眼睛 + 大号金额」。
/// 高度固定：休息日 / 无工资权限 / 今日数据未到时，金额列用 opacity 0 占位
/// （看不见但占高度），卡片不因行数变化而一会儿大一会儿小。
/// 倒计时沿用 TodayLiveState（PayCalc.todayLiveState），每秒走；
/// 状态圆点色沿用旧映射（上班中/已下班绿，上班前/两班之间橙，休息灰），
/// 呼吸脉冲只在上班中（.working）时开。
/// 预估小字不做（规格里没有，老爷令：先不做）。
struct TodayOverviewCard: View {
    let dateText: String           // "2026年11月28日 周六"
    let myTeam: String             // "B"
    let isViewingOtherTeam: Bool   // 当前是否在看其他班组
    let shiftLine: String          // "日班 08:00–16:00" / "休息" / "请假（年假）"
    let day: DaySchedule?          // 今天的日程（nil = 今日数据未到）
    let earlyRate: Double
    let midRate: Double
    let inputs: PayCalc.DayEstimateInputs
    let payAccess: Bool
    @Binding var hideAmounts: Bool
    let showBackToToday: Bool      // 当前浏览非本月时为 true
    let onTapMyTeamBadge: () -> Void   // 切回本人班组
    let onBackToToday: () -> Void      // 回到当月

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 13) {
            headerRow
            Divider().opacity(0.45)
            bottomRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppStyle.surface1, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.035), radius: 10, y: 3)
        .animation(.snappy(duration: 0.22), value: showBackToToday)
    }

    // MARK: 上行：日期 + 徽标 | 今天按钮

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(dateText)
                .font(.system(size: 17, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)
            // 徽标：看别班时可点回本班（轻震动 + 箭头）；看自己班时是静态标签，不可点。
            Button {
                if isViewingOtherTeam {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onTapMyTeamBadge()
                }
            } label: {
                HStack(spacing: 3) {
                    Text("\(myTeam)班 · 我的今日")
                        .font(.system(size: 11, weight: .medium))
                    if isViewingOtherTeam {
                        Image(systemName: "arrow.uturn.left")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .foregroundStyle(isViewingOtherTeam ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(
                    (isViewingOtherTeam ? Color.accentColor.opacity(0.10) : AppStyle.surface2),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .fixedSize()
            .disabled(!isViewingOtherTeam)
            .animation(.easeInOut(duration: 0.2), value: isViewingOtherTeam)
            Spacer(minLength: 4)
            // 「今天」按钮只在浏览非本月时出现（在上行右端，不再单独撑一行）。
            if showBackToToday {
                Button(action: onBackToToday) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text("今天")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppStyle.surface2, in: Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
    }

    // MARK: 下行：左班次状态 | 右今日已挣

    /// 状态与金额共用同一个 TimelineView（同一时刻的 state），不各算各的。
    private var bottomRow: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            let now = context.date
            let state = liveState(now: now)
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(shiftLine)
                        .font(.system(size: 14, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.primary.opacity(0.84))
                    HStack(spacing: 6) {
                        statusDot(state: state)
                        Text(statusText(state: state, now: now))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Spacer()
                moneyColumn(state: state)
            }
        }
    }

    // MARK: 状态（沿用旧 TodayStatusLine 的逻辑）

    private func liveState(now: Date) -> PayCalc.TodayLiveState? {
        guard let day else { return nil }
        let today = DateUtil.calendar.startOfDay(for: now)
        return PayCalc.todayLiveState(
            shift: day.shift, onLeave: day.onLeave == true, day: today, now: now,
            earlyRate: earlyRate, midRate: midRate, inputs: inputs
        )
    }

    /// 上班中（.working）才算 working；其余一律不脉冲。
    private func isWorking(_ state: PayCalc.TodayLiveState?) -> Bool {
        guard let state else { return false }
        if case .working = state { return true }
        return false
    }

    /// 休息态（含今日数据未到）才算休息；金额列靠它决定占不占位。
    private func isRestState(_ state: PayCalc.TodayLiveState?) -> Bool {
        guard let state else { return true }
        if case .rest = state { return true }
        return false
    }

    /// 状态圆点色（沿用旧 TodayStatusLine 映射）：上班中/已下班绿，
    /// 上班前/两班之间橙，休息/请假灰；今日数据未到时灰。
    private func dotColor(state: PayCalc.TodayLiveState?) -> Color {
        guard let state else { return .gray }
        switch state {
        case .rest: return .gray
        case .before: return .orange
        case .working: return .green
        case .between: return .orange
        case .done: return .green
        }
    }

    /// 状态文案 = 旧 countdownText 逻辑（倒计时每秒走）。
    private func statusText(state: PayCalc.TodayLiveState?, now: Date) -> String {
        guard let state else { return "—" }
        switch state {
        case .rest:
            return day?.onLeave == true ? "今日请假" : "今日休息"
        case .before(let start, _):
            return "距上班 " + durationText(from: now, to: start)
        case .working(let end, _, _):
            return "距下班 " + durationText(from: now, to: end)
        case .between(let nextStart, _, _):
            return "距下一班 " + durationText(from: now, to: nextStart)
        case .done:
            return "今日已下班"
        }
    }

    /// 时长 HH:MM:SS（不足 1 小时也写 00:MM:SS，保持位数不动、不跳行）。
    private func durationText(from: Date, to: Date) -> String {
        let total = max(0, Int(to.timeIntervalSince(from)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    /// 状态圆点：上班中时带呼吸脉冲光晕（减弱动态效果时不脉冲，只留实心点）。
    /// 脉冲与不脉冲共用 10pt 外框，列宽不变、行高不变。
    @ViewBuilder
    private func statusDot(state: PayCalc.TodayLiveState?) -> some View {
        if isWorking(state) && !reduceMotion {
            PulsingDot(color: dotColor(state: state))
        } else {
            Circle()
                .fill(dotColor(state: state))
                .frame(width: 6.5, height: 6.5)
                .frame(width: 10, height: 10)
        }
    }

    // MARK: 金额（沿用旧 TodayMoneyRow.moneyParts 的后缀与取整逻辑）

    /// 金额列：整列是一个按钮（点标签/金额都切隐藏），热区 = 整列高度（>32pt），
    /// 不靠 padding 撑高、不把卡片撑大。休息日 / 无工资权限 / 今日数据未到时，
    /// 内容照常算、opacity 0 占位 + 禁用，卡片高度纹丝不动。
    private func moneyColumn(state: PayCalc.TodayLiveState?) -> some View {
        let money = moneyParts(state: state)
        let visible = payAccess && !isRestState(state)
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                hideAmounts.toggle()
            }
        } label: {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text(money.label)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Image(systemName: hideAmounts ? "eye.slash" : "eye")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(money.amount)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }
        }
        .buttonStyle(.plain)
        .disabled(!visible)
        .opacity(visible ? 1 : 0)
        .accessibilityLabel(hideAmounts ? "金额已隐藏，点按显示" : "今日已挣 \(money.amount)，点按隐藏金额")
    }

    /// 金额两件套：标签固定「今日已挣」+ 三薪/加班后缀；预估小字不做。
    /// 休息日 / 今日数据未到返回占位内容（¥0.00），由调用方 opacity 0 藏起来。
    private func moneyParts(state: PayCalc.TodayLiveState?) -> (label: String, amount: String) {
        let suffix = inputs.isTriple ? "（三薪）" : (inputs.isOvertime ? "（加班）" : "")
        let label = "今日已挣" + suffix
        // 隐藏时金额一律 ¥****（1.3.2.013），三薪/加班后缀照常显示。
        let m: (Double) -> String = { hideAmounts ? "¥****" : MoneyUtil.money($0) }
        guard let state else { return (label, m(0)) }
        switch state {
        case .rest: return (label, m(0))
        case .before: return (label, m(0))
        case .working(_, let earned, _): return (label, m(earned))
        case .between(_, let earned, _): return (label, m(earned))
        case .done(let total): return (label, m(total))
        }
    }
}

/// 呼吸脉冲圆点（只在上班中时出现）：光晕 1.4s 一圈缩放淡出。
/// 自带 @State，插入时从头开始脉冲；状态切走时视图移除、状态丢弃，
/// 下次再上班重新插入、重新开始——不依赖卡片级的 pulse 标志，
/// TimelineView 每秒重绘也不会打断它（视图标识稳定、状态保留）。
private struct PulsingDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.32))
                .frame(width: 13, height: 13)
                .scaleEffect(pulse ? 1.35 : 0.75)
                .opacity(pulse ? 0.0 : 0.9)
            Circle()
                .fill(color)
                .frame(width: 6.5, height: 6.5)
        }
        .frame(width: 10, height: 10)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}
