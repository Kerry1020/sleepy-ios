// PeriodHeaderLayoutModel.swift — ← ui/component/PeriodHeaderLayoutModel.kt 逐行翻译 (GPL-3.0)
// 三行表头几何模型 + 自适应字号 (纯函数, 0 SwiftUI 依赖, 单测覆盖)

import Foundation
import CoreGraphics

/**
 * 三行表头几何模型(纯数据)。
 *
 * 用户定稿 2026-09-27: 三行文字是唯一呈现元素, 元素矩形 =
 *   top = 第一行顶, bottom = 第三行底,
 *   left = min(时间行左缘, 标签左缘), right = max(时间行右缘, 标签右缘)。
 * 卡片自适应这个矩形 — 有字的地方就是卡片, 禁止用轨道宽度撑出空白。
 *
 * u ∈ [-1, +1]: 滑杆值。端点异锚:
 *   u=-1 标签右缘贴时间块左缘; u=+1 标签左缘贴时间块右缘; u=0 标签中心=时间块中心。
 * 3W 只是滑杆行程 (标签可移动总量), 与卡片尺寸无关。
 */
struct PeriodHeaderMetrics: Equatable {
    let startWidth: CGFloat
    let endWidth: CGFloat
    let labelWidth: CGFloat
    let showX: Bool

    var timeMax: CGFloat { max(startWidth, endWidth) }
    /// ← W = startWidth (Compose 端别名, 渲染侧未使用; 保留便于审计)
    var W: CGFloat { startWidth }
    /// ← trackWidth = 3 × startWidth (滑杆行程基线, 渲染侧未使用)
    var trackWidth: CGFloat { 3 * startWidth }

    /** 标签左缘原始坐标 (时间块左缘=0)。u=-1 → -labelWidth, u=+1 → timeMax, 线性。 */
    private func rawLabelLeft(u: CGFloat) -> CGFloat {
        -labelWidth + (u + 1) / 2 * (timeMax + labelWidth)
    }

    /** 当前 u 的元素矩形 (实际墨迹) 宽度 = 卡片内容区应取的宽度。 */
    func inkWidth(u: CGFloat) -> CGFloat {
        let labelLeft = rawLabelLeft(u: u)
        let left = min(0, labelLeft)
        let right = max(timeMax, labelLeft + labelWidth)
        return right - left
    }
}

/// 元素矩形左缘归零的排布: 谁在最左谁贴 0, 卡片宽 = 矩形宽。
struct PeriodHeaderPlacement: Equatable {
    /// L/R 时间块左缘最终 x (px, 相对元素矩形左缘)。
    let timeBaseLeft: CGFloat
    /// M 标签左缘最终 x (px)。
    let labelLeft: CGFloat
    /// 元素矩形总宽 (px) = 当前 u 的 inkWidth。
    let contentWidth: CGFloat
}

extension PeriodHeaderMetrics {
    /// 元素矩形左缘归零的排布: 谁在最左谁贴 0, 卡片宽 = 矩形宽。
    func solvePlacement(u: CGFloat) -> PeriodHeaderPlacement {
        let rawLabelLeft = -labelWidth + (u + 1) / 2 * (timeMax + labelWidth)
        let inkLeft = min(0, rawLabelLeft)
        let inkRight = max(timeMax, rawLabelLeft + labelWidth)
        return PeriodHeaderPlacement(
            timeBaseLeft: -inkLeft,
            labelLeft: rawLabelLeft - inkLeft,
            contentWidth: inkRight - inkLeft
        )
    }
}

/**
 * 整列统一排布 (用户定稿 2026-09-30):
 *   ① 卡片宽 = 最宽行的包络宽 — 全列一张宽, 不再逐行收口;
 *   ② 每行三元素以基准行 (最宽) 对应元素的 middle point 对齐 —
 *      时间中点对时间中点, 标签中点对标签中点, 行间固有错开保留。
 *
 * 实现: 每行先按自身 solvePlacement 解出元素中点 (相对各自元素矩形),
 * 再平移到基准行坐标系, 使对应中点重合; 卡片统一为基准 contentWidth。
 * 平移后矩形可能越出 [0, contentWidth] — 由调用方保证基准行是最宽行
 * (越出即说明存在更宽行, 本函数取的 max 自动吸收)。
 */
func solveColumnPlacement(rows: [PeriodHeaderMetrics], u: CGFloat) -> [PeriodHeaderPlacement] {
    if rows.isEmpty { return [] }
    let perRow = rows.map { $0.solvePlacement(u: u) }
    // 基准行 = 包络最宽者 (与 legacyColumnWidthDp 同一"最宽"语义)
    var baseIdx = 0
    for i in perRow.indices {
        if perRow[i].contentWidth > perRow[baseIdx].contentWidth { baseIdx = i }
    }
    let base = perRow[baseIdx]
    let baseMetrics = rows[baseIdx]
    // 基准行元素中点 (矩形内坐标)
    let baseTimeMid = base.timeBaseLeft + baseMetrics.timeMax / 2
    let baseLabelMid = base.labelLeft + baseMetrics.labelWidth / 2
    return perRow.enumerated().map { (i, p) in
        let m = rows[i]
        let timeMid = p.timeBaseLeft + m.timeMax / 2
        let labelMid = p.labelLeft + m.labelWidth / 2
        // 时间中点对齐 → 行整体平移量
        let shift = baseTimeMid - timeMid
        // 标签跟随自身中点对齐 (时间平移后标签中点若仍偏离基准, 用同一坐标系解标签 x)
        return PeriodHeaderPlacement(
            timeBaseLeft: p.timeBaseLeft + shift,
            labelLeft: baseLabelMid - m.labelWidth / 2,
            contentWidth: base.contentWidth
        )
    }
}

/**
 * 三行表头自适应字号(纯函数, Compose / Widget 共享单一事实来源)。
 *
 * 用户 2026-09-29 v3 连续自适应:
 *   - 字号随卡宽/卡高连续变化, 上下限钳制可读区间 [label 11~16, time 10~14]
 *   - 圈圈/罗马/大写/阿拉伯/汉字 五样式统一字号 (汉字作参考, 字宽用 ink 实测)
 *   - 内容更长 → 卡片变宽 (上游 widthBudget 负责), 禁缩字号迁就
 *   - 卡宽不够装墨迹 (最坏兜底) → 等比回缩
 *
 * 算法:
 *   - (cardH + 2.5) / 3.75 = 标签字号上限 — 3.75 来自渲染行盒公式
 *     (三行行盒 = 2.5×time + 1.25×label, time=label-1), 保证三行严格分隔永不重叠
 *   - cardW / labelWidth  ≈ 实测当前字号; (cardW/labelWidth) × scale_per_char
 *     其中 label 字宽 / 字号 ≈ 1.0 (汉字参考, 其它样式 ≤ 1.0)
 *   - 取 min(高上限, 宽上限), 钳到 [MIN, MAX]
 *   - time = label - 1 (时间永远比标签小 1sp, 等距梯度)
 *
 * 输入/输出单位: **sp** — Compose 消费端直接 `.sp`, Widget 消费端用
 * `TypedValue.applyDimension(COMPLEX_UNIT_SP, ..., displayMetrics)` 自带 density 转换。
 * 三链在数学上等价, 与 density 无关。
 */
struct PeriodHeaderAdaptiveFont: Equatable {
    let timeSize: CGFloat
    let labelSize: CGFloat

    /// 总行高 = 行间距行高 + 内边距, 保留三行距总和 (sp).
    var lineHeightSp: CGFloat { max(timeSize * 1.25, timeSize + 1) }

    /// 单行的字号约束输入 — 整列取最紧约束统一字号 (用户 2026-09-29 令).
    struct RowConstraint: Equatable {
        let inkWidthSp: CGFloat
        let timeMaxWidthSp: CGFloat
        let labelWidthSp: CGFloat
    }

    /// 可读区间上限 — Material titleSmall/labelLarge 区域, 老花眼舒适.
    static let MAX_LABEL_SP: CGFloat = 16
    static let MAX_TIME_SP: CGFloat = 14
    /// 可读区间下限 — Material bodySmall 下限, 触底不再缩.
    static let MIN_LABEL_SP: CGFloat = 11
    static let MIN_TIME_SP: CGFloat = 10
    /// 三行总占高 ↔ 单 label 字号之比。
    /// 渲染侧每行行盒高 = font × lineHeight(1.25), 三行 = 2.5×timeSize + 1.25×labelSize。
    /// time=size-1 代入 → 2.5(label-1) + 1.25 label = 3.75 label - 2.5。
    /// 此比 (3.75) 是渲染占高与字号的精确反比, 非估算。它能保证: labelSize 满足 heightCap 时,
    /// 三行行盒总高恰等于 cardHeightSp, 永不重叠 (用户 2026-09-30 定稿二: 三行间距不可压缩为代价)。
    private static let HEIGHT_TO_LABEL_RATIO: CGFloat = 3.75
    /// 基准字号 — 墨迹宽度测量用, 与自适应字号无关.
    static let BASE_LABEL_SP: CGFloat = 12
    static let BASE_TIME_SP: CGFloat = 11

    /**
     * @param cardWidthSp   卡片内容宽 (sp, 已扣内边距)
     * @param cardHeightSp  卡片内容高 (sp)
     * @param inkWidthSp    当前 u 下的墨迹宽 (sp). 0 = 未测, 跳过最坏兜底.
     * @param timeMaxWidthSp 起始/结束时间二者中较宽者 (sp). 0 = 未测, 预览链用.
     * @param labelWidthSp  标签宽度 (sp). 0 = 未测.
     */
    static func compute(
        cardWidthSp: CGFloat,
        cardHeightSp: CGFloat,
        inkWidthSp: CGFloat,
        timeMaxWidthSp: CGFloat,
        labelWidthSp: CGFloat
    ) -> PeriodHeaderAdaptiveFont {
        // 高度上限唯一驱动: 三行行盒总高 = 2.5×timeSize + 1.25×labelSize
        //   = 2.5×(labelSize-1) + 1.25×labelSize = 3.75×labelSize - 2.5sp。
        //   要求 ≤ cardHeightSp → labelSize ≤ (cardHeightSp + 2.5) / 3.75。
        //   此即 HEIGHT_TO_LABEL_RATIO 的精确反比 (3.75), 而非估算 2.6。
        // 宽度不做上限 — 宽度由上游按自适应字号实测后撑卡 (内容长→卡变宽, 禁缩字号迁就);
        // inkWidth 超卡宽仅在真装不下时兜底回缩 (见下)。
        // labelSize ≤ (cardHeightSp + 2.5) / 3.75 使三行行盒刚好贴齐卡高不越界。2.5sp 是 time=label-1 带出的补偿。
        let heightCap = (max(cardHeightSp, 1) + 2.5) / HEIGHT_TO_LABEL_RATIO
        // 卡高装不下 MIN 时 (小组件极矮行), 按高度比例缩不硬钳 — 硬钳必竖向溢出
        let labelSize: CGFloat
        if heightCap >= MIN_LABEL_SP {
            labelSize = min(heightCap, MAX_LABEL_SP)
        } else {
            labelSize = max(heightCap, 0.1)
        }
        let rawTime = labelSize - 1
        let timeSize: CGFloat
        if rawTime >= MIN_TIME_SP {
            timeSize = min(rawTime, MAX_TIME_SP)
        } else {
            timeSize = max(rawTime, 0.1)
        }
        // 墨迹闸: 传入的 inkWidthSp 是基准字号 (12sp) 下的测量值,
        // 实际渲染用自适应字号 — 按字号比投影到真实墨迹宽度再判溢出.
        // 例: 基准 12sp 测 ink=80sp, 自适应 16sp → 真实 ink = 80×(16/12) = 106.7sp
        let projectedInk: CGFloat = (inkWidthSp > 0 && labelSize > 0)
            ? inkWidthSp * (labelSize / BASE_LABEL_SP)
            : inkWidthSp
        let scale: CGFloat = (projectedInk > cardWidthSp && cardWidthSp > 0 && projectedInk > 0)
            ? cardWidthSp / projectedInk
            : 1
        return PeriodHeaderAdaptiveFont(
            timeSize: max(timeSize * scale, 0.1),
            labelSize: max(labelSize * scale, 0.1)
        )
    }

    /// One font for a whole column; the WIDEST (hardest-to-fit) row decides the size.
    static func forColumn(
        cardWidthSp: CGFloat,
        cardHeightSp: CGFloat,
        rows: [RowConstraint]
    ) -> PeriodHeaderAdaptiveFont {
        if rows.isEmpty {
            return compute(cardWidthSp: cardWidthSp, cardHeightSp: cardHeightSp,
                           inkWidthSp: 0, timeMaxWidthSp: 0, labelWidthSp: 0)
        }
        return compute(
            cardWidthSp: cardWidthSp,
            cardHeightSp: cardHeightSp,
            inkWidthSp: rows.map { $0.inkWidthSp }.max() ?? 0,
            timeMaxWidthSp: rows.map { $0.timeMaxWidthSp }.max() ?? 0,
            labelWidthSp: rows.map { $0.labelWidthSp }.max() ?? 0
        )
    }

    /// Preview shares the same algorithm; only the ink guard is skipped (it is sized generously).
    static func forPreview(cardWidthSp: CGFloat, cardHeightSp: CGFloat) -> PeriodHeaderAdaptiveFont {
        compute(cardWidthSp: cardWidthSp, cardHeightSp: cardHeightSp,
                inkWidthSp: 0, timeMaxWidthSp: 0, labelWidthSp: 0)
    }
}

/// Width shared by legacy header rows, based on the widest measured row.
func legacyColumnWidthDp(rowWidths: [CGFloat]) -> CGFloat { rowWidths.max() ?? 0 }

/**
 * 老式表头 (legacy 两行: 标签 / 时间串) 的 dash 对齐几何模型。
 *
 * 用户 2026-10-03 第二轮定稿:
 *   - 对齐轴 = 时间串中间 "-" 的中点。串居中 ≠ dash 对齐 (start/end 宽度不等,
 *     dash 不在串中心) — 第一轮"字符串整体居中"即因此越对越歪;
 *   - 整列所有行的 dash 落在同一 X; 标签同以该轴居中;
 *   - 列宽 = 轴左侧最大延伸 + 轴右侧最大延伸 + pad×2 —
 *     最宽行的墨迹两侧同样流出 pad 余量 (用户原话: "最宽的那一行, 余量也流出来")。
 *
 * 输入行墨迹: [labelPx] 标签整宽; [timeLeftPx] start 宽; [dashPx] 中间 "-" 宽;
 * [timeRightPx] end 宽; [labelHeightPx] 标签行高; [timeHeightPx] 时间行高。实测 px,
 * 高度 0 = 未测 (垂直解按宽度退化估值, 见 legacyVerticalFit)。
 */
struct LegacyDashRowInk: Equatable {
    let labelPx: CGFloat
    let timeLeftPx: CGFloat
    var dashPx: CGFloat = 0
    let timeRightPx: CGFloat
    var labelHeightPx: CGFloat = 0
    var timeHeightPx: CGFloat = 0
}

/// 单行最终排布: 标签左缘 / 时间串左缘 (px, 相对列左缘)。
struct LegacyDashPlacement: Equatable {
    let labelLeft: CGFloat
    let timeLeft: CGFloat
}

/// 整列统一几何: 列宽 / 共享 dash 轴 X / 每行排布。
struct LegacyDashColumn: Equatable {
    let columnWidthPx: CGFloat
    let dashCenterX: CGFloat
    let placements: [LegacyDashPlacement]
}

func legacyDashColumnPx(rows: [LegacyDashRowInk], padPx: CGFloat) -> LegacyDashColumn {
    if rows.isEmpty {
        return LegacyDashColumn(columnWidthPx: 0, dashCenterX: 0, placements: [])
    }
    // 轴 = dash **字形中心** (非盒左缘) — 渲染时 dash Text 盒左缘在
    // timeLeft + timeLeftPx 处, 字形中心还要加 dashPx/2 (2026-10-04 设备实锤
    // dash 全列偏右 dashPx/2 ≈ 4px, 根因 = 把盒左缘当轴心)。
    // 时间串左缘 = 轴 − timeLeftPx − dashPx/2; 串右缘 = 轴 + dashPx/2 + timeRightPx。
    let leftExtent = rows.map { max($0.labelPx / 2, $0.timeLeftPx + $0.dashPx / 2) }.max() ?? 0
    let rightExtent = rows.map { max($0.labelPx / 2, $0.dashPx / 2 + $0.timeRightPx) }.max() ?? 0
    let dashCenter = padPx + leftExtent
    let width = leftExtent + rightExtent + 2 * padPx
    let placements = rows.map {
        LegacyDashPlacement(
            labelLeft: dashCenter - $0.labelPx / 2,
            timeLeft: dashCenter - $0.timeLeftPx - $0.dashPx / 2
        )
    }
    return LegacyDashColumn(columnWidthPx: width, dashCenterX: dashCenter, placements: placements)
}

/**
 * 老式表头 union 包络垂直解 (用户 2026-10-03 定稿续):
 *   - 两行 (标签 + 时间串) 的墨迹是一个**整体矩形** (整体矩形 = 两行墨迹的
 *     最上/最下端围出), 卡片自适应这个**整体矩形**做水平 + 垂直居中
 *     (不是每行各自居中);
 *   - 垂直永不重叠: 每行高度 = 该行字体行高 (用户原话: "每行高度必须 ≥ 该行字体行高");
 *   - 高度不够时**两行同比例缩小** (用户原话: "高度实在不够时缩小两行字体"),
 *     不许压缩行距或让文字重叠 — 缩字优先于重叠;
 *   - dash 轴对齐保留为整体内部的水平排布规则。
 *
 * 输入: 行墨迹 (labelHeightPx/timeHeightPx 0 = 按宽度退化估值)
 *       + 卡片内容区高 px + 字号缩放下限 (单行 < 该值 → 触底不再缩).
 *
 * 输出: (labelTopPx, timeTopPx) (相对卡顶) + fontScale (与 render 时 lineHeight×
 *       scale 联动, 全行同缩放).
 */
struct LegacyDashVerticalFit: Equatable {
    let labelTopPx: CGFloat
    let timeTopPx: CGFloat
    let fontScale: CGFloat
}

/// 整列同一字号缩放(全列共用) — 取列内最紧行约束, 与 PeriodHeaderAdaptiveFont.forColumn 同口径.
struct LegacyDashColumnVertical: Equatable {
    let fontScale: CGFloat
    let labelTopPx: CGFloat
    let timeTopPx: CGFloat
}

/**
 * 单行 union 包络垂直解。
 *
 * 算法:
 *   - union = labelH + timeH (两行不重叠, 行间零间距 — legacy 模式历史上就没间距)
 *   - cardH ≥ union → fontScale = 1, 整体居中:
 *     labelTop = (cardH - union)/2, timeTop = labelTop + labelH
 *   - cardH < union → fontScale = cardH / union, 钳 [minScale, 1];
 *     union 顶贴卡顶 (union > 卡已无居中意义, 溢出由卡高接住, 缩字优先)
 */
func legacyVerticalFit(
    row: LegacyDashRowInk,
    cardContentHeightPx: CGFloat,
    minScale: CGFloat = 0.6
) -> LegacyDashVerticalFit {
    let labelH = row.labelHeightPx > 0 ? row.labelHeightPx : row.labelPx
    let timeH: CGFloat
    if row.timeHeightPx > 0 {
        timeH = row.timeHeightPx
    } else {
        timeH = row.timeLeftPx + row.dashPx + row.timeRightPx
    }
    let union = labelH + timeH
    if union <= 0 || cardContentHeightPx <= 0 {
        return LegacyDashVerticalFit(labelTopPx: 0, timeTopPx: 0, fontScale: 1)
    }
    if cardContentHeightPx >= union {
        let top = (cardContentHeightPx - union) / 2
        return LegacyDashVerticalFit(labelTopPx: top, timeTopPx: top + labelH, fontScale: 1)
    } else {
        let scale = max(min((cardContentHeightPx / union), 1), minScale)
        let scaledLabel = labelH * scale
        // union 顶贴卡顶, 字号缩小后真实行高 = labelH*scale, timeTop 接上, 底部溢出由 minScale 接住
        return LegacyDashVerticalFit(labelTopPx: 0, timeTopPx: scaledLabel, fontScale: scale)
    }
}

/**
 * 整列同一字号缩放(列级 union = max(labelH) + max(timeH)):
 *   - fontScale = cardH < union ? min(cardH/union, 1) : 1; 钳 [minScale, 1]
 *   - labelTop / timeTop 与单行解同口径
 *
 * 单卡预览/网格列/widget 三链共用本函数, 一致性优先。
 */
func legacyColumnVerticalFit(
    rows: [LegacyDashRowInk],
    cardContentHeightPx: CGFloat,
    minScale: CGFloat = 0.6,
    rowGapPx: CGFloat = 0
) -> LegacyDashColumnVertical {
    if rows.isEmpty || cardContentHeightPx <= 0 {
        return LegacyDashColumnVertical(fontScale: 1, labelTopPx: 0, timeTopPx: 0)
    }
    let labelH = rows.map { $0.labelHeightPx > 0 ? $0.labelHeightPx : $0.labelPx }.max() ?? 0
    let timeH: CGFloat = rows.map {
        $0.timeHeightPx > 0
            ? $0.timeHeightPx
            : $0.timeLeftPx + $0.dashPx + $0.timeRightPx
    }.max() ?? 0
    // 用户原话 2026-10-04 (行间距不对): label 与 time 之间恒留一个 gap (px)。
    // 缩字不压行距; 卡不够时 gap 优先被吞 (gap ≤ 总余量), 余量耗尽才缩字。
    let gap = max(rowGapPx, 0)
    let union = labelH + timeH + gap
    let slack = cardContentHeightPx - union
    let (scale, effectiveGap): (CGFloat, CGFloat)
    if slack >= 0 {
        (scale, effectiveGap) = (1, gap)
    } else if slack > -gap {
        // 负余量小于原 gap → 吞掉 gap 至 0, 不缩字
        (scale, effectiveGap) = (1, gap + slack)
    } else {
        // 连 gap 都吃完了, 还得缩字 — 按 (labelH + timeH) 缩, gap 归零
        let rest = cardContentHeightPx / (labelH + timeH)
        (scale, effectiveGap) = (max(min(rest, 1), minScale), 0)
    }
    let scaledLabel = labelH * scale
    let top = max((cardContentHeightPx - (labelH + timeH) * scale - effectiveGap) / 2, 0)
    return LegacyDashColumnVertical(
        fontScale: scale,
        labelTopPx: top,
        timeTopPx: top + scaledLabel + effectiveGap
    )
}

/**
 * 由卡片宽度 + 行高推导卡片高度(Compose / Widget 共享, 保证垂直节奏一致)。
 * 三行垂直均分, timeSize + labelSize + timeSize = 三行行高, 上下各加 1dp 内边距。
 */
func adaptiveCardHeightPx(rowHeightPx: CGFloat) -> CGFloat {
    max(rowHeightPx * 3, 18)
}
