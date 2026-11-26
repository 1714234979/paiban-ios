import SwiftUI

/// 日历显示设置（1.2.7.001，第 23 条，图三样式）：4 个开关 + 下面实时预览当月小日历。
/// 改了立刻生效（保存到本地 + 同步到服务端 profile，换设备也能同步）。
/// 「适配第2班次展示」不做——没有第2班次。
struct CalendarDisplaySettingsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var settings: CalendarDisplaySettings
    @State private var isSaving = false

    init() {
        _settings = State(initialValue: CalendarDisplaySettings.loadLocal())
    }

    var body: some View {
        Form {
            Section {
                Toggle("周一为每周首日", isOn: binding(\.mondayFirst))
                Toggle("显示法定节假日", isOn: binding(\.showHolidays))
                Toggle("显示农历", isOn: binding(\.showLunar))
                Toggle("当月显示上下月", isOn: binding(\.showAdjacentMonths))
                Text("改了立即生效。显示法定节假日的日历标注来自服务器节假日数据（每年 11 月更新）；三薪是工资计算概念，不在日历上混着标。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 实时预览（图三样式）：当月小日历，按当前开关显示。
            Section("预览") {
                CalendarPreviewView(settings: settings)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }
        }
        .navigationTitle("日历显示设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            settings = store.calendarDisplay
        }
    }

    private func binding(_ keyPath: WritableKeyPath<CalendarDisplaySettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                settings[keyPath: keyPath] = newValue
                Task {
                    isSaving = true
                    defer { isSaving = false }
                    try? await store.saveDisplaySettings(settings)
                }
            }
        )
    }
}

/// 预览小日历（按显示设置渲染当月）：周几行 + 日期格（阳历大数字、阴历小字；
/// 上下月日期按开关显示/隐藏）。用 DateUtil + ChineseCalendar 本地算，不走服务端。
private struct CalendarPreviewView: View {
    var settings: CalendarDisplaySettings

    private var year: Int { DateUtil.yearMonth(of: Date()).year }
    private var month: Int { DateUtil.yearMonth(of: Date()).month }

    private var weekdays: [String] {
        settings.mondayFirst ? ["一", "二", "三", "四", "五", "六", "日"]
            : ["日", "一", "二", "三", "四", "五", "六"]
    }

    /// 当月格子：(日号, 是否当月, 是否今天)。周一首日时前导空格按周一偏移。
    private var cells: [(day: Int, isCurrentMonth: Bool, isToday: Bool)] {
        let days = DateUtil.daysInMonth(year: year, month: month)
        let firstWeekday = DateUtil.firstWeekday(year: year, month: month) // 0=周日
        let leading = settings.mondayFirst ? (firstWeekday + 6) % 7 : firstWeekday
        let todayDay = DateUtil.calendar.component(.day, from: Date())
        var out: [(day: Int, isCurrentMonth: Bool, isToday: Bool)] = []
        let prevDays = DateUtil.daysInMonth(year: month == 1 ? year - 1 : year, month: month == 1 ? 12 : month - 1)
        for i in 0..<leading {
            out.append((day: prevDays - leading + 1 + i, isCurrentMonth: false, isToday: false))
        }
        for d in 1...days {
            out.append((day: d, isCurrentMonth: true,
                        isToday: DateUtil.yearMonth(of: Date()).year == year
                            && DateUtil.yearMonth(of: Date()).month == month && todayDay == d))
        }
        let remainder = out.count % 7
        if remainder != 0 {
            for i in 1...(7 - remainder) {
                out.append((day: i, isCurrentMonth: false, isToday: false))
            }
        }
        return out
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                ForEach(weekdays, id: \.self) { w in
                    Text(w)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(cells.indices, id: \.self) { idx in
                    let cell = cells[idx]
                    VStack(spacing: 0) {
                        Text(cell.isCurrentMonth ? "\(cell.day)" : (settings.showAdjacentMonths ? "\(cell.day)" : ""))
                            .font(.system(size: 13, weight: cell.isToday ? .bold : .regular))
                            .foregroundColor(cell.isCurrentMonth ? .primary : .secondary)
                            .frame(width: 26, height: 26)
                            .background(cell.isToday ? Color.green.opacity(0.25) : Color.clear)
                            .clipShape(Circle())
                        if settings.showLunar {
                            Text(lunarText(for: cell))
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
            }
            // 36 条：Text("\(year)年\(month)月") 是 LocalizedStringKey，年份会带分组符变 2,026；verbatim 拼纯数字。
            Text(verbatim: "\(year)年\(month)月 · 预览按当前开关显示")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func lunarText(for cell: (day: Int, isCurrentMonth: Bool, isToday: Bool)) -> String {
        guard cell.isCurrentMonth else { return "" }
        guard let date = DateUtil.date(from: "\(year)-\(String(format: "%02d", month))-\(String(format: "%02d", cell.day))") else { return "" }
        return ChineseCalendar.info(for: date).lunarText
    }
}
