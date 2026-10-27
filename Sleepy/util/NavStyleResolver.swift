// NavStyleResolver.swift — 底栏形态决策单点
//
// ★ 2026-10-26 Kerry 定稿(两项制): 设置页只有「贴底 / 悬浮」两个选项, 默认悬浮。
//   没有「自动」档 —— 设备/系统差异全部折叠进「悬浮」一项内部:
//   - 悬浮 + 系统原生 TabBar 可用(iOS 26+ Liquid Glass)→ native(原生玻璃悬浮)
//   - 悬浮 + 原生不可用(iOS 15~25)                      → floating(自绘悬浮药丸)
//   - 贴底                                                  → docked(自绘贴底, 恒自绘)
//   prefs 键从未写入(老装/新装未动过设置)= 悬浮(缺省 true)。
//
// 优先级链(高→低):
//   0. 宽屏形态闸(keyWindow ≥600pt → rail 左侧栏; ← Android 版本 issue#45 ③
//      !isCompact → 官方 NavigationRail; UITest forcePill 除外。用户两项选择在
//      宽屏下不生效 = Android 侧 navDock 仅在 Compact 分支参与分流, 同语义)
//   1. UITest 钉死自绘(-SLEEPY_FORCE_PILL_NAV, 全量 UITests 依赖 pill_* 标识)
//   2. 用户选择(贴底 → docked 恒定; 悬浮 → native 可用则原生)
//
// ★ "未设置" ≠ "设置了贴底": isNavDocked() 对未写入返回 false 是缺省值而非
//   用户意志; 存在性判定走 AppPrefs.hasExplicitNavStyle(), 未写入按悬浮缺省。

import SwiftUI

enum NavBarRenderMode: Equatable {
    case native                       // iOS 26+ 系统 TabBar(Liquid Glass)
    case floating                     // 自绘悬浮药丸(原生不可用时的悬浮兜底)
    case docked                       // 自绘贴底
    case rail                         // 宽屏左侧栏(iPad/横屏/分屏/Stage Manager
                                       //   ≥600pt ← Android 版本 WindowWidthSizeClass
                                       //   !Compact → 官方 NavigationRail, issue#45 ③)
}

enum NavStyleResolver {

    /// UITests 钉死自绘的启动参数(全量套件按 pill_<id> 导航, 原生 TabBar 无此标识)。
    static let forcePillArg = "-SLEEPY_FORCE_PILL_NAV"

    /// 宽屏断点 ← Android 版本 Material3 WindowWidthSizeClass.Compact 上界(<600dp):
    /// 可用宽度 ≥600pt 即平板形态。iPad 全系(竖屏 768+/横屏 1024+)、Split View/
    /// Stage Manager 宽侧命中; iPhone 恒竖屏(≤430pt)永不触发。
    static let railWidthThreshold: CGFloat = 600

    // MARK: - 纯逻辑(单测直打)

    /// floating=true(悬浮) / false(贴底) → 渲染形态。
    /// forcedPill: UITest 钉死 → 悬浮语义降级为自绘 floating(永不 native)。
    /// isWide: 宽屏形态闸(← Android 版本 !isCompact→NavigationRail, 先于用户选择;
    ///   底部药丸/贴底是手机形态语义, 平板横屏下不适用)。forcePill 不降级 rail,
    ///   全量 UITests 的 pill_* 标识链路保持。
    static func effectiveMode(floating: Bool,
                              supportsNative: Bool,
                              forcedPill: Bool,
                              isWide: Bool = false) -> NavBarRenderMode {
        if isWide && !forcedPill { return .rail }
        if !floating { return .docked }
        if forcedPill { return .floating }
        return supportsNative ? .native : .floating
    }

    // MARK: - 运行时判定(生产入口)

    /// 生产入口。windowWidth = AppRoot 实时上报(优先级高, 旋转/分屏即时覆盖);
    /// nil 时回退 keyWindow 实测(冷启/scenePhase 路径)。
    static func effectiveMode(windowWidth: CGFloat? = nil) -> NavBarRenderMode {
        effectiveMode(floating: isFloatingRequested(),
                      supportsNative: supportsNativeTabBar,
                      forcedPill: ProcessInfo.processInfo.arguments.contains(forcePillArg),
                      isWide: isWideLayout(windowWidth: windowWidth))
    }

    /// 宽屏实测 = 可用宽度 ≥ 断点(竖/横/分屏/Stage Manager 缩放皆覆盖)。
    /// 两值皆 nil(冷启极早期) = false 保守按手机形态; AppRoot 的宽度回调
    /// (onPreferenceChange)与 scenePhase.active 会在窗口就位后重判纠偏。
    static func isWideLayout(windowWidth: CGFloat? = nil) -> Bool {
        let width = windowWidth ?? connectedKeyWindowWidth()
        return (width ?? 0) >= railWidthThreshold
    }

    private static func connectedKeyWindowWidth() -> CGFloat? {
        UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .bounds.width
    }

    /// 用户意图 = 悬浮? 未写入键 → true(缺省悬浮, Kerry 2026-10-26 定)。
    static func isFloatingRequested() -> Bool {
        let prefs = AppPrefs.shared
        return prefs.hasExplicitNavStyle() ? prefs.isNavDocked() : true
    }

    /// 悬浮语义布尔(AppRootViewModel.navFloating 兼容旧口径)。
    /// native 归 true — 原生同样是悬浮语义(内容直通屏底)。
    static func effectiveFloating() -> Bool {
        floating(for: effectiveMode())
    }

    /// 形态 → 内容布局口径(纯函数, 单测直打): docked/rail=false, floating/native=true。
    /// native 归悬浮语义 — 原生 TabBar 玻璃悬浮, 内容同样直通屏底。
    /// rail 归 false — 侧栏水平占位, 底部零遮挡, 不需要直通屏底/滚动余量。
    static func floating(for mode: NavBarRenderMode) -> Bool {
        switch mode {
        case .native, .floating: return true
        case .docked, .rail: return false
        }
    }

    // MARK: - 能力探测

    /// 系统原生 TabBar 可用作底栏(iOS 26 起 SwiftUI TabView = Liquid Glass 悬浮玻璃;
    /// 部署目标 15.6 下 iOS 15~25 返回 false → 自绘兜底)。
    static var supportsNativeTabBar: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }
}
