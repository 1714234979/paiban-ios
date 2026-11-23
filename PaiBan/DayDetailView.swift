import SwiftUI

/// 某天的详情（点日历弹出的 sheet）：班次、时间、双班、请假、节假日、调班/对方班，
/// 以及调班 / 请假 / 取消的操作。连班禁令在界面上写明，服务端拒绝时原样显示中文错误。
struct DayDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let day: DaySchedule

    /// 刷新后从当月数据里取最新状态（调班/请假保存后 sheet 里的内容跟着变）。
    private var shownDay: DaySchedule {
        store.month?.day(for: day.date) ?? day
    }

    @State private var showSwapForm = false
    @State private var showLeaveForm = false
    @State private var showLeaveRangeForm = false
    @State private var showOvertimeForm = false

    @State private var newShift = "日班"
    @State private var partnerTeam = ""
    @State private var partnerShift = ""
    @State private var swapNote = ""

    @State private var leaveType = "事假"
    @State private var leaveNote = ""
    @State private var rangeStart = Date()
    @State private var rangeEnd = Date()

    /// 记加班：开始 / 结束时间（DatePicker 只取时分），时长当场算出来。
    @State private var overtimeStart = Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var overtimeEnd = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var overtimeNote = ""

    @State private var errorText: String?
    @State private var doneMessage: String?

    private let partnerTeams = ["", "A", "B", "C", "D"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleCard
                    detailRows
                    banHint
                    if let errorText {
                        Text(errorText)
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                    if let doneMessage {
                        Text(doneMessage)
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                    actionButtons
                    if showSwapForm { swapForm }
                    if showLeaveForm { leaveForm }
                    if showLeaveRangeForm { leaveRangeForm }
                    if showOvertimeForm { overtimeForm }
                }
                .padding(20)
            }
            .navigationTitle("当天详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    // MARK: 内容

    private var titleCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(DateUtil.fullFormatter.string(from: DateUtil.date(from: shownDay.date) ?? Date()) + " " + shownDay.weekdayText)
                    .font(.headline)
                Text("\(shownDay.team ?? store.myTeam)班 · 基础班次 \(shownDay.baseShift ?? "—")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(shownDay.shift)
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(ShiftStyle.color(for: ShiftStyle.parts(of: shownDay.shift).first ?? shownDay.shift))
                .cornerRadius(8)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var detailRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("实际班次", shownDay.shift)
            row("时间", shownDay.displayTime)
            if shownDay.isDouble == true {
                row("双班", ShiftStyle.parts(of: shownDay.shift).joined(separator: " + ") + "（共 \(shownDay.totalHours ?? 16) 小时）")
            }
            if let holiday = shownDay.holiday, !holiday.isEmpty {
                row("节假日", holiday)
            }
            if shownDay.onLeave == true {
                row("请假", (shownDay.leaveType ?? "请假") + (shownDay.leaveNote.map { " · \($0)" } ?? ""))
            }
            if let ot = store.overtime(for: shownDay.date) {
                row("加班", "\(ot.start)–\(ot.end)（\(ot.durationText)）" + (ot.note.map { " · \($0)" } ?? ""))
            }
            if shownDay.overridden == true {
                row("已调班", (shownDay.note ?? "调班"))
                if let partner = shownDay.partner, !partner.isEmpty {
                    row("对方班组", "\(partner)班" + (shownDay.partnerShift.map { "（\($0)）" } ?? ""))
                }
                if let cover = shownDay.coverDate {
                    row("替班日", cover)
                }
                if let payback = shownDay.paybackDate {
                    row("还班日", payback)
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
            Spacer()
        }
        .font(.subheadline)
    }

    private var banHint: some View {
        Text("连班禁令：中班接次日早班不行；一天不能上两个相同的班。")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.10))
            .cornerRadius(10)
    }

    // MARK: 操作

    /// 四个操作并排两列（调班 / 请假 / 请一段假 / 记加班），一次只开一个表单；
    /// 取消类操作单独放一行红色文字按钮，不跟主操作抢位置。
    private var actionButtons: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                Button("调班") {
                    newShift = shownDay.shift
                    showSwapForm.toggle()
                    showLeaveForm = false
                    showLeaveRangeForm = false
                    showOvertimeForm = false
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                Button("请假") {
                    showLeaveForm.toggle()
                    showSwapForm = false
                    showLeaveRangeForm = false
                    showOvertimeForm = false
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                Button("请一段假") {
                    rangeStart = DateUtil.date(from: shownDay.date) ?? Date()
                    rangeEnd = rangeStart
                    showLeaveRangeForm.toggle()
                    showSwapForm = false
                    showLeaveForm = false
                    showOvertimeForm = false
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                Button("记加班") {
                    if let ot = store.overtime(for: shownDay.date) {
                        overtimeStart = timeDate(ot.start) ?? overtimeStart
                        overtimeEnd = timeDate(ot.end) ?? overtimeEnd
                        overtimeNote = ot.note ?? ""
                    }
                    showOvertimeForm.toggle()
                    showSwapForm = false
                    showLeaveForm = false
                    showLeaveRangeForm = false
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            if shownDay.overridden == true || shownDay.onLeave == true || store.overtime(for: shownDay.date) != nil {
                HStack(spacing: 20) {
                    if shownDay.overridden == true {
                        Button("取消调班") { Task { await cancelOverride() } }
                            .foregroundColor(.red)
                            
                    }
                    if shownDay.onLeave == true {
                        Button("取消请假") { Task { await cancelLeave() } }
                            .foregroundColor(.red)
                            
                    }
                    if store.overtime(for: shownDay.date) != nil {
                        Button("删除加班") { Task { await deleteOvertime() } }
                            .foregroundColor(.red)
                            
                    }
                }
                .font(.subheadline)
            }
        }
    }

    /// "HH:MM" 转成今天那个时间的 Date（只取时分，供 DatePicker 用）。
    private func timeDate(_ hhmm: String) -> Date? {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return nil }
        return Calendar.current.date(bySettingHour: p[0], minute: p[1], second: 0, of: Date())
    }

    /// 记加班表单：开始 / 结束时间 + 当场算出的时长，跨夜自动加 24 小时。
    private var overtimeForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("记加班")
                .font(.headline)
            DatePicker("开始", selection: $overtimeStart, displayedComponents: .hourAndMinute)
            DatePicker("结束", selection: $overtimeEnd, displayedComponents: .hourAndMinute)
            HStack {
                Text("时长")
                    .foregroundColor(.secondary)
                Spacer()
                Text(overtimeDurationText)
                    .font(.headline)
                    .foregroundColor(.blue)
            }
            Text("结束比开始早算跨夜（比如 22:00 到 02:00 是 4 小时）。")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("备注（可选）", text: $overtimeNote)
                .textFieldStyle(.roundedBorder)
            Button("确认加班") { Task { await submitOvertime() } }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    /// 表单里当场算出的时长（跟服务端同一规则）。
    private var overtimeDurationText: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let start = fmt.string(from: overtimeStart)
        let end = fmt.string(from: overtimeEnd)
        if start == end { return "开始和结束不能一样" }
        return OvertimeCalc.text(minutes: OvertimeCalc.minutes(start: start, end: end))
    }

    private var swapForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("调成哪个班")
                .font(.headline)
            Picker("班次", selection: $newShift) {
                ForEach(ShiftStyle.allShifts, id: \.self) { shift in
                    Text("\(shift) \(ShiftStyle.timeRange(for: shift))").tag(shift)
                }
            }
            .pickerStyle(.menu)
            HStack {
                Text("对方班组")
                Spacer()
                Picker("对方班组", selection: $partnerTeam) {
                    ForEach(partnerTeams, id: \.self) { team in
                        Text(team.isEmpty ? "不指定" : "\(team)班").tag(team)
                    }
                }
                .pickerStyle(.menu)
            }
            if !partnerTeam.isEmpty {
                HStack {
                    Text("对方上的班")
                    Spacer()
                    Picker("对方班次", selection: $partnerShift) {
                        Text("不指定").tag("")
                        ForEach(["日班", "中班", "早班"], id: \.self) { shift in
                            Text(shift).tag(shift)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            TextField("备注（可选）", text: $swapNote)
                .textFieldStyle(.roundedBorder)
            Button("确认调班") { Task { await submitSwap() } }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var leaveForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("请假类型")
                .font(.headline)
            Picker("类型", selection: $leaveType) {
                ForEach(ShiftStyle.leaveTypes, id: \.self) { type in
                    Text(type).tag(type)
                }
            }
            .pickerStyle(.segmented)
            TextField("备注（可选）", text: $leaveNote)
                .textFieldStyle(.roundedBorder)
            Button("确认请假") { Task { await submitLeave() } }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var leaveRangeForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("请一段假（只算有班的日子，休班跳过，最多 62 天）")
                .font(.headline)
            DatePicker("从", selection: $rangeStart, displayedComponents: .date)
            DatePicker("到", selection: $rangeEnd, displayedComponents: .date)
            Picker("类型", selection: $leaveType) {
                ForEach(ShiftStyle.leaveTypes, id: \.self) { type in
                    Text(type).tag(type)
                }
            }
            .pickerStyle(.segmented)
            TextField("备注（可选）", text: $leaveNote)
                .textFieldStyle(.roundedBorder)
            Button("确认请假") { Task { await submitLeaveRange() } }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: 提交

    // 提交都是乐观更新：本地先改好、立刻显示“已保存”，后台再静默同步到服务端。
    // 同步失败会刷回来回滚，错误写进 store.errorMessage。
    private func submitSwap() async {
        errorText = nil
        doneMessage = nil
        await store.submitOverride(date: shownDay.date, shift: newShift,
                                   note: swapNote.isEmpty ? nil : swapNote,
                                   partner: partnerTeam.isEmpty ? nil : partnerTeam,
                                   partnerShift: partnerShift.isEmpty ? nil : partnerShift)
        doneMessage = "调班已保存"
        showSwapForm = false
    }

    private func submitLeave() async {
        errorText = nil
        doneMessage = nil
        await store.submitLeave(date: shownDay.date, type: leaveType,
                                note: leaveNote.isEmpty ? nil : leaveNote)
        doneMessage = "请假已保存"
        showLeaveForm = false
    }

    private func submitLeaveRange() async {
        errorText = nil
        doneMessage = nil
        if rangeEnd < rangeStart {
            errorText = "结束日期不能早于开始日期"
            return
        }
        await store.submitLeaveRange(start: DateUtil.string(from: rangeStart),
                                     end: DateUtil.string(from: rangeEnd),
                                     type: leaveType,
                                     note: leaveNote.isEmpty ? nil : leaveNote)
        doneMessage = "请假已保存"
        showLeaveRangeForm = false
    }

    private func cancelOverride() async {
        errorText = nil
        doneMessage = nil
        await store.cancelOverride(date: shownDay.date)
        doneMessage = "调班已取消"
    }

    private func cancelLeave() async {
        errorText = nil
        doneMessage = nil
        await store.cancelLeave(date: shownDay.date)
        doneMessage = "请假已取消"
    }

    private func submitOvertime() async {
        errorText = nil
        doneMessage = nil
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let start = fmt.string(from: overtimeStart)
        let end = fmt.string(from: overtimeEnd)
        if start == end {
            errorText = "开始和结束时间不能一样"
            return
        }
        await store.submitOvertime(date: shownDay.date, start: start, end: end,
                                   note: overtimeNote.isEmpty ? nil : overtimeNote)
        doneMessage = "加班已保存（\(OvertimeCalc.text(minutes: OvertimeCalc.minutes(start: start, end: end)))）"
        showOvertimeForm = false
    }

    private func deleteOvertime() async {
        errorText = nil
        doneMessage = nil
        await store.deleteOvertime(date: shownDay.date)
        doneMessage = "加班已删除"
    }
}
