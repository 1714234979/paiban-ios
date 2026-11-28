import SwiftUI
import UIKit // 1.3.2.017：保存成功轻震动用 UIImpactFeedbackGenerator（iOS 16 可用，不用 iOS 17 的 sensoryFeedback）

/// 手动排班页（1.2.7.002，1.3.2.017 按参考图 3–6 重做版式）：月历 + 底部班次按钮，
/// 点某天再点班次就是给那天排班。样式：浅灰画布 + 纯白圆角卡 + 藏青强调，
/// 不用参考图里的大绿大橙按钮。周日开头（日一二三四五六）；每天一格：阳历大数字、
/// 右上角农历小字、下面一个班次色块（休息=青色、白班=绿、夜班=紫、早班=橙、中班=粉）；
/// 选中的那天藏青底 + 藏青边；今天那格描绿边；底部是分段选择器风格的班次胶囊 + 藏青「完成」。
struct ManualScheduleView: View {
    @Environment(AppStore.self) private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var year: Int
    @State private var month: Int
    @State private var selectedDate: Date?
    @State private var isBusy = false
    @State private var showAddCustom = false
    @State private var customName = ""
    @State private var customColorHex = "#F59E0B"
    @State private var errorText: String?

    private static let customColors = ["#F59E0B", "#EF4444", "#8B5CF6", "#06B6D4", "#10B981", "#EC4899", "#64748B"]

    init() {
        let ym = DateUtil.yearMonth(of: Date())
        _year = State(initialValue: ym.year)
        _month = State(initialValue: ym.month)
        _selectedDate = State(initialValue: Date())
    }

    // MARK: 月份数据

    private var firstDay: Date { DateUtil.firstDayOfMonth(year: year, month: month) ?? Date() }
    private var daysInMonth: Int { DateUtil.daysInMonth(year: year, month: month) }
    /// 当月 1 号是周几（0=周日）。
    private var firstWeekday: Int {
        DateUtil.calendar.component(.weekday, from: firstDay) - 1
    }
    /// 格子数（按周补齐）。
    private var cellCount: Int {
        let total = firstWeekday + daysInMonth
        return ((total + 6) / 7) * 7
    }

    private func dateForCell(_ idx: Int) -> Date? {
        let day = idx - firstWeekday + 1
        guard day >= 1, day <= daysInMonth else { return nil }
        return DateUtil.calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// 当天的手动班次码（manualShifts 里没有就是休息）。
    private func codeFor(_ date: Date) -> String {
        store.rotation.manualShifts[DateUtil.string(from: date)] ?? "-"
    }

    /// 手动码 → 显示（标签 + 颜色）。E 码早班橙色、N 码早班紫色（按夜班显示），
    /// 与参考图一致：休息青、白班绿、夜班紫、早班橙、中班粉。
    private func displayFor(code: String) -> (label: String, color: Color) {
        switch code {
        case "D": return ("白班", ShiftStyle.color(for: "日班"))
        case "N": return ("夜班", ShiftStyle.color(for: "早班"))
        case "E": return ("早班", Color(red: 0.95, green: 0.55, blue: 0.15))
        case "M": return ("中班", ShiftStyle.color(for: "中班"))
        case "W": return ("白班", ShiftStyle.color(for: "白班"))
        case "Y": return ("夜班", ShiftStyle.color(for: "夜班"))
        case "P": return ("前夜", ShiftStyle.color(for: "前夜"))
        case "F": return ("下午", ShiftStyle.color(for: "下午"))
        case "R": return ("早", ShiftStyle.color(for: "早"))
        case "L": return ("后夜", ShiftStyle.color(for: "后夜"))
        case "1": return ("一班", ShiftStyle.color(for: "第一班"))
        case "2": return ("二班", ShiftStyle.color(for: "第二班"))
        case "3": return ("三班", ShiftStyle.color(for: "第三班"))
        case "4": return ("四班", ShiftStyle.color(for: "第四班"))
        default:
            if let custom = store.rotation.customShifts[code] {
                return (custom.name, Color(hex: custom.color))
            }
            return ("休息", ShiftStyle.color(for: "休息"))
        }
    }

    private func shiftFor(_ date: Date) -> String {
        store.rotation.baseShift(team: store.viewTeam, date: date)
    }

    private func isToday(_ date: Date) -> Bool {
        DateUtil.calendar.isDateInToday(date)
    }

    private func shiftMonth(_ delta: Int) {
        var comps = DateComponents(year: year, month: month, day: 1)
        comps.month = (comps.month ?? 1) + delta
        if let d = DateUtil.calendar.date(from: comps) {
            let ym = DateUtil.yearMonth(of: d)
            year = ym.year
            month = ym.month
        }
    }

    // MARK: 视图

    var body: some View {
        VStack(spacing: 0) {
            // 顶部：月份左右切（1.3.2.017：删掉与导航标题重复的「手动排班」文字；
            // 箭头改成与月份标题栏同款 36pt 白底圆框）。
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(AppStyle.surface1, in: Circle())
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                }
                .buttonStyle(PressableButtonStyle())
                Spacer()
                Text(DateUtil.yearMonthTitle(year: year, month: month))
                    .font(.system(size: 18, weight: .bold))
                    .monospacedDigit()
                Spacer()
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(AppStyle.surface1, in: Circle())
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // 月历白卡（1.3.2.017）：周几头 + 格子收进一张纯白圆角卡，卡片与间距收紧。
            VStack(spacing: 4) {
                // 周几头（周日开头）。
                HStack(spacing: 0) {
                    ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { w in
                        Text(w)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 4)

                // 月历格子。
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(0..<cellCount, id: \.self) { idx in
                        if let date = dateForCell(idx) {
                            dayCell(date)
                        } else {
                            Color.clear.frame(height: 64)
                        }
                    }
                }
            }
            .padding(12)
            .background(AppStyle.surface1, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)

            Spacer()

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
            }

            // 底部班次选择条（1.3.2.017）：分段选择器风格的白底胶囊 + 色点；
            // 「完成」改藏青胶囊（原来的大橙按钮不要了）。
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    shiftButton(title: "白班", shift: "日班")
                    shiftButton(title: "夜班", shift: "早班")
                    // 早班（E 码，06–14）是独立的班次，橙色，与 8h 早班（紫，N 码）区分。
                    shiftButton(title: "早班", shift: "早班", code: "E", color: Color(red: 0.95, green: 0.55, blue: 0.15))
                    shiftButton(title: "休息", shift: "休息")
                    shiftButton(title: "中班", shift: "中班")
                    Button("无") { assignNone() }
                        .buttonStyle(ShiftChipStyle())
                    ForEach(customShiftButtons, id: \.code) { item in
                        Button { assignCustom(code: item.code) } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: item.color))
                                    .frame(width: 8, height: 8)
                                Text(item.name)
                            }
                        }
                        .buttonStyle(ShiftChipStyle())
                    }
                    Button("+") { showAddCustom = true }
                        .buttonStyle(ShiftChipStyle())
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 4)

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(AppStyle.navyAdaptive)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(AppStyle.pageBackground)
        .navigationTitle("手动排班")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddCustom) {
            addCustomSheet
        }
    }

    // MARK: 一天一格

    private func dayCell(_ date: Date) -> some View {
        let disp = displayFor(code: codeFor(date))
        let selected = selectedDate.map { DateUtil.calendar.isDate($0, inSameDayAs: date) } ?? false
        let today = isToday(date)
        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    Text("\(DateUtil.calendar.component(.day, from: date))")
                        .font(.title3)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text(ChineseCalendar.info(for: date).lunarText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text(disp.label)
                    .font(.caption)
                    .bold()
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 20)
                    .background(disp.color)
                    .clipShape(Capsule())
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
            // 1.3.2.017：选中改藏青底 + 藏青边（原来绿底）；今天描绿边（原来淡黄底，
            // 跟主日历今天格一致）；两者叠加时选中优先。
            .background(selected ? AppStyle.navyAdaptive.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? AppStyle.navyAdaptive : (today ? Color.green : Color.clear), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .frame(height: 64)
    }

    // MARK: 班次按钮

    /// 按钮显示名 + 对应班次名；code 指定时用该码（如早班用 E 码，不与早班 N 码混）；
    /// color 指定时用该色（早班 E 码用橙色，不走 ShiftStyle 的早班紫）。
    /// 胶囊里带一个色点（1.3.2.017，分段选择器风格）。
    private func shiftButton(title: String, shift: String, code: String? = nil, color: Color? = nil) -> some View {
        let c = color ?? ShiftStyle.color(for: shift)
        return Button { assignShift(shift: shift, code: code) } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(c)
                    .frame(width: 8, height: 8)
                Text(title)
            }
        }
        .buttonStyle(ShiftChipStyle())
    }

    private var customShiftButtons: [(code: String, name: String, color: String)] {
        store.rotation.customShifts.map { (code: $0.key, name: $0.value.name, color: $0.value.color) }
            .sorted { $0.code < $1.code }
    }

    private func assignShift(shift: String, code: String? = nil) {
        guard let date = selectedDate else { return }
        let dateStr = DateUtil.string(from: date)
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                if let code {
                    // 指定码（如早班 E）：直接写码。
                    var r = store.rotation
                    r.manualShifts[dateStr] = code
                    try await store.saveRotation(r)
                } else {
                    try await store.setManualShift(date: dateStr, shift: shift)
                }
            } catch {
                errorText = (error as? APIError)?.message ?? error.localizedDescription
            }
        }
    }

    private func assignCustom(code: String) {
        guard let date = selectedDate else { return }
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                var r = store.rotation
                r.manualShifts[DateUtil.string(from: date)] = code
                try await store.saveRotation(r)
            } catch {
                errorText = (error as? APIError)?.message ?? error.localizedDescription
            }
        }
    }

    private func assignNone() {
        guard let date = selectedDate else { return }
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                try await store.clearManualShift(date: DateUtil.string(from: date))
            } catch {
                errorText = (error as? APIError)?.message ?? error.localizedDescription
            }
        }
    }

    // MARK: 加自定义班次

    private var addCustomSheet: some View {
        NavigationStack {
            Form {
                Section("自定义班次") {
                    TextField("班次名（如：替班）", text: $customName)
                        .fieldBackground()
                    HStack {
                        Text("颜色")
                        Spacer()
                        ForEach(Self.customColors, id: \.self) { hex in
                            Button {
                                customColorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Group {
                                            if customColorHex == hex {
                                                Image(systemName: "checkmark")
                                                    .font(.caption)
                                                    .bold()
                                                    .foregroundColor(.white)
                                                    .shadow(color: .black.opacity(0.4), radius: 1)
                                            }
                                        }
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section {
                    Button("保存") {
                        Task {
                            do {
                                let name = customName.trimmingCharacters(in: .whitespaces)
                                guard !name.isEmpty else { return }
                                _ = try await store.addCustomShift(name: name, colorHex: customColorHex)
                                customName = ""
                                // 1.3.2.017：保存成功轻震一下 + 关弹窗（之前只关弹窗没震动；
                                // 失败时 errorText 现在也在弹窗里显示出来，不再静默）。
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showAddCustom = false
                            } catch {
                                errorText = (error as? APIError)?.message ?? error.localizedDescription
                            }
                        }
                    }
                    .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("加自定义班次")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showAddCustom = false }
                }
            }
        }
    }
}

/// 班次选择胶囊（1.3.2.017）：白底胶囊 + 细描边 + 主字（分段选择器风格），
/// 不再是实色底白字（原来那套太抢，跟参考图的大色块一样不要了）。
private struct ShiftChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .bold()
            .foregroundColor(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(AppStyle.surface1)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(AppStyle.outline, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch h.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 142, 142, 147)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
