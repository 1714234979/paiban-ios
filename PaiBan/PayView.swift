import SwiftUI

/// 预估工资页：月份步进（1.2.6 冷启动回当天：默认当月），只按月看（全年视图已删）。
/// 数字在手机本地算（服务端只给排班与工资配置原始数据），切月秒出。
/// 1.1.4：切月改成原生 TabView 分页滑（和排班页一样，跟着手指走、左右月预渲染）。
/// 原来是自定义 DragGesture（minimumDistance 12）+ onEnded 里才调 stepPayMonth，
/// 手指拖动时内容完全不动、松手后才用 0.25s 动画切月——这就是「不跟手」。
/// 现在 TabView 自己管滑动，内容跟着手指走；每页是自己的 ScrollView（竖滚），
/// 横滑归 TabView、竖滚归页内 ScrollView，两边不抢手势。
struct PayView: View {
    @Environment(AppStore.self) private var store: AppStore

    /// 单月可改的 inline 编辑框：一次只改一行（科室绩效 / 绩效系数 / 奖金系数 / 加班天数 / 水电费），
    /// 样式与收起规则五种字段完全一致。点外面或切页面就收起，丢弃未保存的改动。
    @State private var editingField: PayRecordField? = nil
    @State private var editText = ""
    @State private var editSaving = false
    @State private var editError: String?
    @FocusState private var editFieldFocused: Bool
    /// 工资设定还没填完时，工资页显示空状态（2026-11-27 10:28）：点按钮进引导。
    @State private var showPayGuide = false
    /// 专项扣除询问弹窗里点「有，去填写」后打开的编辑页（第 52 条）。
    @State private var showSpecialDeductions = false
    /// 年月快选弹窗（1.3.2.013）：点月份标题弹出，选年月直接跳过去。
    @State private var showMonthJump = false
    /// 滑页的页码 = 月份绝对序号（年*12 + 月-1），与排班页同一套。
    /// 1.2.6 冷启动回当天：默认当月。
    @State private var pageIndex: Int = PayView.monthIndex(year: DateUtil.yearMonth(of: Date()).year, month: DateUtil.yearMonth(of: Date()).month)
    /// 标题跟的月份（2026-11-28 改，取代落定才变）：拖过一半就换（分页器的过半回调写这里），
    /// 落定时跟 pageIndex 同步；拖一半松手弹回时跟着回来。工资数据仍只跟 pageIndex（落定页）。
    /// 1.3.2.011（Gemini）：改成 MonthTitleState——过半变月只刷新标题，滑动中不重算
    /// PayView.body，也不叠糊数字；滑动中/0.28s 内连变禁动画，慢速单次点按保留数字滚动。
    @State private var titleState: MonthTitleState = {
        let now = DateUtil.yearMonth(of: Date())
        return MonthTitleState(monthIndex: PayView.monthIndex(year: now.year, month: now.month))
    }()
    /// 冷启动回当天只做一次（切 Tab 闪跳的根因，和排班页同一个 .task 毛病）：
    /// .task 在切 Tab 回来时也会重跑，不加标志每次回来都强制回当月，先闪一帧离开时的月份
    /// 再跳回当月；有了标志，只有第一次创建时才回当天。
    @State private var didInitialMonthAlign = false
    /// 基准月（视图第一次创建时的当月，之后不再动）：月份偏移数组相对它算。
    /// 月份切换重做（老爷 2026-11-28 14:30 亲口令「直接重做」）：分页走 SmoothMonthPager
    ///（原生分页 ScrollView），月份索引是相对基准月的固定偏移数组（-120..<120，共 240 个月，
    /// 覆盖 10 年窗口 2016-11～2036-10），数组本身永远不变。pageIndex 是已落定的月份
    ///（标题 + 工资数据都跟它走），拖拽中不动，只在分页落定时才变——标题绝不提前跳变。
    @State private var baseIndex: Int = {
        let now = DateUtil.yearMonth(of: Date())
        return PayView.monthIndex(year: now.year, month: now.month)
    }()
    private var pageRange: Range<Int> { (baseIndex - 120)..<(baseIndex + 120) }
    /// 固定月份偏移数组（-120..<120，共 240 个月，相对基准月）。
    private var monthOffsets: [Int] { Array(-120..<120) }
    /// 分页器用的已落定偏移（pageIndex 与 baseIndex 的差）：分页器落定时写回 pageIndex。
    private var selectedOffsetBinding: Binding<Int> {
        Binding(get: { pageIndex - baseIndex }, set: { pageIndex = baseIndex + $0 })
    }
    /// 今天所在的月份绝对序号（“今天”按钮的跳转目标）。
    private var currentMonthIndex: Int {
        let now = DateUtil.yearMonth(of: Date())
        return Self.monthIndex(year: now.year, month: now.month)
    }

    /// 月明细骨架延迟 150ms 的在途任务（1.3.2.006）：加载开始后 150ms 再现骨架，
    /// 数据快回来就不闪；加载结束或视图消失时取消。
    @State private var paySkeletonTask: Task<Void, Never>?
    /// 月明细的骨架是否显示（同上，150ms 延迟后才置 true）。
    @State private var showPaySkeleton = false
    /// 箭头 / 今天点按切月（重做）：直接改 pageIndex（已落定），标题立刻淡入过去
    ///（1.3.2.011：标题走 MonthTitleState，慢速单次点按保留数字滚动）；分页器收到
    /// selectedOffset 变化滑过去（0.25s snappy，减弱动态效果时 0.15s 淡入）。
    /// 不做位移、不做交叉淡入——旧的 jumpToMonth 整段删掉。
    private func goToMonth(_ index: Int) {
        let target = min(max(index, pageRange.lowerBound), pageRange.upperBound - 1)
        titleState.update(to: target)
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25)) {
            pageIndex = target
        }
    }

    /// 点顶卡右下角“回到今天”：切回当月（工资页没有日期格要闪，只跳页）。
    private func goToCurrentMonth() {
        goToMonth(currentMonthIndex)
    }

    /// 减弱动态效果（重做，1.3.2.008）：月份切换只做 0.15s 淡入，不做位移、不做数字滚动。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 黑卡（Gemini 整改模块 4d，老爷 2026-11-28 14:49 亲口改回）：上一轮按 14:31 的意思
    /// 把只写「预估工资」四个字的黑卡删掉了，现在恢复——当月实发合计作为大号核心数据
    /// 放进去，和排班页顶部顶卡视觉统一（1.3.2.014 起是白框 AppStyle.surface1 + 16pt 圆角，
    /// 不再是黑底 navyAdaptive）。
    /// 数从当月工资数据里取已有的 grandTotal（下面合计行同一个数），不重算、不改公式；
    /// 当月工资还没算出来显示“—”；12h/6h 方式工资口径待定时也显示“—”并注一句。
    /// 2026-11-28 改：从固定在分页器上方改成每个月页面的页眉（见 body），
    /// 跟着月份一起翻页；所以改成函数、按页面的年月取数，不再读 pageIndex。
    /// 1.3.2.010：页眉放在页内、纵向 ScrollView 外（之前在 ScrollView 顶部，
    /// 嵌套 ScrollView 的竖向偏移一漂移就把黑卡顶出可视区、顶部横切）。
    /// 顶卡（1.3.2.014，Gemini 排版 + 白框）：本月实发合计 + 眼睛；下面大号总数；
    /// 再下面三段进度条（实发工资绿 / 实发奖金蓝 / 餐贴灰，按三者之和归一化）；
    /// 最下面三列小字（实发工资 / 实发奖金 / 餐贴）。
    /// 1.3.2.014 老爷令：顶卡从黑底（navyAdaptive）改成白框——浅色白、深色深，
    /// 跟随系统浅深色变（AppStyle.surface1），字也全改成自适应色（主字 onSurface、
    /// 次字 secondary），黑底那套白字不再用。隐藏金额时总数与三列变 ¥****，
    /// 进度条只露一条中性灰条、不露占比。
    private func headerCard(for ym: (year: Int, month: Int)) -> some View {
        let pay = store.cachedPay(year: ym.year, month: ym.month)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本月实发合计")
                    .appFont(size: AppFont.bodySmall)
                    .foregroundColor(.secondary)
                Spacer()
                // 金额一键隐藏（1.3.2.013）：右上角眼睛，点一下本页全部金额脱敏为 ¥****。
                HideAmountsEyeButton()
            }
            if let pay = pay, !isPayTBD {
                Text(store.moneyText(pay.grandTotal))
                    .appFont(size: 32, weight: 700).monospacedDigit()
                    .foregroundColor(AppStyle.onSurface)
                PayCompositionBar(
                    salary: pay.salaryNet ?? 0,
                    bonus: pay.bonusAfterTax ?? 0,
                    meal: pay.mealAllowance ?? 0,
                    hidden: store.hideAmounts
                )
                HStack(spacing: 0) {
                    payMiniColumn(label: "实发工资", value: store.moneyText(pay.salaryNet))
                    Rectangle().fill(AppStyle.outline).frame(width: 1, height: 28)
                    payMiniColumn(label: "实发奖金", value: store.moneyText(pay.bonusAfterTax))
                    Rectangle().fill(AppStyle.outline).frame(width: 1, height: 28)
                    payMiniColumn(label: "餐贴", value: store.moneyText(pay.mealAllowance))
                }
            } else {
                Text("—")
                    .appFont(size: 32, weight: 700).monospacedDigit()
                    .foregroundColor(AppStyle.onSurface)
                if isPayTBD {
                    Text("工资口径待定，金额暂不算")
                        .appFont(size: AppFont.bodySmall)
                        .foregroundColor(.secondary)
                }
            }
            // 回到今天（1.3.2.014，老爷令）：不在当月时才出现，放在顶卡右下角；
            // 导航栏「本月」胶囊不要了，排班/工资两页统一放这里。
            if PayView.monthIndex(year: ym.year, month: ym.month) != currentMonthIndex {
                HStack {
                    Spacer()
                    backToTodayButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppStyle.surface1)
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }

    /// 顶卡底下三列小字里的一列：上面小灰标签，下面大号金额。
    private func payMiniColumn(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .appFont(size: AppFont.caption)
                .foregroundColor(.secondary)
            Text(value)
                .appFont(size: AppFont.bodySmall, weight: 700).monospacedDigit()
                .foregroundColor(AppStyle.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    /// 回到今天按钮（1.3.2.014，老爷令）：顶卡右下角的小胶囊——不在当月时才出现，
    /// 点按回到当月（走 goToCurrentMonth）。排班/工资两页一样。样式跟顶卡角标同款
    ///（surface2 底 + 主字），轻，不抢顶卡的数字。热区扩到 48pt。
    private var backToTodayButton: some View {
        Button(action: goToCurrentMonth) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .semibold))
                Text("回到今天")
                    .appFont(size: AppFont.caption, weight: 600)
            }
            .foregroundColor(AppStyle.onSurface)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppStyle.surface2)
            .clipShape(Capsule())
            .touchTarget(vertical: 9, horizontal: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("回到今天")
    }

/// 本月实发构成条（1.3.2.014，Gemini 排版）：实发工资（绿）+ 实发奖金（蓝）+
/// 餐贴（灰）三段，按三者之和归一化，拼成一条 6pt 圆角横条；三者都为 0 时不画。
/// 隐藏金额时只露一条中性灰条，不露占比（比例本身就是金额信息）。
private struct PayCompositionBar: View {
    let salary: Double
    let bonus: Double
    let meal: Double
    let hidden: Bool

    var body: some View {
        if hidden {
            Capsule()
                .fill(AppStyle.surface2)
                .frame(height: 6)
        } else {
            let total = max(0, salary) + max(0, bonus) + max(0, meal)
            if total > 0 {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Color.green.frame(width: geo.size.width * (max(0, salary) / total))
                        Color.blue.frame(width: geo.size.width * (max(0, bonus) / total))
                        Color.gray.frame(width: geo.size.width * (max(0, meal) / total))
                    }
                }
                .frame(height: 6)
                .clipShape(Capsule())
            }
        }
    }
}

    static func monthIndex(year: Int, month: Int) -> Int { year * 12 + (month - 1) }
    private func yearMonth(from index: Int) -> (year: Int, month: Int) { (index / 12, index % 12 + 1) }

    /// 某个月的整页内容（1.3.2.010）：黑卡固定页眉 + 明细竖滚。
    /// 单独抽成函数——整页塞在分页器闭包里会让 body 的类型检查超时（编包报错），
    /// 拆出来才能编过（.008 日期格拆 6 块是同一个毛病）。
    /// 黑卡放在页内、ScrollView 外：跟着月份翻页（在页里），但不跟竖滚走
    ///（不在 ScrollView 里），嵌套 ScrollView 的竖向偏移漂移再也切不到它。
    /// 明细（monthBreakdown + syncTimeFooter）仍在 ScrollView 里竖滚。
    /// 落定纠偏那层不要了（编包三连挂的教训）：竖滚位置纠偏要用 ScrollPosition /
    /// .scrollPosition(point:)，全是 iOS 18 才有的 API，部署目标 17.0 编不过；
    /// iOS 17 的 .scrollPosition(id:) 只认视图 id、读不到偏移量，纠不了。
    /// 黑卡已在 ScrollView 外、切不到它；明细若真机上还漂，再用
    /// GeometryReader + ScrollViewReader 那套老办法修。
    private func payMonthPage(offset: Int) -> some View {
        let ym = yearMonth(from: baseIndex + offset)
        return VStack(spacing: 16) {
            headerCard(for: ym)
            ScrollView {
                VStack(spacing: 16) {
                    monthBreakdown(year: ym.year, month: ym.month)
                    syncTimeFooter
                }
                // 底部留白（1.3.2.012）：右下角悬浮「今天」按钮已挪到导航栏，
                // 这里不用再给它留 76pt；留 24pt 让明细底部在底栏上方有呼吸余量。
                .padding(.bottom, 24)
                // 底部留白（重做，老爷 2026-11-28 14:36 亲口令）：1.3.2.006 加的 88pt
                // 删掉——那是给自定义底栏留的，底栏已改回原生 TabView（iOS 26+ 液态玻璃 +
                // 往下滚自动收起），安全区由原生底栏自动处理，不再手动垫大额留白。
                // 点编辑框以外的地方就收起（丢弃未保存的改动）。Tap 手势只认轻点，
                // 拖动（滚动/横滑）不会触发，不跟左右滑切月、上下滚动冲突。
                .onTapGesture {
                    if editingField != nil { dismissEdit() }
                }
            }
            // 嵌套 ScrollView 的自动 safe-area 顶边距关掉（1.3.2.010）：
            // 纵向 ScrollView 嵌在横向分页器里时，系统会按 safe-area 给内容加顶边距，
            // 是竖向偏移漂移的头号嫌疑；显式写 0，不让它自己加。
            .contentMargins(.top, 0)
            // 1.3.0.013：滚动指示条常显（老爷 19:24 说「没有滑动框」）——.visible 没用，
            // 画廊实拍证明它根本不画出来，改走自绘滑块 AlwaysVisibleScrollIndicator。
            .modifier(AlwaysVisibleScrollIndicator())
        }
    }

    /// 骨架延迟 150ms（1.3.2.006）：加载开始后 150ms 再现骨架，数据快回来就不闪；
    /// 加载结束立刻消失；视图消失时取消任务。Task 注明 @MainActor，置 @State 安全。
    private func schedulePaySkeleton() {
        paySkeletonTask?.cancel()
        paySkeletonTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            showPaySkeleton = true
        }
    }
    private func hidePaySkeleton() {
        paySkeletonTask?.cancel()
        paySkeletonTask = nil
        showPaySkeleton = false
    }

    var body: some View {
        // 工资权限兜底（1.2.7.001，第 23 条）：没权限的人工资 Tab 本来就隐藏，
        // 这里是万一从别处进了工资页的兜底——只显示提示，不崩、不拉数据。
        if !store.payAccess {
            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("没有工资权限")
                    .appFont(size: AppFont.headline, weight: 600)
                Text("你的账号没有查看工资的权限。如需开通，请联系管理员。")
                    .appFont(size: AppFont.bodySmall)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppStyle.pageBackground)
        } else if store.needsPaySetup {
            // 工资设定还没填完（2026-11-27 10:28，老爷亲口定，取代第 30 条自动弹窗）：
            // 干净的空页面，中间只有一个按钮，不显示任何空数字或零；点进去走一遍
            // 工资设置引导（基本工资、奖金系数、缴费基数、岗位、入职时间、剩余年休假），
            // 填完引导，工资页才开始正常显示数据。
            VStack(spacing: 20) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
                Text("还没填工资设置")
                    .appFont(size: AppFont.headline, weight: 600)
                Text("基本工资、奖金系数、缴费基数、岗位、入职时间和剩余年休假填好后，工资页就按你的数算。")
                    .appFont(size: AppFont.bodySmall)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    showPayGuide = true
                } label: {
                    Text("填写工资设置")
                        .appFont(size: AppFont.headline, weight: 600)
                        .frame(maxWidth: 240)
                        .frame(height: AppStyle.buttonHeight)
                        .background(AppStyle.navyAdaptive)
                        .foregroundColor(.white)
                        .cornerRadius(AppStyle.buttonHeight / 2)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppStyle.pageBackground)
            .sheet(isPresented: $showPayGuide) {
                PayGuideView()
            }
        } else {
        VStack(spacing: 16) {
            // 月份标题栏（重做）：共用的 MonthHeaderView，跟排班页同一套。
            // 标题走 titleState（过半就换），“回到今天”按钮不在标题栏里（1.3.2.014：
            // 顶卡右下角；标题行只剩 < 标题 >）。
            ObservedMonthHeaderView(
                state: titleState,
                onPrevious: { goToMonth(pageIndex - 1) },
                onNext: { goToMonth(pageIndex + 1) },
                onTitleTap: { showMonthJump = true }
            )
            .padding(.top, 8)
            .sheet(isPresented: $showMonthJump) {
                MonthJumpSheet(currentIndex: pageIndex, range: pageRange) { goToMonth($0) }
            }
            // 月份分页重做（老爷 2026-11-28 14:30 亲口令）：共用的 SmoothMonthPager——
            // 原生分页 ScrollView + .scrollTargetBehavior(.paging)，手势物理曲线、回弹与
            // 打断全交给系统；每页一个 ScrollView 竖滚，横滑归分页器、竖滚归页内，两边
            // 不抢手势。旧的 TabView 分页 + 20pt 轻移 + 交叉淡入整段删掉。
            // 顶栏和月份标题固定在上面不滚动，工资明细在页内上下滚、左右滑切月；
            // 分页器只预渲染当前页与相邻页，切月不整页重算（工资走 payFor 缓存）。
            // pagePadding 传 0：明细卡片自带 16pt 横向留白，两页卡片之间自然有 32pt
            // 间距，不粘连；再加 16pt 会把卡片挤得过窄。
            // 黑卡进页（2026-11-28 改，1.3.2.010 再改）：原来固定在标题栏下方、分页器上方，
            // 不跟页内滚动走，切月时黑卡不动、只有下面明细在滑，看着像卡住了；.009 放进
            // 每个月页面的纵向 ScrollView 最顶部，跟着月份一起翻页、一起滚动——但嵌套
            // ScrollView 的竖向偏移会漂移（实测静止偏约 42pt），黑卡被顶出可视区、
            // 顶部横切。1.3.2.010 改成每页固定页眉：放在页内、ScrollView 外，
            // 跟着月份翻页、不跟竖滚走。内容和数字不变（grandTotal，不重算、
            // 不改公式），只是位置从 ScrollView 里改成页眉。
            SmoothMonthPager(monthOffsets: monthOffsets, selectedOffset: selectedOffsetBinding, pagePadding: 0, fillHeight: true, onMidpointPageChange: { offset in
                titleState.update(to: baseIndex + offset)
            }, onScrollingChange: { scrolling in
                titleState.setScrolling(scrolling)
            }) { offset in
                payMonthPage(offset: offset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppStyle.pageBackground)
        // 导航栏毛玻璃隔离：和排班页同一毛病（黑卡文字透过导航栏、被栏底边切一半），
        // 改回系统原生 .automatic（排班页见 CalendarView；设置页见 SettingsView）。
        // 工资页之前没写 toolbarBackground，走的是系统默认（就是 .automatic），
        // 这里显式写出来，和两边保持一致、以后改一处就能对上。
        // 1.3.2.014：导航栏右上角「本月」胶囊删了（老爷令）——回到今天改成顶卡
        // 右下角的「回到今天」按钮（见 headerCard），排班/工资两页一样。
        .toolbarBackground(.automatic, for: .navigationBar)
        // 滑到哪页，Store 就跟到哪月（setPayMonth 只改月份、只读缓存，
        // 1.3.2.011：落定那帧不同步算，未命中 pay 置空、后台 prewarm 算好再换）；
        // 切月时把敞着的编辑框收起（那是上个月的数，别留在新月上误触）。
        .onChange(of: pageIndex) { newIndex in
            // 落定就跟标题同步（标题平时跟过半回调走，落定时一定等于 pageIndex）。
            titleState.update(to: newIndex)
            let ym = yearMonth(from: newIndex)
            dismissEdit()
            store.setPayMonth(year: ym.year, month: ym.month)
            store.prewarmPayAround(year: ym.year, month: ym.month, radius: 10)
        }
        // 切到别的页面（排班/设置）时，敞着的编辑框自动收起，丢弃未保存的改动。
        .onDisappear { dismissEdit(); hidePaySkeleton() }
        // 骨架延迟 150ms（1.3.2.006）：加载开始计时、结束立刻消失。
        .onChange(of: store.isLoadingPay) { loading in
            if loading { schedulePaySkeleton() } else { hidePaySkeleton() }
        }
        .onAppear {
            if store.isLoadingPay { schedulePaySkeleton() }
        }
        .task {
            // 1.2.6 冷启动回当天：进页先对齐到今天所在的月（不再跟 Store 恢复的月份走）。
            // 切 Tab 闪跳的根因（和排班页同一个 .task 毛病）：.task 在切 Tab 回来时也会重跑，
            // 原来每次都强制回当月；只第一次跑时回当天（didInitialMonthAlign 标志），
            // 切 Tab 回来只做刷新/预取，月份保持原地不动。
            // 基准月（baseIndex）只在创建时定一次，这里不再重定——动态改基准会让
            // 分页器的 scrollPosition id 错位、跳月。
            if !didInitialMonthAlign {
                didInitialMonthAlign = true
                let now = DateUtil.yearMonth(of: Date())
                pageIndex = Self.monthIndex(year: now.year, month: now.month)
                titleState.update(to: pageIndex)
                store.setPayMonth(year: now.year, month: now.month)
            }
            let ym = yearMonth(from: pageIndex)
            if store.cachedPay(year: ym.year, month: ym.month) == nil {
                await store.refreshPay()
            }
            store.prewarmPayAround(year: ym.year, month: ym.month, radius: 10)
            // 专项扣除询问（第 52 条，2026-11-27）：有工资权限、设定已填完、还没问过、
            // 且还没填专项扣除，第一次进工资页时弹窗问一次「有没有专项附加扣除」。
            if store.payAccess && !store.needsPaySetup && !store.specialDeductionAsked
                && PayCalc.specialDeductionMonthly(store.user?.paySettings?.specialDeductions) == 0 {
                store.needsSpecialDeductionAsk = true
            }
        }
        .alert("有没有专项附加扣除？", isPresented: Bindable(store).needsSpecialDeductionAsk) {
            Button("有，去填写") {
                store.markSpecialDeductionAsked()
                showSpecialDeductions = true
            }
            Button("没有", role: .cancel) {
                store.markSpecialDeductionAsked()
            }
        } message: {
            Text("子女教育、房贷利息、赡养老人这些，每月能从应纳税所得额里扣，个税会少交。有的话填一下，没有就跳过，只问一次。")
        }
        .sheet(isPresented: $showSpecialDeductions) {
            NavigationStack {
                SpecialDeductionsView()
            }
        }
        // 替换原来两条会重复触发 refreshPay 的 onChange：输入补齐时触发后台预热即可。
        .onChange(of: store.payInputsVersion) { _ in
            let ym = yearMonth(from: pageIndex)
            store.prewarmPayAround(year: ym.year, month: ym.month, radius: 10)
        }
        } // else: 有工资权限时显示工资页
    }

    // MARK: 月度明细

    /// 当前倒班方式的工资是否待定（1.2.7.002：12h/6h 方式工资口径未定，金额不可信）。
    private var isPayTBD: Bool { store.rotation.mode?.isPayTBD == true }

    /// 当月各班次个数（按实际班次名统计，12h/6h 方式用这个，不走 8h 的日/早/中计数）。
    private func shiftCountsForMonth(year: Int, month: Int) -> [(name: String, count: Int)] {
        let m = store.monthFor(year: year, month: month)
        var counts: [String: Int] = [:]
        for d in (m.days ?? []) {
            let parts = ShiftStyle.parts(of: d.shift)
            for p in parts { counts[p, default: 0] += 1 }
        }
        let order = ["白班", "夜班", "日班", "中班", "早班", "前夜", "下午", "早", "后夜", "第一班", "第二班", "第三班", "第四班", "休息"]
        return counts.map { (name: $0.key, count: $0.value) }
            .sorted { (order.firstIndex(of: $0.name) ?? 99) < (order.firstIndex(of: $1.name) ?? 99) }
    }

    /// 某月的工资明细：工资取 store.cachedPay（只读缓存，1.3.2.011）——
    /// 切月那一刻主线程上不许有同步工资计算，body 只能读缓存；未命中且后台正在算
    /// 时显示骨架，算完写缓存再重画换真数；既没缓存又没在算才显示“暂无工资数据”。
    /// 相邻月预渲染时直接读缓存、不现算、不发网络；输入没到齐算不出时先显示加载，
    /// refreshPay 把输入补齐后重画。只看当前页这一份，不用等整页刷新。
    @ViewBuilder
    private func monthBreakdown(year: Int, month: Int) -> some View {
        if let pay = store.cachedPay(year: year, month: month) {
            VStack(spacing: 16) {
                // 1.2.7.002：12h/6h 方式工资口径待定——金额不算，只显示班次统计。
                if isPayTBD {
                    payTBDBanner(year: year, month: month)
                    let counts = shiftCountsForMonth(year: year, month: month)
                    paySection(title: "出勤", rows: [
                        ("当月应出勤", pay.basicDays.map { "\($0) 天" } ?? "—"),
                        ("实际出勤", attendanceText(pay.attendance)),
                        ("班次统计", counts.isEmpty ? "—" : counts.map { "\($0.name) \($0.count) 个" }.joined(separator: "、")),
                        ("请假", pay.leaveDays.map { "\($0) 天" } ?? "—"),
                        ("年假剩余", pay.annualLeaveRemaining.map { "\($0) 天（全年 \(pay.annualLeaveTotal ?? 5) 天，已用 \(pay.annualLeaveYearUsed ?? 0) 天）" } ?? "—"),
                    ])
                } else {
                salarySection(pay: pay)
                bonusSection(pay: pay)
                paySection(title: "合计", rows: [
                    ("实发工资 + 实发奖金", store.moneyText(pay.grandTotal)),
                    ("餐贴", store.moneyText(pay.mealAllowance)),
                ])
                paySection(title: "出勤", rows: [
                    ("当月应出勤", pay.basicDays.map { "\($0) 天" } ?? "—"),
                    ("实际出勤", attendanceText(pay.attendance)),
                    ("日班 / 早班 / 中班", "\(MoneyUtil.int(pay.counts?.day)) / \(MoneyUtil.int(pay.counts?.early)) / \(MoneyUtil.int(pay.counts?.mid)) 个"),
                    ("请假", pay.leaveDays.map { "\($0) 天" } ?? "—"),
                    ("年假剩余", pay.annualLeaveRemaining.map { "\($0) 天（全年 \(pay.annualLeaveTotal ?? 5) 天，已用 \(pay.annualLeaveYearUsed ?? 0) 天）" } ?? "—"),
                ])
                }
                if let tripleDates = pay.tripleDates, !tripleDates.isEmpty {
                    // 1.3.2.014：标题小灰字放白卡外面（Gemini 排版，与工资/奖金明细同款）。
                    VStack(alignment: .leading, spacing: 6) {
                        Text("三薪明细")
                            .appFont(size: AppFont.bodySmall)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                        VStack(alignment: .leading, spacing: 6) {
                        ForEach(tripleDates, id: \.date) { item in
                            HStack {
                                Text(item.date ?? "")
                                Text(item.name ?? "")
                                Spacer()
                                Text(item.shift ?? "")
                                    .foregroundColor(.secondary)
                            }
                            .appFont(size: AppFont.bodySmall)
                        }
                        }
                        .padding(AppStyle.cardPadding)
                        .background(AppStyle.surface1)
                        .cornerRadius(AppStyle.cardRadius)
                        .padding(.horizontal, 16)
                    }
                }
            }
        } else if store.isLoadingPay || store.isComputingPay(year: year, month: month) {
            // 骨架屏（1.3.2.005，方案 §4.4/§5.4）：四块灰卡，按真布局排
            //（工资 / 奖金 / 合计 / 出勤四张卡的个头），不转圈、不闪烁；
            // 输入到了直接换真内容。加载逻辑本身没动。
            // 1.3.2.006：加载开始 150ms 后才出现，数据快回来时不闪骨架；
            // 150ms 内数据到了，这四块就不出现（也不显示“暂无工资数据”，那是加载结束才有的）。
            if showPaySkeleton {
                VStack(spacing: 16) {
                    SkeletonBar(height: 450)
                    SkeletonBar(height: 420)
                    SkeletonBar(height: 120)
                    SkeletonBar(height: 210)
                }
                .padding(.horizontal, 16)
            }
        } else {
            Text("暂无工资数据，稍后再试")
                .foregroundColor(.secondary)
                .padding()
        }
    }

    /// 工资待定提示卡（1.2.7.002）：12h/6h 方式的工资口径还没定，金额暂不算，
    /// 只显示班次统计与总工时；等工资口径定了再算。
    private func payTBDBanner(year: Int, month: Int) -> some View {
        let mode = store.rotation.mode
        let hours = (mode?.shiftHours ?? 8)
        let counts = shiftCountsForMonth(year: year, month: month)
        let workShifts = counts.filter { $0.name != "休息" }.reduce(0) { $0 + $1.count }
        return VStack(alignment: .leading, spacing: 6) {
            Text("工资口径待定")
                .appFont(size: AppFont.headline, weight: 600)
            Text("\(mode?.name ?? "")是 \(hours) 小时班，工资口径还没定（12 小时/6 小时班的加班与津贴规则与 8 小时班不一样），金额暂不算，只显示班次统计。")
                .appFont(size: AppFont.bodySmall)
                .foregroundColor(.secondary)
            Text("当月共上 \(workShifts) 个班 · \(workShifts * hours) 小时")
                .appFont(size: AppFont.bodySmall, weight: 700)
                .monospacedDigit()
        }
        .padding(AppStyle.cardPadding)
        .background(AppStyle.surface1)
        .cornerRadius(AppStyle.cardRadius)
        .padding(.horizontal, 16)
    }

    /// 明细分区（1.3.2.014，Gemini 排版）：标题是小灰字、放在白卡外面、上面，
    /// 卡片里只留行——原来标题是 17pt 粗体在卡片里面，又占地方又抢眼。
    /// 合计/出勤/三薪明细都走这套，标题字不变（合计、出勤），工资/奖金那两张
    /// 标题改成“工资明细”“奖金明细”。
    private func paySection(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .appFont(size: AppFont.bodySmall)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows, id: \.0) { row in
                    HStack {
                        Text(row.0)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(row.1)
                            .appFont(size: AppFont.bodySmall, weight: row.0.hasPrefix("实发") || row.0.hasPrefix("应发") || row.0.hasPrefix("税前") || row.0.contains("合计") ? 700 : 400)
                            .monospacedDigit()
                    }
                    .appFont(size: AppFont.bodySmall)
                    .padding(.vertical, 5)
                    Divider()
                }
            }
            .padding(AppStyle.cardPadding)
            .background(AppStyle.surface1)
            .cornerRadius(AppStyle.cardRadius)
            .padding(.horizontal, 16)
        }
    }

    /// 奖金区：科室绩效、绩效系数、奖金系数、加班天数四行点一下就能改当月那个数
    ///（只有老爷能改，改完存服务端、本地立刻重算）。其余行只看。行顺序跟原来一样。
    /// 1.3.2.014：标题“奖金明细”是小灰字、放在白卡外面（Gemini 排版），卡片里只留行。
    private func bonusSection(pay: PayMonth) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("奖金明细")
                .appFont(size: AppFont.bodySmall)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 0) {
            editableRow(title: "科室绩效", valueText: store.moneyText(pay.deptPerf), field: .deptPerf,
                        currentValue: pay.deptPerf.map { String(format: "%.2f", $0) } ?? "4000",
                        placeholder: "科室绩效（如 3800）")
            staticRow(title: "其他奖罚", valueText: store.moneyText(pay.otherReward), bold: false, dimmed: (pay.otherReward ?? 0) == 0)
            staticRow(title: "缺员补贴", valueText: store.moneyText(pay.shortageSubsidy), bold: false, dimmed: (pay.shortageSubsidy ?? 0) == 0)
            editableRow(title: "绩效系数", valueText: MoneyUtil.number(pay.perfCoef), field: .perfCoef,
                        currentValue: pay.perfCoef.map { String(format: "%.2f", $0) } ?? "1",
                        placeholder: "绩效系数（如 1.2）")
            editableRow(title: "奖金系数", valueText: MoneyUtil.number(pay.bonusCoef), field: .bonusCoef,
                        currentValue: pay.bonusCoef.map { String(format: "%.2f", $0) } ?? "1",
                        placeholder: "奖金系数（如 1.2）")
            staticRow(title: "加班费（含三薪）", valueText: store.moneyText(pay.overtimePay), bold: false, dimmed: (pay.overtimePay ?? 0) == 0)
            staticRow(title: "三薪天数", valueText: pay.tripleDays.map { String(format: "%.1f 天", $0) } ?? "—", bold: false)
            staticRow(title: "三薪金额", valueText: store.moneyText(pay.triplePay), bold: false, dimmed: (pay.triplePay ?? 0) == 0)
            editableRow(title: "加班天数", valueText: pay.overtimeDays.map { String(format: "%.1f 天", $0) } ?? "—", field: .overtimeDays,
                        currentValue: pay.overtimeDays.map { String(format: "%.1f", $0) } ?? "0",
                        placeholder: "加班天数（如 2）")
            staticRow(title: "税前奖金", valueText: store.moneyText(pay.bonusTotal), bold: true)
            // 专项附加扣除（第 52 条）：这个月扣了多少，一眼就能看到税少了是因为扣了专项。
            // 负号改走 staticRow 的 deduction 旗标（和别的扣款行同一套样式），值里不再自带“−”。
            if (pay.specialDeductionMonthly ?? 0) > 0 {
                staticRow(title: "专项附加扣除", valueText: "\(store.moneyText(pay.specialDeductionMonthly))/月", bold: false, deduction: true)
            }
            // 大病医疗（修订版）：只汇算时扣，不进月度预扣；填了年度自付总额就提示一句。
            if let selfPay = store.user?.paySettings?.specialDeductions?.medicalSelfPayAnnual, selfPay > 0 {
                Text("大病医疗需在次年汇算时扣除，未计入本月预扣；年度自付 \(store.moneyText(selfPay))，预计汇算可扣 \(store.moneyText(PayCalc.medicalAnnualDeduction(store.user?.paySettings?.specialDeductions)))。")
                    .appFont(size: AppFont.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            }
            staticRow(title: "个税（累计预扣，税从奖金里扣）", valueText: store.moneyText(pay.incomeTax), bold: false, dimmed: (pay.incomeTax ?? 0) == 0)
            staticRow(title: "实发奖金", valueText: store.moneyText(pay.bonusAfterTax), bold: true)
            }
            .padding(AppStyle.cardPadding)
            .background(AppStyle.surface1)
            .cornerRadius(AppStyle.cardRadius)
            .padding(.horizontal, 16)
        }
    }

    /// 公积金标题（1.3.2.013）：费率是反推的（公积金金额 ÷ 缴费基数），不是存量——
    /// 老爷的是 403 ÷ 5938 = 6.8%，不是别的 AI 猜的 12%；算不出来（没填公积金或
    /// 没基数）就不标，只写「公积金」。
    private func housingFundTitle(pay: PayMonth) -> String {
        guard let hf = pay.housingFund, hf > 0, let base = pay.contributionBase, base > 0 else {
            return "公积金"
        }
        let pct = hf / base * 100
        let s = String(format: "%.1f", pct)
        let trimmed = s.hasSuffix(".0") ? String(s.dropLast(2)) : s
        return "公积金（\(trimmed)%）"
    }

    /// 工资区：水电费那行点一下就能改当月那个数（只有老爷能改），其余行只看。
    /// 行顺序跟原来 paySection 那张表一样。
    /// 1.3.2.014：标题“工资明细”是小灰字、放在白卡外面（Gemini 排版），卡片里只留行。
    private func salarySection(pay: PayMonth) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("工资明细")
                .appFont(size: AppFont.bodySmall)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 0) {
            staticRow(title: "基本工资", valueText: store.moneyText(pay.baseSalary), bold: false)
            staticRow(title: "岗位", valueText: pay.position ?? "—", bold: false)
            staticRow(title: "早夜班补贴", valueText: store.moneyText(pay.allowance), bold: false, dimmed: (pay.allowance ?? 0) == 0)
            staticRow(title: "学历补贴", valueText: store.moneyText(pay.educationSubsidy), bold: false, dimmed: (pay.educationSubsidy ?? 0) == 0)
            staticRow(title: "高温费", valueText: store.moneyText(pay.heat), bold: false, dimmed: (pay.heat ?? 0) == 0)
            staticRow(title: "工龄津贴", valueText: store.moneyText(pay.seniority), bold: false)
            staticRow(title: "应发工资", valueText: store.moneyText(pay.salarySubtotal), bold: true)
            staticRow(title: "养老（8%）", valueText: store.moneyText(pay.pension), bold: false, deduction: true)
            staticRow(title: "医疗（2%）", valueText: store.moneyText(pay.medical), bold: false, deduction: true)
            staticRow(title: "失业（0.3%）", valueText: store.moneyText(pay.unemployment), bold: false, deduction: true)
            staticRow(title: "五险一金合计", valueText: store.moneyText(pay.contributionTotal), bold: true, deduction: true)
            staticRow(title: housingFundTitle(pay: pay), valueText: store.moneyText(pay.housingFund), bold: false, deduction: true)
            editableRow(title: "水电费", valueText: store.moneyText(pay.utilities), field: .utilities,
                        currentValue: pay.utilities.map { String(format: "%.2f", $0) } ?? "0",
                        placeholder: "水电费（如 60）", deduction: true)
            staticRow(title: "实发工资", valueText: store.moneyText(pay.salaryNet), bold: true)
            }
            .padding(AppStyle.cardPadding)
            .background(AppStyle.surface1)
            .cornerRadius(AppStyle.cardRadius)
            .padding(.horizontal, 16)
        }
    }

    /// 只看的行（标签 + 值 + 分隔线），样式跟原来 paySection 里的一致。
    /// 1.3.2.013：扣款项（deduction）补负号并用浅色（.secondary）区分——养老/医疗/
    /// 失业/五险一金合计/公积金/水电费都是从应发里扣减的；金额为 0 的行（dimmed）
    /// 金额也降为浅灰，让真正有钱的项目跳出来。两者都不影响标题色（本来就是 .secondary）。
    private func staticRow(title: String, valueText: String, bold: Bool, deduction: Bool = false, dimmed: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .foregroundColor(.secondary)
                Spacer()
                Text(deduction ? "−\(valueText)" : valueText)
                    .appFont(size: AppFont.bodySmall, weight: bold ? 700 : 400)
                    .monospacedDigit()
                    .foregroundColor(deduction || dimmed ? .secondary : .primary)
            }
            .appFont(size: AppFont.bodySmall)
            .padding(.vertical, 5)
            Divider()
        }
    }

    /// 一行可改的数值：点“可改”弹出 inline 编辑框（输入框 + 保存/取消），下面再跟分隔线。
    /// 只有老爷能改；点外面或切页面自动收起（dismissEdit）。
    /// 1.1.3：只有「可改」这个小徽标是按钮（明确的编辑入口），整行不再是按钮。
    /// 之前整行都是 Button，左右滑切月时手指从行上划过、抬手还在行内，
    /// Button 就当成一次点按、把编辑框打开了。现在行本身不可点，横滑只会触发切月；
    /// 想改就点「可改」徽标（小目标，横滑起止很难同时落在它上面），误触基本杜绝。
    /// 1.1.4：TabView 滑页时手指从行上划过也不会再打开编辑框（行本身不是按钮，
    /// TabView 的横滑手势优先），这条保留、继续有效。
    /// 1.3.2.012（Gemini 2026-11-28 逐帧复核）：「可改」徽标放金额左边——
    /// 原来放金额右边，徽标把金额往左顶了一截，金额和上下没徽标的行对不齐；
    /// 放左边后金额全部贴右沿对齐，徽标仍是同一按钮、点法不变。
    private func editableRow(title: String, valueText: String, field: PayRecordField, currentValue: String, placeholder: String, deduction: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    openEdit(field, currentValue: currentValue)
                } label: {
                    Text("可改")
                        .appFont(size: AppFont.caption)
                        .foregroundColor(AppStyle.editableBlue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppStyle.editableBlue.opacity(0.10))
                        .cornerRadius(6)
                        // 1.3.2.005（方案 §3.3）：徽标只有约 20pt 高，透明留白扩到 48pt；
                        // 行会跟着变高一点（可改的 5 行），换点得准，值。
                        .touchTarget(vertical: 14, horizontal: 4)
                }
                .buttonStyle(.plain)
                // 扣款项（水电费，1.3.2.013）同样补负号并用浅色，和 staticRow 的扣款行一致。
                Text(deduction ? "−\(valueText)" : valueText)
                    .monospacedDigit()
                    .foregroundColor(deduction ? .secondary : .primary)
            }
            .appFont(size: AppFont.bodySmall)
            .padding(.vertical, 5)
            if editingField == field {
                VStack(spacing: 8) {
                    HStack {
                        TextField(placeholder, text: $editText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(editFieldFocused ? AppStyle.surface2 : AppStyle.surface1)
                            .cornerRadius(8)
                            .shadow(color: editFieldFocused ? Color.black.opacity(0.12) : .clear, radius: 4, y: 1)
                            .focused($editFieldFocused)
                        Button("保存") { Task { await saveEdit() } }
                            .buttonStyle(.borderedProminent)
                            // 1.3.2.005（方案 §3.3）：系统按钮只有约 34pt 高，透明留白扩到 48pt。
                            .touchTarget(vertical: 7)
                            .disabled(editSaving)
                        Button("取消") { dismissEdit() }
                            .buttonStyle(.bordered)
                            // 1.3.2.005（方案 §3.3）：同上，透明留白扩到 48pt。
                            .touchTarget(vertical: 7)
                    }
                    if let editError {
                        Text(editError)
                            .appFont(size: AppFont.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 8)
            }
            Divider()
        }
    }

    /// 打开某行的 inline 编辑框（1.2.7 起每人改自己的当月数，不再只对老爷开放；打开时填当前值、弹键盘）。
    private func openEdit(_ field: PayRecordField, currentValue: String) {
        editText = currentValue
        editError = nil
        editSaving = false
        editingField = field
        editFieldFocused = true
    }

    /// 收起编辑框（丢弃未保存的改动：输入框恢复成原来的值——下次打开时重新填当前值；同时收键盘）。
    private func dismissEdit() {
        editingField = nil
        editText = ""
        editError = nil
        editSaving = false
        editFieldFocused = false
    }

    /// 保存当前编辑框（按字段校验范围，写服务端，本地立刻重算；保存完收起）。
    private func saveEdit() async {
        guard let field = editingField else { return }
        editError = nil
        guard let value = Double(editText.trimmingCharacters(in: .whitespaces)) else {
            editError = "输个数字"
            return
        }
        let range: ClosedRange<Double>
        let hint: String
        switch field {
        case .deptPerf:
            range = 0...10000; hint = "0–10000"
        case .perfCoef, .bonusCoef:
            range = 0...3; hint = "0–3"
        case .overtimeDays:
            range = 0...31; hint = "0–31"
        case .utilities:
            range = 0...1000; hint = "0–1000"
        }
        guard range.contains(value) else {
            editError = "输个 \(hint) 之间的数"
            return
        }
        editSaving = true
        let key = String(format: "%04d-%02d", store.payYearMonth.year, store.payYearMonth.month)
        await store.updatePayMonthField(monthKey: key, field: field, value: value)
        editSaving = false
        dismissEdit()
    }

    /// 实际出勤可能是小数（如录入的 23.4、24.31）：整数按整数显示，小数保留 1 位。
    private func attendanceText(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value == value.rounded() { return "\(Int(value)) 天" }
        return String(format: "%.1f 天", value)
    }

    /// 数据更新时间（1.3.2.005，方案 §9 第四条）：本地缓存最后一次成功取数的时间；
    /// 冷启动读磁盘缓存时是缓存的写入时间。没取到过就不显示。
    private var syncTimeFooter: some View {
        Group {
            if let at = store.lastSyncAt {
                Text("数据更新于 \(Self.syncTimeFormatter.string(from: at))")
                    .appFont(size: AppFont.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private static let syncTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
