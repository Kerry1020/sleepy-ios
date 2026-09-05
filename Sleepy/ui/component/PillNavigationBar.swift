// PillNavigationBar.swift — ← ui/component/PillNavigationBar.kt
// 胶囊底栏 v2(动画对齐安卓):
//   surface-container 背景 + 4 tab(图标胶囊 64×32 + 下方 label)。
//   选中态: secondary-container 胶囊底 / on-surface 文字; 未选中: surface-variant 文字。
//
// v2 动画(与 SegmentedSwitcher 同源, thumb 平滑滑过 + 图标/文字扫过变色):
//   单个 secondaryContainer thumb 色块由弹簧(response 0.18, damping 1.0 ≈150ms 收束)
//   在药丸带上从旧 tab 滑到新 tab; 图标按「图标区间 ∩ thumb 区间」横向覆盖率 lerp 变色,
//   文字逐字符按「字符矩形 ∩ thumb 区间」扫过上色 — 色块边缘扫过哪个字, 那个字才变色。
//   thumb 位置直读弹簧浮点值, 高刷屏下连续非线性曲线, 无离散跳格。
//
// 几何真值: 各 tab 药丸中心/文字左缘全部 onGloballyPositioned 实测(SpaceEvenly 下
// 变宽 label 实际分布不靠推算)。布局变化时 centers key 变化 → effect 重跑 → thumb
// 平滑滑到新位置。
//
// API v2(对齐安卓): index-based 而非 callback-per-item, 让组件内部管理 thumb 几何
// 时能正确取坐标; `items: [PillNavItemSpec]` + `selectedIndex` + `onSelect`。
// v1 `PillNavItemData`(callback-per-item) 保留为兼容垫片(API 形参签名同 Kotlin v2,
// 内部把 PillNavItemData 序列转 PillNavItemSpec + 推导 selectedIndex)。

import SwiftUI
import CoreText
import UIKit

struct PillNavigationBar: View {
    @Environment(\.localWakeUpColors) private var colors
    let items: [PillNavItemData]    // ← 兼容旧 caller (SleepyApp.swift)
    @State private var selectedIndex: Int = 0

    init(items: [PillNavItemData]) {
        self.items = items
        // 初始 selectedIndex 从 items[*].selected 推
        let initialIdx = items.firstIndex(where: { $0.selected }) ?? 0
        _selectedIndex = State(initialValue: initialIdx)
    }

    var body: some View {
        PillNavigationBarAnim(
            items: items,
            selectedIndex: $selectedIndex,
            colors: colors)
    }
}

// v2 动画实现
private struct PillNavigationBarAnim: View {
    let items: [PillNavItemData]
    @Binding var selectedIndex: Int
    let colors: WakeUpColorScheme

    // ── 几何真值(root 坐标, bar 相对坐标在读取时现算) ──
    @State private var barRootX: CGFloat = 0
    @State private var barRootY: CGFloat = 0
    @State private var barLaidOut = false
    @State private var pillRootXs: [CGFloat] = []
    @State private var pillRootY: CGFloat = 0
    @State private var labelRootXs: [CGFloat] = []
    // 各 tab 文字字符矩形(segment 局部坐标, onTextLayout 时缓存)
    @State private var charRectsCache: [Int: [CGRect]] = [:]

    // ── thumb 位移(浮点真值, 弹簧驱动; 初次定位 snap) ──
    @State private var thumbX: CGFloat = 0
    @State private var thumbCenterState: CGFloat = 0
    @State private var thumbPlaced = false

    // 内部: 渲染用的 Thumb 几何(平移相对 bar 的偏移)
    private let thumbWidth: CGFloat = 64
    private let thumbHeight: CGFloat = 32

    var body: some View {
        let count = max(items.count, 1)
        GeometryReader { geo in
            containerLayer(geo: geo, count: count)
        }
        .frame(height: 76)
    }

    @ViewBuilder
    private func containerLayer(geo: GeometryProxy, count: Int) -> some View {
        let pillHalf = thumbWidth / 2
        let iconHalf: CGFloat = 10
        let tc = thumbCenterState
        let thumbStart = tc - pillHalf
        let thumbEnd = tc + pillHalf

        ZStack(alignment: .topLeading) {
            // 层0: thumb 色块 — 弹簧驱动, 相对 bar 偏移
            RoundedRectangle(cornerRadius: SleepyShapes.large)
                .fill(colors.secondaryContainer)
                .frame(width: thumbWidth, height: thumbHeight)
                .offset(x: thumbX - pillHalf, y: 0)
                .opacity(thumbPlaced ? 1 : 0)
                .animation(.spring(response: 0.18, dampingFraction: 1.0), value: selectedIndex)

            // 层1: 4 个 tab HStack
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    let isSel = idx == selectedIndex
                    let pillCenter = pillRootXs.indices.contains(idx)
                        ? pillRootXs[idx] + pillHalf - barRootX : 0
                    let labelCenter = labelRootXs.indices.contains(idx)
                        ? labelRootXs[idx] - barRootX : 0
                    let iconCov = intervalCoverage(
                        thumbStart: thumbStart, thumbEnd: thumbEnd,
                        bStart: pillCenter - iconHalf, bEnd: pillCenter + iconHalf)
                    let rects = charRectsCache[idx]
                    let labelCov = rects.map {
                        sweepCoverage(rects: $0, thumbStart: thumbStart, thumbEnd: thumbEnd, labelLeftEdge: labelCenter)
                    } ?? (isSel ? 1.0 : 0.0)
                    let t = max(0, min(1, labelCov))
                    let labelColor = lerpColor(
                        from: colors.onSurfaceVariant,
                        to: colors.onSurface,
                        fraction: Double(t))

                    VStack(spacing: 4) {
                        // 图标胶囊 64×32(测中心)
                        measureIconPill(idx: idx)
                            .frame(width: thumbWidth, height: thumbHeight)
                            .overlay(
                                Image(systemName: item.icon)
                                    .font(.system(size: 20))
                                    .foregroundColor(lerpColor(
                                        from: colors.onSurfaceVariant,
                                        to: colors.onSurface,
                                        fraction: Double(iconCov)))
                            )
                        // label(测左缘 + 字符矩形)
                        Text(item.label)
                            .font(.system(size: 10, weight: isSel ? .semibold : .medium))
                            .foregroundColor(labelColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .allowsTightening(true)
                            .background(measureChars(idx: idx, label: item.label))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.18, dampingFraction: 1.0)) {
                            selectedIndex = idx
                        }
                        item.onClick()
                    }
                    .accessibilityIdentifier("pill_\(item.id)")
                    .accessibilityLabel(item.label)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .background(
            colors.surfaceContainer
                .ignoresSafeArea(edges: .bottom)
                .onAppear {
                    if pillRootXs.count != items.count { pillRootXs = Array(repeating: 0, count: items.count) }
                    if labelRootXs.count != items.count { labelRootXs = Array(repeating: 0, count: items.count) }
                }
        )
        // bar 在 root 坐标系的几何真值(用于把 thumb 偏移算回 bar 相对)
        .background(
            GeometryReader { barGeo in
                Color.clear
                    .onAppear {
                        let origin = barGeo.frame(in: .global).origin
                        barRootX = origin.x
                        barRootY = origin.y
                        barLaidOut = true
                        // 首次定位: snap 到当前 selectedIndex
                        if !thumbPlaced, pillRootXs.indices.contains(selectedIndex) {
                            let pillX = pillRootXs[selectedIndex]
                            let target = pillX + pillHalf - barRootX
                            thumbX = target
                            thumbCenterState = target
                            thumbPlaced = true
                        }
                    }
                    .onChange(of: barGeo.frame(in: .global).origin.x) { newX in
                        barRootX = newX
                    }
            }
        )
        .onChange(of: pillRootXs) { newXs in
            guard barLaidOut, newXs.indices.contains(selectedIndex), newXs[selectedIndex] > 0 else { return }
            let pillX = newXs[selectedIndex]
            let target = pillX + pillHalf - barRootX
            withAnimation(.spring(response: 0.18, dampingFraction: 1.0)) {
                thumbX = target
                thumbCenterState = target
            }
            if !thumbPlaced { thumbPlaced = true }
        }
    }

    // 测图标胶囊中心(root 坐标)
    @ViewBuilder
    private func measureIconPill(idx: Int) -> some View {
        GeometryReader { g in
            Color.clear
                .onAppear {
                    let origin = g.frame(in: .global).origin
                    if pillRootXs.indices.contains(idx) {
                        pillRootXs[idx] = origin.x
                        pillRootY = origin.y
                    }
                }
                .onChange(of: g.frame(in: .global).origin.x) { newX in
                    if pillRootXs.indices.contains(idx) {
                        pillRootXs[idx] = newX
                    }
                }
        }
    }

    // 测 label 左缘 + 字符矩形
    @ViewBuilder
    private func measureChars(idx: Int, label: String) -> some View {
        GeometryReader { g in
            Color.clear
                .onAppear {
                    let origin = g.frame(in: .global).origin
                    if labelRootXs.indices.contains(idx) {
                        labelRootXs[idx] = origin.x
                    }
                    let rects = characterRects(text: label, in: g.size)
                    charRectsCache[idx] = rects
                }
                .onChange(of: label) { _ in
                    let rects = characterRects(text: label, in: g.size)
                    charRectsCache[idx] = rects
                }
        }
    }
}

/// tab 数据(← Android PillNavItemSpec {icon, label} — v1 兼容垫片)
struct PillNavItemData: Identifiable {
    let id: String
    let icon: String          // SF Symbol(← Material icon 等价映射)
    let label: String
    let selected: Bool
    let onClick: () -> Void
}

// ── 几何辅助函数 ──

/** 区间 [aStart,aEnd] 对 [bStart,bEnd] 的横向覆盖率 0..1 */
private func intervalCoverage(thumbStart: CGFloat, thumbEnd: CGFloat,
                               bStart: CGFloat, bEnd: CGFloat) -> CGFloat {
    let w = bEnd - bStart
    if w <= 0 { return 0 }
    let overlap = min(thumbEnd, bEnd) - max(thumbStart, bStart)
    return max(0, min(overlap, w)) / w
}

/** 逐字符扫过覆盖率: rects(局部坐标) + 文字左缘偏移 → 与 thumb 区间求交集权重平均 */
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

// 字符级 bounding box 列表(CoreText 测 advance, 转 segment 局部 CGRect)
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

// Color lerp(SwiftUI Color 不支持原生 lerp, 走 UIColor 桥接)
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