// SleepyRoutes.swift — ← ui/nav/SleepyRoutes.kt
// Stable, typed keys for the app's single navigation stack.
// Android navigation3 @Serializable NavKey → SwiftUI NavigationStack path element
// (Hashable enum; 栈持久化由 NavigationStack(path:) + Codable path 承担)。

import Foundation

/// 单导航栈的稳定类型化路由。
enum SleepyRoute: Hashable {
    case main
    case addCourse(courseId: Int64, editing: Bool)
    case allTables
    case courseList
    case editTable(tableId: Int64, pendingNew: Int64, prevDefault: Int64)
    case appearance
    case periodHeaderSettings
    case general
    case holiday
    case export
    case reminder
    case about
    case license
    case widgetManagement
    case widgetEdit(widgetId: Int)
    case periodTables
    case periodEdit(periodId: Int64, isNew: Bool)

    static let NO_ID: Int64 = -1

    /// 便利构造 — 对齐 Android data class 默认参数。
    static func addCourseDefault() -> SleepyRoute {
        return .addCourse(courseId: NO_ID, editing: false)
    }
    static func editTableDefault() -> SleepyRoute {
        return .editTable(tableId: NO_ID, pendingNew: NO_ID, prevDefault: NO_ID)
    }
}
