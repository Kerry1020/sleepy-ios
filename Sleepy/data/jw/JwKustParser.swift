// JwKustParser.swift — ← JwKustParser.kt
//
// 昆明理工大学统一门户 (KMUST) 周课表网格解析器。
//
// 协议: JwProtocol.TYPE_KUST = "kust"
//
// 数据来源: GET /queryAWeekSchedule?XNXQ=<term>
//   返回: { data: { resultsJsonArr: [[col0,row1],[col1,row1],...], zs: weekNo } }
//   resultsJsonArr[0] = [null, "1节", "2节", ...]
//   resultsJsonArr[rowIndex] (rowIndex>=2): [null, col1_cell, col2_cell, ...]
//   单元格内容: "课名1,课名2;教师1,教师2" (分号分隔多个课时)
//   字段: [0]=课名(逗号分隔), 课名后;分号分隔教师, 无教师时为";"
//   列索引 → 星期: columnIndex.coerceIn(1, 7)
//   行索引 → 节次: rowIndex - 1

import Foundation

final class JwKustParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    func generateCourseList() throws -> [JwCourse] {
        guard let data = source.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let objData = root["data"] as? [String: Any],
              let grid = objData["resultsJsonArr"] as? [[Any]],
              let weekVal = objData["zs"] as? String,
              let week = Int(weekVal) else {
            return []
        }

        var out: [JwCourse] = []
        var seen: [String: JwCourse] = [:]

        for (rowIndex, row) in grid.enumerated() {
            guard rowIndex >= 2, row.count > 1 else { continue }
            let section = rowIndex - 1
            for (colIndex, cell) in row.enumerated() {
                guard colIndex >= 1 else { continue }
                let day = min(max(colIndex, 1), 7)
                guard let text = cell as? String, !text.isEmpty else { continue }

                let parts = text.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
                let namePart = String(parts[0])
                let names = namePart.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                let teacherPart = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

                for name in names where !name.isEmpty {
                    let key = [name, "", teacherPart, day.description, week.description]
                        .joined(separator: "|")
                    if let existing = seen[key] {
                        if section == existing.endNode + 1 {
                            let merged = JwCourse(name: existing.name, room: existing.room, teacher: existing.teacher,
                                day: existing.day, startNode: existing.startNode, endNode: section,
                                startWeek: existing.startWeek, endWeek: existing.endWeek, type: existing.type)
                            seen[key] = merged
                        }
                    } else {
                        var c = JwCourse(name: name, day: day, startNode: section, endNode: section,
                            startWeek: week, endWeek: week)
                        c.teacher = teacherPart
                        seen[key] = c
                    }
                }
            }
        }

        return Array(seen.values)
    }

    // MARK: - T8

    var confidenceValue: Int {
        guard let data = source.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let objData = root["data"] as? [String: Any],
              objData["resultsJsonArr"] is [[Any]] else { return 0 }
        return 90
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains("queryAWeekSchedule") { out.append("queryAWeekSchedule") }
        if source.contains("resultsJsonArr") { out.append("resultsJsonArr") }
        if source.contains("weekcount") { out.append("weekcount") }
        return out
    }
}
