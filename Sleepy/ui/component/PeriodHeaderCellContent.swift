// PeriodHeaderCellContent.swift — ← ui/component/PeriodHeaderCellContent.kt 逐行翻译 (GPL-3.0)
// 三行式 / 老式节次表头卡片内容 — 预览/周视图/小组件唯一的宽度事实来源 + 渲染入口。
//
// 行为契约(逐行对齐 Compose 版):
//   - layout == "three_line": 悬挂式 (hanging) 三行, 字号自适应 (PeriodHeaderAdaptiveFont)
//   - layout == "legacy"      : 两行, dash 轴对齐 (LegacyDashColumn / VerticalFit)
//   - sharedFont / sharedPlacement / sharedLegacyAxis 整列同源, 来自上游网格侧
//   - 内边距 0 — 卡片层负责 (与 Android 同一契约)

import SwiftUI

/** ← PERIOD_HEADER_CARD_PAD_DP = 3dp (卡片内边距事实来源, 预览/网格/widget 同一常量). */
let periodHeaderCardPadDp: CGFloat = 3

/// 三行式表头字号/行高常量(基线 11sp/12sp, 乘 scale 联动)。
/// ← headerTimeStyle / headerLabelStyle: 仅作为宽度预算基线, 实际绘制字号由卡片尺寸自适应。
func headerTimeStyle(scale: CGFloat) -> Font {
    .system(size: 11 * scale) // ← SleepyTextStyle.micro + fontSize 11*scale
}
func headerLabelStyle(scale: CGFloat) -> Font {
    .system(size: 12 * scale, weight: .semibold) // ← SleepyTextStyle.smallMeta SemiBold 12*scale
}

/** 自适应字号 → SwiftUI Font: 数值单位是 sp (font.px 与 density 无关的字号语义)。*/
func adaptiveHeaderTimeStyle(scale: CGFloat, font: PeriodHeaderAdaptiveFont) -> Font {
    .system(size: font.timeSize * scale)
}
func adaptiveHeaderLabelStyle(scale: CGFloat, font: PeriodHeaderAdaptiveFont) -> Font {
    .system(size: font.labelSize * scale, weight: .semibold)
}

/// 节次表头单元格(预览/周视图/小组件共用) — 真实网格列宽与设置页预览卡共用同一算法。
struct PeriodHeaderCellContent: View {
    @Environment(\.localWakeUpColors) private var colors

    /// ← data class TimeSlot 的渲染期最小集; iOS TimeSlot 已存在于 CourseTableView.swift,
    /// 渲染函数单独解构字段避免跨文件耦合。
    let displayStart: String
    let displayEnd: String
    let nodeStart: Int
    let nodeEnd: Int
    /// 渲染期占位节次(buildRenderSlotPlan 生成的空档): label 空 = 占位行
    let isPlaceholder: Bool

    let layout: String      // "three_line" | "legacy"
    let style: String       // "arabic" | "chinese" | "financial" | "circled" | "roman"
    var scale: CGFloat = 1
    var hangingUnitsOverride: CGFloat? = nil
    var showXOverride: Bool? = nil
    var sharedFont: PeriodHeaderAdaptiveFont? = nil
    var sharedPlacement: PeriodHeaderPlacement? = nil
    var sharedLegacyAxis: CGFloat? = nil

    var body: some View {
        // 内边距由卡片层统一负责, 这里不再叠加 — Compose 版同口径
        GeometryReader { geo in
            let cardW = geo.size.width
            let cardH = geo.size.height
            let showX = showXOverride ?? false  // ← AppPrefs.isPeriodHeaderShowX(context) — iOS 设置未落地, 暂 false
            let label: String = (showX && nodeStart == nodeEnd)
                ? PeriodHeaderFormatter.fullLabel(nodeStart, style)
                : PeriodHeaderFormatter.range(nodeStart, nodeEnd, style)

            if layout == "three_line" {
                threeLineBody(cardW: cardW, cardH: cardH, label: label, showX: showX)
            } else {
                legacyBody(cardW: cardW, cardH: cardH, label: label)
            }
        }
    }

    // MARK: - 三行式

    /// 三行式测量结果 (纯计算, 非 ViewBuilder — if 赋值块在 ViewBuilder 里不合法)
    private struct ThreeLineMeasure {
        let adLabelFont: UIFont
        let adTimeFont: UIFont
        let startH: CGFloat
        let labelH: CGFloat
        let contentHeight: CGFloat
        let timeBaseLeft: CGFloat
        let labelLeft: CGFloat
        let inkUnionWidthPx: CGFloat
        let placement: PeriodHeaderPlacement
    }

    private func measureThreeLine(cardW: CGFloat, cardH: CGFloat, label: String, showX: Bool) -> ThreeLineMeasure {
        // 文字测量用 UIKit UIFont 实例 (SwiftUI Font 在 View 外测不准, 必须底层 UIFont)
        let labelFont: UIFont = UIFont.systemFont(ofSize: 12 * scale, weight: .semibold)
        let timeFont: UIFont = UIFont.systemFont(ofSize: 11 * scale)
        let baseStartW = textWidth(displayStart, font: timeFont)
        let baseEndW = textWidth(displayEnd, font: timeFont)
        let baseLabelW = textWidth(label, font: labelFont)
        let hangingUnits = (hangingUnitsOverride ?? 0).clamped(to: -1...1) // ← AppPrefs.getPeriodHeaderHanging
        let baseMetrics = PeriodHeaderMetrics(
            startWidth: baseStartW, endWidth: baseEndW, labelWidth: baseLabelW,
            showX: showX && nodeStart == nodeEnd
        )
        // sharedFont 来自上游网格列最紧约束; 未传(预览)时按本卡自适应
        var adaptiveFont = sharedFont ?? PeriodHeaderAdaptiveFont.compute(
            cardWidthSp: cardW, cardHeightSp: cardH,
            inkWidthSp: baseMetrics.inkWidth(u: hangingUnits),
            timeMaxWidthSp: baseMetrics.timeMax,
            labelWidthSp: baseLabelW
        )
        // 重测自适应字号下的字宽/字高
        var adLabelFont: UIFont = .systemFont(ofSize: adaptiveFont.labelSize * scale, weight: .semibold)
        var adTimeFont: UIFont = .systemFont(ofSize: adaptiveFont.timeSize * scale)
        var startWidth = textWidth(displayStart, font: adTimeFont)
        var endWidth = textWidth(displayEnd, font: adTimeFont)
        var labelWidth = textWidth(label, font: adLabelFont)
        var startH = singleLineHeight(font: adTimeFont)
        var labelH = singleLineHeight(font: adLabelFont)
        var endH = singleLineHeight(font: adTimeFont)
        // 不重叠硬约束: 三行行盒总高 > 卡高 → 等比缩字, 宁小勿叠
        let requiredHPx = startH + labelH + endH
        if requiredHPx > cardH && requiredHPx > 0 && cardH > 0 {
            let shrink = cardH / requiredHPx
            adaptiveFont = PeriodHeaderAdaptiveFont(
                timeSize: max(adaptiveFont.timeSize * shrink, 0.1),
                labelSize: max(adaptiveFont.labelSize * shrink, 0.1)
            )
            adLabelFont = .systemFont(ofSize: adaptiveFont.labelSize * scale, weight: .semibold)
            adTimeFont = .systemFont(ofSize: adaptiveFont.timeSize * scale)
            startWidth = textWidth(displayStart, font: adTimeFont)
            endWidth = textWidth(displayEnd, font: adTimeFont)
            labelWidth = textWidth(label, font: adLabelFont)
            startH = singleLineHeight(font: adTimeFont)
            labelH = singleLineHeight(font: adLabelFont)
            endH = singleLineHeight(font: adTimeFont)
        }
        let metrics = PeriodHeaderMetrics(
            startWidth: startWidth, endWidth: endWidth, labelWidth: labelWidth,
            showX: showX && nodeStart == nodeEnd
        )
        let placement = sharedPlacement ?? metrics.solvePlacement(u: hangingUnits)
        // 真实墨迹并集左/右缘 (px, 相对元素矩形左缘)
        let timeMaxW = max(startWidth, endWidth)
        let inkLeftPx = min(placement.timeBaseLeft, placement.labelLeft)
        let inkRightPx = max(placement.timeBaseLeft + timeMaxW, placement.labelLeft + labelWidth)
        let inkUnionWidthPx = max(inkRightPx - inkLeftPx, 0)
        let contentHeight = startH + labelH + endH
        let timeBaseLeft = placement.timeBaseLeft - inkLeftPx
        let labelLeft = placement.labelLeft - inkLeftPx
        return ThreeLineMeasure(
            adLabelFont: adLabelFont, adTimeFont: adTimeFont,
            startH: startH, labelH: labelH,
            contentHeight: contentHeight, timeBaseLeft: timeBaseLeft,
            labelLeft: labelLeft, inkUnionWidthPx: inkUnionWidthPx,
            placement: placement
        )
    }

    @ViewBuilder
    private func threeLineBody(cardW: CGFloat, cardH: CGFloat, label: String, showX: Bool) -> some View {
        let m = measureThreeLine(cardW: cardW, cardH: cardH, label: label, showX: showX)
        let adLabelFont = m.adLabelFont
        let adTimeFont = m.adTimeFont
        let contentHeight = m.contentHeight
        let timeBaseLeft = m.timeBaseLeft
        let labelLeft = m.labelLeft

        // ← Android 结构: 外层 Box(fillMaxSize, Center) { 内层 Box(inkUnionWidth × contentHeight) {
        //     Text(start) TopStart.offset(timeBaseLeft); Text(label) CenterStart.offset(labelLeft);
        //     Text(end) BottomStart.offset(timeBaseLeft) } }
        // 三行行盒总高可能 < 卡高 (缩字守卫触发时) — 盒高 = 行盒总高, 外层 Center 上下间隙均分, 水平同理。
        let topPad = max((cardH - contentHeight) / 2, 0)

        ZStack(alignment: .topLeading) {
            // 第一行: 开始时间, 行盒顶 = contentHeight 顶, x = timeBaseLeft
            Text(displayStart)
                .font(Font(adTimeFont))
                .foregroundColor(colors.onSurfaceVariant)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: timeBaseLeft, y: topPad)
            // 第二行: 标签, 垂直中点对齐, x = labelLeft (端点异锚悬挂偏移)
            // (中点近似 = topPad + startH + (labelH)/2 - labelH/2 = topPad + startH, 用行盒近似)
            Text(label)
                .font(Font(adLabelFont))
                .foregroundColor(colors.onSurface)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: labelLeft, y: topPad + m.startH)
            // 第三行: 结束时间, 行盒底 = contentHeight 底, x = timeBaseLeft (与第一行同左缘基线)
            Text(displayEnd)
                .font(Font(adTimeFont))
                .foregroundColor(colors.onSurfaceVariant)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: timeBaseLeft, y: topPad + m.startH + m.labelH)
        }
        .frame(width: cardW, height: cardH, alignment: .topLeading)
    }

    // MARK: - Legacy 两行

    @ViewBuilder
    private func legacyBody(cardW: CGFloat, cardH: CGFloat, label: String) -> some View {
        let labelFont: UIFont = UIFont.systemFont(ofSize: 12 * scale, weight: .semibold)
        let timeFont: UIFont = UIFont.systemFont(ofSize: 11 * scale)
        let labelPx = textWidth(label, font: labelFont)
        let timeLeftPx = textWidth(displayStart, font: timeFont)
        let dashPx = textWidth("-", font: timeFont)
        let timeRightPx = textWidth(displayEnd, font: timeFont)
        let labelHeightPx = singleLineHeight(font: labelFont)
        let timeHeightPx = singleLineHeight(font: timeFont)
        let rowInk = LegacyDashRowInk(
            labelPx: labelPx, timeLeftPx: timeLeftPx, dashPx: dashPx, timeRightPx: timeRightPx,
            labelHeightPx: labelHeightPx, timeHeightPx: timeHeightPx
        )
        let axisX = sharedLegacyAxis ?? max(rowInk.labelPx / 2, rowInk.timeLeftPx)
        let vertical = legacyColumnVerticalFit(
            rows: [rowInk],
            cardContentHeightPx: cardH,
            rowGapPx: 2 * scale
        )
        let baseFont = PeriodHeaderAdaptiveFont(
            timeSize: PeriodHeaderAdaptiveFont.BASE_TIME_SP,
            labelSize: PeriodHeaderAdaptiveFont.BASE_LABEL_SP
        )
        let effectiveScale = scale * vertical.fontScale
        let labelFontScaled = UIFont.systemFont(ofSize: baseFont.labelSize * effectiveScale, weight: .semibold)
        let timeFontScaled = UIFont.systemFont(ofSize: baseFont.timeSize * effectiveScale)
        let labelLeft = axisX - rowInk.labelPx / 2
        let timeLeft = axisX - rowInk.timeLeftPx - rowInk.dashPx / 2

        // 外层 Box 摆两行 (label + time) 绝对定位
        ZStack(alignment: .topLeading) {
            // 第一行: label 水平以 dash 轴居中
            Text(label)
                .font(Font(labelFontScaled))
                .foregroundColor(colors.onSurface)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: labelLeft, y: vertical.labelTopPx)
            // 第二行: 时间串 start/dash/end 共享基线, 整体左缘 = timeLeft
            HStack(spacing: 0) {
                Text(displayStart)
                    .font(Font(timeFontScaled))
                    .foregroundColor(colors.onSurfaceVariant)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text("-")
                    .font(Font(timeFontScaled))
                    .foregroundColor(colors.onSurfaceVariant)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(displayEnd)
                    .font(Font(timeFontScaled))
                    .foregroundColor(colors.onSurfaceVariant)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .offset(x: timeLeft, y: vertical.timeTopPx)
        }
        .frame(width: cardW, height: cardH)
    }

    // MARK: - 文字测量 (UIKit 底层, SwiftUI Font 在 View 外测不准)

    private func textWidth(_ s: String, font: UIFont) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = (s as NSString).size(withAttributes: attrs)
        return size.width
    }
    private func singleLineHeight(font: UIFont) -> CGFloat {
        // 行高 = font × lineHeight(1.25) — 与 Android 渲染侧同一公式
        font.lineHeight
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
