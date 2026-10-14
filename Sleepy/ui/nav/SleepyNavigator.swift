// SleepyNavigator.swift — ← ui/nav/SleepyNavigator.kt
// issue#45: 官方 navigation3 的极薄封装 → SwiftUI NavigationStack path 封装。
//
// 决策对齐: 栈本体 = @Published [SleepyRoute](NavigationStack path 绑定);
// 所有「栈意图」封成命名方法 — 不对外暴露栈内部形态,只暴露 push/pop/popToMain/openXxx。
//
// NavSession.editingCourse 是会话态: 不纳入任何持久化, 旋转/进程恢复安全丢弃。

import Foundation
import SwiftUI
import Combine

/// 会话态 — 编辑中的课程(跨屏传递, 不持久化)。
final class NavSession: ObservableObject {
    static let NO_ID: Int64 = SleepyRoute.NO_ID

    @Published private(set) var editingCourse: CourseEntity?

    func beginEditCourse(_ course: CourseEntity) { editingCourse = course }
    func clearEditCourse() { editingCourse = nil }
}

/// 导航器 — 栈意图命名方法集合。
final class SleepyNavigator: ObservableObject {
    @Published private(set) var backStack: [SleepyRoute]

    let session: NavSession

    init(initial: SleepyRoute = .main, session: NavSession = NavSession()) {
        self.backStack = [initial]
        self.session = session
    }

    func push(_ route: SleepyRoute) {
        if backStack.last == route { return }
        backStack.append(route)
    }

    @discardableResult
    func pop() -> Bool {
        if backStack.count <= 1 { return false }
        backStack.removeLast()
        return true
    }

    func popToMain() {
        while backStack.count > 1 && backStack.last != .main {
            backStack.removeLast()
        }
    }

    // MARK: - openXxx (对齐 Android 全套命名意图)

    func openAddCourse(courseId: Int64 = NavSession.NO_ID, editing: Bool = false) {
        push(.addCourse(courseId: courseId, editing: editing))
    }
    func openAllTables() { push(.allTables) }
    func openCourseList() { push(.courseList) }
    func openAppearance() { push(.appearance) }
    func openPeriodHeaderSettings() { push(.periodHeaderSettings) }
    func openGeneral() { push(.general) }
    func openHoliday() { push(.holiday) }
    func openExport() { push(.export) }
    func openReminder() { push(.reminder) }
    func openAbout() { push(.about) }
    func openLicense() { push(.license) }
    func openWidgetManagement() { push(.widgetManagement) }
    func openPeriodTables() { push(.periodTables) }
    func openWidgetEdit(widgetId: Int) { push(.widgetEdit(widgetId: widgetId)) }
    func openPeriodEdit(periodId: Int64, isNew: Bool = false) {
        push(.periodEdit(periodId: periodId, isNew: isNew))
    }
    func openEditTable(tableId: Int64 = NavSession.NO_ID,
                       pendingNew: Int64 = NavSession.NO_ID,
                       prevDefault: Int64 = NavSession.NO_ID) {
        push(.editTable(tableId: tableId, pendingNew: pendingNew, prevDefault: prevDefault))
    }
    func createPeriodTableAndEdit(newId: Int64) {
        openPeriodEdit(periodId: newId, isNew: true)
    }
}
