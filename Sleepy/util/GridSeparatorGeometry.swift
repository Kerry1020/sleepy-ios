// GridSeparatorGeometry.swift — ← util/GridSeparatorGeometry.kt 逐行翻译 (GPL-3.0)
// Compose 课程表与 Canvas 周网格 widget 共用的纯几何。

import Foundation

enum GridSeparatorGeometry {
    struct Span: Equatable {
        let start: CGFloat
        let end: CGFloat
    }

    /// 返回 [start, end] 扣除给定纵向间隙后的剩余段。
    static func verticalSegments(start: CGFloat, end: CGFloat, excluded: [Span]) -> [Span] {
        guard start.isFinite, end.isFinite, end > start else { return [] }

        var result: [Span] = []
        var cursor = start
        for span in excluded.sorted(by: { $0.start < $1.start }) {
            guard span.start.isFinite, span.end.isFinite else { continue }
            let gapStart = min(max(span.start, start), end)
            let gapEnd = min(max(span.end, start), end)
            if gapEnd <= gapStart || gapEnd <= cursor { continue }
            if gapStart > cursor { result.append(Span(start: cursor, end: gapStart)) }
            cursor = max(cursor, gapEnd)
        }
        if cursor < end { result.append(Span(start: cursor, end: end)) }
        return result
    }
}
