// JwNuitParser.swift — ← JwNuitParser.kt
//
// 南开大学 Wisedu 课表对象解析器。
//
// 协议: JwProtocol.TYPE_NUIT = "nuit"
//
// 数据来源: Wisedu JSON { "datas": [...] } 每行 classDateAndPlace 形如:
//   "1-3周,5,7 / 星期二 / 第3-4节 / 张老师[主讲] / 教室名"
//
// 关键语义: classDateAndPlace 中 Week 部分用「周」描述(不含「星期」),
//   单双周用 "(单)" / "(双)" 标记。

import Foundation

final class JwNuitParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    // MARK: - T8

    func generateCourseList() throws -> [JwCourse] {
        guard let data = source.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["datas"] as? [[String: Any]] else {
            return []
        }

        let dayMap = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7]
        let regex = try! NSRegularExpression(
            pattern: "(.+?)\\s*/\\s*星期([一二三四五六日])\\s*/\\s*第(\\d+)节-第(\\d+)节\\s*/\\s*(.+?)\\[主讲\\]\\s*/\\s*(.+)",
            options: []
        )
        var out: [JwCourse] = []
        for obj in rows {
            guard let name = (obj["courseName"] as? String)?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty,
                  let detailsRaw = obj["classDateAndPlace"] as? String,
                  !detailsRaw.isEmpty else { continue }

            let parts = detailsRaw.components(separatedBy: "，")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .flatMap { detail -> [JwCourse] in
                    let range = NSRange(detail.startIndex..., in: detail)
                    guard let m = regex.firstMatch(in: detail, options: [], range: range) else { return [] }
                    let ns = detail as NSString
                    let weekPart = ns.substring(with: m.range(at: 1))
                    guard let dayChar = ns.substring(with: m.range(at: 2)).first,
                          let day = dayMap[String(dayChar)] else { return [] }
                    let start = Int(ns.substring(with: m.range(at: 3))) ?? 0
                    let end = Int(ns.substring(with: m.range(at: 4))) ?? start
                    let teacher = ns.substring(with: m.range(at: 5)).trimmingCharacters(in: .whitespaces)
                    let room = ns.substring(with: m.range(at: 6)).trimmingCharacters(in: .whitespaces)

                    let weeks = parseWeeks(weekPart)
                    return weeks.map { week in
                        JwCourse(name: name, room: room, teacher: teacher,
                            day: day, startNode: start, endNode: end,
                            startWeek: week, endWeek: week)
                    }
                }
            out.append(contentsOf: parts)
        }
        return out
    }

    private func parseWeeks(_ text: String) -> [Int] {
        let cleaned = text
            .replacingOccurrences(of: "\\[[^]]*]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "周", with: "")
            .replacingOccurrences(of: " ", with: "")

        return cleaned
            .components(separatedBy: CharacterSet(charactersIn: ",，"))
            .flatMap { segment -> [Int] in
                let seg = segment.trimmingCharacters(in: .whitespaces)
                guard !seg.isEmpty else { return [] }
                let odd = seg.contains("(单)")
                let even = seg.contains("(双)")
                let clean = seg.replacingOccurrences(of: "(单)", with: "")
                    .replacingOccurrences(of: "(双)", with: "")

                let nums = extractInts(clean)
                guard !nums.isEmpty else { return [] }

                var from = nums[0]
                var to = nums.count > 1 ? nums[1] : nums[0]
                if from > to { swap(&from, &to) }

                var result: [Int] = []
                for w in from...to {
                    if (!odd || w % 2 == 1) && (!even || w % 2 == 0) {
                        result.append(w)
                    }
                }
                return result
            }
    }

    private func extractInts(_ text: String) -> [Int] {
        let nums = try? NSRegularExpression(pattern: "\\d+", options: [])
            .matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            .map { Int((text as NSString).substring(with: $0.range))! }
        return nums ?? []
    }

    // MARK: - T9

    var confidenceValue: Int {
        guard let data = source.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["datas"] is [[String: Any]],
              source.contains("classDateAndPlace") else { return 0 }
        return 90
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains("student/courses.do") { out.append("student/courses.do") }
        if source.contains("classDateAndPlace") { out.append("classDateAndPlace") }
        if source.contains("courseName") { out.append("courseName") }
        return out
    }
}
