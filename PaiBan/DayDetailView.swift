import SwiftUI
import UIKit // 1.3.2.005：保存成功轻震动用 UIImpactFeedbackGenerator（iOS 16 可用，不用 iOS 17 的 sensoryFeedback）

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
    @Environment(AppStore.self) private var store: AppStore
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
    /// 请假方式：单日 / 多日（1.3.2.018：请一段假收进请假卡内，不再是独立入口）。
    @State private var leaveMode = "单日"
    /// 旧记录里的「年假」读出来时归一到「年休假」（与 leaveTypes 合并去重配套）。
    @State private var leaveType = "年休假"
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

    // MARK: 自己改排班（点某天直接改这天的班，走单日覆盖接口）

    @State private var showEditShiftForm = false
    /// 正在改成的班次（默认当天现在的班次；现在不是这 5 个之一时默认日班）。
    @State private var editShiftSelection = "日班"
    @State private var editShiftSaving = false

    @State private var errorText: String?
    @State private var doneMessage: String?

    /// 连班禁令弹窗（1.3.2.018：黄色大框收进操作栏右上角「? 规则」按钮，点开弹窗看）。
    @State private var showBanRules = false

    /// sheet 高度自适应内容（1.1.4）：原来 sheet 默认近乎全屏，内容只有上半截、
    /// 下面留大片空白。没开表单时用 .medium（半屏刚好装下标题+详情+提示+按钮），
    /// 点开调班/请假/记加班任一表单时切到 .large；表单关了再缩回 .medium。
    @State private var sheetDetent: PresentationDetent = .medium
    private var formOpen: Bool {
        showSwapFlow || showFillPayback || showLeaveForm || showOvertimeForm || showEditShiftForm
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    otherTeamsCard
                    if !canEdit {
                        readOnlyNote
                    }
                    if let errorText {
                        Text(errorText)
                            .appFont(size: AppFont.bodySmall)
                            .foregroundColor(.red)
                    }
                    if let doneMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .iconAligned()
                            Text(doneMessage)
                                .appFont(size: AppFont.bodySmall)
                                .foregroundColor(.green)
                        }
                        .fadeIn()
                        .task(id: doneMessage) {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            if self.doneMessage == doneMessage { self.doneMessage = nil }
                        }
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
                        if showOvertimeForm { overtimeForm }
                        if showEditShiftForm { editShiftForm }
                    }
                }
                .padding(AppStyle.pagePadding)
            }
            // 1.3.2.018：Sheet 背景统一浅灰 #F4F6F9（与主页面画布同款），内部卡片纯白。
            .background(sheetBackground)
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

    /// Sheet 背景（1.3.2.018）：浅灰 #F4F6F9，与主页面画布统一；内部模块用纯白圆角卡片。
    private var sheetBackground: Color {
        AppStyle.adaptive(light: UIColor(red: 0.957, green: 0.965, blue: 0.976, alpha: 1),
                          dark: UIColor(red: 0.043, green: 0.043, blue: 0.059, alpha: 1))
    }

    /// 紧凑头部卡（1.3.2.018：原来 titleCard + detailRows 两张卡合并）：
    /// 左侧「日期 + 班组 · 班次 时间」，右侧「预估工资 + 金额」；有调班时追加一行小字
    /// 「原班次：xx」。去掉重复：班次名不再写三遍，预估不再写两遍（值里不带「预估」前缀）。
    /// 节假日 / 请假 / 加班只在存在时各占一行；调班的对方班组与还班日细节在下面的
    /// swapStatusCard 里，不在这里重复。
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(DateUtil.fullFormatter.string(from: DateUtil.date(from: shownDay.date) ?? Date()) + " " + shownDay.weekdayText)
                        .appFont(size: AppFont.headline, weight: 600)
                    Text(teamShiftLine)
                        .appFont(size: AppFont.bodySmall)
                        .foregroundColor(.secondary)
                    if let original = originalShiftText {
                        Text("原班次：\(original)")
                            .appFont(size: AppFont.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if let amount = estimateAmountText {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("预估工资")
                            .appFont(size: AppFont.caption)
                            .foregroundColor(.secondary)
                        Text(amount)
                            .appFont(size: AppFont.headline, weight: 600)
                            .monospacedDigit()
                    }
                }
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
        }
        .padding(AppStyle.cardPadding)
        .background(AppStyle.surface1)
        .cornerRadius(AppStyle.cardRadius)
    }

    /// 左侧第二行：班组 · 班次 时间。休息只写「休息」，不重复写时间。
    private var teamShiftLine: String {
        let team = shownDay.team ?? store.myTeam
        if shownDay.isRest { return "\(team)班 · 休息" }
        return "\(team)班 · \(shownDay.shift) \(shownDay.displayTime)"
    }

    /// 有调班时的小字「原班次：xx」：只在已调班且原班次与现在不同时显示。
    private var originalShiftText: String? {
        guard shownDay.overridden == true,
              let base = shownDay.baseShift, !base.isEmpty,
              base != shownDay.shift else { return nil }
        return base
    }

    /// 右侧预估工资金额（只看自己班 + 有工资权限才显示；休息/请假不显示金额，
    /// 状态已在左侧班次行与请假行里写明）。1.3.2.018：值里不再带「预估」前缀。
    private var estimateAmountText: String? {
        guard (shownDay.team ?? store.myTeam) == store.myTeam && store.payAccess else { return nil }
        if shownDay.onLeave == true { return nil }
        let inputs = store.estimateInputs(for: shownDay.date)
        let est = PayCalc.todayEstimate(shift: shownDay.shift, earlyRate: inputs.earlyRate, midRate: inputs.midRate, inputs: inputs.inputs)
        if est.isRest { return nil }
        let suffix = est.isTriple ? "（三薪）" : (est.isOvertime ? "（加班）" : "")
        return MoneyUtil.money(est.total) + suffix
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .monospacedDigit()
            Spacer()
        }
        .appFont(size: AppFont.bodySmall)
    }

    /// 其他班次：选中这天，其他三个班组按 8 天一轮基础排班算出的班次（横向一排小 chip）。
    /// 只按基础轮换算，不含调班/请假——App 里没有其他用户的调班记录。
    /// 正在看的班组不列在这里，它的班次已在上面头部卡里显示。
    /// 1.3.2.018：色块降饱和——浅底深字（班次色只做浅底 tint + 深色字，不再用整块饱和色）。
    /// 1.3.2.019：休息改回浅青——主日历 DayCell 的「休」是浅青（ShiftStyle teal 0.14 底 +
    /// 深青字），全站休的既定颜色；.018 改成的浅灰跟主日历不统一，这次改回浅青。
    private var otherTeamsCard: some View {
        HStack(spacing: 8) {
            Text("其他班次")
                .appFont(size: AppFont.caption)
                .foregroundColor(.secondary)
            ForEach(otherTeams, id: \.team) { item in
                otherTeamChip(team: item.team, shift: item.shift)
            }
        }
        .padding(.horizontal, AppStyle.cardPadding)
        .padding(.vertical, 10)
        .background(AppStyle.surface1)
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

    /// 一个班组的 chip：班组名 + 班次。1.3.2.018：降饱和——浅底深字：
    /// 上班用班次色的浅底 tint + 班次色深字，不再整块饱和色白字；
    /// 休息也走 ShiftStyle（浅青底 + 深青字，跟主日历的「休」一致）。
    private func otherTeamChip(team: String, shift: String) -> some View {
        HStack(spacing: 4) {
            Text("\(team)班")
                .bold()
            Text(shift == "休息" ? "休" : shift)
        }
        .appFont(size: AppFont.bodySmall)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .foregroundColor(ShiftStyle.color(for: shift))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(ShiftStyle.background(for: shift))
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

    /// 只读提示：看别的班的日历时显示，改数据的入口全部不出现。
    /// 1.3.2.016（Gemini 升级版规格的 Toast 改成本地化做法）：看别班时调班/请假
    /// 入口根本不出现，没有能挂 Toast 的编辑入口；这条只读提示就是引导本身，
    /// 这里直接给一个「切回自己班」按钮——点一下回自己班、关掉本页，再点当天就能改。
    private var readOnlyNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("正在看 \(shownDay.team ?? store.viewTeam) 班的日历，只能看，不能改。切回自己班（\(store.myTeam) 班）才能调班、请假、记加班。")
                .appFont(size: AppFont.bodySmall)
                .foregroundColor(.secondary)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                store.viewTeam = store.myTeam
                dismiss()
            } label: {
                Text("切回 \(store.myTeam)班")
                    .appFont(size: AppFont.bodySmall, weight: 600)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppStyle.navyAdaptive)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(AppStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppStyle.surface1)
        .cornerRadius(AppStyle.cardRadius)
    }

    /// 手动排班：点一天直接设当天班次（日/中/早/休），不用走调班。
    /// 设完立刻保存，日历与工资跟着变。
    @State private var manualShiftSaving = false
    private var manualShiftPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("设当天班次")
                .appFont(size: AppFont.headline, weight: 600)
            Text("手动排班没有周期规律，点一天设当天班次；没设的当天算休息。")
                .appFont(size: AppFont.bodySmall)
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
        .background(AppStyle.surface1)
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

    // MARK: 自己改排班（点某天直接改这天的班，走单日覆盖接口）

    /// 改排班的可选班次：5 个（没有"休息"，想恢复原班次用已有的「删除这次调班」）。
    private var editShiftOptions: [String] { ["日班", "中班", "早班", "早中班", "日中班"] }

    /// 这天有没有对方班组的调班记录：partner 不为空，或是还班日/替班日
    /// （paybackDate/coverDate）。有就不能直接改排班，先取消调班再改。
    /// 普通单边覆盖（partner 为空）可以直接覆盖重改。
    private var hasPartnerSwap: Bool {
        if let partner = shownDay.partner, !partner.isEmpty { return true }
        return shownDay.paybackDate != nil || shownDay.coverDate != nil
    }

    /// 点「改排班」：请假那天、已有对方班组调班记录那天先拦住（只提示，不开表单）；
    /// 其余直接开表单，默认选中当天现在的班次。
    private func openEditShiftForm() {
        resetFlowStates()
        if shownDay.onLeave == true {
            errorText = "这天请假了，先取消请假再改"
            return
        }
        if hasPartnerSwap {
            errorText = "这天已有调班（对方班组），先取消调班再改"
            return
        }
        editShiftSelection = editShiftOptions.contains(shownDay.shift) ? shownDay.shift : "日班"
        showEditShiftForm = true
    }

    /// 改排班表单：5 个班次选项（默认当天现在的班次）+ 确认修改。
    /// 守规矩：选的和现在一样不让改（按钮直接置灰）；等服务端回话再报成功，失败显示服务端原话；
    /// 成功后刷新当月日历和工资页，详情里头部卡的班次跟着变成改后的班。
    /// 1.3.2.018：撤销提示只在当天已有改班/调班记录时才显示（没调过班的日子根本没有
    /// 「删除这次调班」入口，提示是幽灵文案）；确认修改用通栏主按钮。
    private var editShiftForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("改排班")
                .appFont(size: AppFont.headline, weight: 600)
            Text("现在这天是 \(shownDay.shift)。改成：")
                .appFont(size: AppFont.bodySmall)
                .foregroundColor(.secondary)
            ForEach(editShiftOptions, id: \.self) { shift in
                editShiftOptionRow(shift)
            }
            if shownDay.overridden == true {
                Text("没有「休息」：想恢复原来的班，用下面的「删除这次调班」。")
                    .appFont(size: AppFont.caption)
                    .foregroundColor(.secondary)
            }
            submitButton("确认修改", loading: editShiftSaving, disabled: editShiftSelection == shownDay.shift) {
                Task { await submitEditShift() }
            }
        }
        .padding(AppStyle.cardPadding)
        .background(AppStyle.surface1)
        .cornerRadius(AppStyle.cardRadius)
    }

    private func editShiftOptionRow(_ shift: String) -> some View {
        Button {
            editShiftSelection = shift
            errorText = nil
        } label: {
            HStack {
                Text(shift)
                    .appFont(size: AppFont.bodySmall, weight: 700)
                    .foregroundColor(.primary)
                Text(ShiftStyle.timeRange(for: shift))
                    .appFont(size: AppFont.bodySmall)
                    .foregroundColor(.secondary)
                Spacer()
                if editShiftSelection == shift {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(editShiftSelection == shift ? Color.accentColor.opacity(0.12) : AppStyle.surface2)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func submitEditShift() async {
        if editShiftSelection == shownDay.shift {
            errorText = "跟现在这天的班一样，不用改"
            return
        }
        errorText = nil
        doneMessage = nil
        editShiftSaving = true
        defer { editShiftSaving = false }
        do {
            try await store.submitDayShift(date: shownDay.date, shift: editShiftSelection)
            doneMessage = "这天已改成 \(editShiftSelection)"
            showEditShiftForm = false
        } catch {
            errorText = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    // MARK: 操作入口

    /// 当前激活的操作（1.3.2.018）：哪个表单开着，操作栏就高亮哪个按钮，唯一高亮；
    /// 没开表单时都不高亮。原来调班常驻深色、高亮卡死不动的 bug 就在这里。
    private var activeAction: String? {
        if showSwapFlow { return "调班" }
        if showLeaveForm { return "请假" }
        if showOvertimeForm { return "记加班" }
        if showEditShiftForm { return "改排班" }
        return nil
    }

    /// 旧记录里的「年假」归一到「年休假」（leaveTypes 已合并去重，picker 里不再有「年假」，
    /// 直接用旧值会让分段选择器没有选中项）。
    private func normalizedLeaveType(_ stored: String?) -> String {
        guard let stored, !stored.isEmpty else { return "年休假" }
        return stored == "年假" ? "年休假" : stored
    }

    /// 四个核心操作单行 4 列分段条（1.3.2.018：请一段假已收进请假卡内做单日/多日切换，
    /// 外层只剩调班 / 请假 / 记加班 / 改排班），一次只开一个表单；当前激活的唯一高亮；
    /// 已有调班/请假时，取消类操作单独放一行红色文字按钮。
    /// 连班禁令收进右上角小「? 规则」按钮，点开弹窗看，不再占一整张黄卡。
    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Button {
                    showBanRules = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "questionmark.circle")
                        Text("规则")
                    }
                    .appFont(size: AppFont.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppStyle.surface1)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                actionButton("调班", prominent: activeAction == "调班") {
                    resetFlowStates()
                    if shownDay.overridden == true && shownDay.onLeave != true {
                        // 1.3.2.021：已有调班再点调班，不开表单，轻震一下 + 提示一行字。
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        errorText = "已经进行调班了，如果需要再次更改，请删除此次调班，或者直接更改排班"
                    } else {
                        showSwapFlow.toggle()
                    }
                }
                actionButton("请假", prominent: activeAction == "请假") {
                    leaveType = normalizedLeaveType(shownDay.leaveType)
                    leaveNote = shownDay.leaveNote ?? ""
                    leaveCoverPartner = nil
                    leaveMode = "单日"
                    rangeStart = DateUtil.date(from: shownDay.date) ?? Date()
                    rangeEnd = rangeStart
                    resetFlowStates()
                    showLeaveForm.toggle()
                }
                actionButton("记加班", prominent: activeAction == "记加班") {
                    if let ot = store.overtime(for: shownDay.date) {
                        overtimeStart = timeDate(ot.start) ?? overtimeStart
                        overtimeEnd = timeDate(ot.end) ?? overtimeEnd
                        overtimeNote = ot.note ?? ""
                    }
                    resetFlowStates()
                    showOvertimeForm.toggle()
                }
                // 自己改排班：和调班/请假并列。手动排班时不出现——那套已有上面的
                // 「设当天班次」，走的是本机逐日设定；再叠一个服务端覆盖会打架
                // （改完 picker 再设会被覆盖记录盖住，看着像没改）。
                if !store.rotation.isManual {
                    actionButton("改排班", prominent: activeAction == "改排班") {
                        openEditShiftForm()
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: activeAction)
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
                .appFont(size: AppFont.bodySmall)
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
        .alert("连班禁令", isPresented: $showBanRules) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(banHintText)
        }
    }

    /// 四个操作按钮共用：等宽等高（48 高、圆角 12、撑满各自一格）。
    /// 1.3.2.018：同一个 Button、底色随 prominent 条件变（激活藏青底白字、其余浅灰底深字），
    /// 不再是主/次两种不同视图，这样高亮切换时颜色能平滑过渡、不会跳变。
    private func actionButton(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: AppStyle.buttonHeight)
                .background(prominent ? AppStyle.navyAdaptive : AppStyle.surface1)
                .foregroundColor(prominent ? .white : .primary)
                .cornerRadius(AppStyle.buttonRadius)
        }
        .buttonStyle(.plain)
    }

    /// 提交按钮（1.3.2.018）：通栏主按钮——撑满卡片内边距、46pt 高、圆角 12、藏青底白字；
    /// loading 时显示白色转圈，disabled 时底色变灰、不可点。
    private func submitButton(_ title: String, loading: Bool = false, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if loading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(disabled || loading ? Color(.systemGray4) : AppStyle.navyAdaptive)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(disabled || loading)
    }

    private func resetFlowStates() {
        showSwapFlow = false
        showFillPayback = false
        showLeaveForm = false
        showOvertimeForm = false
        showEditShiftForm = false
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
                    .appFont(size: AppFont.bodySmall)
                Text("我这天上 \(shownDay.shift)\(shownDay.partner.map { "，\($0)班这天休息" } ?? "")。")
                    .appFont(size: AppFont.bodySmall)
                    .foregroundColor(.secondary)
            } else {
                if let partner = shownDay.partner, let pShift = shownDay.partnerShift {
                    Text("已调班：我这天休息，\(partner)班替我上 \(pShift)\(shownDay.note.map { "（\($0)）" } ?? "")。")
                        .appFont(size: AppFont.bodySmall)
                } else {
                    Text("已调班：我这天改成 \(shownDay.shift)\(shownDay.note.map { "（\($0)）" } ?? "")。")
                        .appFont(size: AppFont.bodySmall)
                }
                if let payback = shownDay.paybackDate {
                    Text("还班日：\(payback)\(paybackShiftText(payback))。")
                        .appFont(size: AppFont.bodySmall)
                        .foregroundColor(.secondary)
                } else {
                    Text("还班日还没定（待还班）。过几天再补填还班日，一直不还就转为请假。")
                        .appFont(size: AppFont.bodySmall)
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
                                .appFont(size: AppFont.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 12) {
                                Button("确认转请假") { Task { await convertToLeave() } }
                                    .buttonStyle(.borderedProminent)
                                Button("取消") { showConvertLeave = false }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .padding(10)
                        .background(AppStyle.surface2)
                        .cornerRadius(10)
                    }
                }
            }
        }
        .padding(AppStyle.cardPadding)
        .background(AppStyle.surface1)
        .cornerRadius(AppStyle.cardRadius)
    }

    private var deleteSwapConfirm: some View {
        HStack(spacing: 12) {
            Text("删除这次调班，两边一起恢复原排班（还班日也一起删）。")
                .appFont(size: AppFont.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("确认删除") { Task { await cancelSwap() } }
                .foregroundColor(.red)
            Button("取消") { showDeleteSwap = false }
        }
        .padding(10)
        .background(AppStyle.surface1)
        .cornerRadius(10)
    }

    private var deleteLeaveConfirm: some View {
        HStack(spacing: 12) {
            Text(shownDay.partner != nil ? "确认取消？请假和顶岗一起取消。" : "确认取消请假？")
                .appFont(size: AppFont.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("确认取消") { Task { await cancelLeave() } }
                .foregroundColor(.red)
            Button("取消") { showDeleteLeave = false }
        }
        .padding(10)
        .background(AppStyle.surface1)
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
            Text("调班")
                .appFont(size: AppFont.headline, weight: 600)
            if shownDay.onLeave == true {
                Text("这天已请假，要调班先取消请假。")
                    .appFont(size: AppFont.bodySmall)
                    .foregroundColor(.secondary)
            } else if shownDay.shift == "休息" {
                Text("这天我休息，没有班可调。")
                    .appFont(size: AppFont.bodySmall)
                    .foregroundColor(.secondary)
            } else {
                Text("我这天上 \(shownDay.shift)（\(ShiftStyle.timeRange(for: shownDay.shift))），调班后我这天休息。选一个班替我上这天的班：")
                    .appFont(size: AppFont.bodySmall)
                Text("第一步：选择替班班组")
                    .appFont(size: AppFont.bodySmall, weight: 700)
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
                        .appFont(size: AppFont.bodySmall)
                    Text("第 2 步 · 还班日（本月任意一天，也可以以后再定）")
                        .appFont(size: AppFont.bodySmall, weight: 700)
                    Button {
                        swapLater = true
                        swapPayback = nil
                        swapPaybackShift = nil
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("还班日先不填 · 以后再定")
                                .appFont(size: AppFont.bodySmall, weight: 700)
                                .foregroundColor(.primary)
                            Text("先把这天调了，这条记成「待还班」；过几天再到当天详情里补填还班日，一直不还就转为请假。")
                                .appFont(size: AppFont.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(swapLater ? Color.accentColor.opacity(0.12) : AppStyle.surface2)
                        .cornerRadius(10)
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
                        .textFieldStyle(.plain)
                        .fieldBackground()
                    submitButton("确认调班", loading: swapSaving, disabled: !swapLater && swapPayback == nil) {
                        Task { await submitSwap() }
                    }
                }
            }
        }
        .padding(AppStyle.cardPadding)
        .background(AppStyle.surface1)
        .cornerRadius(AppStyle.cardRadius)
        .task { await loadTeamsRange() }
    }

    private func candidateCard(team: String, ev: CoverEval, selected: Bool, resultLabel: String, onPick: @escaping () -> Void) -> some View {
        Button(action: onPick) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(team)班")
                        .appFont(size: AppFont.headline, weight: 600)
                    Spacer()
                    Text(ev.eligible ? "可选" : "冲突")
                        .appFont(size: AppFont.bodySmall, weight: 700)
                        .foregroundColor(ev.eligible ? .green : .secondary)
                }
                Text("原排班：\(ev.ownShift.isEmpty ? "—" : ev.ownShift)\(ev.ownShift.isEmpty || ev.ownShift == "休息" ? "" : " \(ShiftStyle.timeRange(for: ev.ownShift))")")
                    .appFont(size: AppFont.bodySmall)
                    .foregroundColor(.secondary)
                if ev.eligible, let result = ev.result {
                    if ev.ownShift == "休息" {
                        Text("\(resultLabel)：只上一个班 · \(result)\n这天本来休息，替班后就上这一个班（\(ShiftStyle.timeRange(for: result))），不算双班")
                            .appFont(size: AppFont.bodySmall)
                    } else {
                        Text("\(resultLabel)：\(result)\n\(ShiftStyle.timeRange(for: result))")
                            .appFont(size: AppFont.bodySmall)
                    }
                } else {
                    Text(ev.reason ?? "不行")
                        .appFont(size: AppFont.bodySmall)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(selected ? Color.accentColor.opacity(0.12) : AppStyle.surface2)
            .cornerRadius(10)
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
                        .appFont(size: AppFont.bodySmall)
                    Text("我本来 \(r.myShift)")
                        .appFont(size: AppFont.caption)
                        .foregroundColor(.secondary)
                    if let result = r.result {
                        Text("还班后我上 \(result)（\(ShiftStyle.timeRange(for: result))）")
                            .appFont(size: AppFont.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(r.reason ?? "不行")
                            .appFont(size: AppFont.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text(r.result == nil ? "不行" : "可以")
                    .appFont(size: AppFont.caption, weight: 700)
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
                .appFont(size: AppFont.bodySmall, weight: 700)
            Text("替班日 \(shownDay.date)：我 \(shownDay.shift) → 休息；\(partner)班替我上 \(partnerShift)（\(ShiftStyle.timeRange(for: partnerShift))）。")
                .appFont(size: AppFont.bodySmall)
            if swapLater {
                Text("还班日：还没定。先这样保存，这条记成「待还班」；以后在当天详情里补填还班日，一直不还就转为请假（这天按请假算）。")
                    .appFont(size: AppFont.bodySmall)
            } else if let payback = swapPayback, let pbShift = swapPaybackShift {
                Text("还班日 \(payback)：我 \(myDayOn(payback)?.shift ?? "") → \(pbShift)（\(ShiftStyle.timeRange(for: pbShift))）；\(partner)班那天休息。")
                    .appFont(size: AppFont.bodySmall)
            } else {
                Text("还班日：还没选。选一天当还班日，或者点「还班日先不填」。")
                    .appFont(size: AppFont.bodySmall)
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
                .appFont(size: AppFont.headline, weight: 600)
            if let partner = shownDay.partner, let covered = coveredShift {
                Text("给 \(shownDay.date) 那次调班补一个还班日（本月任意一天）：那天我替 \(partner)班上他那天的班（那次调班里我被替掉的是 \(covered)）。")
                    .appFont(size: AppFont.bodySmall)
                    .foregroundColor(.secondary)
            } else {
                Text("给 \(shownDay.date) 那次调班补一个还班日（本月任意一天）。")
                    .appFont(size: AppFont.bodySmall)
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
                        .appFont(size: AppFont.bodySmall)
                }
            } else {
                Text("这条调班记录不完整（没有对方班组），补不上还班日。")
                    .appFont(size: AppFont.bodySmall)
                    .foregroundColor(.secondary)
            }
            submitButton("确认补填", disabled: fillPayback == nil || fillPaybackShift == nil) {
                Task { await submitFillPayback() }
            }
        }
        .padding(AppStyle.cardPadding)
        .background(AppStyle.surface1)
        .cornerRadius(AppStyle.cardRadius)
        .task { await loadTeamsRange() }
    }

    // MARK: 请假

    /// 请假（1.3.2.018：请一段假收进这里做「单日 / 多日」切换，不再是独立入口；
    /// 多日分支标题「连续请假」，副标题「自动跳过休息日，单次最多 62 天」）。
    private var leaveForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("请假")
                .appFont(size: AppFont.headline, weight: 600)
            if shownDay.onLeave == true {
                Text("已请假（\(shownDay.leaveType ?? "请假")）\(shownDay.leaveNote.map { " · \($0)" } ?? "")")
                    .appFont(size: AppFont.bodySmall)
                if let partner = shownDay.partner, !partner.isEmpty {
                    Text("顶岗：\(partner)班上 \(shownDay.partnerShift ?? "")。")
                        .appFont(size: AppFont.bodySmall)
                        .foregroundColor(.secondary)
                } else if shownDay.shift != "休息" {
                    Text("还没安排顶岗。")
                        .appFont(size: AppFont.bodySmall)
                        .foregroundColor(.secondary)
                    Button("选择顶岗同事") {
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
                                .appFont(size: AppFont.bodySmall)
                            submitButton("确认安排顶岗") {
                                Task { await submitLeaveCover() }
                            }
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
                    .textFieldStyle(.plain)
                    .fieldBackground()
                submitButton("保存修改") {
                    Task { await submitLeave() }
                }
            } else {
                Picker("请假方式", selection: $leaveMode) {
                    Text("单日").tag("单日")
                    Text("多日").tag("多日")
                }
                .pickerStyle(.segmented)
                if leaveMode == "多日" {
                    Text("连续请假")
                        .appFont(size: AppFont.headline, weight: 600)
                    Text("自动跳过休息日，单次最多 62 天")
                        .appFont(size: AppFont.bodySmall)
                        .foregroundColor(.secondary)
                    DatePicker("从", selection: $rangeStart, displayedComponents: .date)
                    DatePicker("到", selection: $rangeEnd, displayedComponents: .date)
                    Picker("类型", selection: $leaveType) {
                        ForEach(ShiftStyle.leaveTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("备注（可选）", text: $leaveNote)
                        .textFieldStyle(.plain)
                        .fieldBackground()
                    submitButton("确认请假") {
                        Task { await submitLeaveRange() }
                    }
                } else {
                    Picker("请假类型", selection: $leaveType) {
                        ForEach(ShiftStyle.leaveTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("备注（可选）", text: $leaveNote)
                        .textFieldStyle(.plain)
                        .fieldBackground()
                    if shownDay.shift != "休息" {
                        Text("安排顶岗（选填）")
                            .appFont(size: AppFont.bodySmall, weight: 700)
                        Button("选择顶岗同事") {
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
                    submitButton("确认请假") {
                        Task { await submitLeaveWithCover() }
                    }
                }
            }
        }
        .padding(AppStyle.cardPadding)
        .background(AppStyle.surface1)
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
                .appFont(size: AppFont.headline, weight: 600)
            DatePicker("开始", selection: $overtimeStart, displayedComponents: .hourAndMinute)
            DatePicker("结束", selection: $overtimeEnd, displayedComponents: .hourAndMinute)
            HStack {
                Text("时长")
                    .foregroundColor(.secondary)
                Spacer()
                Text(overtimeDurationText)
                    .appFont(size: AppFont.headline, weight: 600)
                    .foregroundColor(.blue)
            }
            Text("结束时间早于开始时间时，自动按跨天计算（如 22:00–次日 02:00 计 4 小时）")
                .appFont(size: AppFont.caption)
                .foregroundColor(.secondary)
            TextField("备注（可选）", text: $overtimeNote)
                .textFieldStyle(.plain)
                .fieldBackground()
            submitButton("确认加班") {
                Task { await submitOvertime() }
            }
        }
        .padding(AppStyle.cardPadding)
        .background(AppStyle.surface1)
        .cornerRadius(AppStyle.cardRadius)
    }

    /// 加班起止时间的格式器（"HH:mm"）：静态单例，不再每次算时长/每次提交都新建一个。
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// 表单里当场算出的时长（跟服务端同一规则）。
    private var overtimeDurationText: String {
        let start = Self.timeFormatter.string(from: overtimeStart)
        let end = Self.timeFormatter.string(from: overtimeEnd)
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
            // 1.3.2.005（方案 §6 车间噪音环境）：调班保存成功，轻震一下确认。
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
        // 1.3.2.005（方案 §6 车间噪音环境）：请假保存成功，轻震一下确认。
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        doneMessage = "请假已保存"
        showLeaveForm = false
    }

    private func submitLeaveWithCover() async {
        errorText = nil
        doneMessage = nil
        await store.submitLeave(date: shownDay.date, type: leaveType,
                                note: leaveNote.isEmpty ? nil : leaveNote)
        // 1.3.2.005（方案 §6 车间噪音环境）：请假本身保存成功，轻震一下确认
        //（顶岗安排是后一步，安排不上也不影响请假已保存这个确认）。
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
        // 1.3.2.005（方案 §6 车间噪音环境）：请假（一段）保存成功，轻震一下确认。
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        doneMessage = "请假已保存"
        showLeaveForm = false
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
        let start = Self.timeFormatter.string(from: overtimeStart)
        let end = Self.timeFormatter.string(from: overtimeEnd)
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
