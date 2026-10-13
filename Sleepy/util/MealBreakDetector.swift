// MealBreakDetector.swift — ← util/MealBreakDetector.kt 逐行翻译 (GPL-3.0)

import Foundation

/// 从相邻配置的响铃槽位推断的保守视觉休息段。
enum MealBreakDetector {
    enum Zone: CaseIterable {
        case midday
        case evening
    }

    struct Break: Equatable {
        let afterRowIndex: Int
        let minutes: Int
        let zone: Zone
    }

    /// 把探测器索引(按 timeJson 数组顺序)映射进网格实际渲染的行序。
    /// 渲染行可能被排序或过滤, 行索引不得跨越该边界携带; 配置的 node 才是稳定身份。
    static func detectDisplayRowIndexes(
        timeJson: String,
        courses: [CourseEntity],
        displayedNodeEnds: [Int]
    ) -> Set<Int> {
        let configuredRows = TimeTableUtils.parseTimeSlotRows(timeJson)
        return Set(
            detect(timeJson: timeJson, courses: courses).compactMap { detected in
                guard detected.afterRowIndex < configuredRows.count else { return nil }
                let leftNode = configuredRows[detected.afterRowIndex].node
                guard let idx = displayedNodeEnds.lastIndex(where: { $0 == leftNode }) else { return nil }
                return idx
            }
        )
    }

    /// 返回其后网格应留更宽间隙的行索引(0 起)。
    static func detect(timeJson: String, courses: [CourseEntity]) -> [Break] {
        guard let data = timeJson.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        if array.count < 2 { return [] }
        // parseTimeSlotRows 会给畸形行填默认响铃时间。对本视觉启发式而言,
        // 数据缺失必须意味着"不推断", 绝不是猜一个饭休。
        for row in array {
            guard row["node"] != nil, row["start"] != nil, row["end"] != nil else { return [] }
            guard let s = row["start"] as? String, parse(s) != nil,
                  let e = row["end"] as? String, parse(e) != nil else { return [] }
        }
        let rows = TimeTableUtils.parseTimeSlotRows(timeJson)
        if rows.count != array.count ||
            rows.contains(where: { row in
                guard let start = parse(row.start), let end = parse(row.end) else { return true }
                return end <= start
            }) {
            return []
        }
        var candidates: [Break] = []
        for i in 0..<(rows.count - 1) {
            let left = rows[i]
            let right = rows[i + 1]
            if left.edgeClass != nil || right.edgeClass != nil || right.node != left.node + 1 { continue }
            guard let leftEnd = parse(left.end), let rightStart = parse(right.start) else { continue }
            let gapMinutes = Int(rightStart.timeIntervalSince(leftEnd) / 60)
            if gapMinutes <= 45 || gapMinutes > 240 || rightStart <= leftEnd { continue }
            let mid = leftEnd.addingTimeInterval(TimeInterval(gapMinutes / 2) * 60)
            let zone: Zone
            if inRange(mid, "10:30", "14:30") { zone = .midday }
            else if inRange(mid, "16:30", "20:30") { zone = .evening }
            else { continue }
            if courses.contains(where: { courseCrosses($0, leftNode: left.node, rightNode: right.node, gapStart: leftEnd, gapEnd: rightStart, timeJson: timeJson) }) { continue }
            candidates.append(Break(afterRowIndex: i, minutes: gapMinutes, zone: zone))
        }
        // 每个区带至多取一个(单例过滤), 按 afterRowIndex 升序
        return Zone.allCases.flatMap { zone in
            let matches = candidates.filter { $0.zone == zone }
            return matches.count == 1 ? [matches[0]] : []
        }.sorted { $0.afterRowIndex < $1.afterRowIndex }
    }

    private static func courseCrosses(
        _ course: CourseEntity,
        leftNode: Int,
        rightNode: Int,
        gapStart: Date,
        gapEnd: Date,
        timeJson: String
    ) -> Bool {
        if !course.isIrregularTime && course.startNode <= leftNode && course.startNode + course.step - 1 >= rightNode { return true }
        guard let interval = TimeTableUtils.effectiveCourseTime(
            isIrregularTime: course.isIrregularTime, startTime: course.startTime, endTime: course.endTime,
            startNode: course.startNode, step: course.step, timeJson: timeJson) else { return false }
        guard let start = parse(interval.0), let end = parse(interval.1) else { return false }
        return start < gapEnd && end > gapStart
    }

    /// "HH:mm" → 当日时间点(以 2001-01-01 为任意锚日, 只做当日比较); 非法 → nil。
    /// Kotlin LocalTime.parse 接受 "HH:mm(:ss)" 及带秒的 ISO; 这里同语义。
    private static func parse(_ value: String) -> Date? {
        let v = value.trimmingCharacters(in: .whitespaces)
        let comps = v.split(separator: ":")
        guard comps.count >= 2,
              let h = Int(comps[0]), let m = Int(comps[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        var cal = DateUtils.isoCalendar
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(hour: h, minute: m, second: comps.count > 2 ? Int(comps[2]) ?? 0 : 0))
    }

    /// 闭区间 [lo, hi] 判定(锚日同 parse, UTC)
    private static func inRange(_ t: Date, _ lo: String, _ hi: String) -> Bool {
        guard let l = parse(lo), let h = parse(hi) else { return false }
        return t >= l && t <= h
    }
}
