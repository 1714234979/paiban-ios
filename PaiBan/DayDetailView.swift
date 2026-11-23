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

    @State private var newShift = "日班"
    @State private var partnerTeam = ""
    @State private var partnerShift = ""
    @State private var swapNote = ""

    @State private var leaveType = "事假"
    @State private var leaveNote = ""
    @State private var rangeStart = Date()
    @State private var rangeEnd = Date()

    @State private var isBusy = false
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
        Text("连班禁令：① 中班接次日早班不行；② 一天不能上两个相同的班（早班 + 日班不行）。违反时服务端会拒绝并提示原因。")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(12)
            .background(Color.yellow.opacity(0.10))
            .cornerRadius(10)
    }

    // MARK: 操作

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button("调班") {
                newShift = shownDay.shift
                showSwapForm.toggle()
                showLeaveForm = false
                showLeaveRangeForm = false
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            Button("请假") {
                showLeaveForm.toggle()
                showSwapForm = false
                showLeaveRangeForm = false
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            Button("请一段假") {
                rangeStart = DateUtil.date(from: shownDay.date) ?? Date()
                rangeEnd = rangeStart
                showLeaveRangeForm.toggle()
                showSwapForm = false
                showLeaveForm = false
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            if shownDay.overridden == true {
                Button("取消调班") { Task { await cancelOverride() } }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .frame(maxWidth: .infinity)
                    .disabled(isBusy)
            }
            if shownDay.onLeave == true {
                Button("取消请假") { Task { await cancelLeave() } }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .frame(maxWidth: .infinity)
                    .disabled(isBusy)
            }
        }
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
                .disabled(isBusy)
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
                .disabled(isBusy)
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
                .disabled(isBusy)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: 提交

    private func submitSwap() async {
        errorText = nil
        doneMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await store.submitOverride(date: shownDay.date, shift: newShift,
                                           note: swapNote.isEmpty ? nil : swapNote,
                                           partner: partnerTeam.isEmpty ? nil : partnerTeam,
                                           partnerShift: partnerShift.isEmpty ? nil : partnerShift)
            doneMessage = "调班已保存"
            showSwapForm = false
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func submitLeave() async {
        errorText = nil
        doneMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await store.submitLeave(date: shownDay.date, type: leaveType,
                                        note: leaveNote.isEmpty ? nil : leaveNote)
            doneMessage = "请假已保存"
            showLeaveForm = false
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func submitLeaveRange() async {
        errorText = nil
        doneMessage = nil
        if rangeEnd < rangeStart {
            errorText = "结束日期不能早于开始日期"
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await store.submitLeaveRange(start: DateUtil.string(from: rangeStart),
                                             end: DateUtil.string(from: rangeEnd),
                                             type: leaveType,
                                             note: leaveNote.isEmpty ? nil : leaveNote)
            doneMessage = "请假已保存"
            showLeaveRangeForm = false
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func cancelOverride() async {
        errorText = nil
        doneMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await store.cancelOverride(date: shownDay.date)
            doneMessage = "调班已取消"
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func cancelLeave() async {
        errorText = nil
        doneMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await store.cancelLeave(date: shownDay.date)
            doneMessage = "请假已取消"
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
