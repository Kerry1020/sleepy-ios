// NavigationRailBar.swift — 宽屏左侧导航栏 ← Android 版本 SleepyNavHost.kt issue#45 ③
// (WindowWidthSizeClass != Compact → 官方 Material3 NavigationRail + Row{rail, content})
//
// iOS 原生等价 = NavigationSplitView sidebar，但本工程导航是 AppRootViewModel
// 自绘 overlay 状态机(全量 UITests/深链/转场都挂在它上面)，切 NavigationSplitView
// 等于重写路由层 → 不可行。故与 Android 选择官方 NavigationRail 的思路一致,
// iOS 侧用系统控件语感的自绘侧栏(本组件), 保持 root.currentTab 单点真值不变。
//
// 视觉规格(对齐 M3 NavigationRail):
//   - 宽 80pt(M3 默认 railWidth=80)
//   - 项 = 图标(24) + 标签(12), 垂直堆叠, 项间距 8
//   - 选中 = primaryContainer 胶囊(56×32) 包裹图标, 图标/标签 primary
//   - badge = 图标右上 7pt primary 圆点(← Android v1.0.60 badge 语义,
//     PillNavigationBar 同款)
//   - 顶对齐(M3 默认 verticalArrangement 从顶部开始)

import SwiftUI

struct NavigationRailBar: View {
    @Environment(\.localWakeUpColors) private var colors
    let items: [PillNavItemData]

    /// M3 NavigationRail 默认宽度
    static let railWidth: CGFloat = 80

    var body: some View {
        VStack(spacing: 8) {
            ForEach(items) { item in
                RailItemView(item: item, colors: colors)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 16)
        .frame(width: Self.railWidth)
        .frame(maxHeight: .infinity)
        .background(colors.background)
    }
}

private struct RailItemView: View {
    let item: PillNavItemData
    let colors: WakeUpColorScheme

    var body: some View {
        Button(action: item.onClick) {
            VStack(spacing: 4) {
                ZStack {
                    // 选中胶囊(← M3 indicator; Android NavigationRailItem 同款语义)
                    RoundedRectangle(cornerRadius: 16)
                        .fill(item.selected ? colors.primaryContainer : Color.clear)
                        .frame(width: 56, height: 32)
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: item.icon)
                            .font(.system(size: 20))
                            .foregroundColor(item.selected ? colors.onPrimaryContainer
                                                           : colors.onSurfaceVariant)
                        if item.badge {
                            Circle()
                                .fill(colors.primary)
                                .frame(width: 7, height: 7)
                                .offset(x: 4, y: -3)
                        }
                    }
                }
                Text(item.label)
                    .font(.system(size: 12, weight: item.selected ? .semibold : .regular))
                    .foregroundColor(item.selected ? colors.onSurface : colors.onSurfaceVariant)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 2)
            }
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 与 pill_* 同命名空间: rail_<id>; UITests 宽屏分支按此定位
        .accessibilityIdentifier("rail_\(item.id)")
    }
}
