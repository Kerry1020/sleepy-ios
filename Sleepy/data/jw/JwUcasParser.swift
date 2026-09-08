// JwUcasParser.swift — ← JwUcasParser.kt 1:1 translation (GPL-3.0) — 1.0.52 alignment
// UCAS (中国科学院大学) personal schedule parser — JSON (authoritative) + HTML (fallback).

import Foundation
import SwiftSoup

final class JwUcasParser: JwParser {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    /// HTML path provisional weeks (详情页尚未捕获, 1-16 周占位)
    static let PROVISIONAL_START_WEEK = 1
    static let PROVISIONAL_END_WEEK = 16

    /// ldiex/UCAS_Course_Schedule_Convertor 实测 dayBits -> 星期 1..7 (POSITIVE 证据, hardcode 不发明新编码)
    static let DAY_BITS: [String: Int] = [
        "10": 1, "11": 1, "100": 2, "110": 3,
        "1000": 4, "1010": 5, "1100": 6, "1110": 7,
    ]

    /// 课程周次类型: 0=每周, 1=单周, 2=双周
    static let TYPE_DEFAULT = 0
    static let TYPE_ODD = 1
    static let TYPE_EVEN = 2

    func generateCourseList() -> [JwCourse] {
        return parseJson() ?? parseHtml()
    }

    /// ← confidence(): JSON 命中 95 / HTML 命中 90 (iOS 检测层不消费, 保留供对齐)
    func confidence() -> Int {
        if source.contains("\"courseTimeList\"") && source.contains("\"selectedCourse\"") { return 95 }
        if source.contains("个人课表") && source.contains("/course/coursetime/") { return 90 }
        return 0
    }

    func matchedFeatures() -> [String] {
        var f: [String] = []
        if source.contains("\"courseTimeList\"") { f.append("json:courseTimeList") }
        if source.contains("\"selectedCourse\"") { f.append("json:selectedCourse") }
        if source.contains("个人课表") { f.append("title:个人课表") }
        if source.contains("/course/coursetime/") { f.append("href:/course/coursetime/") }
        return f
    }

    /// JSON path: pick courseTimeList array, decode each schedule.
    /// nil return = no parsable JSON, caller falls back to HTML path.
    private func parseJson() -> [JwCourse]? {
        guard let courseTimeList = JwUcasParser.extractCourseTimeList(source) else { return nil }
        var result: [JwCourse] = []
        for item in courseTimeList {
            guard let item = item as? [String: Any] else { continue }
            let name = trim(item["courseName"])
            let place = trim(item["coursePlace"])
            guard let weekInt = optInt(item, "courseWeek"), let timeInt = optInt(item, "courseTime") else { continue }
            if name.isEmpty { continue }

            let weeks = JwUcasParser.decodeWeeks(weekInt)
            if weeks.isEmpty { continue }
            guard let (day, startNode, endNode) = JwUcasParser.decodeTime(timeInt) else { continue }
            let type = JwUcasParser.weeksToType(weeks)
            result.append(JwCourse(name: name, room: place, day: day,
                                   startNode: startNode, endNode: endNode,
                                   startWeek: weeks.first!, endWeek: weeks.last!, type: type))
        }
        return result
    }

    /// 兼容两种 JSON 形态: A. 顶层 courseTimeList (拼合文档) B. 嵌套 data 字段 / 顶层数组
    static func extractCourseTimeList(_ raw: String) -> [Any]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        // 跳过前导 HTML 注释/空白, 找首个 '{' 或 '[' 真正 JSON 起点(优先 '{', 避开注释里 [2:] 误命中)
        let objStart = trimmed.firstIndex(of: "{")
        let arrStart = trimmed.firstIndex(of: "[")
        let jsonStart: String.Index
        if let o = objStart, let a = arrStart { jsonStart = min(o, a) }
        else if let o = objStart { jsonStart = o }
        else if let a = arrStart { jsonStart = a }
        else { return nil }
        let jsonBody = String(trimmed[jsonStart...])
        guard let obj = try? JSONSerialization.jsonObject(with: Data(jsonBody.utf8)) else { return nil }
        if let dict = obj as? [String: Any] {
            return (dict["courseTimeList"] as? [Any])
                ?? ((dict["data"] as? [String: Any])?["courseTimeList"] as? [Any])
        }
        if let arr = obj as? [Any] { return arr }
        return nil
    }

    /// courseWeek 整数位图 -> 周次列表 (低位=第1周)。21 (0b10101) -> [1,3,5]
    static func decodeWeeks(_ weekInt: Int) -> [Int] {
        if weekInt <= 0 { return [] }
        var weeks: [Int] = []
        var bit = 0
        var n = weekInt
        while n > 0 {
            if n & 1 == 1 { weeks.append(bit + 1) }
            bit += 1
            n >>= 1
        }
        return weeks
    }

    /// courseTime 整数 -> (day, startNode, endNode)。dayBits 不在 DAY_BITS 内 = 数据异常, 返回 nil。
    static func decodeTime(_ timeInt: Int) -> (Int, Int, Int)? {
        if timeInt <= 0 { return nil }
        let binary = String(timeInt, radix: 2)
        if binary.count <= 12 { return nil }
        let dayBits = String(binary.prefix(binary.count - 12))
        guard let day = JwUcasParser.DAY_BITS[dayBits] else { return nil }
        let nodeBits = String(String(binary.suffix(12)).reversed())
        var nodes: [Int] = []
        for (idx, c) in nodeBits.enumerated() where c == "1" { nodes.append(idx + 1) }
        if nodes.isEmpty { return nil }
        return (day, nodes.first!, nodes.last!)
    }

    /// weeks 列表归类 type: 全单周=1, 全双周=2, 混合=0
    static func weeksToType(_ weeks: [Int]) -> Int {
        if weeks.allSatisfy({ $0 % 2 == 1 }) { return TYPE_ODD }
        if weeks.allSatisfy({ $0 % 2 == 0 }) { return TYPE_EVEN }
        return TYPE_DEFAULT
    }

    /// HTML path fallback: server-rendered schedule grid.
    private func parseHtml() -> [JwCourse] {
        guard let doc = try? SwiftSoup.parse(source) else { return [] }
        guard let table = findScheduleTable(doc) else { return [] }
        return mergeAdjacentRows(collectCourses(table))
    }

    private func findScheduleTable(_ doc: Document) -> Element? {
        let tables = ((try? doc.getElementsByTag("table")) ?? nil)?.array() ?? []
        for t in tables {
            guard tableHasHeader(t) else { continue }
            let links = (try? t.select("a[href*=/course/coursetime/]")) ?? nil
            if (links?.array().count ?? 0) > 0 { return t }
        }
        return nil
    }

    private func tableHasHeader(_ t: Element) -> Bool {
        guard let thead = (try? t.getElementsByTag("thead").first()) ?? nil else { return false }
        let ths = ((try? thead.getElementsByTag("th")) ?? nil)?.array() ?? []
        return ths.contains { ((try? $0.text()) ?? "").contains("节次/星期") }
    }

    private func collectCourses(_ table: Element) -> [JwCourse] {
        var result: [JwCourse] = []
        let rows = ((try? table.getElementsByTag("tr")) ?? nil)?.array() ?? []
        for row in rows {
            guard let th = (try? row.getElementsByTag("th").first()) ?? nil else { continue }
            let nodeText = ((try? th.text()) ?? "").trimmingCharacters(in: .whitespaces)
            guard let node = Int(nodeText) else { continue }
            let tds = ((try? row.getElementsByTag("td")) ?? nil)?.array() ?? []
            for (index, cell) in tds.enumerated() {
                let day = index + 1
                let links = ((try? cell.getElementsByTag("a")) ?? nil)?.array() ?? []
                var seen = Set<String>()
                for link in links where ((try? link.attr("href")) ?? "").contains("/course/coursetime/") {
                    let name = ((try? link.text()) ?? "").trimmingCharacters(in: .whitespaces)
                    if name.isEmpty || seen.contains(name) { continue }
                    seen.insert(name)
                    result.append(JwCourse(name: name, day: day, startNode: node, endNode: node,
                                           startWeek: JwUcasParser.PROVISIONAL_START_WEEK,
                                           endWeek: JwUcasParser.PROVISIONAL_END_WEEK))
                    continue
                }
            }
        }
        return result
    }

    /// 相邻节次合并 (同名同天同周域: endNode+1 链式合并)
    private func mergeAdjacentRows(_ courses: [JwCourse]) -> [JwCourse] {
        var merged: [JwCourse] = []
        let groups = Dictionary(grouping: courses) { c in "\(c.name)|\(c.day)|\(c.startWeek)|\(c.endWeek)|\(c.type)" }
        for (_, group) in groups {
            let sorted = group.sorted { $0.startNode < $1.startNode }
            for course in sorted {
                if let prev = merged.last, prev.name == course.name, prev.day == course.day,
                   prev.startWeek == course.startWeek, prev.endWeek == course.endWeek, prev.type == course.type,
                   prev.endNode + 1 == course.startNode {
                    // JwCourse 字段全 let — 以扩展 endNode 重建
                    merged[merged.count - 1] = JwCourse(
                        name: prev.name, room: prev.room, teacher: prev.teacher,
                        day: prev.day, startNode: prev.startNode, endNode: course.endNode,
                        startWeek: prev.startWeek, endWeek: prev.endWeek, type: prev.type)
                } else {
                    merged.append(course)
                }
            }
        }
        return merged
    }

    private func trim(_ v: Any?) -> String {
        (v as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func optInt(_ d: [String: Any], _ k: String) -> Int? {
        guard let v = d[k], !(v is NSNull) else { return nil }
        return v as? Int ?? (v as? String).flatMap(Int.init)
    }
}
