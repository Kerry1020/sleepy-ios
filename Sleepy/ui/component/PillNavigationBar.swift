// PillNavigationBar.swift — ← ui/component/PillNavigationBar.kt
// 胶囊底栏(动画对齐安卓 v2):
//   surface-container 背景 + 4 tab(图标胶囊 64×32 + 下方 label)。
//   选中态: secondary-container 胶囊底 / on-surface 文字; 未选中: surface-variant 文字。
//
// v2 动画(与 SegmentedSwitcher 同源):
//   弹簧(response 0.18, damping 1.0)驱动 thumb center 横向位移;
//   图标按「图标区间 ∩ thumb 区间」横向覆盖率 lerp 变色;
//   文字按「字符矩形 ∩ thumb 区间」扫过上色(色块边缘扫过哪个字哪个字才变色)。
//
// ★ v2.2 回归修复 (2026-09-06, 用户报障):
//   1) 切换页面色块不切:外层 PillNavigationBar wrapper 用 @State selectedIndex + init 时
//      从 items[*].selected 推一次 → 外部 onClick 改 root.currentTab 后 items[*].selected
//      翻转但 wrapper 的 @State 不变,thumb 留在原 tab。改为 wrapper 不持有 state,
//      每次 body 按 items[*].selected 现算 selectedIndex → 与 Kotlin Android index-driven
//      API 等价(真值在 caller)。
//   2) 色块高度溢出下边框:thumb 是顶层 RoundedRectangle .offset(y:0),但 frame 76pt 内
//      还有 .padding(.top,6) + .padding(.bottom,8),SwiftUI 算坐标时 thumb 在 0..32pt,
//      下方留 8pt 边界不对称;改为 thumb 直接 .offset(y:12) 居中图标胶囊位置,
//      frame 76 - (12 + 32) = 32pt 上下对称。
//
// v2.3 (2026-09-06): 用 .coordinateSpace(name: "pillBar") 把测量统一到 bar 局部坐标系,
//   pill center + label left 全在 bar 局部坐标中计算(无 root→bar 换算)。
//
// v2.4 (2026-09-06): pill 中心 / label 左缘通过 PreferenceKey 一次性收集,根层
//   .onPreferenceChange 接收 → thumb 弹簧跟随 selectedIndex 平滑滑动。

import SwiftUI
import CoreText
import UIKit

struct PillNavigationBar: View {
    @Environment(\.localWakeUpColors) private var colors
    let items: [PillNavItemData]
    /// 底栏样式: .docked(贴底 默认) 或 .floating(悬浮玻璃胶囊)
    /// ← Android v1.0.45 b0f8280/ff66ddd;状态由 AppRoot 持有下传与设置页同源。
    var dockStyle: DockStyle = .docked

    enum DockStyle { case docked, floating }

    var body: some View {
        PillNavigationBarAnim(items: items, colors: colors, dockStyle: dockStyle)
    }
}

private struct PillNavigationBarAnim: View {
    let items: [PillNavItemData]
    let colors: WakeUpColorScheme
    let dockStyle: PillNavigationBar.DockStyle

    // bar 局部坐标系下,每个 tab 的 pill center + label left
    @State private var pillCentersBar: [Int: CGFloat] = [:]
    @State private var labelLeftsBar: [Int: CGFloat] = [:]
    // 各 tab label 的字符矩形(bar 局部坐标)
    @State private var charRectsCache: [Int: [CGRect]] = [:]

    // thumb center(bar 局部坐标),弹簧驱动
    @State private var thumbCenterX: CGFloat = 0
    @State private var thumbPlaced = false

    private let thumbWidth: CGFloat = 64
    private let thumbHeight: CGFloat = 32
    private let barHeight: CGFloat = 76
    private let thumbYOffset: CGFloat = 12   // 顶栏 12pt + thumb 32pt + 底栏 32pt = 76pt 上下对称

    // 悬浮形态专属尺寸(← Android b0f8280/351436d 56dp 胶囊 + 16dp 左右边距 + 28dp 圆角 + 12dp 底距)
    private let floatingSideMargin: CGFloat = 16
    private let floatingCornerRadius: CGFloat = 28
    private let floatingBottomPadding: CGFloat = 12

    /// 单一真值:每次 body 现算。外部 onClick → items[*].selected 翻转 → 立即反映。
    private var selectedIndex: Int {
        items.firstIndex(where: { $0.selected }) ?? 0
    }

    var body: some View {
        let selected = selectedIndex
        let isFloating = dockStyle == .floating

        // 形态选择: 悬浮 → 外层 HStack 撑侧边距 + 玻璃胶囊 surfaceContainer 高圆角;
        //            贴底 → 全宽表面 + SleepyShapes.large 圆角。
        return Group {
            if isFloating {
                HStack(spacing: 0) {
                    barBody(selected: selected)
                        .background(
                            colors.surfaceContainer
                                .opacity(0.92)   // 玻璃质感:半透明上层,靠 surfaceContainer 实际色
                        )
                        .clipShape(RoundedRectangle(cornerRadius: floatingCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: floatingCornerRadius)
                                .stroke(colors.outlineVariant.opacity(0.4),
                                        lineWidth: 0.5)
                        )
                        .shadow(color: colors.onBackground.opacity(0.12),
                                radius: 8, x: 0, y: 2)
                }
                .padding(.horizontal, floatingSideMargin)
                .padding(.bottom, floatingBottomPadding)
            } else {
                barBody(selected: selected)
                    .background(colors.surfaceContainer.ignoresSafeArea(edges: .bottom))
            }
        }
        // 收集 pill 中心 + label 左缘(bar 局部)
        .onPreferenceChange(PillGeomKey.self) { value in
            pillCentersBar = value.centers
            labelLeftsBar = value.labelLefts
        }
        // thumb 弹簧跟随 selectedIndex
        .onChange(of: selected) { _ in animateThumbToSelected() }
        .onChange(of: pillCentersBar) { _ in animateThumbToSelected() }
        .onAppear { animateThumbToSelected() }
    }

    /// 共享的底栏内部结构(ZStack + 4 tab)。外层 barBody 复用贴底/悬浮两态。
    @ViewBuilder
    private func barBody(selected: Int) -> some View {
        ZStack(alignment: .topLeading) {
            // thumb 色块(顶层 ZStack,bar 局部坐标)
            RoundedRectangle(cornerRadius: SleepyShapes.large)
                .fill(colors.secondaryContainer)
                .frame(width: thumbWidth, height: thumbHeight)
                .offset(x: thumbCenterX - thumbWidth / 2, y: thumbYOffset)
                .opacity(thumbPlaced ? 1 : 0)

            // 4 个 tab HStack(整层 .coordinateSpace("pillBar"))
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    tabColumn(idx: idx, item: item, selected: selected)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: barHeight)
            .padding(.horizontal, 6)
            .coordinateSpace(name: "pillBar")
        }
        .frame(maxWidth: .infinity)
        .frame(height: barHeight)
    }

    private func animateThumbToSelected() {
        let idx = selectedIndex
        guard let center = pillCentersBar[idx] else { return }
        withAnimation(.spring(response: 0.18, dampingFraction: 1.0)) {
            thumbCenterX = center
        }
        if !thumbPlaced {
            thumbCenterX = center
            thumbPlaced = true
        }
    }

    @ViewBuilder
    private func tabColumn(idx: Int, item: PillNavItemData, selected: Int) -> some View {
        let isSel = idx == selected
        let pillCenter = pillCentersBar[idx] ?? 0
        let labelLeft = labelLeftsBar[idx] ?? 0
        let pillHalf = thumbWidth / 2
        let iconHalf: CGFloat = 10
        let thumbStart = thumbCenterX - pillHalf
        let thumbEnd = thumbCenterX + pillHalf
        let iconCov = intervalCoverage(
            thumbStart: thumbStart, thumbEnd: thumbEnd,
            bStart: pillCenter - iconHalf, bEnd: pillCenter + iconHalf)
        let rects = charRectsCache[idx]
        let labelCov = rects.map {
            sweepCoverage(rects: $0,
                          thumbStart: thumbStart,
                          thumbEnd: thumbEnd,
                          labelLeftEdge: labelLeft)
        } ?? (isSel ? 1.0 : 0.0)
        let t = max(0, min(1, labelCov))
        let labelColor = lerpColor(
            from: colors.onSurfaceVariant,
            to: colors.onSurface,
            fraction: Double(t))

        VStack(spacing: 4) {
            // 图标胶囊(测 pill center;写入 PillGeomKey)
            Color.clear
                .frame(width: thumbWidth, height: thumbHeight)
                .background(
                    GeometryReader { g in
                        let frame = g.frame(in: .named("pillBar"))
                        Color.clear.preference(
                            key: PillGeomKey.self,
                            value: PillGeomValue(
                                centers: [idx: frame.midX],
                                labelLefts: [:]))
                    }
                )
                .overlay(
                    Image(systemName: item.icon)
                        .font(.system(size: 20))
                        .foregroundColor(lerpColor(
                            from: colors.onSurfaceVariant,
                            to: colors.onSurface,
                            fraction: Double(iconCov)))
                )
            // label(测字符矩形 + 左缘)
            Text(item.label)
                .font(.system(size: 10, weight: isSel ? .semibold : .medium))
                .foregroundColor(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
                .background(
                    GeometryReader { g in
                        let frame = g.frame(in: .named("pillBar"))
                        Color.clear
                            .preference(
                                key: PillGeomKey.self,
                                value: PillGeomValue(
                                    centers: [:],
                                    labelLefts: [idx: frame.minX]))
                            .onAppear {
                                let rects = characterRects(text: item.label, in: g.size)
                                charRectsCache[idx] = rects
                            }
                            .onChange(of: item.label) { _ in
                                let rects = characterRects(text: item.label, in: g.size)
                                charRectsCache[idx] = rects
                            }
                    }
                )
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            // 不改内 state:让外部 onClick 改 items[*].selected → 上层重渲染
            item.onClick()
        }
        .accessibilityIdentifier("pill_\(item.id)")
        .accessibilityLabel(item.label)
    }
}

// PreferenceKey:收集每个 tab 的 pill center + label left(bar 局部坐标)
private struct PillGeomValue: Equatable {
    var centers: [Int: CGFloat]
    var labelLefts: [Int: CGFloat]
}

private struct PillGeomKey: PreferenceKey {
    static var defaultValue: PillGeomValue = .init(centers: [:], labelLefts: [:])
    static func reduce(value: inout PillGeomValue, nextValue: () -> PillGeomValue) {
        let v = nextValue()
        for (k, val) in v.centers { value.centers[k] = val }
        for (k, val) in v.labelLefts { value.labelLefts[k] = val }
    }
}

/// tab 数据(← Android PillNavItemSpec {icon, label} — v1 兼容垫片)
struct PillNavItemData: Identifiable {
    let id: String
    let icon: String
    let label: String
    let selected: Bool
    let onClick: () -> Void
}

// ── 几何辅助函数 ──

private func intervalCoverage(thumbStart: CGFloat, thumbEnd: CGFloat,
                               bStart: CGFloat, bEnd: CGFloat) -> CGFloat {
    let w = bEnd - bStart
    if w <= 0 { return 0 }
    let overlap = min(thumbEnd, bEnd) - max(thumbStart, bStart)
    return max(0, min(overlap, w)) / w
}

private func sweepCoverage(rects: [CGRect], thumbStart: CGFloat, thumbEnd: CGFloat,
                           labelLeftEdge: CGFloat) -> CGFloat {
    if rects.isEmpty { return 0 }
    var sum: CGFloat = 0
    var total: CGFloat = 0
    for r in rects {
        let w = r.width
        if w <= 0 { continue }
        let l = r.minX + labelLeftEdge
        let e = r.maxX + labelLeftEdge
        let overlap = max(0, min(thumbEnd, e) - max(thumbStart, l))
        sum += min(overlap, w)
        total += w
    }
    if total <= 0 { return 0 }
    return min(1, max(0, sum / total))
}

private func characterRects(text: String, in size: CGSize) -> [CGRect] {
    guard !text.isEmpty, size.width > 0 else { return [] }
    let font = UIFont.systemFont(ofSize: 10, weight: .semibold)
    let attr = NSAttributedString(string: text, attributes: [.font: font])
    let framesetter = CTFramesetterCreateWithAttributedString(attr)
    let path = CGPath(rect: CGRect(origin: .zero,
                                  size: CGSize(width: max(size.width, 1), height: max(size.height, 1))),
                      transform: nil)
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attr.length), path, nil)
    guard let lines = CTFrameGetLines(frame) as? [CTLine], let line = lines.first else { return [] }
    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
    let xOffset = (size.width - lineWidth) / 2
    var rects: [CGRect] = []
    let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
    var xCursor: CGFloat = 0
    for run in runs {
        let glyphCount = CTRunGetGlyphCount(run)
        var advances = [CGSize](repeating: .zero, count: glyphCount)
        CTRunGetAdvances(run, CFRange(location: 0, length: glyphCount), &advances)
        for g in 0..<glyphCount {
            let w = advances[g].width
            if w > 0 {
                rects.append(CGRect(x: xOffset + xCursor, y: 0, width: w, height: size.height))
            }
            xCursor += w
        }
    }
    return rects
}

private func lerpColor(from: Color, to: Color, fraction: Double) -> Color {
    let a = UIColor(from).cgColor
    let b = UIColor(to).cgColor
    let aComps = a.components ?? [0, 0, 0, 1]
    let bComps = b.components ?? [0, 0, 0, 1]
    let aN = max(a.numberOfComponents, 1)
    let bN = max(b.numberOfComponents, 1)
    let ar = aN >= 3 ? aComps[0] : 0
    let ag = aN >= 3 ? aComps[1] : 0
    let ab = aN >= 3 ? aComps[2] : 0
    let aa = aN >= 4 ? aComps[3] : 1
    let br = bN >= 3 ? bComps[0] : 0
    let bg = bN >= 3 ? bComps[1] : 0
    let bb = bN >= 3 ? bComps[2] : 0
    let ba = bN >= 4 ? bComps[3] : 1
    let mixR = ar + (br - ar) * CGFloat(fraction)
    let mixG = ag + (bg - ag) * CGFloat(fraction)
    let mixB = ab + (bb - ab) * CGFloat(fraction)
    let mixA = aa + (ba - aa) * CGFloat(fraction)
    return Color(red: Double(mixR), green: Double(mixG), blue: Double(mixB), opacity: Double(mixA))
}