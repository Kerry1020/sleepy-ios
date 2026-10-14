// DialogActionButtons.swift — ← ui/component/DialogActionButtons.kt
// [intentional custom] 官方弹窗的 textButton 槽 = 裸文字按钮; 用户 2026-09-16
// 明确「裸 TextButton 无背景看不出可点」→ 色块按钮 + 宽度自适应换行是 Sleepy 领域需求,
// 官方无等价组合件, 保留薄层。
//
// 弹窗动作按钮行 — 全 app 弹窗 confirm/dismiss 唯一入口。
// 视觉 = 与全屏按钮同语言: 确认键 primary 色块, 取消/第三键 secondaryContainer 色块;
// 危险确认传 destructive=true 确认键变 errorContainer。
//
// 布局自适应(2026-09-16 用户第二轮: "文字完整 > 一排"): 按 DialogButtonsLayoutPolicy
// 估行内总需求, 放得下 → 等宽一行; 放不下 → 整组降级竖排全宽按钮, 不截断文字。

import SwiftUI

struct DialogActionButtons: View {
    @Environment(\.localWakeUpColors) private var colors
    let confirmText: String
    let onConfirm: () -> Void
    var dismissText: String? = nil
    var onDismiss: () -> Void = {}
    var destructive: Bool = false
    var confirmEnabled: Bool = true

    var body: some View {
        // 可用宽度按屏幕宽 - 弹窗左右 padding(24×2) 估计
        let availableWidth = UIScreen.main.bounds.width - 48
        let labels = [dismissText, confirmText].compactMap { $0 }
        let horizontal = DialogActionsLayoutPolicyBridge.fit(labels: labels, availableWidthDp: availableWidth)

        Group {
            if horizontal {
                HStack(spacing: DialogButtonsLayoutPolicy.ROW_GAP_DP) {
                    if let dismissText = dismissText {
                        blockButton(text: dismissText, onClick: onDismiss,
                                    container: colors.secondaryContainer,
                                    content: colors.onSecondaryContainer)
                    }
                    blockButton(text: confirmText, onClick: onConfirm,
                                container: destructive ? colors.errorContainer : colors.primary,
                                content: destructive ? colors.onErrorContainer : colors.onPrimary)
                }
            } else {
                // 竖排降级: 全宽按钮上下堆叠, 文字必然完整。顺序 = 取消 → 确认(动作在末位)。
                VStack(spacing: DialogButtonsLayoutPolicy.ROW_GAP_DP) {
                    if let dismissText = dismissText {
                        blockButton(text: dismissText, onClick: onDismiss,
                                    container: colors.secondaryContainer,
                                    content: colors.onSecondaryContainer)
                    }
                    blockButton(text: confirmText, onClick: onConfirm,
                                container: destructive ? colors.errorContainer : colors.primary,
                                content: destructive ? colors.onErrorContainer : colors.onPrimary)
                }
            }
        }
    }

    // 2026-09-18 用户: 文字必须完整展示 — 横排按必需宽比例分配(每键 ≥ 文字宽),
    // 竖排全宽更装得下, 两者都不截断。
    private func blockButton(text: String, onClick: @escaping () -> Void,
                             container: Color, content: Color) -> some View {
        Button(action: onClick) {
            Text(text)
                .font(.system(size: 14, weight: .medium))   // ← labelLarge 14 Medium
                .foregroundColor(content)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 48)   // ← SleepyTheme.Buttons.regularHeight
                .background(container)
                .cornerRadius(SleepyShapes.large)
        }
        .buttonStyle(SleepyButtonStyle())
        .disabled(!confirmEnabled && text == confirmText)
        .opacity(confirmEnabled || text != confirmText ? 1 : SleepyTheme.Alpha.inactive)
    }
}
