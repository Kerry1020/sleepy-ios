// AppearanceNavigationRow.swift — ← ui/screen/mine/AppearanceNavigationRow.kt
// 外观页二级入口行(节次表头/课表显示等), 单行纯标题 + 右侧 chevron。
// 视觉对齐 M3 ListItem: surfaceContainer 底, 12dp 圆角, 16dp 内外边距。
//
// 调用方现状: iOS AppearanceScreen 当前未使用(历史已 1:1 移植其他导航入口);
// 保留此组件, Android 端 Compose 行为 1:1 — 后续要加新分组直接复用本组件。

import SwiftUI

struct AppearanceNavigationRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 16))    // ← Android bodyLarge 16sp
                    .foregroundColor(colors.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 20))    // ← ChevronRight 默认 24dp, iOS 22pt 视觉近似
                    .foregroundColor(colors.onSurfaceVariant)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .buttonStyle(SleepyButtonStyle())
        .frame(maxWidth: .infinity)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.medium)
    }
}
