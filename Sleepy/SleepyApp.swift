// SleepyApp.swift — ← SleepyApp.kt + MainActivity.kt
// iOS App 壳: 全局依赖初始化 + 主题 Provider + 4 Tab 底栏 + overlay 导航 + 深链。
//
// 平台映射:
//   - SleepyApp.onCreate(通知调度/小组件刷新) → AppDelegate.init + didFinishLaunching
//   - MainActivity.setContent + AppRoot → WindowGroup { AppRoot }
//   - 深链 EXTRA_COURSE_ID → URL scheme sleepy://course/<id>(平台差异表#4)
//   - pendingImportText(外部 json 打开) → onOpenURL sleepy://import?text=

import SwiftUI
import GRDB
import WidgetKit

@main
struct SleepyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environmentObject(appDelegate.rootViewModel)
        }
    }
}

// ← SleepyApp(Application): 全局依赖 + 通知调度 + 小组件刷新
class AppDelegate: NSObject, UIApplicationDelegate {
    let database: AppDatabase
    let repository: ScheduleRepository
    let notificationScheduler: NotificationScheduler
    let rootViewModel: AppRootViewModel

    override init() {
        database = AppDatabase.getShared()
        // UI 测试种子钩子: -SLEEPY_UI_TEST_SEED 1 → 清库+注入确定性测试数据
        // (XCUITest 无法直接触 DB;真实建表/导课走 UI 流程另有专项测试)
        if ProcessInfo.processInfo.arguments.contains("-SLEEPY_UI_TEST_SEED") {
            SleepyUITestSeeder.seed(database: AppDatabase.getShared())
        }
        repository = ScheduleRepository(database)
        notificationScheduler = NotificationScheduler.shared
        rootViewModel = AppRootViewModel(repository: repository)
        super.init()
        // ← onCreate: 通知调度器接 repo;数据变更 → 刷 widget + 重排通知
        notificationScheduler.repositoryProvider = { [weak self] in self?.repository }
        repository.onDataChangedHook = { [weak self] in
            guard let self = self else { return }
            WidgetCenter.shared.reloadAllTimelines()
            self.notificationScheduler.scheduleAll()
        }
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // ← onCreate: 首启刷新小组件(WidgetUpdater.notifyDataChanged)
        WidgetCenter.shared.reloadAllTimelines()
        // ★ v1.0.45 高刷新率: 启动时按用户偏好(默认开)钉 CALayer.preferredFramesPerSecond
        //   ← Android edec776 onCreate / attachBaseContext 同位;无 ProMotion 屏自然维持设备上限
        Task { @MainActor in
            _ = HighRefreshRate.apply(enabled: AppPrefs.shared.isHighRefreshEnabled())
        }
        return true
    }
}

// ← AppRoot 状态机(overlay 导航 + 深链)
@MainActor
final class AppRootViewModel: ObservableObject {
    enum Tab: Hashable { case schedule, today, manage, mine }
    // ★ v7.10.18 原生化: OverlayScreen 用于 presentation(.sheet/.fullScreenCover item:)
    //   子屏独立呈现,iOS 16+ 自动获得 swipe-to-dismiss,iOS 15 仍有系统 ✕ 按钮。
    //   GeneralSettingsScreen 内嵌 NavigationView 容纳 HolidaySettings 嵌套跳转。
    enum OverlayScreen: String, Identifiable {
        case addCourse, allTables, editTable, theme, general, export, reminder, about, license
        // holiday 由 GeneralSettings 内部 sheet 呈现,不再出现在根 enum
        var id: String { rawValue }
    }

    @Published var currentTab: Tab = .schedule
    @Published var overlayScreen: OverlayScreen? = nil
    @Published var editingCourse: CourseEntity? = nil
    // ← rememberSaveable 导航参数(旋转恢复语义 — iOS 状态默认保留)
    @Published var editTableId: Int64? = nil
    @Published var pendingNewTableId: Int64? = nil
    @Published var previousDefaultTableId: Int64? = nil
    // 深链课程
    @Published var deepLinkCourse: CourseEntity? = nil
    // 语言切换重建 token(← Activity.recreate): L10n.didChange → 递增 → AppRoot 全树重建
    @Published var languageReload = 0
    // ★ v1.0.45 底栏 dock 样式(默认 .docked = 贴底;悬浮形态由 PillNavigationBar.dockStyle 渲染)
    //   ← Android v1.0.45 b0f8280;状态由 AppPrefs 持有, 监听 .didChange 自动反向同步
    @Published var navDocked: Bool = AppPrefs.shared.isNavDocked()

    private var langObserver: NSObjectProtocol?
    private var prefsObserver: NSObjectProtocol?

    let scheduleViewModel: ScheduleViewModel

    init(repository: ScheduleRepository) {
        scheduleViewModel = ScheduleViewModel(
            repo: repository,
            onWidgetsNeedReload: { WidgetCenter.shared.reloadAllTimelines() })
        langObserver = NotificationCenter.default.addObserver(
            forName: L10n.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.languageReload += 1
        }
        // ★ v1.0.45: 用户在设置页改 nav dock 偏好 → AppPrefs 写盘 → UserDefaults 发 .didChange →
        //   这里刷新 navDocked → PillNavigationBar 下一帧切 dockStyle 重建。
        //   高刷新率开关不需要反向同步(开关自身直接调 HighRefreshRate.apply, 不经 root)。
        prefsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let docked = AppPrefs.shared.isNavDocked()
            if self.navDocked != docked { self.navDocked = docked }
        }
    }

    deinit {
        if let langObserver { NotificationCenter.default.removeObserver(langObserver) }
        if let prefsObserver { NotificationCenter.default.removeObserver(prefsObserver) }
    }

    // ← BackHandler: overlay 返回(pendingNewTable 丢弃链)
    func handleBack() {
        if let discardId = pendingNewTableId {
            let fallback = previousDefaultTableId
            pendingNewTableId = nil
            previousDefaultTableId = nil
            scheduleViewModel.discardNewTable(discardId, fallbackId: fallback)
            overlayScreen = nil
            editTableId = nil
        } else {
            overlayScreen = nil
            editingCourse = nil
            editTableId = nil
        }
    }

    // ← 新建空表(AllTables / Management 共用)
    func createNewTableThenEdit() {
        let previousId = scheduleViewModel.state.currentTable?.id
        let newId = scheduleViewModel.createEmptyTable(commitSelection: false)
        previousDefaultTableId = previousId
        pendingNewTableId = newId
        editTableId = newId
        overlayScreen = .editTable
    }

    // ← 深链: sleepy://course/<id>
    func handleDeepLinkCourse(_ id: Int64) {
        if deepLinkCourse?.id == id { return }
        let repo = ScheduleRepository(AppDatabase.getShared())
        if let course = try? repo.getCourse(id) {
            deepLinkCourse = course
        }
    }
}

// ← AppRoot composable
struct AppRoot: View {
    @EnvironmentObject var root: AppRootViewModel
    @Environment(\.colorScheme) private var systemScheme
    // ← themeMode/手动切主题联动
    @State private var themeMode: String = AppPrefs.shared.getThemeMode()
    @State private var themeKey: String = AppPrefs.shared.getThemeKey()
    @State private var jwImportActive = false
    // ★ iOS 16 sheet 冲突修复: ImportSheet 关闭动画中直接 present JwImportFlow
    //   会被 SwiftUI 丢弃(同一 runloop 两个 sheet 状态翻转)→ 延到 dismiss 完成。
    @State private var jwImportRequested = false

    var body: some View {
        // iOS 15 兼容(6s Plus 真机 = 15.8.8):此处仅作容器,无 NavigationLink 压栈,
        // 旧 API 行为等价(NavigationStack 是 iOS16+ API)。
        // ★ v7.10.17 6sp 空白修复 v2: NavigationView 即使 .navigationBarHidden(true)
        //   在 iOS 15.6 stack 风格仍预占约 88pt 透明 navbar 区域(.navigationBarHidden
        //   在 16+ 才稳定生效,15 上是 best-effort) → 所有页面顶栏上方 112pt 纯空白。
        //   AppRoot 没有 NavigationLink 需求 → 直接 root,不要 NavigationView 壳。
        //   JwImportFlow 内部仍保留 NavigationView(那里有真正的 nav stack 行为)。
        mainContent
            .ignoresSafeArea(.keyboard, edges: .bottom)
        // ← Activity.recreate(): 语言切换 → L10n.didChange → languageReload+1 → 全树重建
        .id(root.languageReload)
        .modifier(SleepyThemeProvider(darkTheme: isDark, themeKey: themeKey))
        .onOpenURL { url in
            handleDeepLink(url)
        }
        // ★ Xcode14/iOS16.4 模拟器: XCUIApplication.open(_:) 丢 URL(只 launch 不投递,
        //   SpringBoard 收不到 with-url 请求)→ UI 测试改由 app 内自触发
        //   UIApplication.open 走真实系统路由。真实用户路径 onOpenURL 不变。
        .onAppear {
            if let raw = ProcessInfo.processInfo.environment["SLEEPY_UI_TEST_OPENURL"],
               let url = URL(string: raw) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    UIApplication.shared.open(url)
                }
            }
            // ← SleepyApp.onCreate: 预加载当年+明年节假日数据(磁盘/网络)
            Task { await HolidayManager.preload() }
        }
        // 深链课程 → 编辑(← LaunchedEffect(deepLinkCourse?.id))
        .onChange(of: root.deepLinkCourse?.id) { courseId in
            if courseId != nil {
                root.editingCourse = root.deepLinkCourse
                root.deepLinkCourse = nil
            }
        }
        // pendingImportText → 自动切 Manage + 弹导入(← LaunchedEffect(pendingImportText))
        .onChange(of: PendingImportText.value) { text in
            if text != nil {
                root.currentTab = .manage
            }
        }
        .sheet(isPresented: $jwImportActive) {
            JwImportFlow {
                jwImportActive = false
            }
            // Sheet 是独立 presentation tree；显式注入主题，避免自定义颜色环境回落到 lightScheme。
            .modifier(SleepyThemeProvider(darkTheme: isDark, themeKey: themeKey))
            .preferredColorScheme(isDark ? .dark : .light)
        }
        // ★ sheet 冲突修复续: ImportSheet dismiss 完成后(0.45s 动画)再 present JW 流程
        .onChange(of: jwImportRequested) { req in
            guard req else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if jwImportRequested {
                    jwImportActive = true
                    jwImportRequested = false
                }
            }
        }
    }

    // ← AppPrefs.isDarkMode(context, systemDark)
    private var isDark: Bool {
        AppPrefs.shared.isDarkMode(isSystemDark: systemScheme == .dark)
    }

    @ViewBuilder
    private var mainContent: some View {
        // ★ v7.10.18 原生化重构:
        //   9 个独立 overlay 子页 → .fullScreenCover(item:) / .sheet(item:)
        //   - iOS 16+: 享有系统 swipe-to-dismiss / pull-down dismiss(原生手势)
        //   - iOS 15 (6sp 真机): 系统 ✕ 按钮 + 下拉 dismiss(无 edge swipe,但仍是原生)
        //   - holiday 子页由 GeneralSettings 内部 NavigationView 承载,不再列根
        //   - .sheet(item:) 用 OverlayScreen: Identifiable + rawValue 区分 item
        //   - 不再有 if/else if 条件树 → 渲染条件回到 tabs 即可
        // ★ v7.10.18 type-check v3: 9 个独立 PresentXxx ViewModifier, 每个子树
        //   独立类型推导, 避免 9 个 modifier 链触发 SwiftUI "unable to type-check"。
        tabs
            .modifier(PresentAddCourse(
                    isDark: isDark, themeKey: themeKey,
                    overlayScreen: root.overlayScreen,
                    editingCourse: root.editingCourse,
                    scheduleViewModel: root.scheduleViewModel,
                    onDismissAdd: { root.overlayScreen = nil; root.editingCourse = nil },
                    onSavedAdd: { root.overlayScreen = nil; root.editingCourse = nil; root.currentTab = .schedule }))
            .modifier(PresentEditTable(
                    isDark: isDark, themeKey: themeKey,
                    overlayScreen: root.overlayScreen,
                    editTableId: root.editTableId,
                    pendingNewTableId: root.pendingNewTableId,
                    scheduleViewModel: root.scheduleViewModel,
                    onBack: { root.handleBack() },
                    onDiscardPending: {
                        let discardId = root.pendingNewTableId
                        let fallback = root.previousDefaultTableId
                        root.pendingNewTableId = nil
                        root.previousDefaultTableId = nil
                        if let discardId = discardId {
                            root.scheduleViewModel.discardNewTable(discardId, fallbackId: fallback)
                        }
                        root.overlayScreen = nil
                        root.editTableId = nil
                    },
                    onSavedTable: {
                        root.overlayScreen = nil
                        root.editTableId = nil
                        root.pendingNewTableId = nil
                        root.previousDefaultTableId = nil
                    },
                    onDeletedTable: { root.overlayScreen = nil; root.editTableId = nil; root.currentTab = .schedule }))
            .modifier(PresentAllTables(
                    isDark: isDark, themeKey: themeKey,
                    overlayScreen: root.overlayScreen,
                    scheduleViewModel: root.scheduleViewModel,
                    onDismissOverlay: { root.overlayScreen = nil },
                    onCreateNewTable: { root.createNewTableThenEdit() },
                    onOpenEditTable: { tableId in
                        root.editTableId = tableId
                        root.pendingNewTableId = nil
                        root.overlayScreen = .editTable
                    }))
            .modifier(PresentGeneral(
                    isDark: isDark, themeKey: themeKey,
                    overlayScreen: root.overlayScreen,
                    onDismissOverlay: { root.overlayScreen = nil }))
            .modifier(PresentTheme(
                    isDark: isDark, themeKey: themeKey,
                    overlayScreen: root.overlayScreen,
                    themeMode: themeMode,
                    onDismissOverlay: { root.overlayScreen = nil },
                    onThemeModeChange: { mode in
                        themeMode = mode
                        themeKey = AppPrefs.shared.getThemeKey()
                    }))
            .modifier(PresentExport(
                    isDark: isDark, themeKey: themeKey,
                    overlayScreen: root.overlayScreen,
                    scheduleViewModel: root.scheduleViewModel,
                    onDismissOverlay: { root.overlayScreen = nil }))
            .modifier(PresentReminder(
                    isDark: isDark, themeKey: themeKey,
                    overlayScreen: root.overlayScreen,
                    onDismissOverlay: { root.overlayScreen = nil }))
            .modifier(PresentAbout(
                    isDark: isDark, themeKey: themeKey,
                    overlayScreen: root.overlayScreen,
                    onDismissOverlay: { root.overlayScreen = nil },
                    onOpenLicense: { root.overlayScreen = .license }))
            .modifier(PresentLicense(
                    isDark: isDark, themeKey: themeKey,
                    overlayScreen: root.overlayScreen,
                    onDismissOverlay: { root.overlayScreen = nil }))
    }

    // ← Scaffold + PillNavigationBar + 4 Tab
    private var tabs: some View {
        VStack(spacing: 0) {
            ZStack {
                switch root.currentTab {
                case .schedule:
                    ScheduleScreen(
                        viewModel: root.scheduleViewModel,
                        onGoImport: { root.currentTab = .manage },
                        onManualAdd: { root.overlayScreen = .addCourse },
                        onEditCourse: { course in root.editingCourse = course })
                case .today:
                    TodayScreen(viewModel: root.scheduleViewModel,
                                onEditCourse: { course in root.editingCourse = course })
                case .manage:
                    ManagementPage(
                        viewModel: root.scheduleViewModel,
                        autoShowImportSheet: PendingImportText.value != nil,
                        onJwImportRequested: { jwImportRequested = true },
                        onCreateNewTableRequested: { root.createNewTableThenEdit() },
                        onManualAdd: { root.overlayScreen = .addCourse },
                        onEditCurrentTable: {
                            root.editTableId = nil
                            root.pendingNewTableId = nil
                            root.overlayScreen = .editTable
                        },
                        // ★ 导入完成链(← Android onImported: 关导入框+切课表 Tab;
                        //   onOpenEditTable: 新导入表 → 打开表编辑页)
                        onImported: {
                            PendingImportText.value = nil
                            root.currentTab = .schedule
                        },
                        onOpenEditTable: { tableId in
                            PendingImportText.value = nil
                            root.editTableId = tableId
                            root.pendingNewTableId = nil
                            root.overlayScreen = .editTable
                        })
                case .mine:
                    MineScreen(
                        viewModel: root.scheduleViewModel,
                        onOpenAllTables: { root.overlayScreen = .allTables },
                        onOpenAppearance: { root.overlayScreen = .theme },
                        onOpenGeneral: { root.overlayScreen = .general },
                        onOpenExport: { root.overlayScreen = .export },
                        onOpenReminder: { root.overlayScreen = .reminder },
                        onOpenAbout: { root.overlayScreen = .about })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // PillNavigationBar(← Scaffold.bottomBar)
            PillNavigationBar(items: [
                PillNavItemData(id: "schedule", icon: "calendar", label: L10n.format("tab_schedule"),
                                selected: root.currentTab == .schedule) { root.currentTab = .schedule },
                PillNavItemData(id: "today", icon: "doc.on.doc", label: L10n.format("tab_today"),
                                selected: root.currentTab == .today) { root.currentTab = .today },
                PillNavItemData(id: "manage", icon: "gearshape", label: L10n.format("tab_manage"),
                                selected: root.currentTab == .manage) { root.currentTab = .manage },
                PillNavItemData(id: "mine", icon: "person", label: L10n.format("tab_mine"),
                                selected: root.currentTab == .mine) { root.currentTab = .mine },
            ], dockStyle: root.navDocked ? .docked : .floating)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    // ← handleDeepLinkIntent(平台差异表#4: Intent extras → URL scheme)
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "sleepy" else { return }
        switch url.host {
        case "open":
            break   // widget 点击(sleepy://open) → 冷启/回前台即达
        case "course":
            if let id = Int64(url.lastPathComponent) {
                root.handleDeepLinkCourse(id)
            }
        case "import":
            // 分享扩展/其他 app 传文本: sleepy://import?text=...
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let text = comps.queryItems?.first(where: { $0.name == "text" })?.value {
                PendingImportText.value = text
                root.currentTab = .manage
            }
        default:
            break
        }
    }
}

// ★ v7.10.18 type-check v3: 9 个独立 PresentXxx ViewModifier, 每个只挂 1 个
//   presentation (.fullScreenCover 或 .sheet), 由 Group { EmptyView().modifier(...) }
//   在 mainContent 里链式挂载。每个 modifier 子树类型推导独立预算, 避免
//   "unable to type-check this expression in reasonable time"。
//   闭包走构造注入, AppRoot 显式传 root 派生值。

private struct PresentAddCourse: ViewModifier {
    let isDark: Bool
    let themeKey: String
    let overlayScreen: AppRootViewModel.OverlayScreen?
    let editingCourse: CourseEntity?
    let scheduleViewModel: ScheduleViewModel
    let onDismissAdd: () -> Void
    let onSavedAdd: () -> Void
    func body(content: Content) -> some View {
        content.fullScreenCover(item: Binding<AppRootViewModel.OverlayScreen?>(
            get: { (overlayScreen == .addCourse || editingCourse != nil) ? .addCourse : nil },
            set: { newVal in if newVal == nil { onDismissAdd() } }
        )) { _ in
            AddCourseScreen(
                viewModel: scheduleViewModel,
                onDismiss: onDismissAdd,
                onSaved: onSavedAdd,
                editingCourse: editingCourse)
            .modifier(SleepyThemeProvider(darkTheme: isDark, themeKey: themeKey))
            .preferredColorScheme(isDark ? .dark : .light)
        }
    }
}

private struct PresentEditTable: ViewModifier {
    let isDark: Bool
    let themeKey: String
    let overlayScreen: AppRootViewModel.OverlayScreen?
    let editTableId: Int64?
    let pendingNewTableId: Int64?
    let scheduleViewModel: ScheduleViewModel
    let onBack: () -> Void
    let onDiscardPending: () -> Void
    let onSavedTable: () -> Void
    let onDeletedTable: () -> Void
    func body(content: Content) -> some View {
        content.fullScreenCover(item: Binding<AppRootViewModel.OverlayScreen?>(
            get: { overlayScreen == .editTable ? .editTable : nil },
            set: { newVal in if newVal == nil { onBack() } }
        )) { _ in
            EditTableScreen(
                viewModel: scheduleViewModel,
                tableId: editTableId,
                pendingNewTableId: pendingNewTableId,
                onDismiss: onBack,
                onDiscardPending: onDiscardPending,
                onSaved: onSavedTable,
                onDeleted: onDeletedTable)
            .modifier(SleepyThemeProvider(darkTheme: isDark, themeKey: themeKey))
            .preferredColorScheme(isDark ? .dark : .light)
        }
    }
}

private struct PresentAllTables: ViewModifier {
    let isDark: Bool
    let themeKey: String
    let overlayScreen: AppRootViewModel.OverlayScreen?
    let scheduleViewModel: ScheduleViewModel
    let onDismissOverlay: () -> Void
    let onCreateNewTable: () -> Void
    let onOpenEditTable: (Int64) -> Void
    func body(content: Content) -> some View {
        content.fullScreenCover(item: Binding<AppRootViewModel.OverlayScreen?>(
            get: { overlayScreen == .allTables ? .allTables : nil },
            set: { newVal in if newVal == nil { onDismissOverlay() } }
        )) { _ in
            AllTablesScreen(
                viewModel: scheduleViewModel,
                onDismiss: onDismissOverlay,
                onCreateNewTable: onCreateNewTable,
                onOpenEditTable: onOpenEditTable)
            .modifier(SleepyThemeProvider(darkTheme: isDark, themeKey: themeKey))
            .preferredColorScheme(isDark ? .dark : .light)
        }
    }
}

private struct PresentGeneral: ViewModifier {
    let isDark: Bool
    let themeKey: String
    let overlayScreen: AppRootViewModel.OverlayScreen?
    let onDismissOverlay: () -> Void
    func body(content: Content) -> some View {
        content.fullScreenCover(item: Binding<AppRootViewModel.OverlayScreen?>(
            get: { overlayScreen == .general ? .general : nil },
            set: { newVal in if newVal == nil { onDismissOverlay() } }
        )) { _ in
            GeneralSettingsScreen(onDismiss: onDismissOverlay)
                .modifier(SleepyThemeProvider(darkTheme: isDark, themeKey: themeKey))
                .preferredColorScheme(isDark ? .dark : .light)
        }
    }
}

private struct PresentTheme: ViewModifier {
    let isDark: Bool
    let themeKey: String
    let overlayScreen: AppRootViewModel.OverlayScreen?
    let themeMode: String
    let onDismissOverlay: () -> Void
    let onThemeModeChange: (String) -> Void
    func body(content: Content) -> some View {
        content.sheet(item: Binding<AppRootViewModel.OverlayScreen?>(
            get: { overlayScreen == .theme ? .theme : nil },
            set: { newVal in if newVal == nil { onDismissOverlay() } }
        )) { _ in
            AppearanceScreen(
                onDismiss: onDismissOverlay,
                themeMode: themeMode,
                onThemeModeChange: onThemeModeChange)
            .modifier(SleepyThemeProvider(darkTheme: isDark, themeKey: themeKey))
            .preferredColorScheme(isDark ? .dark : .light)
        }
    }
}

private struct PresentExport: ViewModifier {
    let isDark: Bool
    let themeKey: String
    let overlayScreen: AppRootViewModel.OverlayScreen?
    let scheduleViewModel: ScheduleViewModel
    let onDismissOverlay: () -> Void
    func body(content: Content) -> some View {
        content.fullScreenCover(item: Binding<AppRootViewModel.OverlayScreen?>(
            get: { overlayScreen == .export ? .export : nil },
            set: { newVal in if newVal == nil { onDismissOverlay() } }
        )) { _ in
            ExportScreen(viewModel: scheduleViewModel, onDismiss: onDismissOverlay)
                .modifier(SleepyThemeProvider(darkTheme: isDark, themeKey: themeKey))
                .preferredColorScheme(isDark ? .dark : .light)
        }
    }
}

private struct PresentReminder: ViewModifier {
    let isDark: Bool
    let themeKey: String
    let overlayScreen: AppRootViewModel.OverlayScreen?
    let onDismissOverlay: () -> Void
    func body(content: Content) -> some View {
        content.fullScreenCover(item: Binding<AppRootViewModel.OverlayScreen?>(
            get: { overlayScreen == .reminder ? .reminder : nil },
            set: { newVal in if newVal == nil { onDismissOverlay() } }
        )) { _ in
            ReminderScreen(onDismiss: onDismissOverlay)
                .modifier(SleepyThemeProvider(darkTheme: isDark, themeKey: themeKey))
                .preferredColorScheme(isDark ? .dark : .light)
        }
    }
}

private struct PresentAbout: ViewModifier {
    let isDark: Bool
    let themeKey: String
    let overlayScreen: AppRootViewModel.OverlayScreen?
    let onDismissOverlay: () -> Void
    let onOpenLicense: () -> Void
    func body(content: Content) -> some View {
        content.fullScreenCover(item: Binding<AppRootViewModel.OverlayScreen?>(
            get: { overlayScreen == .about ? .about : nil },
            set: { newVal in if newVal == nil { onDismissOverlay() } }
        )) { _ in
            AboutScreen(
                onDismiss: onDismissOverlay,
                onOpenLicense: onOpenLicense)
            .modifier(SleepyThemeProvider(darkTheme: isDark, themeKey: themeKey))
            .preferredColorScheme(isDark ? .dark : .light)
        }
    }
}

private struct PresentLicense: ViewModifier {
    let isDark: Bool
    let themeKey: String
    let overlayScreen: AppRootViewModel.OverlayScreen?
    let onDismissOverlay: () -> Void
    func body(content: Content) -> some View {
        content.fullScreenCover(item: Binding<AppRootViewModel.OverlayScreen?>(
            get: { overlayScreen == .license ? .license : nil },
            set: { newVal in if newVal == nil { onDismissOverlay() } }
        )) { _ in
            LicenseScreen(onDismiss: onDismissOverlay)
                .modifier(SleepyThemeProvider(darkTheme: isDark, themeKey: themeKey))
                .preferredColorScheme(isDark ? .dark : .light)
        }
    }
}