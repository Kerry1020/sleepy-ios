import Foundation

// SleepyRoutes — Android SleepyRoutes.kt (NavHost 路由表) → iOS 等价路由表.
//
// Android 侧: 23 个 case 的 sealed `SleepyRoute : NavKey` 驱动 Compose Navigation.
// iOS 侧导航由 AppRootViewModel.currentTab + .overlayScreen (SleepyApp.PresentOverlay
// 跟手侧滑容器) 驱动, 本文件保留同一套 17 个 case 名称 + 参数语义作为"路由表真源",
// 并附 路由 → iOS 导航态 映射表 (recon.md 平台映射: NavigationStack 自有路由枚举,
// 不引入第三方导航库).
// Long 参数在 iOS 侧统一 Int64 (对齐 AppRootViewModel.editTableId: Int64?).

enum SleepyRoute: Equatable {
    case main
    case addCourse(courseId: Int64 = SleepyRoute.NO_ID, editing: Bool = false)
    case allTables
    case courseList
    case editTable(tableId: Int64 = SleepyRoute.NO_ID, pendingNew: Int64 = SleepyRoute.NO_ID, prevDefault: Int64 = SleepyRoute.NO_ID)
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
    case periodEdit(periodId: Int64, isNew: Bool = false)
}

extension SleepyRoute {
    /// Android SleepyRoute.NO_ID 常量 1:1 (-1L → Int64).
    static let NO_ID: Int64 = -1

    /// 路由 → iOS 导航态映射 (AppRootViewModel: Tab + OverlayScreen).
    /// unported 路由尚无 iOS 页面 → 映射为文档, 待对应切片落地.
    var iosNavigation: AppRootViewModel.OverlayScreen? {
        switch self {
        case .main:
            return nil // 根 tab 栏
        case .addCourse:
            return .addCourse
        case .allTables:
            return .allTables
        case .editTable:
            return .editTable
        case .appearance:
            return .theme
        case .general:
            return .general
        case .export:
            return .export
        case .reminder:
            return .reminder
        case .about:
            return .about
        case .license:
            return .license
        // 以下 iOS 尚无对应页面 (holiday 内嵌在 GeneralSettings sheet):
        case .courseList: return nil
        case .periodHeaderSettings: return nil
        case .holiday: return nil
        case .widgetManagement: return nil
        case .widgetEdit: return nil
        case .periodTables: return nil
        case .periodEdit: return nil
        }
    }

    /// 是否已有 iOS 页面承接 (SleepyNavigator facade 放行条件).
    var isIOSPorted: Bool {
        switch self {
        case .addCourse, .allTables, .editTable, .appearance,
             .general, .export, .reminder, .about, .license:
            return true
        default:
            return false
        }
    }
}
