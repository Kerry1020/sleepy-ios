// SegmentedSwitcher.swift — ← ui/component/SegmentedSwitcher.kt
// 单选分段按钮 — 主视图模式切换(整周/卡片)。
// v2 动画对齐 Android: 单个 secondaryContainer thumb 色块由弹簧响应
// (response 0.18, damping 1.0 — 高硬度+无阻尼, ≈150ms 收束) 在轨道上从旧段滑到新段;
// 每帧读 thumb 实时像素位置, 每个字符按「自身矩形 ∩ thumb 矩形」的横向覆盖率
// lerp 上色 — 色块边缘扫过哪个字, 那个字才跟着变色, 逐像素擦除感, 与 thumb 严格同帧。
//
// 容器: surface-container (M3), 圆角 14dp
// 选中: secondary-container 色块(12dp 圆角)
// 字符未就绪/字形无效 → 退化整词翻转(选中色/未选中色)。

import SwiftUI
import CoreText
import UIKit

struct SegmentedSwitcher<T: Hashable>: View {
    @Environment(\.localWakeUpColors) private var colors
    let options: [(T, String)]
    let selected: T
    let onSelect: (T) -> Void

    var body: some View {
        SegmentedSwitcherAnim(
            options: options,
            selected: selected,
            onSelect: onSelect,
            colors: colors)
    }
}

// 动画实现(单独抽出便于读: 几何真值全部 @State, 弹簧驱动 thumb)
private struct SegmentedSwitcherAnim<T: Hashable>: View {
    let options: [(T, String)]
    let selected: T
    let onSelect: (T) -> Void
    let colors: WakeUpColorScheme

    // ── 几何真值(外框宽; thumb 用轨道可用宽/段数推算位置) ──
    @State private var trackWidth: CGFloat = 0
    // thumb 弹簧浮点(段索引 0..count-1)
    @State private var thumbSegment: Int = 0
    @State private var thumbValue: CGFloat = 0
    @State private var didPlaceThumb = false
    // 各段文字字符矩形(segment 局部坐标, onTextLayout 时缓存)
    @State private var charRects: [Int: [CGRect]] = [:]

    private var count: Int { max(options.count, 1) }
    private var selectedIndex: Int {
        max(options.firstIndex(where: { $0.0 == selected }) ?? 0, 0)
    }

    var body: some View {
        GeometryReader { geo in
            containerLayer(containerWidth: geo.size.width)
        }
        .frame(height: 42)
    }

    @ViewBuilder
    private func containerLayer(containerWidth: CGFloat) -> some View {
        let trackW = max(containerWidth - 8, 0)
        let segW = count > 0 ? trackW / CGFloat(count) : 0
        let thumbStart = CGFloat(thumbSegment) * segW
        let thumbEnd = thumbStart + segW

        ZStack(alignment: .topLeading) {
            // 层0: thumb 色块 — 弹簧浮点驱动, 亚像素平滑
            RoundedRectangle(cornerRadius: 12)
                .fill(colors.secondaryContainer)
                .frame(width: segW, height: 32)
                .offset(x: 4 + thumbValue * segW, y: 4)
                .opacity(didPlaceThumb ? 1 : 0)
                .animation(.spring(response: 0.18, dampingFraction: 1.0), value: thumbSegment)

            // 层1: 透明点击段(整段尺寸, 命中区)
            clickLayer()

            // 层2: 文字层 — 每个字符按覆盖率 lerp 上色
            textLayer(thumbStart: thumbStart, thumbEnd: thumbEnd, segW: segW)
        }
        .padding(4)
        .frame(width: containerWidth, height: 42)
        .background(colors.surfaceContainer)
        .cornerRadius(14)
        .onAppear {
            trackWidth = trackW
            if !didPlaceThumb {
                thumbValue = CGFloat(selectedIndex)
                thumbSegment = selectedIndex
                didPlaceThumb = true
            }
        }
        .onChange(of: containerWidth) { newW in
            trackWidth = max(newW - 8, 0)
        }
        .onChange(of: selectedIndex) { newIdx in
            // 弹簧驱动 thumb 滑到新段
            withAnimation(.spring(response: 0.18, dampingFraction: 1.0)) {
                thumbValue = CGFloat(newIdx)
                thumbSegment = newIdx
            }
        }
    }

    @ViewBuilder
    private func clickLayer() -> some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, pair in
                Button {
                    onSelect(pair.0)
                } label: {
                    Color.clear
                }
                .buttonStyle(SleepyButtonStyle())
                .accessibilityIdentifier("seg_\(pair.1)")
            }
        }
        .frame(height: 42)
    }

    @ViewBuilder
    private func textLayer(thumbStart: CGFloat, thumbEnd: CGFloat, segW: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { idx, pair in
                let (_, label) = pair
                let isSel = idx == selectedIndex
                let labelColor = segmentLabelColor(
                    index: idx,
                    charRects: charRects[idx],
                    thumbStartPx: thumbStart,
                    thumbEndPx: thumbEnd,
                    segmentWidthPx: segW,
                    selected: isSel,
                    selectedColor: colors.onSecondaryContainer,
                    unselectedColor: colors.onSurfaceVariant)
                Text(label)
                    .font(.system(size: 13, weight: isSel ? .semibold : .medium))
                    .foregroundColor(labelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(measureChars(idx: idx, label: label))
            }
        }
        .frame(height: 42)
    }

    // 字符测量: SwiftUI Text 在 .frame(maxWidth: .infinity) 下水平居中(SwiftUI 默认),
    // 我们用 NSAttributedString 测每个字符 advance, 转 segment 局部 CGRect。
    @ViewBuilder
    private func measureChars(idx: Int, label: String) -> some View {
        GeometryReader { textGeo in
            Color.clear
                .onAppear {
                    let rects = characterRects(text: label, in: textGeo.size)
                    charRects[idx] = rects
                }
                .onChange(of: label) { _ in
                    let rects = characterRects(text: label, in: textGeo.size)
                    charRects[idx] = rects
                }
        }
    }
}

// 字符级 bounding box 列表(用 CoreText 拿每字符 advance)
private func characterRects(text: String, in size: CGSize) -> [CGRect] {
    guard !text.isEmpty, size.width > 0 else { return [] }
    let font = UIFont.systemFont(ofSize: 13, weight: .semibold)
    let attr = NSAttributedString(string: text, attributes: [.font: font])
    let framesetter = CTFramesetterCreateWithAttributedString(attr)
    let path = CGPath(rect: CGRect(origin: .zero,
                                  size: CGSize(width: max(size.width, 1), height: max(size.height, 1))),
                      transform: nil)
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attr.length), path, nil)
    guard let lines = CTFrameGetLines(frame) as? [CTLine], let line = lines.first else { return [] }

    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
    // 文字水平居中(SwiftUI Text 在 maxWidth:.infinity 容器内由自身 content size 居中)
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
                let charRect = CGRect(x: xOffset + xCursor, y: 0, width: w, height: size.height)
                rects.append(charRect)
            }
            xCursor += w
        }
    }
    return rects
}

// 字符级覆盖率上色: thumb 像素区间 [thumbStart, thumbEnd] 与每个字符矩形求横向交集,
// 覆盖率 0..1 → lerp(未选中色, 选中色, coverage)。
private func segmentLabelColor(
    index: Int,
    charRects: [CGRect]?,
    thumbStartPx: CGFloat,
    thumbEndPx: CGFloat,
    segmentWidthPx: CGFloat,
    selected: Bool,
    selectedColor: Color,
    unselectedColor: Color) -> Color {
    if segmentWidthPx <= 0 { return selected ? selectedColor : unselectedColor }
    guard let rects = charRects, !rects.isEmpty else {
        return selected ? selectedColor : unselectedColor
    }
    let segStart = CGFloat(index) * segmentWidthPx
    var sum: CGFloat = 0
    var total: CGFloat = 0
    for r in rects {
        let w = r.width
        if w <= 0 { continue }
        let l = r.minX + segStart
        let e = r.maxX + segStart
        let overlap = max(min(thumbEndPx, e) - max(thumbStartPx, l), 0)
        sum += min(overlap, w)
        total += w
    }
    if total <= 0 { return selected ? selectedColor : unselectedColor }
    let coverage = Double(min(max(sum / total, 0), 1))
    return lerpColor(from: unselectedColor, to: selectedColor, fraction: coverage)
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