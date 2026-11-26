import SwiftUI

/// 某天的详情（点日历弹出的 sheet）：班次、时间、双班、请假、节假日、调班，
/// 以及调班 / 请假 / 取消的操作。连班禁令在界面上写明，服务端拒绝时原样显示中文错误。
///
/// 调班（1.2.9.001 第 31 条：空间那套，配对互换）：选一个班替我上这天
/// （我这天休息，对方那天变成组合班），再挑一天还班（还班日也可以先空着，以后再定）；
/// 保存前预览两边（替班日我和对方、还班日我和对方）；删一边两边一起删。
/// 只写我自己的记录，不动对方账号（老爷 2026-11-26 08:59 定）。位置不变，
/// 仍在当天详情这个二级菜单里。
/// 只读门禁（老爷 2026-11-24 04:49/04:50 定）：切到别的班看日历是纯只读，
/// 调班/请假/记加班入口全部不出现；能改的班 = 设置页设定的班组（跟着设置走，不是写死 B 班）。
/// 手动排班时：点一天直接设当天班次（日/中/早/休），不用走调班。
struct DayDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let day: DaySchedule

    /// 刷新后从当月数据里取最新状态（调班/请假保存后 sheet 里的内容跟着变）。
    private var shownDay: DaySchedule {
        store.month?.day(for: day.date) ?? day
    }

    /// 能不能改：正在看的班组 = 设置页设定的班组。看别的班时整个详情都是只读。
    private var canEdit: Bool { store.canEditCurrentCalendar }

    // MARK: 四班数据（调班/请假流程用）

    /// 当月窗口的四班日程（上月末 + 当月 + 次月初，一次取够）：
    /// 候选卡片要对方当天与前后天，还班日列表要当月每一天。
    @State private var teamsRange: TeamsRangeResponse?
    @State private var teamsLoading = false

    /// "A|2026-12-04" → 当天日程（四班同取的快速查找）。
    private var teamsLookup: [String: DaySchedule] {
        var dict: [String: DaySchedule] = [:]
        if let teams = teamsRange?.teams {
            for (team, days) in teams {
                for d in days { dict["\(team)|\(d.date)"] = d }
            }
        }
        return dict
    }

    private func teamDay(_ team: String, _ date: String) -> DaySchedule? {
        teamsLookup["\(team)|\(date)"]
    }

    /// 我某天的日程：优先当月已加载的数据（带我自己的调班/请假），
    /// 没有就用四班同取里的我班数据（老爷的全局 B 班就是这个；同事看全局班组近似）。
    private func myDayOn(_ date: String) -> DaySchedule? {
        if let d = store.month?.day(for: date) { return d }
        return teamDay(store.myTeam, date)
    }

    /// 我前一天 / 后一天的日程（连班禁令用）。
    private func myPrevDay(_ date: String) -> DaySchedule? {
        guard let d = DateUtil.date(from: date) else { return nil }
        return myDayOn(DateUtil.string(from: DateUtil.addingDays(d, -1)))
    }

    private func myNextDay(_ date: String) -> DaySchedule? {
        guard let d = DateUtil.date(from: date) else { return nil }
        return myDayOn(DateUtil.string(from: DateUtil.addingDays(d, 1)))
    }

    /// 某班组前一天 / 后一天的日程（请假顶岗候选的邻日禁令用）。
    private func prevDayOf(team: String, date: String) -> DaySchedule? {
        guard let d = DateUtil.date(from: date) else { return nil }
        return teamDay(team, DateUtil.string(from: DateUtil.addingDays(d, -1)))
    }

    private func nextDayOf(team: String, date: String) -> DaySchedule? {
        guard let d = DateUtil.date(from: date) else { return nil }
        return teamDay(team, DateUtil.string(from: DateUtil.addingDays(d, 1)))
    }

    /// 当月窗口的起止（上月末、次月初各多取一天，供邻日校验）。
    private var teamsWindow: (start: String, days: Int) {
        let comps = DateUtil.yearMonth(of: DateUtil.date(from: shownDay.date) ?? Date())
        let dim = DateUtil.daysInMonth(year: comps.year, month: comps.month)
        let first = DateUtil.string(from: DateUtil.calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: 1)) ?? Date())
        let start = DateUtil.string(from: DateUtil.addingDays(DateUtil.date(from: first) ?? Date(), -1))
        return (start, dim + 2)
    }

    private func loadTeamsRange() async {
        guard !teamsLoading else { return }
        teamsLoading = true
        defer { teamsLoading = false }
        let w = teamsWindow
        if let r = try? await store.fetchTeamsRange(start: w.start, days: w.days) {
            teamsRange = r
        }
    }

    // MARK: 调班流程状态（1.2.9.001 第 31 条：空间那套，配对互换）

    @State private var showSwapFlow = false
    /// 替我上这天班的班组（A/C/D，我自己的班除外）。
    @State private var swapPartner: String?
    /// 对方替我上完这天后、对方那天最终上的班（我这天的班 + 对方自己那天的班并成的组合班）。
    @State private var swapPartnerShift: String?
    @State private var swapPayback: String?
    /// 还班日那天我最终上的班（我自己那天的班 + 我替对方上的班并成的组合班），选还班日时算出来。
    @State private var swapPaybackShift: String?
    @State private var swapLater = false
    /// 备注（可选）。
    @State private var swapNote = ""
    @State private var swapSaving = false

    @State private var showFillPayback = false
    @State private var fillPayback: String?
    @State private var fillPaybackShift: String?

    @State private var showConvertLeave = false
    @State private var showDeleteSwap = false

    // MARK: 请假流程状态

    @State private var showLeaveForm = false
    @State private var showLeaveRangeForm = false
    @State private var leaveType = "年假"
    @State private var leaveNote = ""
    @State private var rangeStart = Date()
    @State private var rangeEnd = Date()
    @State private var leaveCoverPartner: String?
    @State private var showDeleteLeave = false

    // MARK: 加班

    @State private var showOvertimeForm = false
    @State private var overtimeStart = Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var overtimeEnd = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var overtimeNote = ""

    @State private var errorText: String?
    @State private var doneMessage: String?

    /// sheet 高度自适应内容（1.1.4）：原来 sheet 默认近乎全屏，内容只有上半截、
    /// 下面留大片空白。没开表单时用 .medium（半屏刚好装下标题+详情+提示+按钮），
    /// 点开调班/请假/记加班任一表单时切到 .large；表单关了再缩回 .medium。
    @State private var sheetDetent: PresentationDetent = .medium
    private var formOpen: Bool {
        showSwapFlow || showFillPayback || showLeaveForm || showLeaveRangeForm || showOvertimeForm
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleCard
                    detailRows
                    otherTeamsCard
                    banHint
                    if !canEdit {
                        readOnlyNote
                    }
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
                    if canEdit {
                        // 手动排班（1.2.7.001，第 24 条）：点一天直接设当天班次，不用走调班。
                        if store.rotation.isManual {
                            manualShiftPicker
                        }
                        actionButtons
                        if showSwapFlow { swapFlow }
                        if showFillPayback { fillPaybackFlow }
                        if showLeaveForm { leaveForm }
                        if showLeaveRangeForm { leaveRangeForm }
                        if showOvertimeForm { overtimeForm }
                    }
                }
                .padding(AppStyle.pagePadding)
            }
            .navigationTitle("当天详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .presentationDetents([.medium, .large], selection: $sheetDetent)
            .onChange(of: formOpen) { open in
                sheetDetent = open ? .large : .medium
            }
            // 打开当天详情就取一次四班派生日程：「其他班次」卡片按调班后的显示，
            // 不用等点开调班/请假才读（loadTeamsRange 自带去重，重复调只跑一次）。
            .task { await loadTeamsRange() }
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
        .padding(AppStyle.cardPadding)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(AppStyle.cardRadius)
    }

    private var detailRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("实际班次", shownDay.shift)
            row("时间", shownDay.displayTime)
            if shownDay.isDouble == true {
                row("双班", ShiftStyle.parts(of: shownDay.shift).joined(separator: " + ") + "（共 \(shownDay.totalHours ?? 16) 小时）")
            }
            // 1.2.7：预估工资（只看自己班时显示；看别的班不显示——那是别人的工资口径）。
            // 1.2.9.001：第 29 条补充规矩——没工资权限不显示这行（钱跟着 payAccess 走）。
            if (shownDay.team ?? store.myTeam) == store.myTeam && store.payAccess {
                row("预估工资", estimateText(for: shownDay))
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
                if shownDay.onLeave == true {
                    row("顶岗", (shownDay.partner.map { "\($0)班上 \(shownDay.partnerShift ?? "")" } ?? "未安排"))
                } else {
                    row("已调班", (shownDay.note ?? "调班"))
                    if let partner = shownDay.partner, !partner.isEmpty {
                        row("对方班组", "\(partner)班" + (shownDay.partnerShift.map { "（\($0)）" } ?? ""))
                    }
                    if let cover = shownDay.coverDate {
                        row("替班日", cover + "（这是还班日）")
                    } else if let payback = shownDay.paybackDate {
                        row("还班日", payback)
                    } else if shownDay.partner != nil {
                        row("还班日", "还没定（待还班）")
                    }
                }
            }
        }
        .padding(AppStyle.cardPadding)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(AppStyle.cardRadius)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
            Spacer()
        }
        .font(.subheadline)
    }

    /// 1.2.9.003：当天预估工资（与 PayCalc.todayEstimate 同口径，第 40 条）：
    /// 每个班 = 基本工资 ÷ 当月实际班数 + 班次补贴（早 70/中 30/日 0）
    ///          + (工龄津贴 + 高温补贴 + 学历补贴) ÷ 当月实际班数 − 五险一金 ÷ 当月实际班数
    ///          − 当月个税 ÷ 当月实际班数 + （正常班次才有的）奖金分摊 + 当日类型加成；
    /// 三薪日每班再加 3 倍日工资（不拿分摊），加班班次每个再加 2 倍日工资（不拿分摊）；
    /// 双班两个班都算；休息 0 元；请假不算钱。
    /// 基本工资按当天所在月的生效表解析（不是今天的口径——看 12 月的日子就用 12 月的数）；
    /// 奖金分摊与加班班次也按当天所在月算。
    private func estimateText(for day: DaySchedule) -> String {
        if day.onLeave == true { return "请假" }
        let inputs = store.estimateInputs(for: day.date)
        let est = PayCalc.todayEstimate(shift: day.shift, earlyRate: inputs.earlyRate, midRate: inputs.midRate, inputs: inputs.inputs)
        // 第 33 条：休息日逢法定节假日也标「（三薪）」（只标，不算钱；工资口径不动）。
        if est.isRest { return PayCalc.isStatutoryDay(day.date) ? "今日休息（三薪）" : "今日休息" }
        let suffix = est.isTriple ? "（三薪）" : (est.isOvertime ? "（加班）" : "")
        return "预估 " + MoneyUtil.money(est.total) + suffix
    }

    /// 其他班次：选中这天，其他三个班组按 8 天一轮基础排班算出的班次（横向一排小 chip）。
    /// 只按基础轮换算，不含调班/请假——App 里没有其他用户的调班记录。
    /// 正在看的班组不列在这里，它的班次已在上面「实际班次」里显示。
    /// 班次色沿用 DayCell 那套（日绿/中红/早紫、休息浅青底深青字）。
    private var otherTeamsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("其他班次")
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                ForEach(otherTeams, id: \.team) { item in
                    otherTeamChip(team: item.team, shift: item.shift)
                }
            }
        }
        .padding(AppStyle.cardPadding)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(AppStyle.cardRadius)
    }

    /// 其他三个班组在选中这天的班次。优先用四班派生日程（teamsRange：我的调班记录
    /// 里 partner==对方的那条会改对方那天的班）；没读到就退回基础轮换。
    /// 排除正在看的班组（shownDay.team 是正在看的日历班组；它的班次已在「实际班次」里）。
    private var otherTeams: [(team: String, shift: String)] {
        let shownTeam = shownDay.team ?? store.myTeam
        let date = DateUtil.date(from: shownDay.date) ?? Date()
        return TeamInfo.allTeams
            .filter { $0 != shownTeam }
            .map { team in
                if let d = teamDay(team, shownDay.date) { return (team, d.shift) }
                return (team, ScheduleCalculator.baseShift(team: team, date: date, rotation: store.rotation))
            }
    }

    /// 一个班组的 chip：班组名 + 班次。班次色是底色、白字；
    /// 休息用浅青底 + 深青字（跟 DayCell 的休息 pill 同一套），显示「休」。
    private func otherTeamChip(team: String, shift: String) -> some View {
        HStack(spacing: 4) {
            Text("\(team)班")
                .bold()
            Text(shift == "休息" ? "休" : shift)
        }
        .font(.subheadline)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .foregroundColor(shift == "休息" ? ShiftStyle.color(for: "休息") : .white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(shift == "休息" ? ShiftStyle.background(for: "休息") : ShiftStyle.color(for: shift))
        .cornerRadius(8)
    }

    /// 连班禁令提示：1.1.4 重排——原来是 .caption 小灰字 + 淡黄底（yellow 0.10），
    /// 字挤、对比度低，看着像水印。现在字号提到 .subheadline、行距 4、深棕字 +
    /// 暖黄底（对比度够），padding 12、圆角 12，和详情卡同一尺寸语言。
    /// 当前方式的禁令组（1.2.7.002：12h 方式用 12 小时那套，绝不能复用 8 小时那两条）。
    private var banSet: String { store.rotation.mode?.banSet ?? "8h" }

    /// 12h 方式连上天数上限（与服务端 MAX_CONSECUTIVE_12H 一致）。
    private var maxConsecutive12h: Int? {
        switch store.rotation.modeId {
        case "4-2-a", "4-2-b", "3-2-b": return 2
        case "4-2-c", "panama": return 3
        case "4-2-d1", "4-2-d2", "3-2-a", "dupont": return 4
        default: return nil
        }
    }

    /// 连班禁令提示文案（按方式走：12h 方式写 12 小时那套，6h 只写一条）。
    private var banHintText: String {
        switch banSet {
        case "12h":
            let max = maxConsecutive12h.map { "最多连上 \($0) 天。" } ?? ""
            return "连班禁令：白班接夜班不行（24 小时连轴）；不能连上两个夜班；夜班后休 48 小时；一天只能上一个班；\(max)"
        case "6h":
            return "连班禁令：一天不能上两个相同的班。"
        default:
            return "连班禁令：中班接次日早班不行；早班+日班不行（0 点直接上到 16 点）；一天不能上两个相同的班；只剩早+中、日+中两种双班。"
        }
    }

    private var banHint: some View {
        Text(banHintText)
            .font(.subheadline)
            .lineSpacing(4)
            .foregroundColor(AppStyle.banHintText)
            .padding(AppStyle.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppStyle.banHintBackground)
            .cornerRadius(AppStyle.cardRadius)
    }

    /// 只读提示：看别的班的日历时显示，改数据的入口全部不出现。
    private var readOnlyNote: some View {
        Text("正在看 \(shownDay.team ?? store.viewTeam) 班的日历，只能看，不能改。切回自己班（\(store.myTeam) 班）才能调班、请假、记加班。")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(AppStyle.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(AppStyle.cardRadius)
    }

    /// 手动排班：点一天直接设当天班次（日/中/早/休），不用走调班。
    /// 设完立刻保存，日历与工资跟着变。
    @State private var manualShiftSaving = false
    private var manualShiftPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("设当天班次")
                .font(.headline)
            Text("手动排班没有周期规律，点一天设当天班次；没设的当天算休息。")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Picker("当天班次", selection: Binding(
                get: { shownDay.shift },
                set: { newValue in
                    Task { await setManualShift(newValue) }
                }
            )) {
                ForEach(["日班", "中班", "早班", "休息"], id: \.self) { s in
                    Text(s).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .disabled(manualShiftSaving)
            if manualShiftSaving {
                ProgressView("正在保存…")
            }
        }
        .padding(AppStyle.cardPadding)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(AppStyle.cardRadius)
    }

    private func setManualShift(_ shift: String) async {
        guard shift != shownDay.shift else { return }
        errorText = nil
        doneMessage = nil
        manualShiftSaving = true
        defer { manualShiftSaving = false }
        do {
            try await store.setManualShift(date: shownDay.date, shift: shift)
            doneMessage = "\(shownDay.date) 已设为\(shift)"
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    // MARK: 操作入口

    /// 四个操作并排两列（调班 / 请假 / 请一段假 / 记加班），一次只开一个表单；
    /// 已有调班/请假时，取消类操作单独放一行红色文字按钮。
    /// 1.1.4：原来是 LazyVGrid + .bordered/.borderedProminent，pill 只包文字、
    /// 按内容定宽（「请一段假」4 个字比「调班」宽），左右两列不对齐、看着歪。
    /// 现在四个按钮共用 actionButton：同一高度 48pt、同一圆角 12、撑满各自半格，
    /// 调班是深色主按钮、其余三个是浅灰，大小位置全对齐。
    private var actionButtons: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                actionButton("调班", prominent: true) {
                    resetFlowStates()
                    if shownDay.overridden == true && shownDay.onLeave != true {
                        // 已有调班：下面直接显示状态与删除/补填入口，不用再开表单。
                    } else {
                        showSwapFlow.toggle()
                    }
                }
                actionButton("请假") {
                    leaveType = shownDay.leaveType ?? "年假"
                    leaveNote = shownDay.leaveNote ?? ""
                    leaveCoverPartner = nil
                    resetFlowStates()
                    showLeaveForm.toggle()
                }
                actionButton("请一段假") {
                    rangeStart = DateUtil.date(from: shownDay.date) ?? Date()
                    rangeEnd = rangeStart
                    resetFlowStates()
                    showLeaveRangeForm.toggle()
                }
                actionButton("记加班") {
                    if let ot = store.overtime(for: shownDay.date) {
                        overtimeStart = timeDate(ot.start) ?? overtimeStart
                        overtimeEnd = timeDate(ot.end) ?? overtimeEnd
                        overtimeNote = ot.note ?? ""
                    }
                    resetFlowStates()
                    showOvertimeForm.toggle()
                }
            }
            // 已有调班/请假/加班时的取消入口（只读日历上不出现）。
            if shownDay.overridden == true || shownDay.onLeave == true || store.overtime(for: shownDay.date) != nil {
                HStack(spacing: 20) {
                    if shownDay.overridden == true && shownDay.onLeave != true {
                        Button("删除这次调班") { showDeleteSwap = true }
                            .foregroundColor(.red)
                    } else if shownDay.overridden == true && shownDay.onLeave != true {
                        Button("取消调班") { Task { await cancelSwap() } }
                            .foregroundColor(.red)
                    }
                    if shownDay.onLeave == true {
                        Button("取消请假") { showDeleteLeave = true }
                            .foregroundColor(.red)
                    }
                    if store.overtime(for: shownDay.date) != nil {
                        Button("删除加班") { Task { await deleteOvertime() } }
                            .foregroundColor(.red)
                    }
                }
                .font(.subheadline)
            }
            if showDeleteSwap {
                deleteSwapConfirm
            }
            if showDeleteLeave {
                deleteLeaveConfirm
            }
            if shownDay.overridden == true && shownDay.onLeave != true {
                swapStatusCard
            }
        }
    }

    /// 四个操作按钮共用：等宽等高（48 高、圆角 12、撑满半格），调班是主按钮、
    /// 其余三个是次按钮。直接用设计规范里的 AppPrimaryButton/AppSecondaryButton，
    /// 不再各写一套样式。1.1.4 之前是 LazyVGrid + .bordered/.borderedProminent，
    /// pill 只包文字、按内容定宽，左右两列不对齐、看着歪。
    private func actionButton(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Group {
            if prominent {
                AppPrimaryButton(title: title, action: action)
            } else {
                AppSecondaryButton(title: title, action: action)
            }
        }
    }

    private func resetFlowStates() {
        showSwapFlow = false
        showFillPayback = false
        showLeaveForm = false
        showLeaveRangeForm = false
        showOvertimeForm = false
        errorText = nil
        doneMessage = nil
    }

    /// 还班日那天我上的班（从当月数据查；查不到就不显示）。
    private func paybackShiftText(_ paybackDate: String) -> String {
        if let shift = store.month?.day(for: paybackDate)?.shift {
            return "（那天我上 \(shift)）"
        }
        return ""
    }

    /// 已有调班的状态卡（1.2.9.001 第 31 条：配对互换）：
    /// 替班日我休息、对方班替我上对方最终的班；还班日我上组合班、对方休息。
    /// 只改我自己的数据，不动对方账号。旧记录（没有 partner 的，如 11-17/11-28）照老样子显示。
    private var swapStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let cover = shownDay.coverDate {
                Text("这是还班日，还的是 \(cover) 那次调班。")
                    .font(.subheadline)
                Text("我这天上 \(shownDay.shift)\(shownDay.partner.map { "，\($0)班这天休息" } ?? "")。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                if let partner = shownDay.partner, let pShift = shownDay.partnerShift {
                    Text("已调班：我这天休息，\(partner)班替我上 \(pShift)\(shownDay.note.map { "（\($0)）" } ?? "")。")
                        .font(.subheadline)
                } else {
                    Text("已调班：我这天改成 \(shownDay.shift)\(shownDay.note.map { "（\($0)）" } ?? "")。")
                        .font(.subheadline)
                }
                if let payback = shownDay.paybackDate {
                    Text("还班日：\(payback)\(paybackShiftText(payback))。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("还班日还没定（待还班）。过几天再补填还班日，一直不还就转为请假。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        Button("补填还班日") {
                            fillPayback = nil
                            fillPaybackShift = nil
                            showFillPayback = true
                        }
                        .buttonStyle(.bordered)
                        Button("转为请假") { showConvertLeave = true }
                            .buttonStyle(.bordered)
                    }
                    if showConvertLeave {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("转为请假后，这天按请假算。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 12) {
                                Button("确认转请假") { Task { await convertToLeave() } }
                                    .buttonStyle(.borderedProminent)
                                Button("取消") { showConvertLeave = false }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                }
            }
        }
        .padding(AppStyle.cardPadding)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(AppStyle.cardRadius)
    }

    private var deleteSwapConfirm: some View {
        HStack(spacing: 12) {
            Text("删除这次调班，两边一起恢复原排班（还班日也一起删）。")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("确认删除") { Task { await cancelSwap() } }
                .foregroundColor(.red)
            Button("取消") { showDeleteSwap = false }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    private var deleteLeaveConfirm: some View {
        HStack(spacing: 12) {
            Text(shownDay.partner != nil ? "确认取消？请假和顶岗一起取消。" : "确认取消请假？")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("确认取消") { Task { await cancelLeave() } }
                .foregroundColor(.red)
            Button("取消") { showDeleteLeave = false }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    // MARK: 顶岗评估（空间 evalCover 的 App 版）

    /// 12h 禁令（1.2.7.002，与服务端 validateDayShift12h 逐条对齐）：
    /// 一天只能上一个班；白班↔夜班不能相邻；不能连上两个夜班；
    /// 夜班后 48 小时内不能上班；连上天数不能超该方式上限。返回 nil = 通过。
    private func validate12h(newShift: String, dateStr: String) -> String? {
        if newShift == "休息" { return nil }
        let parts = ShiftStyle.parts(of: newShift)
        if parts.count != 1 { return "12 小时班一天只能上一个班，不能拼双班" }
        let s = parts[0]
        guard s == "白班" || s == "夜班" else { return nil }
        guard let date = DateUtil.date(from: dateStr) else { return nil }
        func shiftOn(_ offset: Int) -> String? {
            myDayOn(DateUtil.string(from: DateUtil.addingDays(date, offset)))?.shift
        }
        func has(_ sh: String?, _ name: String) -> Bool {
            guard let sh else { return false }
            return ShiftStyle.parts(of: sh).contains(name)
        }
        let prev = shiftOn(-1), prev2 = shiftOn(-2), next = shiftOn(1), next2 = shiftOn(2)
        if s == "夜班" && has(prev, "白班") { return "白班接夜班不行（08:00 上到次日 08:00，24 小时连轴）" }
        if s == "白班" && has(next, "夜班") { return "白班接夜班不行（08:00 上到次日 08:00，24 小时连轴）" }
        if s == "夜班" && (has(prev, "夜班") || has(next, "夜班")) { return "不能连上两个夜班" }
        if has(prev, "夜班") || has(prev2, "夜班") { return "夜班后要休 48 小时才能再上" }
        if s == "夜班" && (has(next, "白班") || has(next, "夜班") || has(next2, "白班") || has(next2, "夜班")) { return "夜班后要休 48 小时才能再上" }
        if let max = maxConsecutive12h {
            var run = 1
            var d = 1
            while d < 40 {
                let sh = shiftOn(-d)
                if sh == nil || sh == "休息" { break }
                run += 1; d += 1
            }
            d = 1
            while d < 40 {
                let sh = shiftOn(d)
                if sh == nil || sh == "休息" { break }
                run += 1; d += 1
            }
            if run > max { return "连上不能超过 \(max) 天" }
        }
        return nil
    }

    /// 某人替我上 addedShift：他那天变成什么、行不行、不行是为什么。
    /// ownDay：他那天；prevDay/nextDay：他前后天（邻日禁令用，取不到就当没有，服务端还会再验）。
    private func evalCover(ownDay: DaySchedule?, prevDay: DaySchedule?, nextDay: DaySchedule?, addedShift: String) -> CoverEval {
        guard let ownDay else {
            return CoverEval(eligible: false, reason: "排班还没读出来", ownShift: "", result: nil)
        }
        let ownShift = ownDay.shift
        if ownDay.onLeave == true {
            return CoverEval(eligible: false, reason: "这天请假", ownShift: ownShift, result: nil)
        }
        let ownComps = ShiftStyle.parts(of: ownShift)
        let addedComps = ShiftStyle.parts(of: addedShift)
        if ownComps.count >= 2 {
            return CoverEval(eligible: false, reason: "这天已经是双班了，顶不了", ownShift: ownShift, result: nil)
        }
        if let dup = addedComps.first(where: { ownComps.contains($0) }) {
            return CoverEval(eligible: false, reason: "这天已经是\(dup)，不能再顶\(dup)：一天不能上两个\(dup)", ownShift: ownShift, result: nil)
        }
        let union = ownComps + addedComps
        if union.count > 2 {
            return CoverEval(eligible: false, reason: "加上就是三个班了，顶不了", ownShift: ownShift, result: nil)
        }
        // 12h：一天只能上一个班（已有班就不能再加）；再按 12h 禁令验邻日。
        if banSet == "12h" {
            if ownShift != "休息" {
                return CoverEval(eligible: false, reason: "12 小时班一天只能上一个班", ownShift: ownShift, result: nil)
            }
            if let reason = validate12h(newShift: addedShift, dateStr: ownDay.date) {
                return CoverEval(eligible: false, reason: reason, ownShift: ownShift, result: nil)
            }
            return CoverEval(eligible: true, reason: nil, ownShift: ownShift, result: ShiftStyle.combined(union))
        }
        // 6h：只查一天不能上两个相同的班（前面已查过重复），不查邻日禁令。
        if banSet == "6h" {
            return CoverEval(eligible: true, reason: nil, ownShift: ownShift, result: ShiftStyle.combined(union))
        }
        // 8h（原有逻辑）。
        if union.contains("早班") && union.contains("日班") {
            return CoverEval(eligible: false, reason: "早班和日班不能一起上：0 点直接上到 16 点，不允许", ownShift: ownShift, result: nil)
        }
        if addedComps.contains("中班") {
            if let next = nextDay, ShiftStyle.parts(of: next.shift).contains("早班") {
                return CoverEval(eligible: false, reason: "次日是早班：中班 24:00 下班直接接次日早班，不允许", ownShift: ownShift, result: nil)
            }
        }
        if addedComps.contains("早班") {
            if let prev = prevDay, ShiftStyle.parts(of: prev.shift).contains("中班") {
                return CoverEval(eligible: false, reason: "前一天是中班：24:00 下班直接接这天早班，不允许", ownShift: ownShift, result: nil)
            }
        }
        return CoverEval(eligible: true, reason: nil, ownShift: ownShift, result: ShiftStyle.combined(union))
    }

    // MARK: 调班流程（空间那套）

    /// 还班日候选（1.2.9.001 第 31 条）：还班日那天我上的班 = 我自己那天的班 + 要还的那个班
    /// （addedShift：新调班是要还的班 = 这天我上的班；补填待还班是那次调班里我被替掉的班）。
    /// 要还的班是定的，每天最多一个结果，不用再选加哪个班；result 就是还班日那天我最终上的班。
    private func paybackCandidates(addedShift: String) -> [(date: String, weekday: String, myShift: String, result: String?, reason: String?)] {
        let comps = DateUtil.yearMonth(of: DateUtil.date(from: shownDay.date) ?? Date())
        let dim = DateUtil.daysInMonth(year: comps.year, month: comps.month)
        var out: [(date: String, weekday: String, myShift: String, result: String?, reason: String?)] = []
        for d in 1...dim {
            guard let dateObj = DateUtil.calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: d)) else { continue }
            let dateStr = DateUtil.string(from: dateObj)
            if dateStr == shownDay.date { continue }
            guard let myDay = myDayOn(dateStr) else { continue }
            if myDay.onLeave == true {
                out.append((dateStr, DateUtil.weekdayCN(of: dateObj), myDay.shift, nil, "这天请假"))
                continue
            }
            if myDay.partner != nil {
                out.append((dateStr, DateUtil.weekdayCN(of: dateObj), myDay.shift, nil, "我这天已有调班记录"))
                continue
            }
            let prev = myPrevDay(dateStr)
            let next = myNextDay(dateStr)
            let ev = evalCover(ownDay: myDay, prevDay: prev, nextDay: next, addedShift: addedShift)
            out.append((dateStr, DateUtil.weekdayCN(of: dateObj), myDay.shift, ev.result, ev.eligible ? nil : (ev.reason ?? "这天加不了班（禁令）")))
        }
        return out
    }

    /// 调班（1.2.9.001 第 31 条：空间那套，配对互换）。
    /// 第 1 步：选哪个班替我上这天（我这天休息，对方那天变成组合班）；
    /// 第 2 步：选还班日（本月任意一天，也可以先不填，待还班）；
    /// 第 3 步：预览两边（替班日我和对方、还班日我和对方），保存。
    /// 只写我自己的记录，不动对方账号（老爷 2026-11-26 08:59 定）。
    private var swapFlow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("调班（和别的班换）")
                .font(.headline)
            if shownDay.onLeave == true {
                Text("这天已请假，要调班先取消请假。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if shownDay.shift == "休息" {
                Text("这天我休息，没有班可调。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("我这天上 \(shownDay.shift)（\(ShiftStyle.timeRange(for: shownDay.shift))），调班后我这天休息。选一个班替我上这天的班：")
                    .font(.subheadline)
                Text("第 1 步 · 哪个班替我上这天")
                    .font(.subheadline).bold()
                if teamsRange == nil && teamsLoading {
                    ProgressView("正在读其他班组排班…")
                } else {
                    ForEach(swapPartnerCandidates, id: \.team) { c in
                        candidateCard(team: c.team, ev: c.ev, selected: swapPartner == c.team, resultLabel: "调完他这天") {
                            swapPartner = c.team
                            swapPartnerShift = c.ev.result
                            errorText = nil
                        }
                    }
                }
                if let partner = swapPartner, let pShift = swapPartnerShift {
                    Text("\(partner)班替我上这天：他那天上 \(pShift)（\(ShiftStyle.timeRange(for: pShift))）；我这天休息。")
                        .font(.subheadline)
                    Text("第 2 步 · 还班日（本月任意一天，也可以以后再定）")
                        .font(.subheadline).bold()
                    Button {
                        swapLater = true
                        swapPayback = nil
                        swapPaybackShift = nil
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("还班日先不填 · 以后再定")
                                .font(.subheadline).bold()
                                .foregroundColor(.primary)
                            Text("先把这天调了，这条记成「待还班」；过几天再到当天详情里补填还班日，一直不还就转为请假。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(swapLater ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(swapLater ? Color.accentColor : Color.clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(paybackCandidates(addedShift: shownDay.shift), id: \.date) { r in
                                paybackRow(r, isSelected: swapPayback == r.date) {
                                    swapLater = false
                                    swapPayback = r.date
                                    swapPaybackShift = r.result
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                    // 预览两边：保存前先看清楚替班日与还班日各变成什么。
                    swapPreview(partner: partner, partnerShift: pShift)
                    TextField("备注（可选）", text: $swapNote)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        Task { await submitSwap() }
                    } label: {
                        if swapSaving {
                            ProgressView()
                        } else {
                            Text("确认调班")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(swapSaving || (!swapLater && swapPayback == nil))
                }
            }
        }
        .padding(AppStyle.cardPadding)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(AppStyle.cardRadius)
        .task { await loadTeamsRange() }
    }

    private func candidateCard(team: String, ev: CoverEval, selected: Bool, resultLabel: String, onPick: @escaping () -> Void) -> some View {
        Button(action: onPick) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(team)班")
                        .font(.headline)
                    Spacer()
                    Text(ev.eligible ? "可以" : "不行")
                        .font(.subheadline).bold()
                        .foregroundColor(ev.eligible ? .green : .secondary)
                }
                Text("这天本来：\(ev.ownShift.isEmpty ? "—" : ev.ownShift)\(ev.ownShift.isEmpty || ev.ownShift == "休息" ? "" : " \(ShiftStyle.timeRange(for: ev.ownShift))")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if ev.eligible, let result = ev.result {
                    if ev.ownShift == "休息" {
                        Text("\(resultLabel)：只上一个班 · \(result)\n这天本来休息，替班后就上这一个班（\(ShiftStyle.timeRange(for: result))），不算双班")
                            .font(.subheadline)
                    } else {
                        Text("\(resultLabel)：\(result)\n\(ShiftStyle.timeRange(for: result))")
                            .font(.subheadline)
                    }
                } else {
                    Text(ev.reason ?? "不行")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(selected ? Color.accentColor.opacity(0.12) : Color(.systemBackground))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
            .opacity(ev.eligible ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!ev.eligible)
    }

    /// 还班日的一行：那天我本来上什么、还班后变成什么（要还的班是定的，只有一个结果）。
    private func paybackRow(_ r: (date: String, weekday: String, myShift: String, result: String?, reason: String?), isSelected: Bool, onSelect: @escaping () -> Void) -> some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(r.date) \(r.weekday)")
                        .font(.subheadline)
                    Text("我本来 \(r.myShift)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let result = r.result {
                        Text("还班后我上 \(result)（\(ShiftStyle.timeRange(for: result))）")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(r.reason ?? "不行")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text(r.result == nil ? "不行" : "可以")
                    .font(.caption).bold()
                    .foregroundColor(r.result == nil ? .secondary : .green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(r.result == nil)
    }

    /// 保存前预览（两边都预览：替班日我和对方、还班日我和对方）。
    private func swapPreview(partner: String, partnerShift: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("保存前预览")
                .font(.subheadline).bold()
            Text("替班日 \(shownDay.date)：我 \(shownDay.shift) → 休息；\(partner)班替我上 \(partnerShift)（\(ShiftStyle.timeRange(for: partnerShift))）。")
                .font(.subheadline)
            if swapLater {
                Text("还班日：还没定。先这样保存，这条记成「待还班」；以后在当天详情里补填还班日，一直不还就转为请假（这天按请假算）。")
                    .font(.subheadline)
            } else if let payback = swapPayback, let pbShift = swapPaybackShift {
                Text("还班日 \(payback)：我 \(myDayOn(payback)?.shift ?? "") → \(pbShift)（\(ShiftStyle.timeRange(for: pbShift))）；\(partner)班那天休息。")
                    .font(.subheadline)
            } else {
                Text("还班日：还没选。选一天当还班日，或者点「还班日先不填」。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08))
        .cornerRadius(10)
    }

    /// 待还班那次调班里、我被替掉的班（还班日要还的就是这个班）：
    /// 对方那天最终上的班 partnerShift，去掉对方自己那天的班。
    /// 对方自己那天的班取派生日的 baseShift（对方没有自己的调班记录时就是他的班；
    /// 对方要是有自己的记录，这里的数可能不准，服务端提交时还会再验、报错会原样显示）。
    private var coveredShift: String? {
        guard let partner = shownDay.partner, let pShift = shownDay.partnerShift else { return nil }
        let own = teamDay(partner, shownDay.date)?.baseShift
            ?? ScheduleCalculator.baseShift(team: partner, date: DateUtil.date(from: shownDay.date) ?? Date(), rotation: store.rotation)
        return ShiftStyle.subtract(combo: pShift, own: own)
    }

    /// 补填还班日（1.2.9.001 第 31 条）：只选一天。
    /// 那天我上的班是定的——我自己那天的班 + 那次调班里我被替掉的班，并成组合班，不用再选。
    private var fillPaybackFlow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("补填还班日")
                .font(.headline)
            if let partner = shownDay.partner, let covered = coveredShift {
                Text("给 \(shownDay.date) 那次调班补一个还班日（本月任意一天）：那天我替 \(partner)班上他那天的班（那次调班里我被替掉的是 \(covered)）。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("给 \(shownDay.date) 那次调班补一个还班日（本月任意一天）。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let covered = coveredShift {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(paybackCandidates(addedShift: covered), id: \.date) { r in
                            paybackRow(r, isSelected: fillPayback == r.date) {
                                fillPayback = r.date
                                fillPaybackShift = r.result
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
                if let payback = fillPayback, let result = fillPaybackShift {
                    Text("还班日 \(payback)：我那天上 \(result)（\(ShiftStyle.timeRange(for: result))）。")
                        .font(.subheadline)
                }
            } else {
                Text("这条调班记录不完整（没有对方班组），补不上还班日。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Button {
                Task { await submitFillPayback() }
            } label: {
                Text("确认补填")
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(fillPayback == nil || fillPaybackShift == nil)
        }
        .padding(AppStyle.cardPadding)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(AppStyle.cardRadius)
        .task { await loadTeamsRange() }
    }

    // MARK: 请假

    private var leaveForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("请假")
                .font(.headline)
            if shownDay.onLeave == true {
                Text("已请假（\(shownDay.leaveType ?? "请假")）\(shownDay.leaveNote.map { " · \($0)" } ?? "")")
                    .font(.subheadline)
                if let partner = shownDay.partner, !partner.isEmpty {
                    Text("顶岗：\(partner)班上 \(shownDay.partnerShift ?? "")。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else if shownDay.shift != "休息" {
                    Text("还没安排顶岗。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("安排顶岗") {
                        leaveCoverPartner = nil
                        Task { await loadTeamsRange() }
                    }
                    .buttonStyle(.bordered)
                    if teamsRange != nil {
                        ForEach(leaveCoverCandidates, id: \.team) { c in
                            candidateCard(team: c.team, ev: c.ev, selected: leaveCoverPartner == c.team, resultLabel: "顶岗后他这天") {
                                leaveCoverPartner = c.team
                            }
                        }
                        if let partner = leaveCoverPartner, let result = leaveCoverCandidates.first(where: { $0.team == partner })?.ev.result {
                            Text("\(partner)班顶岗：他这天上 \(result)（\(ShiftStyle.timeRange(for: result))）；我这天请假休息。")
                                .font(.subheadline)
                            Button("确认安排顶岗") { Task { await submitLeaveCover() } }
                                .buttonStyle(.borderedProminent)
                                .frame(maxWidth: .infinity)
                        }
                    } else if teamsLoading {
                        ProgressView("正在读其他班组排班…")
                    }
                }
                Picker("类型", selection: $leaveType) {
                    ForEach(ShiftStyle.leaveTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                TextField("备注（可选）", text: $leaveNote)
                    .textFieldStyle(.roundedBorder)
                Button("保存修改") { Task { await submitLeave() } }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            } else {
                Picker("请假类型", selection: $leaveType) {
                    ForEach(ShiftStyle.leaveTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                TextField("备注（可选）", text: $leaveNote)
                    .textFieldStyle(.roundedBorder)
                if shownDay.shift != "休息" {
                    Text("安排顶岗（可选）：选一个人替我上这天的班。")
                        .font(.subheadline).bold()
                    Button("选顶岗的人") {
                        leaveCoverPartner = nil
                        Task { await loadTeamsRange() }
                    }
                    .buttonStyle(.bordered)
                    if teamsRange != nil {
                        ForEach(leaveCoverCandidates, id: \.team) { c in
                            candidateCard(team: c.team, ev: c.ev, selected: leaveCoverPartner == c.team, resultLabel: "顶岗后他这天") {
                                leaveCoverPartner = c.team
                            }
                        }
                    } else if teamsLoading {
                        ProgressView("正在读其他班组排班…")
                    }
                }
                Button("确认请假") { Task { await submitLeaveWithCover() } }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(AppStyle.cardPadding)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(AppStyle.cardRadius)
    }

    /// 请假顶岗的候选：除我班外的三个班，各自替我上我这天的班行不行。
    /// 哪个班能替我上这天（调班第 1 步与请假顶岗共用）：对方那天是派生出来的
    /// （teamsRange：我的调班记录已算进去），加上我这天的班（addedShift）后变成什么、行不行。
    private func coverCandidates(addedShift: String) -> [(team: String, ev: CoverEval)] {
        TeamInfo.allTeams.filter { $0 != store.myTeam }.map { team in
            let own = teamDay(team, shownDay.date)
            let prev = prevDayOf(team: team, date: shownDay.date)
            let next = nextDayOf(team: team, date: shownDay.date)
            return (team, evalCover(ownDay: own, prevDay: prev, nextDay: next, addedShift: addedShift))
        }
    }

    private var leaveCoverCandidates: [(team: String, ev: CoverEval)] {
        coverCandidates(addedShift: shownDay.shift)
    }

    /// 调班第 1 步的候选：哪个班替我上这天（我这天休息，对方那天变成组合班）。
    private var swapPartnerCandidates: [(team: String, ev: CoverEval)] {
        coverCandidates(addedShift: shownDay.shift)
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
        .padding(AppStyle.cardPadding)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(AppStyle.cardRadius)
    }

    // MARK: 加班

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
        .padding(AppStyle.cardPadding)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(AppStyle.cardRadius)
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

    // MARK: 提交

    private func submitSwap() async {
        guard let partner = swapPartner, let pShift = swapPartnerShift else { return }
        errorText = nil
        doneMessage = nil
        swapSaving = true
        defer { swapSaving = false }
        do {
            let payback = swapLater ? nil : swapPayback
            let pbShift = swapLater ? nil : swapPaybackShift
            _ = try await store.submitSwap(date: shownDay.date, partner: partner, partnerShift: pShift,
                                           note: swapNote.isEmpty ? nil : swapNote,
                                           paybackDate: payback, paybackMyShift: pbShift)
            doneMessage = payback == nil ? "调班已保存（待还班，以后再补还班日）" : "调班已保存"
            showSwapFlow = false
            swapPartner = nil
            swapPartnerShift = nil
            swapPayback = nil
            swapPaybackShift = nil
            swapLater = false
            swapNote = ""
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func submitFillPayback() async {
        guard let payback = fillPayback, let myShift = fillPaybackShift else { return }
        errorText = nil
        doneMessage = nil
        do {
            try await store.fillSwapPayback(coverDate: shownDay.date, paybackDate: payback, myShift: myShift)
            doneMessage = "还班日已补填：\(payback)"
            showFillPayback = false
            fillPayback = nil
            fillPaybackShift = nil
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func convertToLeave() async {
        errorText = nil
        doneMessage = nil
        do {
            try await store.convertSwapToLeave(date: shownDay.date, type: leaveType, note: leaveNote.isEmpty ? nil : leaveNote)
            doneMessage = "已转为请假（对方的顶岗保留）"
            showConvertLeave = false
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func cancelSwap() async {
        errorText = nil
        doneMessage = nil
        do {
            try await store.cancelSwap(date: shownDay.date)
            doneMessage = "调班已取消，两边一起恢复原排班"
            showDeleteSwap = false
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func submitLeave() async {
        errorText = nil
        doneMessage = nil
        await store.submitLeave(date: shownDay.date, type: leaveType,
                                note: leaveNote.isEmpty ? nil : leaveNote)
        doneMessage = "请假已保存"
        showLeaveForm = false
    }

    private func submitLeaveWithCover() async {
        errorText = nil
        doneMessage = nil
        await store.submitLeave(date: shownDay.date, type: leaveType,
                                note: leaveNote.isEmpty ? nil : leaveNote)
        if let partner = leaveCoverPartner,
           let result = leaveCoverCandidates.first(where: { $0.team == partner })?.ev.result {
            do {
                try await store.submitLeaveCover(date: shownDay.date, partner: partner, partnerShift: result,
                                                 note: leaveNote.isEmpty ? nil : leaveNote)
                doneMessage = "请假已保存，已安排 \(partner) 班顶岗"
            } catch {
                errorText = "请假已保存，但顶岗没安排上：" + ((error as? APIError)?.message ?? error.localizedDescription)
            }
        } else {
            doneMessage = "请假已保存"
        }
        showLeaveForm = false
        leaveCoverPartner = nil
    }

    private func submitLeaveCover() async {
        guard let partner = leaveCoverPartner,
              let result = leaveCoverCandidates.first(where: { $0.team == partner })?.ev.result else { return }
        errorText = nil
        doneMessage = nil
        do {
            try await store.submitLeaveCover(date: shownDay.date, partner: partner, partnerShift: result,
                                             note: leaveNote.isEmpty ? nil : leaveNote)
            doneMessage = "已安排 \(partner) 班顶岗"
            leaveCoverPartner = nil
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
        await store.submitLeaveRange(start: DateUtil.string(from: rangeStart),
                                     end: DateUtil.string(from: rangeEnd),
                                     type: leaveType,
                                     note: leaveNote.isEmpty ? nil : leaveNote)
        doneMessage = "请假已保存"
        showLeaveRangeForm = false
    }

    private func cancelLeave() async {
        errorText = nil
        doneMessage = nil
        await store.cancelLeave(date: shownDay.date)
        doneMessage = "请假已取消（顶岗一起取消）"
        showDeleteLeave = false
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
