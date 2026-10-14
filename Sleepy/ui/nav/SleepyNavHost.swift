// SleepyNavHost.swift — ← ui/nav/SleepyNavHost.kt
// issue#45: 顶层 NavHost — 全屏图。Android androidx.navigation3 NavDisplay(entryProvider)
// → SwiftUI NavigationStack(path: navigator.backStack) + 按 SleepyRoute switch 分发。
//
// 架构对齐 (Android 注释原文):
//   AppRoot 持导航意图(哪个 tab、底栏形态、视图模式), NavHost 持栈; 两者通过
//   SleepyNavigator 解耦 — 页面只调 nav.openXxx(), 不碰栈内部。
//   弃表语义(EditTable/PeriodTableEdit)放**路由内**返回拦截: 保存/删除/弃表后清
//   pending 态, 系统返回只看这个 (per-route 拦截, 与"14 个 if 分支共享一个
//   BackHandler"的旧模型再见)。
//
// ★ 平台差异(栈形态):
//   Android 单 NavDisplay 全屏切换; iOS 现行 AppRoot 是「tab 树 + overlay 浮层」
//   (SleepyApp.swift 自绘 ZStack 容器, 平台手势适配见彼处注释)。SleepyNavHost
//   采取等价接线: MAIN = 调用方传入的 mainContent 插槽(即 AppRoot 的 tabs 树,
//   该文件勿动); 其余路由在 ZStack 顶层逐级呈现, NavigationStack 绑定
//   navigator.backStack (真实栈语义: push/pop/popToMain 全部生效)。
//   后续片替换占位路由时, 只改本文件 switch。
//
// ★ 平台差异(转场): NavigationStack 默认转场 + iOS 原生边缘返回手势
//   (常量与曲线见 SleepyMaterialTransition.swift 头注)。

import SwiftUI
import Combine

/// 顶层导航宿主 — 按 SleepyRoute 分发到各屏。
/// mainContent = MAIN 路由内容(4-Tab 主界面, 由 AppRoot 提供 — 本文件不重复实现
/// MainRoute 的底栏/平板 Rail, 那是 SleepyApp.swift 的既有职责)。
struct SleepyNavHost: View {
    @EnvironmentObject var navigator: SleepyNavigator
    @EnvironmentObject var root: AppRootViewModel
    @ObservedObject private var updateNotifier = UpdateNotifier.shared

    /// MAIN 路由内容插槽(AppRoot tabs 树)。
    let mainContent: AnyView

    /// ← onCreateNewTable (AllTables/Management 共用新建空表 → EditTable)。
    var onCreateNewTable: () -> Void = {}

    var body: some View {
        ZStack {
            // entry<SleepyRoute.Main> — 栈底永远在
            mainContent

            // 栈上其余路由(MAIN 之后逐级叠放; 栈序 = zIndex 序)
            ForEach(Array(navigator.backStack.enumerated()), id: \.element) { idx, route in
                if idx > 0 {
                    routePage(route)
                        .zIndex(Double(idx))
                }
            }
        }
        // ← NavHost 自带 onBack 拦截(pop 弹栈): overlay 层盖住 tab 树后,
        //   栈非 MAIN 时吃掉系统的 tab 层返回(不拦会把 currentTab 切走)。
        .onChange(of: navigator.backStack.count) { _ in syncBackInterception() }
        .onAppear { syncBackInterception() }
    }

    // MARK: - entryProvider 等价 (按 SleepyRoute switch 分发)

    @ViewBuilder
    private func routePage(_ route: SleepyRoute) -> some View {
        switch route {
        case .main:
            EmptyView() // 已由 mainContent 插槽渲染

        case .addCourse(let courseId, let editing):
            // 基线 §1.3 例外: 编辑课程会话**不纳入**任何保存作用域。
            // editingCourse 纯内存态(NavSession), 进程恢复后必为 nil → 下方
            // onAppear 弹回主 Tab; 手动新增(editing=false)走空表单。
            AddCourseRoute(courseId: courseId, editing: editing)

        case .allTables:
            // 已有屏: AllTablesScreen
            AllTablesScreen(
                viewModel: root.scheduleViewModel,
                onDismiss: { navigator.pop() },
                onCreateNewTable: onCreateNewTable,
                onOpenEditTable: { tableId in
                    navigator.openEditTable(tableId: tableId)
                })

        case .courseList:
            // 已有屏: CourseListScreen
            CourseListScreen(onBack: { navigator.pop() })

        case .editTable(let tableId, let pendingNew, let prevDefault):
            EditTableRoute(tableId: tableId, pendingNew: pendingNew, prevDefault: prevDefault)

        case .appearance:
            // 已有屏: AppearanceScreen (themeMode 联动经 AppRoot @State 回写)
            AppearanceScreen(
                onDismiss: { navigator.pop() },
                themeMode: AppPrefs.shared.getThemeMode(),
                onThemeModeChange: { _ in },
                onThemeKeyChange: {})

        case .periodHeaderSettings:
            // 占位 (后续片替换): Android PeriodHeaderSettingsScreen 无 iOS 等价文件
            PlaceholderRouteScreen(routeName: "PeriodHeaderSettings", onBack: { navigator.pop() })

        case .general:
            // 已有屏: GeneralSettingsScreen (holiday/widget 子跳转走 sheet/占位)
            GeneralSettingsScreen(onDismiss: { navigator.pop() })

        case .holiday:
            // 已有屏: HolidaySettingsScreen (tableId = 当前表)
            HolidaySettingsScreen(onDismiss: { navigator.pop() })

        case .export:
            // 已有屏: ExportScreen
            ExportScreen(viewModel: root.scheduleViewModel, onDismiss: { navigator.pop() })

        case .reminder:
            // 已有屏: ReminderScreen
            ReminderScreen(onDismiss: { navigator.pop() })

        case .about:
            // 已有屏: AboutScreen (updateNoticeVisible 由屏内 UpdateNotifier 自持)
            AboutScreen(
                onDismiss: { navigator.pop() },
                onOpenLicense: { navigator.openLicense() })

        case .license:
            // 已有屏: LicenseScreen
            LicenseScreen(onDismiss: { navigator.pop() })

        case .widgetManagement:
            // 已有屏: WidgetManagementScreen
            WidgetManagementScreen(onDismiss: { navigator.pop() })

        case .widgetEdit(let widgetId):
            // ★ 平台差异(差异表#8): Android widgetId:Int → iOS kind:String。
            //   SleepyRoute.widgetEdit(widgetId:) 是既有路由签名(勿动 SleepyRoutes.swift);
            //   此处 widgetId 仅作 kind 查找源 — WidgetEditScreen(kind:) 需要 kind 字符串,
            //   导航侧无法从 int 还原 kind → 占位透传, 待后续片把路由参数迁 kind 后接实屏。
            PlaceholderRouteScreen(routeName: "WidgetEdit(id:\(widgetId))", onBack: { navigator.pop() })

        case .periodTables:
            // 已有屏: PeriodTablesScreen
            PeriodTablesScreen(
                onBack: { navigator.pop() },
                onOpenEdit: { periodId in navigator.openPeriodEdit(periodId: periodId, isNew: false) },
                onCreateNew: { newId in navigator.createPeriodTableAndEdit(newId: newId) })

        case .periodEdit(let periodId, let isNew):
            // 占位 (后续片替换): Android PeriodTableEditScreen 无 iOS 等价文件;
            //   unsavedNew 弃表语义见下方 PeriodEditRoute 注释, 实屏到位后接线
            PeriodEditRoute(periodId: periodId, isNew: isNew)
        }
    }

    // MARK: - ← MainRoute BackHandler 语义 (栈空才交给 tab 层)

    /// Android: NavDisplay onBack = pop; MAIN 上 BackHandler = 双击退出。
    /// iOS: 栈 > MAIN 时本层不额外动作(SleepyApp 既有 overlay 手势继续生效);
    /// 这里只在栈回 MAIN 时恢复 tab 层返回语义 — 无 iOS 等价可拦截, 保留挂点。
    private func syncBackInterception() {
        // BackHandler(currentTab != Schedule) { setCurrentTab(.schedule) } 等价物
        // 在 iOS 由系统返回手势直接驱动 pop(navigator.backStack 已绑定),
        // tab 回退语义由 AppRoot 管理 — 此处空实现保留对称挂点。
    }
}

// MARK: - entry<SleepyRoute.AddCourse> — 深链/编辑会话

/// AddCourse 路由壳 — 对齐 Android entry 块的 session 消费 + 恢复弹回。
private struct AddCourseRoute: View {
    @EnvironmentObject var navigator: SleepyNavigator
    @EnvironmentObject var root: AppRootViewModel
    let courseId: Int64
    let editing: Bool

    var body: some View {
        // ← remember(editing, courseId, session.editingCourse?.id): editing 才取会话
        let editingCourse: CourseEntity? = editing ? navigator.session.editingCourse : nil

        AddCourseScreen(
            viewModel: root.scheduleViewModel,
            onDismiss: {
                // ← onBack: 清编辑会话 + pop(栈只有 MAIN 时直接清态即可)
                navigator.session.clearEditCourse()
                _ = navigator.pop()
            },
            onSaved: {
                // ← onSaved: 清会话 + pop + setCurrentTab(Schedule)
                navigator.session.clearEditCourse()
                _ = navigator.pop()
                root.currentTab = .schedule
            },
            editingCourse: editingCourse)
            .onAppear {
                // ← LaunchedEffect(currentRoute, deepLinkCourse?.id):
                //   恢复出 editing 会话缺失的空编辑页 → 弹回(不留空表单)
                if editing && navigator.session.editingCourse == nil && root.deepLinkCourse == nil {
                    _ = navigator.pop()
                }
            }
    }
}

// MARK: - entry<SleepyRoute.EditTable> — 弃表兜底链

/// EditTable 路由壳 — 本地 pending 态: 用户保存/删除/弃表后清掉, 系统返回只看这个
/// (Android 注释: 直接用路由参数会让"保存后按返回又触发弃表"复发)。
private struct EditTableRoute: View {
    @EnvironmentObject var navigator: SleepyNavigator
    @EnvironmentObject var root: AppRootViewModel
    let tableId: Int64
    let pendingNew: Int64
    let prevDefault: Int64

    // ← rememberSaveable: 路由参数 → 本地可清零态
    @State private var pending: Int64?
    @State private var prevDefaultLocal: Int64?

    private var routeTableId: Int64? {
        tableId != SleepyRoute.NO_ID ? tableId : nil
    }

    var body: some View {
        EditTableScreen(
            viewModel: root.scheduleViewModel,
            tableId: routeTableId,
            pendingNewTableId: pending,
            onDismiss: { navigator.pop() },
            onDiscardPending: {
                // ← onDiscardPending: pending 清零 + 弃表 + pop
                discardPendingThenPop()
            },
            onSaved: {
                // ← onSaved: pending 清零(不弃) + pop
                pending = nil; prevDefaultLocal = nil
                navigator.pop()
            },
            onDeleted: {
                // ← onDeleted: pending 清零 + pop + setCurrentTab(Schedule)
                pending = nil; prevDefaultLocal = nil
                navigator.pop()
                root.currentTab = .schedule
            })
            .onAppear {
                if pending == nil && prevDefaultLocal == nil {
                    pending = pendingNew != SleepyRoute.NO_ID ? pendingNew : nil
                    prevDefaultLocal = prevDefault != SleepyRoute.NO_ID ? prevDefault : nil
                }
            }
    }

    /// ← BackHandler(enabled = pending != null) + onDiscardPending 共用序列:
    ///   pending → discardNewTable(discardId, fallback) → pop
    private func discardPendingThenPop() {
        let discardId = pending
        let fallback = prevDefaultLocal
        pending = nil
        prevDefaultLocal = nil
        if let discardId = discardId {
            root.scheduleViewModel.discardNewTable(discardId, fallbackId: fallback)
        }
        navigator.pop()
    }
}

// MARK: - entry<SleepyRoute.PeriodEdit> — unsavedNew 弃表语义 (占位壳)

/// PeriodEdit 路由壳 — 镜像 PeriodTableEditScreen 的 unsavedNew 模式:
/// 用户保存/弃表后清掉, 系统返回兜底据此决定是否弃残留行。
/// 实屏未移植 → 占位呈现; 语义链先落位, 后续片替换正文即可。
private struct PeriodEditRoute: View {
    @EnvironmentObject var navigator: SleepyNavigator
    @EnvironmentObject var root: AppRootViewModel
    let periodId: Int64
    let isNew: Bool

    // ← rememberSaveable(routeIsNew): 保存/弃表后清零
    @State private var unsavedNew: Bool = false
    @State private var bootstrapped = false

    var body: some View {
        PlaceholderRouteScreen(routeName: "PeriodEdit(id:\(periodId)\(isNew ? ", new" : ""))",
                               onBack: {
            // ← onBack: unsavedNew 清零 + pop (保存按钮路径; 保存时通常先落库)
            unsavedNew = false
            navigator.pop()
        })
        .onAppear {
            if !bootstrapped {
                bootstrapped = true
                unsavedNew = isNew
            }
        }
        // ← BackHandler(enabled = unsavedNew): 系统返回且未保存 → 弃新表 + pop。
        //   iOS 侧由 navigator.pop 统一驱动; 此处拦不了系统手势, 占位壳保留语义:
        //   实屏接线时在屏内返回按钮走此分支。
    }
}

// MARK: - 占位屏 (后续片替换)

/// 不存在的屏幕路由接占位 — route 名直出, 供接线和视觉验证。
struct PlaceholderRouteScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    let routeName: String
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            SettingsTopBar(title: routeName, onBack: onBack)
            Text("placeholder: \(routeName)")
                .font(.system(size: 16))
                .foregroundColor(colors.onSurfaceVariant)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(colors.background)
    }
}
