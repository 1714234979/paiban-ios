import SwiftUI
import UIKit

/// 顶部「今日排班」卡片（1.3.2.016，Gemini 升级版规格 + 老爷令重构；
/// 1.3.3.002：老爷 2026-11-29 00:12 亲口令，顶卡的「预估今日工资」整块删掉）：
/// 上下两区紧凑结构——上行「日期 + 我的班组徽标 | 按需显示的今天按钮」，
/// 下行「左：班次与状态（实时倒计时）」。卡片高度由剩下内容定，是固定值，
/// 不随内容变（没有条件行了）。
/// 倒计时沿用 TodayLiveState（PayCalc.todayLiveState），每秒走；
/// 状态圆点色沿用旧映射（上班中/已下班绿，上班前/两班之间橙，休息灰），
/// 呼吸脉冲只在上班中（.working）时开。
/// 注意：liveState 只取状态与起止时刻（倒计时用），已挣/总额不再算给界面看——
/// todayLiveState 用默认费率与默认输入调用，起止时刻与输入无关，不影响倒计时。
struct TodayOverviewCard: View {
    let dateText: String           // "2026年11月28日 周六"
    let myTeam: String             // "B"
    let isViewingOtherTeam: Bool   // 当前是否在看其他班组
    let shiftLine: String          // "日班 08:00–16:00" / "休息" / "请假（年假）"
    let day: DaySchedule?          // 今天的日程（nil = 今日数据未到）
    let showBackToToday: Bool      // 当前浏览非本月时为 true
    let onTapMyTeamBadge: () -> Void   // 切回本人班组
    let onBackToToday: () -> Void      // 回到当月

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            headerRow
            Divider().opacity(0.45)
            bottomRow
        }
        .padding(.horizontal, 16)
        // 1.3.2.017：上下内边距 14→12，行距 13→10——「今天」胶囊本来就在标题行里，
        // 不增加卡高；两张卡一样紧凑。
        .padding(.vertical, 12)
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
            // 徽标（1.3.2.017，老爷 2026-11-28 20:47 亲口令）：文案统一成「回到本班」——
            // 看别班时可点回本班（强调色 + 回转箭头 + 轻震动）；看自己班时是静态标签（次要色、不可点）。
            Button {
                if isViewingOtherTeam {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onTapMyTeamBadge()
                }
            } label: {
                HStack(spacing: 3) {
                    Text("回到本班")
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

    // MARK: 下行：班次与状态（实时倒计时）

    /// 状态共用一个 TimelineView（每秒重绘）；只取状态与起止时刻，
    /// 金额已在 1.3.3.002 删掉，不再算已挣/总额给界面看。
    private var bottomRow: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            let now = context.date
            let state = liveState(now: now)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 状态（沿用旧 TodayStatusLine 的逻辑）

    /// 只取状态与起止时刻：班次起止时刻与费率/输入无关，默认调用即可。
    private func liveState(now: Date) -> PayCalc.TodayLiveState? {
        guard let day else { return nil }
        let today = DateUtil.calendar.startOfDay(for: now)
        return PayCalc.todayLiveState(
            shift: day.shift, onLeave: day.onLeave == true, day: today, now: now
        )
    }

    /// 上班中（.working）才算 working；其余一律不脉冲。
    private func isWorking(_ state: PayCalc.TodayLiveState?) -> Bool {
        guard let state else { return false }
        if case .working = state { return true }
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
