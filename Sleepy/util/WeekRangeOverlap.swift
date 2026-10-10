// WeekRangeOverlap.swift — ← util/WeekRangeOverlap.kt 逐行翻译 (GPL-3.0)

import Foundation

/// 判断两个周次区间（含单双周类型）是否有公共上课周。
/// type: 0=每周 1=单周 2=双周 3=按周次列实际指定的周; 奇偶按绝对周号判定, 与 CourseEntity.inWeek 一致。
func weekRangesOverlap(
    _ aStart: Int, _ aEnd: Int, _ aType: Int,
    _ bStart: Int, _ bEnd: Int, _ bType: Int
) -> Bool {
    let lo = max(aStart, bStart)
    let hi = min(aEnd, bEnd)
    if lo > hi { return false }
    func hits(_ week: Int, _ type: Int) -> Bool {
        switch type {
        case 1: return week % 2 == 1
        case 2: return week % 2 == 0
        default: return true  // 0/3 及其他: 只要在该周区间内就算命中
        }
    }
    // 任一公共周同时命中两类课即相交
    for week in lo...hi {
        if hits(week, aType) && hits(week, bType) { return true }
    }
    return false
}
