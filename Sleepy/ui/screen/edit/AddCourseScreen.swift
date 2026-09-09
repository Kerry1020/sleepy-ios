// AddCourseScreen.swift — ← ui/screen/edit/AddCourseScreen.kt (1229 行)
// 新建/编辑课程: 基本信息(名/师/室/注/颜色)+周次范围+多时段 block(按节次/按时间双模式+
// 星期多选)+校验(空名/天数/正数/时间格式/时段重叠)+保存(编辑=组替换,新建=共享 groupId)+
// 删除组。HSV 调色盘(SV 面板+色相条)。

import SwiftUI

enum MeetingInputMode: Hashable { case byNode, byClock }

// ← MeetingBlockDraft(SnapshotStateList → @Published 手动管理)
struct MeetingBlockDraft: Identifiable {
    let id: Int
    var days: Set<Int>
    var mode: MeetingInputMode
    var startNode: Int
    var step: Int
    var startTime: String
    var endTime: String
    var startWeek: Int
    var endWeek: Int
    var weekType: Int
    /// issue#22: 老师/地点/备注/颜色下沉到每时段独立编辑 — 同名同周次不同地点不再相互覆盖
    var room: String = ""
    var teacher: String = ""
    var note: String = ""
    var color: String = ""
    var colorMode: Int = CourseColorMode.GROUP
    var clamped: Bool = false
}

struct ValidationIssue {
    let blockId: Int?
    let message: String
}

struct AddCourseScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @ObservedObject var viewModel: ScheduleViewModel
    let onDismiss: () -> Void
    let onSaved: () -> Void
    var editingCourse: CourseEntity? = nil

    @State private var loadedForId: Int64 = -1
    @State private var courseName = ""
    @State private var startWeek = 1
    @State private var endWeek = 16
    @State private var nextBlockId = 2
    @State private var validationIssues: [ValidationIssue] = []
    @State private var meetingBlocks: [MeetingBlockDraft] = []
    @State private var showDeleteConfirm = false
    @State private var showConflictConfirm = false
    @State private var pendingConflictDetails: [String] = []
    @State private var groupLoaded = false

    private var canSave: Bool { !courseName.trimmingCharacters(in: .whitespaces).isEmpty && !meetingBlocks.isEmpty }

    var body: some View {
        let state = viewModel.state
        let currentTable = state.currentTable

        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format(editingCourse != nil ? "edit_course" : "create_course"),
                           onBack: onDismiss)
            ScrollView {
                VStack(spacing: 14) {
                    Spacer().frame(height: 2)

                    if !validationIssues.isEmpty {
                        ValidationCard(issues: validationIssues)
                    }

                    basicInfoCard
                    weekRangeCard

                    // 上课时段标题
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.format("meeting_slots"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colors.onSurface)
                        Text(L10n.format("meeting_slots_sub"))
                            .font(.system(size: 12))
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(Array(meetingBlocks.enumerated()), id: \.element.id) { index, _ in
                        MeetingBlockEditor(
                            title: L10n.format("slot_n", index + 1),
                            block: bindingForBlock(at: index),
                            maxNode: Self.maxNode(for: currentTable),
                            canRemove: meetingBlocks.count > 1,
                            issues: validationIssues.filter { $0.blockId == meetingBlocks[index].id }.map { $0.message },
                            onRemove: { meetingBlocks.remove(at: index) })
                    }

                    // 新增时段按钮
                    VStack(spacing: 10) {
                        Button {
                            meetingBlocks.append(MeetingBlockDraft(
                            id: nextBlockId, days: [2], mode: .byNode,
                            startNode: 3, step: 2, startTime: "10:00", endTime: "11:40",
                            startWeek: min(startWeek, endWeek), endWeek: max(startWeek, endWeek), weekType: 0))
                        nextBlockId += 1
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text(L10n.format("add_slot"))
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onSecondaryContainer)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(colors.secondaryContainer)
                        .cornerRadius(SleepyShapes.large)
                    }
                    .buttonStyle(SleepyButtonStyle())
                    .accessibilityIdentifier("course_add_slot")

                    Button {
                        for index in meetingBlocks.indices {
                            meetingBlocks[index].startWeek = min(startWeek, endWeek)
                            meetingBlocks[index].endWeek = max(startWeek, endWeek)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.to.line.compact")
                            Text(L10n.format("apply_to_all_slots"))
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onSecondaryContainer)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(colors.secondaryContainer)
                        .cornerRadius(SleepyShapes.large)
                    }
                    .buttonStyle(SleepyButtonStyle())
                    .accessibilityIdentifier("course_apply_to_all_slots")
                    }

                    // 保存
                    Button(action: { save(state: state) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                            Text(L10n.format(editingCourse != nil ? "save_course" : "create_course_btn"))
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(colors.primary)
                        .cornerRadius(SleepyShapes.large)
                    }
                    .buttonStyle(SleepyButtonStyle())
                    .disabled(!canSave)
                    .accessibilityIdentifier("course_save")

                    // 删除(编辑模式)
                    if editingCourse != nil {
                        Button(action: { showDeleteConfirm = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "trash")
                                Text(L10n.format("delete_course"))
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colors.onErrorContainer)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(colors.errorContainer)
                            .cornerRadius(SleepyShapes.large)
                        }
                        .buttonStyle(SleepyButtonStyle())
                        .accessibilityIdentifier("course_delete")
                    }

                    Spacer().frame(height: 32)
                }
                .padding(.horizontal, 16)
            }
        }
        .background(colors.background)
        .onAppear { loadIfNeeded(state: state) }
        // issue#22: 顶层 ColorPickerDialog 已删 — 颜色按 block 独立弹窗(见 MeetingBlockEditor 内的 ColorSection)
        .alert(L10n.format("confirm_delete"), isPresented: $showDeleteConfirm) {
            Button(L10n.format("delete"), role: .destructive) {
                showDeleteConfirm = false
                if let eg = editingCourse, let tid = state.selectedTableId {
                    try? ScheduleRepository(AppDatabase.getShared()).deleteCourseGroup(tid, eg.groupId)
                }
                onSaved()
            }
            Button(L10n.format("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.format("delete_course_confirm", editingCourse?.courseName ?? ""))
        }
        .alert(L10n.format("conflict_detail_title"), isPresented: $showConflictConfirm) {
            Button(L10n.format("conflict_detail_save_anyway")) {
                showConflictConfirm = false
                save(state: state, forceAfterConflict: true)
            }
            Button(L10n.format("conflict_detail_go_back"), role: .cancel) {
                showConflictConfirm = false
            }
        } message: {
            Text(pendingConflictDetails.joined(separator: "\n"))
        }
    }

    // ← 基本信息
    private var basicInfoCard: some View {
        CardSection(title: L10n.format("course_basic_info"),
                    subtitle: L10n.format("course_basic_info_sub")) {
            VStack(spacing: 12) {
                FieldTextField(text: $courseName, label: L10n.format("course_name_required"))
                // issue#22: teacher/room/note/color 已下沉到每个 MeetingBlockDraft(同名多地点独立编辑)
            }
        }
    }

    // ← 周次范围
    private var weekRangeCard: some View {
        CardSection(title: L10n.format("week_range"),
                    subtitle: L10n.format("week_range_sub")) {
            HStack(spacing: 12) {
                NumberStepperField(label: L10n.format("start_week"), value: $startWeek, minV: 1, maxV: 30)
                NumberStepperField(label: L10n.format("end_week"), value: $endWeek, minV: 1, maxV: 30)
            }
        }
    }

    private func bindingForBlock(at index: Int) -> Binding<MeetingBlockDraft> {
        Binding(
            get: { meetingBlocks[index] },
            set: { meetingBlocks[index] = $0 })
    }

    // ← remember(editingCourse?.id) 初始状态 + 编辑模式查同 groupId 回填多 block
    private func loadIfNeeded(state: ScheduleState) {
        let key = editingCourse?.id ?? 0
        guard loadedForId != key else { return }
        loadedForId = key
        groupLoaded = false
        courseName = editingCourse?.courseName ?? ""
        startWeek = editingCourse?.startWeek ?? 1
        endWeek = editingCourse?.endWeek ?? 16
        nextBlockId = 2
        validationIssues = []
        meetingBlocks = [Self.initialMeetingBlock(editingCourse)]

        // LaunchedEffect(editingCourse?.groupId): 查同 groupId 分组回填
        if let eg = editingCourse, !eg.groupId.isEmpty, let tid = state.selectedTableId {
            let repo = ScheduleRepository(AppDatabase.getShared())
            if let groupCourses = try? repo.getGroupCourses(tid, eg.groupId), !groupCourses.isEmpty {
                // 按完整时段特征分组: ownTime/startNode/step/startTime/endTime/startWeek/endWeek/type
                // issue#22: room/teacher 进分组 key — 同名同周次不同地点/老师 → 独立编辑块
                let slots = Dictionary(grouping: groupCourses) {
                    "\($0.ownTime)-\($0.startNode)-\($0.step)-\($0.startTime)-\($0.endTime)-\($0.startWeek)-\($0.endWeek)-\($0.type)-\($0.room)-\($0.teacher)"
                }
                var blocks: [MeetingBlockDraft] = []
                var bid = 1
                for (_, courses) in slots {
                    let first = courses[0]
                    blocks.append(MeetingBlockDraft(
                        id: bid,
                        days: Set(courses.map { $0.day }),
                        mode: first.ownTime ? .byClock : .byNode,
                        startNode: first.startNode,
                        step: first.step,
                        startTime: first.startTime.isEmpty ? "08:00" : first.startTime,
                        endTime: first.endTime.isEmpty ? "09:40" : first.endTime,
                        startWeek: first.startWeek, endWeek: first.endWeek,
                        weekType: first.type,
                        room: first.room, teacher: first.teacher,
                        note: first.note, color: first.color,
                        colorMode: first.colorMode))
                    bid += 1
                }
                meetingBlocks = blocks
            }
        }
        groupLoaded = true
    }

    // ← 保存: 校验 → 冲突报告 → 编辑组替换 / 新建共享 groupId
    private func save(state: ScheduleState, forceAfterConflict: Bool = false) {
        let issues = Self.validateCourseDraft(courseName: courseName, blocks: meetingBlocks,
                                              startWeek: startWeek, endWeek: endWeek,
                                              table: state.currentTable)
        validationIssues = issues
        guard issues.isEmpty else { return }

        let draftTableId = state.selectedTableId ?? 0
        // issue#22: color/teacher/room/note 从 block 取(每时段独立)
        let drafts = meetingBlocks.flatMap { block in
            block.days.sorted().map { day in
                Self.buildCourseEntity(
                    tableId: draftTableId, groupId: "",
                    courseName: courseName.trimmingCharacters(in: .whitespaces),
                    day: day, block: block)
            }
        }

        let repo = ScheduleRepository(AppDatabase.getShared())
        // 冲突检测(新建 / 编辑同一 groupId 的草稿都不算 — 用 groupId 排除被编辑的自己)
        if !forceAfterConflict, draftTableId != 0, let table = state.currentTable {
            let stored = ((try? repo.getCourses(draftTableId)) ?? [])
                .filter { editingCourse?.groupId != $0.groupId }
                .map { Self.conflictLite($0.normalizeNode(timeJson: table.timeJson)) }
            let draftLites = drafts.map(Self.conflictLite)
            let dayNames = (1...7).map { DateUtils.localizedDay($0) }
            let details = ConflictDetailReporter.draftConflictDetails(
                drafts: draftLites, stored: stored, dayNames: dayNames)
                .map { ConflictDetailReporter.formatDetail($0, template: L10n.format("conflict_detail_line")) }
            if !details.isEmpty {
                pendingConflictDetails = details
                showConflictConfirm = true
                return
            }
        }

        // 没表就自动建一张
        let tableId = state.selectedTableId ?? viewModel.createEmptyTable()
        var fixedDrafts = drafts
        for i in fixedDrafts.indices { fixedDrafts[i].tableId = tableId }
        if let eg = editingCourse {
            // 编辑: 行级 diff/patch 替换整组覆盖 — issue#22 同名多地点
            // 只动该 groupId 内的行, 不波及同表其他课程;房间/老师改动=新 RowKey → 旧行删新行插
            let gid = eg.groupId
            for i in fixedDrafts.indices { fixedDrafts[i].groupId = gid }
            let existing = ((try? repo.getCourses(tableId)) ?? []).filter { $0.groupId == gid }
            let diff = RowKeyDiffer.diff(fixedDrafts, existing)
            try? repo.applyDiff(tableId, diff)
        } else {
            // 新建: 所有草稿共享同一个 groupId
            let gid = UUID().uuidString
            for i in fixedDrafts.indices { fixedDrafts[i].groupId = gid }
            _ = try? repo.insertCourses(fixedDrafts)
        }
        onSaved()
    }

    // ← initialMeetingBlock
    static func initialMeetingBlock(_ course: CourseEntity?) -> MeetingBlockDraft {
        guard let course = course else {
            return MeetingBlockDraft(id: 1, days: [1], mode: .byNode, startNode: 1, step: 2,
                                     startTime: "08:00", endTime: "09:40",
                                     startWeek: 1, endWeek: 16, weekType: 0)
        }
        return MeetingBlockDraft(id: 1, days: [course.day],
                                 mode: course.ownTime ? .byClock : .byNode,
                                 startNode: course.startNode, step: course.step,
                                 startTime: course.startTime.isEmpty ? "08:00" : course.startTime,
                                 endTime: course.endTime.isEmpty ? "09:40" : course.endTime,
                                 startWeek: course.startWeek, endWeek: course.endWeek,
                                 weekType: course.type,
                                 room: course.room, teacher: course.teacher,
                                 note: course.note, color: course.color,
                                 colorMode: course.colorMode)
    }

    // ← buildCourseEntity
    static func buildCourseEntity(tableId: Int64, groupId: String, courseName: String,
                                  day: Int, block: MeetingBlockDraft) -> CourseEntity {
        let ownTime = block.mode == .byClock
        // issue#22: color/colorMode 从 block 取;AUTO 模式 color 留空(渲染时按 hash 取)
        let finalColor: String
        switch block.colorMode {
        case CourseColorMode.CUSTOM:
            finalColor = block.color.isEmpty ? "#FF6750A4" : block.color
        case CourseColorMode.AUTO:
            finalColor = ""
        default:
            finalColor = block.color.isEmpty ? "#FF6750A4" : block.color
        }
        return CourseEntity(
            groupId: groupId, tableId: tableId, courseName: courseName,
            teacher: block.teacher.trimmingCharacters(in: .whitespaces),
            room: block.room.trimmingCharacters(in: .whitespaces),
            note: block.note.trimmingCharacters(in: .whitespaces),
            day: day, startNode: block.startNode, step: block.step,
            startWeek: min(block.startWeek, block.endWeek),
            endWeek: max(block.startWeek, block.endWeek), type: block.weekType,
            color: finalColor, colorMode: block.colorMode,
            ownTime: ownTime,
            startTime: ownTime ? block.startTime : "",
            endTime: ownTime ? block.endTime : "")
    }

    // ← validateCourseDraft
    static func validateCourseDraft(courseName: String, blocks: [MeetingBlockDraft],
                                    startWeek: Int, endWeek: Int, table: TimeTableEntity?) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if courseName.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(ValidationIssue(blockId: nil, message: L10n.format("course_name_empty")))
        }
        if startWeek <= 0 || endWeek <= 0 {
            issues.append(ValidationIssue(blockId: nil, message: L10n.format("week_must_be_positive")))
        }
        for (index, block) in blocks.enumerated() {
            if block.startWeek <= 0 || block.endWeek <= 0 || block.startWeek > block.endWeek {
                issues.append(ValidationIssue(blockId: block.id,
                                              message: L10n.format("slot_week_order", index + 1)))
            }
            if block.days.isEmpty {
                issues.append(ValidationIssue(blockId: block.id, message: L10n.format("slot_at_least_one_day", index + 1)))
            }
            switch block.mode {
            case .byNode:
                if block.startNode <= 0 {
                    issues.append(ValidationIssue(blockId: block.id, message: L10n.format("slot_start_node_positive", index + 1)))
                }
                if block.step <= 0 {
                    issues.append(ValidationIssue(blockId: block.id, message: L10n.format("slot_step_positive", index + 1)))
                }
                let maxNode = maxNode(for: table)
                if block.startNode + block.step - 1 > maxNode {
                    issues.append(ValidationIssue(
                        blockId: block.id,
                        message: L10n.format("slot_step_exceeds_max", index + 1,
                                            block.startNode + block.step - 1, maxNode)))
                }
            case .byClock:
                guard let start = parseHm(block.startTime), let end = parseHm(block.endTime) else {
                    issues.append(ValidationIssue(blockId: block.id, message: L10n.format("slot_time_format", index + 1)))
                    continue
                }
                if start >= end {
                    issues.append(ValidationIssue(blockId: block.id, message: L10n.format("slot_time_order", index + 1)))
                }
            }
        }
        // 时段重叠检测
        for i in blocks.indices {
            for j in (i + 1)..<blocks.count {
                let first = blocks[i], second = blocks[j]
                let overlapDays = first.days.intersection(second.days)
                if overlapDays.isEmpty { continue }
                guard let firstRange = blockRangeMinutes(first, table),
                      let secondRange = blockRangeMinutes(second, table) else { continue }
                if firstRange.0 < secondRange.1 && secondRange.0 < firstRange.1 {
                    let dayText = overlapDays.sorted().map { DateUtils.localizedDay($0) }.joined(separator: " / ")
                    issues.append(ValidationIssue(blockId: second.id,
                                                  message: L10n.format("slot_time_overlap", i + 1, j + 1, dayText)))
                }
            }
        }
        return issues
    }

    static func maxNode(for table: TimeTableEntity?) -> Int {
        let nodes = TimeTableUtils.parseNodes(table?.timeJson ?? TimeTableUtils.DEFAULT_TIME_JSON)
        return nodes.map(\.node).max() ?? table?.nodesPerDay ?? 12
    }

    private static func conflictLite(_ course: CourseEntity) -> CourseEntityLite {
        CourseEntityLite(courseName: course.courseName, day: course.day,
                         startNode: course.startNode, step: course.step,
                         startWeek: course.startWeek, endWeek: course.endWeek,
                         type: course.type)
    }

    // ← blockRangeMinutes
    static func blockRangeMinutes(_ block: MeetingBlockDraft, _ table: TimeTableEntity?) -> (Int, Int)? {
        switch block.mode {
        case .byClock:
            guard let start = parseHm(block.startTime), let end = parseHm(block.endTime) else { return nil }
            return (start, end)
        case .byNode:
            let timeJson = table?.timeJson ?? TimeTableUtils.DEFAULT_TIME_JSON
            let nodes = parseNodeMinuteMap(timeJson)
            guard let start = nodes[block.startNode]?.0 else { return nil }
            guard let end = nodes[block.startNode + block.step - 1]?.1 else { return nil }
            return (start, end)
        }
    }

    // ← parseNodeMinuteMap
    static func parseNodeMinuteMap(_ timeJson: String) -> [Int: (Int, Int)] {
        guard let data = timeJson.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
        var map: [Int: (Int, Int)] = [:]
        for o in arr {
            guard let node = (o["node"] as? NSNumber)?.intValue,
                  let startS = o["start"] as? String,
                  let endS = o["end"] as? String,
                  let s = parseHm(startS), let e = parseHm(endS) else { continue }
            map[node] = (s, e)
        }
        return map
    }

    // ← parseHm("HH:mm" → 当日分钟数)
    static func parseHm(_ value: String) -> Int? {
        let parts = value.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }
}

// ← ValidationCard
private struct ValidationCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let issues: [ValidationIssue]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.format("fix_issues_first"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colors.onErrorContainer)
            ForEach(issues.prefix(4)) { issue in
                Text("• \(issue.message)")
                    .font(.system(size: 12))
                    .foregroundColor(colors.onErrorContainer)
            }
            if issues.count > 4 {
                Text(L10n.format("more_unexpanded", issues.count - 4))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colors.onErrorContainer)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.errorContainer)
        .cornerRadius(SleepyShapes.large)
    }
}

extension ValidationIssue: Identifiable {
    var id: String { "\(blockId ?? -1)-\(message)" }
}

// ← CardSection(带副标题)
private struct CardSection<Content: View>: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.onSurface)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.extraLarge)
    }
}

// ← MeetingBlockEditor
private struct MeetingBlockEditor: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    @Binding var block: MeetingBlockDraft
    let maxNode: Int
    let canRemove: Bool
    let issues: [String]
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.onSurface)
                    Text(block.days.isEmpty
                         ? L10n.format("select_at_least_one_day")
                         : L10n.format("selected_days",
                                       block.days.sorted().map { DateUtils.localizedDay($0) }.joined(separator: " / ")))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colors.onSurfaceVariant)
                }
                Spacer()
                if canRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                    .buttonStyle(SleepyButtonStyle())
                }
            }

            ModePicker(mode: block.mode) { block.mode = $0 }
            MultiDayPicker(selectedDays: block.days) { day in
                if block.days.contains(day) { block.days.remove(day) } else { block.days.insert(day) }
            }

            HStack(spacing: 12) {
                NumberStepperField(label: L10n.format("start_week"), value: $block.startWeek, minV: 1, maxV: 30)
                NumberStepperField(label: L10n.format("end_week"), value: $block.endWeek, minV: 1, maxV: 30)
            }
            SegmentedSwitcher(options: [
                (0, L10n.format("week_every")),
                (1, L10n.format("week_odd")),
                (2, L10n.format("week_even")),
                (3, L10n.format("week_custom"))
            ], selected: block.weekType) { block.weekType = $0 }

            switch block.mode {
            case .byNode:
                HStack(spacing: 12) {
                    NumberStepperField(label: L10n.format("start_node"), value: Binding(
                        get: { block.startNode }, set: {
                            block.startNode = $0
                            let stepCap = Swift.max(1, maxNode - block.startNode + 1)
                            if block.step > stepCap {
                                block.step = stepCap
                                block.clamped = true
                            }
                        }), minV: 1, maxV: maxNode,
                        onClamp: { block.clamped = true })
                    // startNode 上调 → step 上限同步收紧, 避免越界
                    NumberStepperField(label: L10n.format("step_count"), value: Binding(
                        get: { block.step }, set: { block.step = $0 }),
                        minV: 1, maxV: Swift.max(1, maxNode - block.startNode + 1),
                        onClamp: { block.clamped = true })
                }
            case .byClock:
                HStack(spacing: 12) {
                    TimePickerField(value: block.startTime, onValueChange: { block.startTime = $0 },
                                    label: L10n.format("start_time"))
                    TimePickerField(value: block.endTime, onValueChange: { block.endTime = $0 },
                                    label: L10n.format("end_time"))
                }
            }

            // issue#22: 老师/地点/备注下沉到每时段独立编辑 — 同名同周次不同地点时不再相互覆盖
            // (Group 包一层 — ViewBuilder 单容器 10 子视图上限)
            Group {
                FieldTextField(text: $block.teacher, label: L10n.format("course_teacher"))
                FieldTextField(text: $block.room, label: L10n.format("course_room"))
                MultilineFieldCompat(placeholder: L10n.format("course_note"), text: $block.note, minLines: 2, maxLines: 4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(colors.surfaceContainerLowest)
                    .cornerRadius(SleepyTheme.fieldShape)
                    // ← Android filled TextField, 无描边
                ColorSection(block: $block)
            }

            if block.clamped {
                Text(L10n.format(
                    "slot_step_clamped_hint",
                    block.startNode + block.step - 1,
                    maxNode))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colors.onErrorContainer)
            }
            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(issues, id: \.self) { issue in
                        Text(issue)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.onErrorContainer)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 有 issue 或输入被夹紧时整卡变 errorContainer, 无描边
        .background(issues.isEmpty && !block.clamped ? colors.surfaceContainerHigh : colors.errorContainer)
        .cornerRadius(SleepyShapes.large)
    }
}

// issue#22: 颜色三态 — 开关 OFF = 跟组色(GROUP);开关 ON 后可切 AUTO/CUSTOM
//   - GROUP(默认): color 留空,渲染按 groupId hash 取统一色
//   - AUTO: 同 GROUP 但色相按黄金角(137.508°)发散,自动换色
//   - CUSTOM: 用户在调色盘挑的固定 hex
private struct ColorSection: View {
    @Environment(\.localWakeUpColors) private var colors
    @Binding var block: MeetingBlockDraft
    @State private var showColorPicker = false

    private var useDifferent: Bool { block.colorMode != CourseColorMode.GROUP }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.format("course_color"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onSurfaceVariant)
                Spacer()
                Text(L10n.format(useDifferent ? "color_use_different" : "color_follow_group"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colors.onSurfaceVariant)
                Toggle("", isOn: Binding(
                    get: { useDifferent },
                    set: { on in
                        // 第一次打开: 落 AUTO(自动散色), 用户可再切自定义
                        block.colorMode = on ? CourseColorMode.AUTO : CourseColorMode.GROUP
                    }
                ))
                .labelsHidden()
            }
            if useDifferent {
                HStack(spacing: 10) {
                    // 自动 — 渲染时由 hueForCourse 按黄金角散色
                    AutoColorDot(selected: block.colorMode == CourseColorMode.AUTO) {
                        block.colorMode = CourseColorMode.AUTO
                        block.color = ""
                    }
                    // 自定义 — 弹出调色盘选固定色
                    CustomColorDot(hex: block.colorMode == CourseColorMode.CUSTOM && !block.color.isEmpty
                                   ? block.color : nil) {
                        showColorPicker = true
                    }
                    if block.colorMode == CourseColorMode.CUSTOM && !block.color.isEmpty {
                        Text(block.color)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                }
            }
        }
        .sheet(isPresented: $showColorPicker) {
            NativeColorPicker(initialHex: block.color.isEmpty ? "#FF6750A4" : block.color) { hex in
                block.color = hex
                block.colorMode = CourseColorMode.CUSTOM
                showColorPicker = false
            }
        }
    }
}

// ← ModePicker: native Picker(.segmented) 替代自制分段控件
//   iOS 系统 segmented control → 选中态高亮 + 触摸区域 + 动效全免费
//   签名兼容 (mode + onChange), call site 零改动。
private struct ModePicker: View {
    let mode: MeetingInputMode
    let onChange: (MeetingInputMode) -> Void

    var body: some View {
        Picker("", selection: Binding(
            get: { mode },
            set: { onChange($0) }
        )) {
            Text(L10n.format("mode_by_node")).tag(MeetingInputMode.byNode)
            Text(L10n.format("mode_by_time")).tag(MeetingInputMode.byClock)
        }
        .pickerStyle(.segmented)
    }
}

// ← MultiDayPicker: Form + Toggle 行表 (iOS 设置式多选), 替代自制 4+3 网格
//   SwiftUI Picker 多选无原生 API; 最接近系统设置多选用 Form { Toggle }
//   签名兼容 (selectedDays + onToggleDay), call site 零改动。
private struct MultiDayPicker: View {
    @Environment(\.localWakeUpColors) private var colors
    let selectedDays: Set<Int>
    let onToggleDay: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(1...7, id: \.self) { day in
                let selected = selectedDays.contains(day)
                Button {
                    onToggleDay(day)
                } label: {
                    HStack {
                        Text(DateUtils.localizedDay(day))
                            .font(.system(size: 15))
                            .foregroundColor(colors.onSurface)
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(colors.primary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SleepyButtonStyle())
                if day < 7 {
                    Divider().background(colors.outlineVariant)
                }
            }
        }
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.medium)
    }
}

// ← NumberField(数字输入, 外部值同步 + 空回退 min)
struct NumberStepperField: View {
    @Environment(\.localWakeUpColors) private var colors
    let label: String
    @Binding var value: Int
    var minV: Int
    var maxV: Int
    var onClamp: (() -> Void)? = nil

    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 4) {
            TextField(label, text: Binding(
                get: { text.isEmpty ? "\(value)" : text },
                set: { txt in
                    text = txt
                    if txt.isEmpty {
                        value = minV   // 清空时回退最小值
                    } else if let v = Int(txt) {
                        let clamped = Swift.min(Swift.max(v, minV), maxV)
                        if clamped != v { onClamp?() }
                        value = clamped
                        text = "\(clamped)"
                    }
                }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(colors.surfaceContainerLowest)
            .cornerRadius(SleepyTheme.fieldShape)
            // ← Android filled TextField, 无描边
        }
        .onAppear { text = "\(value)" }
    }
}

// ── 课程颜色选择器 ──

// ← AutoColorDot
private struct AutoColorDot: View {
    @Environment(\.localWakeUpColors) private var colors
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            // ← AutoColorDot.kt: 选中 primaryContainer 色块, 无描边
            ZStack {
                Circle()
                    .fill(selected ? colors.primaryContainer : colors.surfaceVariant)
                    .frame(width: 32, height: 32)
                Text(L10n.format("label_from"))
                    .font(.system(size: 11))
                    .foregroundColor(selected ? colors.onPrimaryContainer : colors.onSurfaceVariant)
            }
        }
        .buttonStyle(SleepyButtonStyle())
    }
}

// ← CustomColorDot
private struct CustomColorDot: View {
    @Environment(\.localWakeUpColors) private var colors
    let hex: String?
    let onClick: () -> Void

    var body: some View {
        let c = hex.flatMap { CourseColorUtil.parseColor($0).map { Color(uiArgb: UInt32($0)) } }
            ?? colors.surfaceVariant
        Button(action: onClick) {
            // ← CustomColorDot.kt: 纯色圆 + ＋号, 无描边
            ZStack {
                Circle()
                    .fill(c)
                    .frame(width: 32, height: 32)
                if hex == nil {
                    Text("＋")
                        .font(.system(size: 16))
                        .foregroundColor(colors.onSurfaceVariant)
                }
            }
        }
        .buttonStyle(SleepyButtonStyle())
    }
}

