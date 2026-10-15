// JwNeuParser.swift — ← JwNeuParser.kt
//
// 东北大学 (NEU) 强智新版教务 mobile JSON 解析器 — jwxt.neu.edu.cn。
//
// 数据源: /jwapp/sys/homeapp/api/home/student/getMyScheduleDetail.do
//   JSON 路径: x.datas.arrangedList[]
//   字段: {courseName, dayOfWeek, beginSection, endSection, weeksAndTeachers,
//           titleDetail[], placeName, cellDetail[]}
//   weeksAndTeachers: "周数串/老师[主讲]" 形式
//   titleDetail[0]: 汇总字符串(无地点); titleDetail[1..]: "周数串 教室"
//   实验课 ([实] 前缀): teacher 来自 titleDetail[1] 第 2 段, 地点来自 placeName 首段。
//
// 上游协议参考: CreamPig233/neu_wisedu2wakeup extract_schedule.js
// (算法自写, 仅复用字段映射)。单/双周: JSON 周次串自带 "单/双" 标记,
// Sleepy 保留 type=1/2 并用 JwParity.adjustedRange 做端点修正。

import Foundation

final class JwNeuParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    // MARK: - JwParser

    func generateCourseList() throws -> [JwCourse] {
        guard let data = source.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        guard let datas = root["datas"] as? [String: Any],
              let arranged = datas["arrangedList"] as? [[String: Any]] else {
            return []
        }

        var out: [JwCourse] = []
        for obj in arranged {
            let name = obj.str("courseName")
            if name.isEmpty { continue }
            let day = obj.int("dayOfWeek") ?? 0
            if day < 1 || day > 7 { continue }
            let begin = obj.int("beginSection") ?? 0
            if begin < 1 { continue }
            let end = obj.int("endSection") ?? begin
            let weeksAndTeachers = obj.str("weeksAndTeachers")
            let titleDetail = obj["titleDetail"] as? [Any]
            let cellDetail = obj["cellDetail"] as? [Any]
            let placeName = obj.str("placeName")
            let isLab = name.hasPrefix("[实]")

            let entries: [(weeks: String, room: String)]
            let teacher: String
            if isLab {
                let lab = extractLabWeeksAndRoom(obj, weeksAndTeachers)
                entries = [lab]
                teacher = extractLabTeacher(titleDetail)
            } else {
                entries = extractWeeksAndRooms(titleDetail, weeksAndTeachers, cellDetail, placeName)
                let cellTeacher = extractTeacherFromCellDetail(cellDetail)
                teacher = cellTeacher.isEmpty ? extractTeacher(weeksAndTeachers) : cellTeacher
            }

            for entry in entries where !entry.weeks.isEmpty {
                let (parity, cleanedWeeks) = extractParity(entry.weeks)
                for (sw, ew) in parseWeeks(cleanedWeeks) {
                    let adj = JwParity.adjustedRange(sw, ew, parity: parity)
                    out.append(JwCourse(
                        name: name,
                        room: entry.room.trimmingCharacters(in: .whitespaces),
                        teacher: teacher,
                        day: day,
                        startNode: begin,
                        endNode: end,
                        startWeek: adj.start,
                        endWeek: adj.end,
                        type: parity
                    ))
                }
            }
        }
        return out
    }

    // MARK: - Teacher

    /// 从 "周数串/老师[主讲]" 提取教师: 取 "/" 末段, 剥 [主讲]。
    func extractTeacher(_ s: String) -> String {
        if s.isBlank { return "" }
        let parts = s.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let last = parts.last ?? ""
        return last.replacingOccurrences(of: "[主讲]", with: "")
            .replacingOccurrences(of: "[主讲 ", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// 从 cellDetail 提取教师 ("教师[周次]" 模式, BUAA byxt 9 仓 cross-verified)。
    func extractTeacherFromCellDetail(_ cellDetail: [Any]?) -> String {
        guard let cellDetail = cellDetail, !cellDetail.isEmpty else { return "" }
        let pattern = #"([^\[\]]+)\[(\d[^\]]*?周?)\]"#
        for case let obj as [String: Any] in cellDetail {
            let text = (obj["text"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard let m = firstMatchStr(pattern, in: text) else { continue }
            let name = m[1].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        return ""
    }

    /// 实验课教师: titleDetail[1] 的第 2 个空白字段。
    private func extractLabTeacher(_ titleDetail: [Any]?) -> String {
        guard let titleDetail = titleDetail, titleDetail.count > 1,
              let detail = titleDetail[1] as? String else { return "" }
        let segs = detail.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return segs.count > 1 ? String(segs[1]) : ""
    }

    // MARK: - Weeks & Rooms

    /// cellDetail 形态 (BUAA byxt 9 仓 cross-verified):
    ///   cellDetail = [{"text": "教师名[1-16周]"}, {"text": "教室名"}, ...]
    ///   - 周次项 = 含 `[数字...周...]` 方括号, 首字符为汉字/拉丁字母
    ///   - 地点项 = 余下文本 (无周次方括号), 含校区/楼/教室关键词
    /// 容忍教研形态: cellDetail 单项即可同时含 "曾煜[1周] 沙河主M101"。
    func extractCellDetailPairs(_ cellDetail: [Any]?, _ placeName: String?) -> [(String, String)] {
        guard let cellDetail = cellDetail, !cellDetail.isEmpty else { return [] }
        let weekPattern = #"([^\[\]]+)\[(\d[^\]]*?周?)\]"#
        guard let ns = try? NSRegularExpression(pattern: weekPattern, options: []) else { return [] }
        let texts: [String] = cellDetail.compactMap {
            guard let obj = $0 as? [String: Any],
                  let raw = obj["text"] as? String else { return nil }
            let t = raw.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }

        // 周次项 = 含周次方括号的文本 → (weeks, room)
        // 地点 = 第一条不含周次方括号的文本 (Android: texts.firstOrNull { !teacherWeekPattern.containsMatchIn(it) })
        var out: [(String, String)] = []
        let room = texts.first { ns.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) == nil } ?? ""
        for text in texts {
            let range = NSRange(text.startIndex..., in: text)
            for m in ns.matches(in: text, options: [], range: range) {
                let weeksRange = m.range(at: 2)
                let weeks = (text as NSString).substring(with: weeksRange).trimmingCharacters(in: .whitespaces)
                if weeks.contains(where: { $0.isNumber }) { out.append((weeks, room)) }
            }
        }
        return out
    }

    /// 实验课: weeksAndTeachers 取 '[' 前内容, placeName 取首段。
    private func extractLabWeeksAndRoom(_ obj: [String: Any], _ weeksAndTeachers: String) -> (String, String) {
        let rawPlace = obj.str("placeName")
        let place = rawPlace.components(separatedBy: .whitespaces).first { !$0.isEmpty } ?? ""
        let room = place.hasSuffix(")") ? "暂未安排教室" : place
        let bracketIdx = weeksAndTeachers.firstIndex(of: "[") ?? weeksAndTeachers.endIndex
        let weeks = weeksAndTeachers[weeksAndTeachers.startIndex..<bracketIdx]
            .trimmingCharacters(in: .whitespaces)
        return (weeks, room)
    }

    /// cellDetail (BUAA byxt) → titleDetail[1..] (NEU) → weeksAndTeachers → placeName 兜底。
    /// 与 Android extractWeeksAndRooms 1:1。
    func extractWeeksAndRooms(
        _ titleDetail: [Any]?,
        _ weeksAndTeachers: String,
        _ cellDetail: [Any]?,
        _ placeName: String?
    ) -> [(String, String)] {
        let byCell = extractCellDetailPairs(cellDetail, placeName)
        if !byCell.isEmpty { return byCell }

        let details = extractTitleDetailPairs(titleDetail)
        if !details.isEmpty { return details }

        let fallback = weeksAndTeachers.split(separator: "/", omittingEmptySubsequences: false)
            .first?.trimmingCharacters(in: .whitespaces) ?? ""
        if !fallback.isEmpty { return [(fallback, "")] }

        // cellDetail/titleDetail/weeksAndTeachers 全空 → placeName 兜底 (1-16周)
        let pn = (placeName as String?)?.trimmingCharacters(in: .whitespaces) ?? ""
        return pn.isEmpty ? [] : [("1-16周", pn)]
    }

    /// titleDetail[1..] 的 "周数串 教室" 形态 (NEU 原生; BUAA byxt 回退)。
    private func extractTitleDetailPairs(_ titleDetail: [Any]?) -> [(String, String)] {
        var details: [(String, String)] = []
        guard let titleDetail = titleDetail else { return details }
        for i in 1..<titleDetail.count {
            let s = (titleDetail[i] as? String ?? "").trimmingCharacters(in: .whitespaces)
            if s.isEmpty || !s.first!.isNumber { continue }
            let parts = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                .map { String($0) }
            if parts.count >= 2 {
                let weeks = parts.first!
                let rawRoom = parts.last!
                let room = rawRoom.hasSuffix("校区") ? "待定" : rawRoom
                details.append((weeks, room))
            } else {
                details.append((parts.first ?? "", ""))
            }
        }
        return details
    }

    // MARK: - Parity & Weeks

    /// 从 "1-16周/王教授[主讲]" 提取 (parity, 净周次串)。
    /// parity: 0=每周 1=单周 2=双周。
    /// 形态: "1-16双周" / "1-16周(双)" / "3-15周（单）" / "2-15单周"
    func extractParity(_ s: String) -> (Int, String) {
        let parity = s.contains("单") ? 1 : (s.contains("双") ? 2 : 0)
        let clean = s.replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "(单)", with: "")
            .replacingOccurrences(of: "(双)", with: "")
        return (parity, clean)
    }

    /// 解析周次串 (已剥单/双标记与括号): "1-16周" / "2,4,6,8"。
    func parseWeeks(_ s: String) -> [(Int, Int)] {
        if s.isBlank { return [] }
        let clean = s.replacingOccurrences(of: "周", with: "")
            .replacingOccurrences(of: "单周", with: "")
            .replacingOccurrences(of: "双周", with: "")
            .replacingOccurrences(of: "单", with: "")
            .replacingOccurrences(of: "双", with: "")
            .trimmingCharacters(in: .whitespaces)
        if clean.isEmpty { return [] }
        var out: [(Int, Int)] = []
        for raw in clean.split(omittingEmptySubsequences: false, whereSeparator: { ",，、".contains($0) }) {
            let seg = String(raw).trimmingCharacters(in: .whitespaces)
            if seg.isEmpty { continue }
            if let range = seg.range(of: "-") {
                let aPart = seg[seg.startIndex..<range.lowerBound]
                let bPart = seg[range.upperBound..<seg.endIndex]
                guard let a = Int(aPart), let b = Int(bPart) else { continue }
                out.append((a, b))
            } else {
                guard let v = Int(seg) else { continue }
                out.append((v, v))
            }
        }
        return out
    }

    // MARK: - T9 confidence / features

    var confidenceValue: Int {
        guard let data = source.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let datas = root["datas"] as? [String: Any],
              datas["arrangedList"] is [Any] else { return 0 }
        return 90
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        let ok: Bool
        if let data = source.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let datas = root["datas"] as? [String: Any],
           datas["arrangedList"] != nil {
            ok = true
        } else {
            ok = false
        }
        if ok { out.append("arrangedList") }
        return out
    }
}

// MARK: - Regex helper (NSRegularExpression capture-group wrapper)

private struct MatchStr {
    let captures: [Int: String]
    subscript(i: Int) -> String { captures[i] ?? "" }
}

/// 一次匹配 → MatchStr (1-based captures; 0 = 全匹配)
private func firstMatchStr(_ pattern: String, in s: String) -> MatchStr? {
    let ns = try? NSRegularExpression(pattern: pattern, options: [])
    let range = NSRange(s.startIndex..., in: s)
    guard let m = ns?.firstMatch(in: s, options: [], range: range) else { return nil }
    var out: [Int: String] = [:]
    for i in 0..<m.numberOfRanges {
        let r = m.range(at: i)
        guard r.location != NSNotFound, r.length > 0,
              let range = Range(r, in: s) else { continue }
        out[i] = String(s[range])
    }
    return out.isEmpty ? nil : MatchStr(captures: out)
}

// MARK: - Dictionary<String,Any> helpers (← Kotlin str()/intOf())

private extension Dictionary where Key == String {
    /// 行元素取字符串 (缺键/非原始类型返回空串) — Kotlin JsonPrimitive?.contentOrNull
    func str(_ key: String) -> String {
        let v = self[key]
        if let s = v as? String { return s.trimmingCharacters(in: .whitespaces) }
        if let n = v as? NSNumber { return "\(n)" }
        if let d = v as? Double { return "\(d)" }
        return ""
    }

    func int(_ key: String) -> Int? {
        let v = self[key]
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String, let i = Int(s) { return i }
        return nil
    }
}
