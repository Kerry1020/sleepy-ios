// DialogButtonsLayoutPolicy.swift — ← util/DialogButtonsLayoutPolicy.kt 逐行翻译 (GPL-3.0)

import Foundation

/**
 * 用户反馈 2026-09-16 (第二轮): 弹窗动作键布局降级策略。
 *
 * 用户优先级: ①文字精炼 ②文字完整展示 ③一排美观。
 * "不是一定要一排, 最好是一排" — 行宽够就一行, 不够整组降级竖排,
 * 任何情况下不截断按钮文字。
 *
 * 宽度估算对 CJK 是精确的(等宽字); 对拉丁字母偏保守(估宽), 只会
 * 更早触发竖排, 不会误判"放得下"却截断 — fail-safe 方向正确。
 */
enum DialogButtonsLayoutPolicy {
    /// M3 Button 默认水平 contentPadding = 24dp×2 + 少量余量。
    static let BUTTON_H_PADDING_DP: CGFloat = 32
    /// 按钮间距(与 DialogActionButtons HStack spacing(8) 同值)。
    static let ROW_GAP_DP: CGFloat = 8

    /// 单键文字宽估算 = 字符数 × 单字宽 + 水平内边距。
    static func buttonTextWidth(_ label: String, _ fontDpPerChar: CGFloat, _ buttonHPaddingDp: CGFloat = BUTTON_H_PADDING_DP) -> CGFloat {
        CGFloat(label.count) * fontDpPerChar + buttonHPaddingDp
    }

    /// 行宽够不够容纳整组按钮(text 总宽 + 键间 gap)。不够 → 调用方换竖排, 不截断文字。
    static func fitsInRow(
        labels: [String], availableWidthDp: CGFloat,
        fontDpPerChar: CGFloat, buttonHPaddingDp: CGFloat = BUTTON_H_PADDING_DP,
        rowGapDp: CGFloat = ROW_GAP_DP
    ) -> Bool {
        if labels.isEmpty { return true }
        let totalNeeded = labels.reduce(CGFloat(0)) { $0 + buttonTextWidth($1, fontDpPerChar, buttonHPaddingDp) } +
            CGFloat(labels.count - 1) * rowGapDp
        return totalNeeded <= availableWidthDp
    }

    /// 横排每键的必需按钮宽。横排时若等分, 长标签键分到的宽度 < 必需宽 → 自动换行成两行。
    /// 所以横排必须按必需宽比例分配, 让每键至少拿到自己的必需宽。
    static func requiredButtonWidths(
        labels: [String], fontDpPerChar: CGFloat, buttonHPaddingDp: CGFloat = BUTTON_H_PADDING_DP
    ) -> [CGFloat] {
        labels.map { buttonTextWidth($0, fontDpPerChar, buttonHPaddingDp) }
    }

    /// HStack Spacer/weight 用的归一化权重 = 必需宽 / 总必需宽 (和恒 1)。
    /// 等分是错的: 权重比必须等于宽度需求比。
    static func normalizedWeights(
        labels: [String], fontDpPerChar: CGFloat, buttonHPaddingDp: CGFloat = BUTTON_H_PADDING_DP
    ) -> [CGFloat] {
        let widths = requiredButtonWidths(labels: labels, fontDpPerChar: fontDpPerChar, buttonHPaddingDp: buttonHPaddingDp)
        let total = widths.reduce(0, +)
        if total <= 0 || widths.isEmpty { return widths.map { _ in 1 / CGFloat(max(widths.count, 1)) } }
        return widths.map { $0 / total }
    }
}

/// 桥接默认字号(labelLarge 14sp → CJK 单字 ≈14dp), 供调用方少传参数。
/// 独立 enum 便于纯单测注入(不引 SwiftUI 依赖)。
enum DialogActionsLayoutPolicyBridge {
    static let LABEL_LARGE_FONT_DP_PER_CJK_CHAR: CGFloat = 14

    static func fit(labels: [String], availableWidthDp: CGFloat) -> Bool {
        DialogButtonsLayoutPolicy.fitsInRow(
            labels: labels, availableWidthDp: availableWidthDp,
            fontDpPerChar: LABEL_LARGE_FONT_DP_PER_CJK_CHAR)
    }
}
