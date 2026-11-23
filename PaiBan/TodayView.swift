import SwiftUI

/// 今日页：今天的班、明天的班、睡眠窗口（能不能吵）、本周 7 天。
struct TodayView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                if let today = store.todayDay {
                    todayCard(today)
                } else {
                    ProgressView("正在加载…")
                        .padding()
                }
                quietCard
                weekCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .task {
            await store.refreshToday()
        }
        .refreshable {
            await store.refreshToday()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("今日")
                .font(.title2).bold()
                .foregroundColor(.white)
            Text(DateUtil.fullFormatter.string(from: Date()) + " " + DateUtil.weekdayCN(of: Date()))
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.75))
            if store.isOffline {
                Label("离线缓存", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(red: 0.11, green: 0.15, blue: 0.23))
        .cornerRadius(16)
        .padding(.top, 8)
    }

    private func todayCard(_ today: DaySchedule) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今天")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(today.shift)
                        .font(.largeTitle).bold()
                    Text(today.displayTime)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if today.onLeave == true {
                        Text("今天请假（\(today.leaveType ?? "")）")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                    if today.isDouble == true {
                        Text("双班：\(ShiftStyle.parts(of: today.shift).joined(separator: " + "))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Circle()
                    .fill(ShiftStyle.color(for: ShiftStyle.parts(of: today.shift).first ?? today.shift))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Text(TeamInfo.shortName(today.shift))
                            .font(.title).bold()
                            .foregroundColor(.white)
                    )
            }
            Divider()
            HStack {
                Text("明天")
                    .foregroundColor(.secondary)
                Spacer()
                if let tomorrow = store.tomorrowDay {
                    Text("\(tomorrow.shift) · \(tomorrow.displayTime)")
                        .bold()
                } else {
                    Text("—")
                }
            }
            .font(.subheadline)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    @ViewBuilder
    private var quietCard: some View {
        if let quiet = store.quiet {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: quiet.quiet == true ? "moon.zzz.fill" : "bell.fill")
                        .foregroundColor(quiet.quiet == true ? .indigo : .green)
                    Text(quiet.quiet == true ? "现在是睡眠窗口，别吵" : "现在可以联系")
                        .font(.headline)
                    Spacer()
                    Text(quiet.status ?? "")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Text(quiet.reason ?? "")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("今天 \(quiet.shiftToday ?? "—") · 明天 \(quiet.shiftTomorrow ?? "—")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(16)
        } else {
            // 服务端没给 quiet 时本地按班次给一句话。
            VStack(alignment: .leading, spacing: 8) {
                Text("睡眠窗口")
                    .font(.headline)
                Text(localQuietHint)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(16)
        }
    }

    /// 本地兜底：按今天/明天班次推睡眠窗口（与服务端规则一致）。
    private var localQuietHint: String {
        guard let today = store.todayDay, let tomorrow = store.tomorrowDay else {
            return "暂无数据"
        }
        let hour = DateUtil.calendar.component(.hour, from: Date())
        let minute = DateUtil.calendar.component(.minute, from: Date())
        let mins = hour * 60 + minute
        if today.shift == "中班" && mins >= 12 * 60 && mins < 14 * 60 + 30 {
            return "中班午休 12:00–14:30，别吵"
        }
        if tomorrow.shift == "早班" && mins >= 19 * 60 && mins < 22 * 60 + 30 {
            return "早班前晚休息 19:00–22:30，别吵"
        }
        if today.shift == "日班" && mins >= 22 * 60 {
            return "日班夜里休息 22:00–次日 06:30，别吵"
        }
        return "不在睡眠窗口，可以联系"
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本周")
                .font(.headline)
            if store.weekDays.isEmpty {
                Text("暂无数据")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            ForEach(store.weekDays, id: \.date) { day in
                HStack {
                    Text(day.date)
                        .font(.subheadline)
                        .frame(width: 96, alignment: .leading)
                    Text(day.weekdayText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .leading)
                    Spacer()
                    Text(day.isDouble == true ? "\(day.shift)（双班）" : day.shift)
                        .font(.subheadline)
                        .bold(day.date == DateUtil.string(from: Date()))
                        .foregroundColor(ShiftStyle.color(for: ShiftStyle.parts(of: day.shift).first ?? day.shift))
                    if day.onLeave == true {
                        Text("假")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}
