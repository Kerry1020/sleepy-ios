import Foundation

/**
 * v7.10.16t 保存时冲突明细报告(issue#10 轮换落地后的配套, 用户 2026-09-04):
 * 加课保存不再拦截冲突(v7.10.16t 撤除三层闸), 但把撞车细节完整讲给用户 —
 * 和哪门存量课、星期几、第几节到第几节、哪几周。只报「新草稿参与的冲突」,
 * 存量课之间的互撞不报(那是既有状态, 与本次保存无关)。
 *
 * 纯 JVM/Swift 可测: 输入草稿 + 存量 + 星期名, 输出结构化明细;文案模板由调用方
 * (AddCourseScreen 里 L10n.format)传入, 本文件不碰 iOS 资源。
 *
 * Android ConflictDetailReporter.kt 1:1 移植。
 */

/// 一条冲突明细。nodeRangeText/weekText 已是可直接嵌句子的短文本
public struct ConflictDetail {
    public let existingName: String
    public let draftName: String
    public let day: Int
    public let dayText: String
    public let nodeRangeText: String
    public let weekText: String
}

/// WeekType: 0=每周 1=单周 2=双周 3=按周次列实际指定的周
public enum CourseWeekType: Int {
    case everyWeek = 0
    case oddWeek = 1
    case evenWeek = 2
    case custom = 3
}

public enum ConflictDetailReporter {

    /**
     * 找出草稿与存量课的全部冲突(同 day + 节次区间相交 + 公共上课周)。
     * 每对(草稿, 存量)至多一条明细;多条草稿多条存量的组合逐对展开, 按存量课
     * 节次起点升序(表单从上往下读的顺序)。
     */
    public static func draftConflictDetails(
        drafts: [CourseEntityLite],
        stored: [CourseEntityLite],
        dayNames: [String]
    ) -> [ConflictDetail] {
        guard !drafts.isEmpty, !stored.isEmpty else { return [] }
        let byDay = Dictionary(grouping: stored, by: { $0.day })
        var out: [ConflictDetail] = []
        for draft in drafts {
            guard let candidates = byDay[draft.day] else { continue }
            // (existing course, (node range, parity?))
            var hits: [(CourseEntityLite, (ClosedRange<Int>, Int?))] = []
            for s in candidates {
                guard let commonWeeks = commonWeeks(draft, s) else { continue }
                if nodesOverlap(draft, s) {
                    hits.append((s, commonWeeks))
                }
            }
            hits.sort { $0.0.startNode < $1.0.startNode }
            for (s, weeks) in hits {
                let dayText = dayIndices(draft.day, names: dayNames)
                out.append(ConflictDetail(
                    existingName: s.courseName,
                    draftName: draft.courseName,
                    day: draft.day,
                    dayText: dayText,
                    nodeRangeText: nodeRangeText(draft, s),
                    weekText: weekText(weeks)
                ))
            }
        }
        return out
    }

    /// 模板拼行(模板含 4 占位: 星期/节次交集文案/周文案/存量课名)
    public static func formatDetail(_ d: ConflictDetail, template: String) -> String {
        return String(format: template, d.dayText, d.nodeRangeText, d.weekText, d.existingName)
    }

    // MARK: - 内部: 区间与周次判定

    private static func nodesOverlap(_ a: CourseEntityLite, _ b: CourseEntityLite) -> Bool {
        let aEnd = a.startNode + a.step - 1
        let bEnd = b.startNode + b.step - 1
        return a.startNode <= bEnd && b.startNode <= aEnd
    }

    /// 节次交集(闭区间), 无交集返回 nil
    private static func nodeIntersection(_ a: CourseEntityLite, _ b: CourseEntityLite) -> ClosedRange<Int>? {
        let lo = max(a.startNode, b.startNode)
        let hi = min(a.startNode + a.step - 1, b.startNode + b.step - 1)
        return lo <= hi ? lo...hi : nil
    }

    /// 公共上课周: 返回(实际命中闭区间, 奇偶限定) 二元组;无公共周返回 nil
    private static func commonWeeks(_ a: CourseEntityLite, _ b: CourseEntityLite) -> (ClosedRange<Int>, Int?)? {
        let lo = max(a.startWeek, b.startWeek)
        let hi = min(a.endWeek, b.endWeek)
        guard lo <= hi else { return nil }
        let parity: Int? = {
            if a.type == 1 || b.type == 1 { return 1 }
            if a.type == 2 || b.type == 2 { return 2 }
            return nil
        }()
        func hits(_ week: Int, _ type: Int) -> Bool {
            switch type {
            case 1: return week % 2 == 1
            case 2: return week % 2 == 0
            default: return true
            }
        }
        var first = -1
        var last = -1
        for week in lo...hi {
            if hits(week, a.type) && hits(week, b.type) {
                if first < 0 { first = week }
                last = week
            }
        }
        guard first >= 0 else { return nil }
        return (first...last, parity)
    }

    private static func nodeRangeText(_ draft: CourseEntityLite, _ s: CourseEntityLite) -> String {
        guard let r = nodeIntersection(draft, s) else { return "" }
        return r.lowerBound == r.upperBound ? "\(r.lowerBound)" : "\(r.lowerBound)-\(r.upperBound)"
    }

    /**
     * 周文案(用户要求「哪几周」讲清):
     *   「第1-16周」/「第5-8周」/「单周 第1-15周」/「双周 第2-14周」/单周点「第5周」。
     * 留 formatGap 钩子供 i18n; 当前实现保留 Kotlin 模板: 单周/双周 前缀 + 第X-Y周
     */
    private static func weekText(_ weeks: (ClosedRange<Int>, Int?)) -> String {
        let (r, parity) = weeks
        let range = r.lowerBound == r.upperBound ? "\(r.lowerBound)" : "\(r.lowerBound)-\(r.upperBound)"
        let prefix: String
        switch parity {
        case 1: prefix = "单周 "
        case 2: prefix = "双周 "
        default: prefix = ""
        }
        return "\(prefix)第\(range)周"
    }

    /// iOS 0-indexed -> 1-indexed day lookup
    private static func dayIndices(_ day: Int, names: [String]) -> String {
        let idx = day - 1
        return idx >= 0 && idx < names.count ? names[idx] : ""
    }
}

/// 极简 Course 实体: 仅冲突检测需要的字段, 避免与 Room/GRDB 实体耦合
public struct CourseEntityLite {
    public let courseName: String
    public let day: Int           // 1..7
    public let startNode: Int     // 第几节开始
    public let step: Int          // 连节数
    public let startWeek: Int
    public let endWeek: Int
    public let type: Int          // CourseWeekType.rawValue

    public init(courseName: String, day: Int, startNode: Int, step: Int,
                startWeek: Int, endWeek: Int, type: Int) {
        self.courseName = courseName
        self.day = day
        self.startNode = startNode
        self.step = step
        self.startWeek = startWeek
        self.endWeek = endWeek
        self.type = type
    }
}
