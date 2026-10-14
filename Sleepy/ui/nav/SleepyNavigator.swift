import Foundation

// SleepyNavigator — Android SleepyNavigator.kt → iOS 薄门面 (1:1 意图面).
//
// Android 侧: 官方 NavBackStack 的极薄封装, 栈意图封成命名方法, 不暴露栈内部形态:
//   push (连续同路由去重) / pop (size<=1 → false) / popToMain / 16 个 openXxx.
// iOS 侧导航态 = AppRootViewModel (currentTab + overlayScreen + 参数),
// 本 facade 保留同一命名意图面, 落地路由直接驱动 VM, unported 路由 no-op
// (统一记录在 SleepyNavHost 尾表 — 🚫silent skip).
//
// push 去重语义: iOS overlay 是单值 (同屏重复置位 = 无操作), 天然等价
// "连续同路由不二次 push".

// 薄门面驱动 @MainActor VM 态 → 整个类 @MainActor (Android 侧同为主线程).
@MainActor
final class SleepyNavigator {
    private let vm: AppRootViewModel
    let session: NavSession

    init(viewModel: AppRootViewModel) {
        self.vm = viewModel
        self.session = NavSession()
    }

    func push(route: SleepyRoute) {
        guard route.isIOSPorted else {
            // unported: courseList / periodHeaderSettings / holiday / widgetManagement
            //            / widgetEdit / periodTables / periodEdit — 见 SleepyNavHost 尾表
            return
        }
        switch route {
        case .main:
            break // 根 tab 栏, 无 overlay
        case .addCourse:
            vm.overlayScreen = .addCourse
        case .allTables:
            vm.overlayScreen = .allTables
        case .editTable(let tableId, let pendingNew, let prevDefault):
            vm.editTableId = (tableId == SleepyRoute.NO_ID) ? nil : tableId
            vm.pendingNewTableId = (pendingNew == SleepyRoute.NO_ID) ? nil : pendingNew
            vm.previousDefaultTableId = (prevDefault == SleepyRoute.NO_ID) ? nil : prevDefault
            vm.overlayScreen = .editTable
        case .appearance:
            vm.overlayScreen = .theme
        case .general:
            vm.overlayScreen = .general
        case .export:
            vm.overlayScreen = .export
        case .reminder:
            vm.overlayScreen = .reminder
        case .about:
            vm.overlayScreen = .about
        case .license:
            vm.overlayScreen = .license
        default:
            break
        }
    }

    /// Android pop(): size<=1 → false. iOS: 清 overlay + 走既有 handleBack
    /// (EditTable pendingNew 丢弃链). 无 overlay 可退 → false.
    @discardableResult
    func pop() -> Bool {
        guard vm.overlayScreen != nil else { return false }
        vm.handleBack()
        return true
    }

    /// Android popToMain(): 弹出到 Main. iOS: 丢弃链后退根 tab.
    func popToMain() {
        vm.handleBack()
        vm.overlayScreen = nil
        vm.currentTab = .schedule
    }

    // ── 16 个 openXxx 意图 (Android 命名 1:1) ──
    func openAddCourse(courseId: Int64 = NavSession.NO_ID, editing: Bool = false) {
        push(route: .addCourse(courseId: courseId, editing: editing))
    }
    func openAllTables() { push(route: .allTables) }
    func openCourseList() { push(route: .courseList) }
    func openAppearance() { push(route: .appearance) }
    func openPeriodHeaderSettings() { push(route: .periodHeaderSettings) }
    func openGeneral() { push(route: .general) }
    func openHoliday() { push(route: .holiday) }
    func openExport() { push(route: .export) }
    func openReminder() { push(route: .reminder) }
    func openAbout() { push(route: .about) }
    func openLicense() { push(route: .license) }
    func openWidgetManagement() { push(route: .widgetManagement) }
    func openPeriodTables() { push(route: .periodTables) }
    func openWidgetEdit(widgetId: Int) { push(route: .widgetEdit(widgetId: widgetId)) }
    func openPeriodEdit(periodId: Int64, isNew: Bool = false) { push(route: .periodEdit(periodId: periodId, isNew: isNew)) }
    func openEditTable(tableId: Int64 = NavSession.NO_ID, pendingNew: Int64 = NavSession.NO_ID, prevDefault: Int64 = NavSession.NO_ID) {
        push(route: .editTable(tableId: tableId, pendingNew: pendingNew, prevDefault: prevDefault))
    }
    /// Android createPeriodTableAndEdit = openPeriodEdit(newId, isNew=true).
    /// iOS: 新建表再编辑由 AppRootViewModel.createNewTableThenEdit 承接;
    /// periodEdit 路由本身未落地 → 仅记映射.
    func createPeriodTableAndEdit(newId: Int64) {
        vm.createNewTableThenEdit()
        openPeriodEdit(periodId: newId, isNew: true)
    }
}

/// Android NavSession 1:1: 会话态, 基线 §1.3 明确不纳入任何保存作用域
/// (旋转/进程恢复安全丢弃; 与栈序列化刻意隔离) → iOS 等价 = 普通属性,
/// 无 scene-phase 持久化.
final class NavSession {
    var editingCourse: CourseEntity? = nil
    func beginEditCourse(_ course: CourseEntity) { editingCourse = course }
    func clearEditCourse() { editingCourse = nil }
    static let NO_ID: Int64 = SleepyRoute.NO_ID
}
