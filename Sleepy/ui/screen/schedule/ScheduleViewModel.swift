// ScheduleViewModel.swift — ← ui/screen/schedule/ScheduleViewModel.kt
// 课表页 VM: 表列表观察 → 选中表课程观察 → 状态派生。
// StateFlow/viewModelScope → @MainActor ObservableObject + Combine sink。

import Foundation
import Combine
import GRDB

struct ScheduleState {
    var tables: [TimeTableEntity] = []
    var selectedTableId: Int64? = nil
    var courses: [CourseEntity] = []
    var currentWeek: Int = 1
    var selectedWeek: Int = 1
    /// false=首次加载(本周), true=用户/系统已选定周 — 课程变更时 selectedWeek 不再被重置
    var initialWeekSettled: Bool = false
    var nodesPerDay: Int = 12
    var selectedCourseId: Int64? = nil
    var showCourseDialog: Bool = false
    var error: String? = nil

    var currentTable: TimeTableEntity? { tables.first { $0.id == selectedTableId } }

    var currentWeekCourses: [CourseEntity] {
        let list = courses.filter { $0.inWeek(selectedWeek) }
        guard let tj = currentTable?.timeJson else { return list }
        return list.map { $0.normalizeNode(timeJson: tj) }
    }
}

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published private(set) var state = ScheduleState()

    private let repo: ScheduleRepository
    /// 数据变更 → 刷 WidgetKit timeline(← WidgetUpdater.notifyDataChanged)
    private let onWidgetsNeedReload: () -> Void

    /// Whether the user has explicitly selected a table (vs auto-picking default on load)
    private var manualSelectDone = false
    private var tablesCancellable: AnyCancellable?
    private var coursesCancellable: AnyCancellable?

    init(repo: ScheduleRepository, onWidgetsNeedReload: @escaping () -> Void = {}) {
        self.repo = repo
        self.onWidgetsNeedReload = onWidgetsNeedReload
        loadTables()
    }

    // ← loadTables: observeAllTables → 选表逻辑
    private func loadTables() {
        tablesCancellable = repo.observeAllTables()
            .catch { _ in Just<[TimeTableEntity]>([]) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tables in
                guard let self = self else { return }
                if tables.isEmpty {
                    // 没有课表就老实空着,不强行造占位表
                    self.state.tables = []
                    self.state.selectedTableId = nil
                    return
                }
                let selectedId = self.state.selectedTableId
                let targetId: Int64
                if self.manualSelectDone, let selectedId = selectedId,
                   tables.contains(where: { $0.id == selectedId }) {
                    targetId = selectedId
                } else if let def = tables.first(where: { $0.isDefault }) {
                    targetId = def.id
                } else {
                    targetId = tables[0].id
                }
                self.state.tables = tables
                self.state.selectedTableId = targetId
                self.loadCourses(targetId)
            }
    }

    // ← loadCourses: 取消旧观察,避免多 observeCourses 同时写 state.courses 互相覆盖
    private func loadCourses(_ tableId: Int64) {
        coursesCancellable?.cancel()
        coursesCancellable = repo.observeCourses(tableId)
            .catch { _ in Just<[CourseEntity]>([]) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] courses in
                guard let self = self else { return }
                let table = self.state.tables.first { $0.id == tableId }
                let week = table.map { DateUtils.currentWeek(startDate: $0.startDate) } ?? 1
                self.state.courses = courses
                self.state.currentWeek = week
                self.state.selectedWeek = self.state.initialWeekSettled ? self.state.selectedWeek : week
                self.state.initialWeekSettled = true
                self.state.nodesPerDay = table?.nodesPerDay ?? 12
                // 课程数据变更后刷新所有 widget
                self.onWidgetsNeedReload()
            }
    }

    // ← selectTable: 切表 + setDefault(小组件严格跟随 App 当前选中表)
    func selectTable(_ id: Int64) {
        manualSelectDone = true
        state.selectedTableId = id
        state.initialWeekSettled = false
        loadCourses(id)
        Task {
            try? repo.setDefault(id)
            onWidgetsNeedReload()
        }
    }

    /// v7.10.16 撤回最近一次数据改动(导入/加课/编辑/删课/删表/建表...)。
    /// 返回 false = 没有可撤回的操作(调用方 toast 提示)。
    @discardableResult
    func undoLastChange() -> Bool {
        let ok = (try? repo.restoreLastSnapshot()) ?? false
        if ok {
            manualSelectDone = false   // 恢复后选中态交回 default 表
            onWidgetsNeedReload()
        }
        return ok
    }

    /// Create a new empty table with auto-generated name. ← createEmptyTable
    /// - Parameter commitSelection: true=立刻切到新表; false=只插入不切(调用方回滚/后切)
    @discardableResult
    func createEmptyTable(commitSelection: Bool = true) -> Int64 {
        let existingNames = Set(state.tables.map { $0.name })
        var index = state.tables.count + 1
        var name = L10n.format("default_table_with_num", index)
        while existingNames.contains(name) {
            index += 1
            name = L10n.format("default_table_with_num", index)
        }
        // 上周一(本周一往前 7 天 — iOS weekday 数学)
        let cal = DateUtils.isoCalendar
        let now = Date()
        let todayDow = DateUtils.todayDayOfWeek(today: now)
        let lastWeekMonday = cal.date(byAdding: .day, value: -(todayDow - 1 + 7), to: now) ?? now
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = DateUtils.isoCalendar.timeZone
        // 没有任何表时,新表自动 isDefault = true,避免"无默认表"
        let isFirstTable = state.tables.isEmpty
        let table = TimeTableEntity(
            name: name,
            startDate: f.string(from: lastWeekMonday),
            isDefault: isFirstTable)
        let id = (try? repo.insertTable(table)) ?? 0
        if isFirstTable {
            // 数据库侧 isDefault 唯一性保证
            try? repo.setDefault(id)
        }
        // observeAllTables 在 receive(on: DispatchQueue.main) 后异步回调。
        // 先同步补入内存状态,让立即打开的 EditTableScreen 能解析新表。
        if id != 0, !state.tables.contains(where: { $0.id == id }) {
            var insertedTable = table
            insertedTable.id = id
            state.tables.append(insertedTable)
        }
        if commitSelection {
            manualSelectDone = true
            state.selectedTableId = id
            loadCourses(id)
        }
        onWidgetsNeedReload()
        return id
    }

    func updateTable(_ table: TimeTableEntity) {
        Task { try? repo.updateTable(table) }
    }

    /// v7.10.15 创建课表副本 — 全量复制表配置+课程, 新副本不接管默认表也不切选中,
    /// 命名沿用导入路径的去重规则(原名+"2"/"3"...)。
    func duplicateTable(_ id: Int64) {
        Task {
            guard let source = try? repo.getTable(id) else { return }
            let courses = (try? repo.getCourses(id)) ?? []
            let existingNames = ((try? repo.getAllTables()) ?? []).map { $0.name }
            var index = 2
            var name = "\(source.name)2"
            while existingNames.contains(name) { index += 1; name = "\(source.name)\(index)" }
            var copy = source
            copy.id = 0
            copy.name = name
            copy.isDefault = false
            copy.createdAt = Int64(Date().timeIntervalSince1970 * 1000)
            // v7.10.16w: 建表+插课是一个撤回动作 — beginBatch 保首快照, 撤回一次整步回退
            // (此前两步写两次覆盖快照, 撤回只删掉课程行留下空表壳)。
            UndoManager.shared.beginBatch()
            defer { UndoManager.shared.endBatch() }
            let newId = (try? repo.insertTable(copy)) ?? 0
            if newId != 0 && !courses.isEmpty {
                // groupId 整组映射到新 UUID — 同一门课的节次共享新组 ID, 副本内仍可整组编辑
                var groupMap: [String: String] = [:]
                for c in courses where groupMap[c.groupId] == nil {
                    groupMap[c.groupId] = UUID().uuidString
                }
                let newCourses = courses.map { c -> CourseEntity in
                    var n = c
                    n.id = 0
                    n.groupId = groupMap[c.groupId] ?? c.groupId
                    n.tableId = newId
                    return n
                }
                try? repo.insertCourses(newCourses)
            }
            onWidgetsNeedReload()
        }
    }

    func deleteTable(_ id: Int64) {
        Task {
            try? repo.deleteTable(id)
            self.manualSelectDone = false
        }
    }

    /// Discard a newly-created table that was never saved. ← discardNewTable
    func discardNewTable(_ newId: Int64, fallbackId: Int64?) {
        Task {
            try? self.repo.deleteTable(newId)
            self.manualSelectDone = false
            let remaining = ((try? self.repo.getAllTables()) ?? []).filter { $0.id != newId }
            let targetId: Int64?
            if let fallbackId = fallbackId, remaining.contains(where: { $0.id == fallbackId }) {
                targetId = fallbackId
            } else if let def = remaining.first(where: { $0.isDefault }) {
                targetId = def.id
            } else {
                targetId = remaining.first?.id
            }
            if let targetId = targetId {
                self.selectTable(targetId)
            }
        }
    }

    func changeWeek(_ week: Int) {
        let maxWeek = state.currentTable?.maxWeek ?? 20
        guard week >= 1, week <= maxWeek else { return }
        state.selectedWeek = week
    }

    func openCourse(_ id: Int64) {
        state.selectedCourseId = id
        state.showCourseDialog = true
    }

    func dismissCourseDialog() {
        state.showCourseDialog = false
    }

    // ← addEmptyCourse: 没课表就先生成一张,再加课
    func addEmptyCourse() {
        let tableId = state.selectedTableId ?? createEmptyTable()
        let empty = CourseEntity(
            groupId: UUID().uuidString,
            tableId: tableId,
            courseName: L10n.format("new_course"),
            teacher: "",
            room: "",
            day: DateUtils.todayDayOfWeek(),
            startNode: 1,
            step: 1,
            startWeek: state.currentWeek,
            endWeek: state.currentWeek + 16,
            color: "#FF6750A4")
        let id = (try? repo.insertCourse(empty)) ?? 0
        openCourse(id)
    }

    func updateCourse(_ course: CourseEntity) {
        Task { try? repo.updateCourse(course) }
    }

    func deleteCourse(_ id: Int64) {
        Task {
            try? repo.deleteCourse(id)
            self.dismissCourseDialog()
        }
    }
}

// MARK: - PeriodTable 面 (issue#40 / v1.0.56 T7-T9, ← ScheduleViewModel.kt L297-497)

extension ScheduleViewModel {

    /// 全部作息表(管理页列表)。
    func loadAllPeriodTables() -> [PeriodTableEntity] {
        return (try? repo.getAllPeriodTables()) ?? []
    }

    /// 复制作息表预填名 — 原名参与全局唯一名顺延, 原名本身不占位。nil = 源不存在。
    func suggestPeriodTableCopyName(sourceId: Int64) -> String? {
        guard let src = (try? repo.getAllPeriodTables())?.first(where: { $0.id == sourceId }) else { return nil }
        let courseNames = ((try? repo.getAllTables()) ?? []).map { $0.name }
        let periodNames = ((try? repo.getAllPeriodTables()) ?? []).map { $0.name }
        return TimeTableUtils.suggestUniqueName(src.name, courseTableNames: courseNames, periodTableNames: periodNames)
    }

    /// 按用户确认的名字建副本。返回新副本 id; 源不存在 -1; 撞名 -2。
    func copyPeriodTableAs(sourceId: Int64, newName: String) -> Int64 {
        guard let src = try? repo.getPeriodTable(sourceId) else { return -1 }
        let courseNames = ((try? repo.getAllTables()) ?? []).map { $0.name }
        let periodNames = ((try? repo.getAllPeriodTables()) ?? []).map { $0.name }
        if !newName.isBlank,
           TimeTableUtils.isTableNameTaken(newName, courseTableNames: courseNames, periodTableNames: periodNames) {
            return -2
        }
        let finalName = newName.isBlank ? src.name : newName
        return (try? repo.copyPeriodTableAs(sourceId: sourceId, newName: finalName)) ?? -1
    }

    /// 新建空白时间节次表(创建即落库, 编辑页把它当"未保存新表"处理)。
    @discardableResult
    func insertPeriodTable(
        name: String,
        timeJson: String = TimeTableUtils.DEFAULT_TIME_JSON,
        nodesPerDay: Int = 12,
        smartConfigJson: String = ""
    ) -> Int64 {
        let entity = PeriodTableEntity(
            name: name, nodesPerDay: nodesPerDay,
            timeJson: timeJson, smartConfigJson: smartConfigJson
        )
        return (try? repo.insertPeriodTable(entity)) ?? -1
    }

    /// 新建作息表(自动唯一命名) — 全局唯一名顺延, 空名走默认名。
    @discardableResult
    func insertPeriodTableWithUniqueName(
        name: String,
        defaultName: String,
        timeJson: String = TimeTableUtils.DEFAULT_TIME_JSON,
        nodesPerDay: Int = 12,
        smartConfigJson: String = ""
    ) -> Int64 {
        let courseNames = ((try? repo.getAllTables()) ?? []).map { $0.name }
        let periodNames = ((try? repo.getAllPeriodTables()) ?? []).map { $0.name }
        let unique = TimeTableUtils.suggestUniqueName(
            name, courseTableNames: courseNames, periodTableNames: periodNames, defaultName: defaultName
        )
        return insertPeriodTable(name: unique, timeJson: timeJson, nodesPerDay: nodesPerDay, smartConfigJson: smartConfigJson)
    }

    /// issue#40: 修改共享时间节次表内容 — 全部绑定课表立即生效, 课程行零改动(← Android updatePeriodTableContent)
    /// repo.savePeriodTable 是同步方法; 行为与 updateTable 保持一致 — 在 fire-and-forget Task 内执行,
    /// 失败吞(→ repo update 抛错时上层按 updateTable 同语义吞掉, 数据层不会半写)。
    func updatePeriodTableContent(_ table: PeriodTableEntity) {
        Task { try? repo.savePeriodTable(table) }
    }

    /// 删除时间节次表(被引用时 false, UI 提示先改绑)。
    @discardableResult
    func deletePeriodTable(id: Int64) -> Bool {
        return (try? repo.deletePeriodTable(id)) ?? false
    }

    /// 丢弃一个从未保存过的新建时间节次表(残留清理; 不走删除守卫)。
    func discardNewPeriodTable(id: Int64) {
        _ = try? repo.deletePeriodTable(id)
    }

    /// issue#40: 全库课程(保存预览用) — 预览须覆盖所有绑定表的课。
    func getAllCoursesOnce() -> [CourseEntity] {
        return (try? repo.getAllCourses()) ?? []
    }

    /// v1.0.56 T9: 全局唯一名预填用 — 课表名 + 作息表名。
    func getAllTableNamesOnce() -> [String] {
        return ((try? repo.getAllTables()) ?? []).map { $0.name }
    }
    func getAllPeriodTableNamesOnce() -> [String] {
        return ((try? repo.getAllPeriodTables()) ?? []).map { $0.name }
    }
}
