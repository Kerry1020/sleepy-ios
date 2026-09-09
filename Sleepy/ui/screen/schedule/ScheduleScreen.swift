// ScheduleScreen.swift — ← ui/screen/schedule/ScheduleScreen.kt
// 课表页: TopBar(周导航+跳周菜单) + 视图切换(周视图/网格) + 左右滑翻周(TabView pager) +
// 详情 BottomSheet。空态两分支: 无表 → EmptyState; 有表无课 → NoCourseState。

import SwiftUI

private enum ViewMode: Hashable {
    case full   // ← ViewMode.Full (周视图)
    case cards  // ← ViewMode.Cards (网格)
}

struct ScheduleScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @ObservedObject var viewModel: ScheduleViewModel
    var onGoImport: () -> Void = {}
    var onManualAdd: () -> Void = {}
    var onCreateTable: () -> Void = {}
    var onEditCourse: (CourseEntity) -> Void = { _ in }

    // ← AppPrefs.getStartView Android; 顶部手动切换仍只改本地页面状态,不写回启动偏好
    @State private var viewMode: ViewMode = AppPrefs.shared.getStartView() == "cards" ? .cards : .full
    @State private var selectedCourse: CourseEntity? = nil
    // v7.10.16: 无可撤回时 toast 提示(按钮不隐藏保持布局稳定)
    @State private var showUndoNoneToast = false
    // v7.10.14 顶栏 logo → 课表切换弹窗
    @State private var showTableSwitcher = false
    // v7.10.7 顶栏分享 → 格式选择弹层
    @State private var showShareSheet = false

    var body: some View {
        let state = viewModel.state
        let displayMode = AppPrefs.shared.getDisplayMode()
        let showDate = AppPrefs.shared.isShowDate()
        let visibleDays = AppPrefs.shared.getVisibleDays()

        let hasTable = !state.tables.isEmpty
        let hasCourses = !state.courses.isEmpty

        VStack(spacing: 0) {
            if !hasTable {
                // 真的没表: 去创建
                EmptyState(onGoImport: onGoImport, onCreateTable: onCreateTable)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else if !hasCourses {
                // 有表无课: 加课/导入
                NoCourseState(tableName: state.currentTable?.name ?? "",
                              onAddCourse: onManualAdd, onImport: onGoImport)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                ScheduleTopBar(
                    currentWeek: state.selectedWeek,
                    maxWeek: state.currentTable?.maxWeek ?? 20,
                    startDate: state.currentTable?.startDate ?? "",
                    onPrevWeek: { viewModel.changeWeek(state.selectedWeek - 1) },
                    onNextWeek: { viewModel.changeWeek(state.selectedWeek + 1) },
                    onJumpToActual: {
                        guard let start = state.currentTable?.startDate else { return }
                        viewModel.changeWeek(DateUtils.currentWeek(startDate: start))
                    },
                    onSelectWeek: { week in viewModel.changeWeek(week) },
                    onUndo: {
                        // v7.10.16: 任何课表数据改动可一键撤销一次
                        if !viewModel.undoLastChange() {
                            showUndoNoneToast = true
                        }
                    },
                    onSwitchTable: { showTableSwitcher = true },
                    onAddCourse: onManualAdd,
                    onShare: { showShareSheet = true },
                    hasUndoSnapshot: UndoManager.shared.hasSnapshot)

                // Segmented Switcher
                SegmentedSwitcher(
                    options: [(ViewMode.full, L10n.format("view_full")),
                              (ViewMode.cards, L10n.format("view_cards"))],
                    selected: viewMode) { viewMode = $0 }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                // 主体视图 — 左右滑动切换周次(TabView pager)
                let pagerMaxWeek = max(state.currentTable?.maxWeek ?? 20, 1)
                WeekPager(viewModel: viewModel, viewMode: viewMode, pagerMaxWeek: pagerMaxWeek,
                          displayMode: displayMode, showDate: showDate, visibleDays: visibleDays) {
                    selectedCourse = $0
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // v7.10.14 课表切换弹窗(← TableSwitcherDialog)
        .sheet(isPresented: $showTableSwitcher) {
            TableSwitcherSheet(
                tables: state.tables,
                selectedTableId: state.selectedTableId,
                onSelect: { id in
                    viewModel.selectTable(id)
                    showTableSwitcher = false
                },
                onDismiss: { showTableSwitcher = false })
        }
        // v7.10.7 顶栏分享 → 格式选择弹层(JSON / 分享文本 / ICS)
        .sheet(isPresented: $showShareSheet) {
            if let table = state.currentTable {
                ShareScheduleSheet(table: table, courses: state.courses,
                                   onDismiss: { showShareSheet = false })
            }
        }
        // ← Android Toast schedule_undo_none
        .overlay(alignment: .bottom) {
            if showUndoNoneToast {
                Text(L10n.format("schedule_undo_none"))
                    .font(.system(size: 14, weight: .medium)) // ← Android Snackbar bodyMedium 14
                    .foregroundColor(colors.onSurface)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(colors.surfaceContainerHigh)
                    .cornerRadius(SleepyShapes.large)
                    .padding(.bottom, 24)
                    .transition(.opacity)
                    // 原生并发取消语义: id 变化自动取消旧计时,连发不误杀(← asyncAfter)
                    .task(id: showUndoNoneToast) {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation { showUndoNoneToast = false }
                    }
            }
        }
        // 详情 Bottom Sheet
        .sheet(item: $selectedCourse) { course in
            CourseDetailSheet(
                course: course,
                timeString: course.nodeString(),
                // v7.10.16q: allCourses 必须与网格同周域(selectedWeek 过滤) —
                // 周次不相交同行(如周1-4/周6-13)全量传会被当成同时存在 → 幽灵图层
                allCourses: state.courses.filter { $0.inWeek(state.selectedWeek) },
                onEdit: { c in
                    selectedCourse = nil
                    onEditCourse(c)
                })
        }
    }
}

// HorizontalPager → TabView(.page): 双向同步(手势→VM / VM→pager)
// Cards 网格的 TimeSlot: parseNodes 每节一行(node/nodeStart 单节, Android 同为逐节行)
private func cardTimeSlots(table: TimeTableEntity?) -> [TimeSlot] {
    let nodes = TimeTableUtils.parseNodes(table?.timeJson ?? TimeTableUtils.DEFAULT_TIME_JSON)
    return nodes.map { n in
        let sc = Calendar.current.dateComponents([.hour, .minute], from: n.start)
        let ec = Calendar.current.dateComponents([.hour, .minute], from: n.end)
        return TimeSlot(label: "\(n.node)", startHour: sc.hour ?? 0, startMinute: sc.minute ?? 0,
                        endHour: ec.hour ?? 0, endMinute: ec.minute ?? 0, nodeStart: n.node)
    }
}
private struct WeekPager: View {
    @ObservedObject var viewModel: ScheduleViewModel
    let viewMode: ViewMode
    let pagerMaxWeek: Int
    let displayMode: String
    let showDate: Bool
    let visibleDays: Set<Int>
    let onCourseClick: (CourseEntity) -> Void

    // 每个 pager 页独立缓存灰显星期 ← Android produceState(greyDays, page, startDate)
    @State private var greyDaysByWeek: [Int: Set<Int>] = [:]

    var body: some View {
        let state = viewModel.state
        // VM 变化(TopBar 点击) → 同步 pager(binding 直写, 防双向打架由 onChange 用户手势分支承担)
        TabView(selection: Binding(
            get: { min(max(state.selectedWeek, 1), pagerMaxWeek) },
            set: { newWeek in viewModel.changeWeek(newWeek) }   // 手势滑动 → VM
        )) {
            ForEach(1...pagerMaxWeek, id: \.self) { page in
                // page 是 1-based 周索引,独立于 state.currentWeek 过滤课程
                let weekCourses: [CourseEntity] = {
                    let list = state.courses.filter { $0.inWeek(page) }
                    guard let tj = state.currentTable?.timeJson else { return list }
                    return list.map { $0.normalizeNode(timeJson: tj) }
                }()
                Group {
                    switch viewMode {
                    case .full:
                        FullWeekView(courses: weekCourses,
                                     visibleDays: visibleDays,
                                     displayMode: displayMode,
                                     timeJson: state.currentTable?.timeJson ?? "",
                                     onCourseClick: onCourseClick,
                                     greyDays: greyDaysByWeek[page] ?? [])
                    case .cards:
                        CardsGridView(courses: weekCourses,
                                      timeSlots: cardTimeSlots(table: state.currentTable),
                                      visibleDays: visibleDays,
                                      showDate: showDate,
                                      startDate: state.currentTable?.startDate ?? "",
                                      currentWeek: page,
                                      onCourseClick: onCourseClick,
                                      greyDays: greyDaysByWeek[page] ?? [])
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tag(page)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tabViewStyle(.page(indexDisplayMode: .never))
        // 每页独立计算灰显星期(节假日/周末) ← Android produceState(greyDays, page, startDate)
        .task(id: "\(state.currentTable?.startDate ?? "")-\(state.selectedWeek)-\(pagerMaxWeek)") {
            let start = state.currentTable?.startDate ?? ""
            guard !start.isEmpty else {
                greyDaysByWeek = [:]
                return
            }
            for week in 1...pagerMaxWeek where greyDaysByWeek[week] == nil {
                var grey: Set<Int> = []
                for day in 1...7 {
                    if let date = DateUtils.dateOfWeek(startDate: start, week: week, dayOfWeek: day),
                       await HolidayManager.shouldGrey(date) {
                        grey.insert(day)
                    }
                }
                greyDaysByWeek[week] = grey
            }
        }
    }
}

// ← TopBar
private struct ScheduleTopBar: View {
    @Environment(\.localWakeUpColors) private var colors
    let currentWeek: Int
    let maxWeek: Int
    let startDate: String
    let onPrevWeek: () -> Void
    let onNextWeek: () -> Void
    let onJumpToActual: () -> Void
    let onSelectWeek: (Int) -> Void
    var onUndo: () -> Void = {}
    var onSwitchTable: () -> Void = {}
    var onAddCourse: () -> Void = {}
    var onShare: () -> Void = {}
    /// v7.10.16g: 撤回按钮仅有可撤回快照时显示(UndoManager.hasSnapshot 订阅)
    var hasUndoSnapshot: Bool = false

    @State private var menuOpen = false

    var body: some View {
        let actualWeek = startDate.isEmpty ? 1 : DateUtils.currentWeek(startDate: startDate)
        let isOnActual = currentWeek == actualWeek
        let semesterStatus = DateUtils.semesterStatus(startDate: startDate, maxWeek: maxWeek)

        // v7.10.12: 三件套改 ZStack 叠加实现屏幕正中 —
        // 旧 Spacer 平衡是在"扣除两侧按钮后的剩余空间"里居中, 视觉偏移;
        // ZStack 叠加让三件套对齐全宽正中, 两侧操作区绝对定位(← Android Box 叠加)。
        ZStack {
            // 翻页三件套(箭头+胶囊+箭头) — 箭头紧贴胶囊, 全宽正中
            HStack(spacing: 8) {
                pagerTriple   // 见下(week label sheet 挂在胶囊上)
            }
            .frame(maxWidth: .infinity)

            // 最左操作区: logo(课表切换) + 撤回(仅有可撤回快照时显示)
            HStack(spacing: 6) {
                WeekNavButton(icon: "calendar", a11yLabel: L10n.format("schedule_switch_table"), onClick: onSwitchTable)
                    .accessibilityIdentifier("switch_table")
                if hasUndoSnapshot {
                    WeekNavButton(icon: "arrow.uturn.backward", a11yLabel: L10n.format("schedule_undo"), onClick: onUndo)
                        .accessibilityIdentifier("undo_button")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右侧操作区: 加课 + 分享 — 与翻页箭头同款圆形底
            HStack(spacing: 6) {
                WeekNavButton(icon: "plus", a11yLabel: L10n.format("schedule_add_course"), onClick: onAddCourse)
                    .accessibilityIdentifier("topbar_add")
                WeekNavButton(icon: "square.and.arrow.up", a11yLabel: L10n.format("schedule_share_table"), onClick: onShare)
                    .accessibilityIdentifier("topbar_share")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(colors.surface)
    }

    // 翻页三件套(箭头+胶囊+箭头); 胶囊点击 = 跳周菜单/一键跳回
    private var pagerTriple: some View {
        let actualWeek = startDate.isEmpty ? 1 : DateUtils.currentWeek(startDate: startDate)
        let isOnActual = currentWeek == actualWeek
        let semesterStatus = DateUtils.semesterStatus(startDate: startDate, maxWeek: maxWeek)
        return HStack(spacing: 8) {
            WeekNavButton(icon: "chevron.left", onClick: onPrevWeek)

            // 第 N 周 标签 — 点击行为根据是否在当前实际周而不同
            // ★ iOS 16 修复(二段): Menu 挂非 Button 顶层内容(VStack/LazyVGrid)在
            //   iOS 16 上点击不展开(实测 menu 元素为 0)→ 改为 Button + sheet 弹层,
            //   与 Android FlowRow 280dp 弹层语义一致。
            Button {
                if isOnActual {
                    menuOpen = true
                } else {
                    onJumpToActual()   // 不在实际周 → 一键跳回(原 simultaneousGesture 语义)
                }
            } label: {
                // ★ 学期外: 标签带上周数(学期未开始 · 第 3 周), 翻周时数字跟着变, 用户才知道自己看到第几周
                Text(semesterStatus == .inRange
                     ? L10n.format("schedule_current_week", currentWeek)
                     : "\(L10n.format(semesterStatus == .beforeStart ? "semester_not_started" : "semester_ended")) · \(L10n.format("schedule_week_prefix", currentWeek))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isOnActual ? colors.onPrimaryContainer : colors.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(isOnActual ? colors.primaryContainer
                                           : colors.primaryContainer.opacity(SleepyTheme.Alpha.inactive))
                    .cornerRadius(SleepyShapes.medium)
            }
            .buttonStyle(SleepyButtonStyle())
            .accessibilityIdentifier("week_label")   // ← G5: 跳周菜单锚点
            .sheet(isPresented: $menuOpen) {
                // ★ v7.10.18 原生化: Picker(.wheel) 系统原生滚轮选择器
                //   - iOS 15+ 自动获得系统震动反馈 + 高亮当前值
                //   - 比自制 LazyVGrid 更短(33 行 → 20 行)+ 一致 iOS 体验
                //   - sheetDetents .medium 自带下拉 dismiss,保持 iOS 16+ swipe 手势
                VStack(spacing: 8) {
                    Text(L10n.format("schedule_jump_week"))
                        .font(.system(size: 12, weight: .medium)) // ← Android labelMedium 12
                        .foregroundColor(colors.onSurfaceVariant)
                    Picker("", selection: Binding(
                        get: { currentWeek },
                        set: { newWeek in onSelectWeek(newWeek) }
                    )) {
                        ForEach(1...maxWeek, id: \.self) { w in
                            Text("\(w)").tag(w)
                                .accessibilityIdentifier("week_num_\(w)")
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 200)
                }
                .padding(.vertical, 16)
                .sheetDetents([.medium])
                // 选中即关(iOS 16+ 用户改值后也能手动 ✕)
                .onChange(of: currentWeek) { _ in
                    if menuOpen { menuOpen = false }
                }
            }

            WeekNavButton(icon: "chevron.right", onClick: onNextWeek)
        }
    }
}

// v7.10.14 顶栏 logo 点击弹出的课表切换弹层 —
// 列出全部课表, 当前行 primaryContainer 高亮 + 对勾, 点击即切换。
private struct TableSwitcherSheet: View {
    @Environment(\.localWakeUpColors) private var colors
    let tables: [TimeTableEntity]
    let selectedTableId: Int64?
    let onSelect: (Int64) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(L10n.format("schedule_switch_table"))
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(colors.onSurface)
                .padding(.top, 16)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(tables) { table in
                        let isCurrent = table.id == selectedTableId
                        Button {
                            onSelect(table.id)
                        } label: {
                            HStack {
                                Text(table.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(isCurrent ? colors.onPrimaryContainer : colors.onSurface)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if isCurrent {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15))
                                        .foregroundColor(colors.primary)
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 8)
                            .background(isCurrent ? colors.primaryContainer : colors.surfaceContainer)
                            .cornerRadius(SleepyShapes.medium)
                        }
                        .buttonStyle(SleepyButtonStyle())
                        .accessibilityIdentifier("switch_table_\(table.id)")
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(maxHeight: 360)
        }
        .padding(.bottom, 16)
        .sheetDetents([.medium])
    }
}

// ← WeekNavButton
private struct WeekNavButton: View {
    @Environment(\.localWakeUpColors) private var colors
    let icon: String
    // ← Android contentDescriptionRes: 传了才挂 a11y 标签, 箭头按钮不传
    var a11yLabel: String? = nil
    let onClick: () -> Void

    var body: some View {
        if let a11yLabel {
            button.accessibilityLabel(a11yLabel)
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: onClick) {
            Image(systemName: icon)
                .foregroundColor(colors.onSurfaceVariant)
                .frame(width: 32, height: 32)
                .background(colors.surfaceContainerHigh)
                .clipShape(Circle())
                .padding(6)
        }
        .buttonStyle(SleepyButtonStyle())
        // ← G5: 周导航箭头锚点(chevron.left → week_prev / chevron.right → week_next)
        .accessibilityIdentifier(icon.contains("left") ? "week_prev" : "week_next")
    }
}

// ← NoCourseState
private struct NoCourseState: View {
    @Environment(\.localWakeUpColors) private var colors
    let tableName: String
    let onAddCourse: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(L10n.format("schedule_empty_name", tableName))
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(colors.onSurface)
            Text(L10n.format("schedule_empty_name_hint"))
                .font(.system(size: 14))
                .foregroundColor(colors.onSurfaceVariant)
            Button(action: onAddCourse) {
                Text(L10n.format("schedule_manual_first"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(colors.primary)
                    .cornerRadius(SleepyShapes.large)
            }
            .buttonStyle(SleepyButtonStyle())
            Button(action: onImport) {
                Text(L10n.format("schedule_go_manage"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onSecondaryContainer)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(colors.secondaryContainer)
                    .cornerRadius(SleepyShapes.large)
            }
            .buttonStyle(SleepyButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.extraLarge)
    }
}

// ← EmptyState — 主按钮=导入第一张课表, 副按钮=建表流(无表载体时"加课"无从谈起, ← Android)
private struct EmptyState: View {
    @Environment(\.localWakeUpColors) private var colors
    let onGoImport: () -> Void
    var onCreateTable: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            Text(L10n.format("schedule_empty"))
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(colors.onSurface)
            Text(L10n.format("schedule_empty_hint"))
                .font(.system(size: 14))
                .foregroundColor(colors.onSurfaceVariant)
            Button(action: onGoImport) {
                Text(L10n.format("schedule_empty_import"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(colors.primary)
                    .cornerRadius(SleepyShapes.large)
            }
            .buttonStyle(SleepyButtonStyle())
            Button(action: onCreateTable) {
                Text(L10n.format("schedule_empty_create_table"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onSecondaryContainer)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(colors.secondaryContainer)
                    .cornerRadius(SleepyShapes.large)
            }
            .buttonStyle(SleepyButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.extraLarge)
    }
}
