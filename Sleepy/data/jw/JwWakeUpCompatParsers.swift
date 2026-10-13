// JwWakeUpCompatParsers.swift — ← JwWakeUpCompatParsers.kt
//
// WakeUp 协议族兼容解析器(kingo_new / jz / south_soft / login_chaoxing / shuwei_json /
// suda_post / cumtb / xju_post)。
//
// 8 个 concrete parser(JwKingoParser / JwJzParser / JwSouthSoftParser / JwChaoxingLegacyParser /
// JwShuweiParser / JwSudaParser / JwCumtbParser / JwXjuParser)都基于抽象基类
// WakeUpMarkerParser, 派发到 WakeUpCompat 的具体子解析器并暴露 markers 锚点。
//
// 主要复用 WakeUpCompat.parse(source, markers) 入口:链式尝试多个子解析器, 第一个产出
// 非空课程列表的胜出; 否则 jsonHint=false 时再回退 parseDelimited(纯文本 CSV)。
//
// 设计思路与 JwWakeUpCompatParsers.kt 1:1 对应, 包含 parseKingoInfo 私有死代码(原 Kotlin
// 标记 private, 无调用点 — 仅保留以备跨语言 diff 审计)。

import Foundation
import SwiftSoup

// MARK: - WakeUpCompat 子解析器集合(逐层回退, 第一个非空结果胜出)

enum WakeUpCompat {

    // 入口: JSON 课表 → JZ 兼容 JSON → JzHtml → marked table → plain CSV
    static func parse(_ source: String, markers: Set<String>, jsonHint: Bool = false) -> [JwCourse] {
        if let root = parseJson(source) {
            if let r = parseJsonCourses(root) as? [JwCourse], !r.isEmpty { return r }
            let jz = parseJzJson(root)
            if !jz.isEmpty { return jz }
        }
        let jzHtml = parseJzHtml(source)
        if !jzHtml.isEmpty { return jzHtml }
        let marked = parseMarkedTable(source, markers: markers)
        if !marked.isEmpty { return marked }
        return jsonHint ? [] : parseDelimited(source)
    }

    /// JZHandCourseInfoItem JSON: xqj=day, djj=起始节, qmz="1-8;10-16", dsz==1→单 / dsz!=2→双 / else 每周 (WakeUp 反转语义).
    static func parseJzJson(_ root: Any) -> [JwCourse] {
        guard let rows = root as? [[String: Any]] else { return [] }
        var out: [JwCourse] = []
        for row in rows {
            let nameRaw = (row["kcmc"] as? String) ?? ""
            let day = intField(row["xqj"]) ?? 0
            let start = intField(row["djj"]) ?? 0
            if nameRaw.trimmingCharacters(in: .whitespaces).isEmpty || day < 1 || day > 7 || start < 1 { continue }
            let type: Int
            switch intField(row["dsz"]) ?? 0 {
            case 1: type = 1
            case 2: type = 0
            default: type = 2
            }
            let qmz = (row["qmz"] as? String) ?? ""
            let skdd = (row["skdd"] as? String) ?? ""
            let jsxm = (row["jsxm"] as? String) ?? ""
            for token in qmz.components(separatedBy: ";") {
                let tokens = token.components(separatedBy: "；")
                for sub in tokens {
                    let nums = extractInts(sub)
                    if nums.isEmpty { continue }
                    let first = nums[0]
                    let second = nums.count > 1 ? nums[1] : first
                    out.append(JwCourse(name: nameRaw, room: skdd, teacher: jsxm,
                        day: day, startNode: start, endNode: start,
                        startWeek: first, endWeek: second, type: type))
                }
            }
        }
        return out
    }

    /// JZ HTML fallback: table#CourseFormTable; 节次行 td 按 <hr> 分块, 每块 <br> 分字段: [0]课名, [1]周次, [2]教师, "第a-b节", 末位地点.
    static func parseJzHtml(_ source: String) -> [JwCourse] {
        let doc = (try? SwiftSoup.parse(source)) ?? Document("")
        guard let els = try? doc.select("#CourseFormTable"), let table = els.first() else { return [] }
        var out: [JwCourse] = []
        for row in (try? table.select("tr")) ?? Elements() {
            let tds = (try? row.select("td")) ?? Elements()
            if tds.array().contains(where: { (try? $0.text().contains("星期")) ?? false }) { continue }
            for (col, td) in tds.array().enumerated() {
                if (try? td.attr("style").contains("center")) ?? false { continue }
                let day = col + 1
                let html = (try? td.html()) ?? ""
                for chunk in html.components(separatedBy: "<hr>") {
                    let lines = chunk.components(separatedBy: "<br>").map { s -> String in
                        let d = (try? SwiftSoup.parse(s)) ?? Document("")
                        return (try? d.text())?.trimmingCharacters(in: .whitespaces) ?? s
                    }.filter { !$0.isEmpty }
                    if lines.count < 2 { continue }
                    let rawFirst = lines[0]
                    let firstName = rawFirst.components(separatedBy: "(").first ?? rawFirst
                    let firstLine = firstName.trimmingCharacters(in: .whitespaces)
                    if firstLine.isEmpty { continue }
                    let name = firstLine
                    let weeksText = lines.first { line -> Bool in
                        line.first?.isNumber == true
                    } ?? ""
                    if weeksText.isEmpty { continue }
                    let nodeField = lines.first { l in l != weeksText && l.range(of: #"第\s*\d+"#, options: .regularExpression) != nil }
                    let nums = nodeField.flatMap { extractInts($0) }
                    let start = nums?.first ?? 1
                    let end = (nums?.count ?? 0) > 1 ? (nums?[1] ?? start) : start
                    let room = lines.last { $0 != name && $0 != weeksText && $0 != nodeField } ?? ""
                    let teacher = lines.first { $0 != name && $0 != weeksText && $0 != nodeField && $0 != room } ?? ""
                    for (from, to, type) in parseWeekTokens(weeksText) {
                        out.append(JwCourse(name: name, room: room, teacher: teacher,
                            day: day, startNode: start, endNode: end,
                            startWeek: from, endWeek: to, type: type))
                    }
                }
            }
        }
        return out
    }

    /// KingoInfo JSON: 顶层数组, 行 week1..week7 → day=列号, 值=[{jcxx:"a-b", kcmc, skdd, rkjs, xf}], week=row 索引.
    /// 死代码: 私有未暴露给 WakeUpCompat.parse 调用, 仅在 WakeUpCompat 内部可见 — 1:1 Kotlin 复制以保
    /// 跨语言 diff 审计一致(Kotlin 侧仅一处 `private fun parseKingoInfo(root: Any)` 声明)。
    fileprivate static func parseKingoInfo(_ root: Any) -> [JwCourse] {
        guard let rows = root as? [[String: Any]] else { return [] }
        if rows.isEmpty { return [] }
        var out: [JwCourse] = []
        for (r, row) in rows.enumerated() {
            for d in 1...7 {
                let key = "week\(d)"
                guard let cells = row[key] as? [[String: Any]] else { continue }
                for cell in cells {
                    let name = (cell["kcmc"] as? String) ?? ""
                    let jcxx = (cell["jcxx"] as? String) ?? ""
                    let bounds = jcxx.components(separatedBy: "-")
                    guard let start = Int(bounds.first?.trimmingCharacters(in: .whitespaces) ?? "") else { continue }
                    if name.trimmingCharacters(in: .whitespaces).isEmpty || start < 1 { continue }
                    let end = bounds.count > 1 ? (Int(bounds[1].trimmingCharacters(in: .whitespaces)) ?? start) : start
                    out.append(JwCourse(name: name,
                        room: (cell["skdd"] as? String) ?? "",
                        teacher: (cell["rkjs"] as? String) ?? "",
                        day: d, startNode: start, endNode: end,
                        startWeek: r, endWeek: r))
                }
            }
        }
        return out
    }
}
// MARK: - chaoxing / cumtb / south_soft 子解析器

extension WakeUpCompat {

    static func parseChaoxing(_ source: String) -> [JwCourse] {
        guard let root = parseJson(source) as? [String: Any] else { return [] }
        let dataNode = root["data"] as? [String: Any]
        let rows = dataNode?["kckbData"] as? [[String: Any]] ?? (root["kckbData"] as? [[String: Any]]) ?? []
        if rows.isEmpty { return [] }
        var out: [JwCourse] = []
        for row in rows {
            let name = stripMarkup((row["kcmc"] as? String) ?? "")
            guard let day = Int((row["xq"] as? String) ?? "") else { continue }
            let node = intField(row["djc"]) ?? 0
            if name.isEmpty || day < 1 || day > 7 || node < 1 { continue }
            let type = intField(row["zctype"]) ?? 0
            let zcRaw = (row["zc"] as? String) ?? ""
            let room = stripMarkup((row["croommc"] as? String) ?? "")
            let teacher = stripMarkup((row["tmc"] as? String) ?? "")
            for token in zcRaw.components(separatedBy: ",") {
                let nums = extractInts(token)
                if nums.isEmpty { continue }
                let first = nums[0]
                let second = nums.count > 1 ? nums[1] : first
                out.append(JwCourse(name: name, room: room, teacher: teacher,
                    day: day, startNode: node, endNode: node,
                    startWeek: first, endWeek: second, type: type))
            }
        }
        return out
    }

    static func parseCumtb(_ source: String) -> [JwCourse] {
        guard let root = parseJson(source) as? [String: Any],
              let payload = root["result"] as? [String: Any] else { return [] }
        var names: [Int: String] = [:]
        let lessons = payload["lessonList"] as? [[String: Any]] ?? []
        for l in lessons {
            let id = intField(l["id"]) ?? -1
            names[id] = (l["courseName"] as? String) ?? ""
        }
        guard let schedules = payload["scheduleList"] as? [[String: Any]] else { return [] }
        var out: [JwCourse] = []
        for row in schedules {
            let lessonId = intField(row["lessonId"]) ?? -1
            let name = (names[lessonId] ?? "").isEmpty ? "未知" : (names[lessonId] ?? "")
            let day = intField(row["weekday"]) ?? 0
            let week = intField(row["weekIndex"]) ?? 0
            let startTime = intField(row["startTime"]) ?? 0
            let start = timeToNode(startTime)
            if day < 1 || day > 7 || week < 1 || start < 1 { continue }
            let endTime = intField(row["endTime"]) ?? 0
            let count = durationToNodes(startTime, endTime)
            let room = (row["room"] as? [String: Any])?["nameZh"] as? String ?? ""
            let teacher = (row["personName"] as? String) ?? ""
            out.append(JwCourse(name: name, room: room, teacher: teacher,
                day: day, startNode: start, endNode: start + count - 1,
                startWeek: week, endWeek: week))
        }
        return out
    }

    static func parseSouthSoft(_ source: String) -> [JwCourse] {
        guard let parsed = parseJson(source) else { return [] }
        let rows: [[String: Any]]
        if let arr = parsed as? [[String: Any]] {
            rows = arr
        } else if let obj = parsed as? [String: Any],
                  let v = obj["value"] as? [[String: Any]] ?? obj["data"] as? [[String: Any]] {
            rows = v
        } else {
            return []
        }
        var out: [JwCourse] = []
        let keyRe = try! NSRegularExpression(pattern: "xq(\\d+)_jc\\d+", options: [])
        for row in rows {
            let keyRaw = (row["KEY"] as? String) ?? ""
            if keyRaw == "bz" { continue }
            let nsKey = keyRaw as NSString
            let keyRange = NSRange(keyRaw.startIndex..., in: keyRaw)
            guard let m = keyRe.firstMatch(in: keyRaw, options: [], range: keyRange),
                  let day = Int(nsKey.substring(with: m.range(at: 1))) else { continue }
            let sksj = (row["SKSJ"] as? String) ?? ""
            let bracketRe = try! NSRegularExpression(pattern: "\\[(.*?)\\]", options: [])
            let sksjNs = sksj as NSString
            let sksjRange = NSRange(sksj.startIndex..., in: sksj)
            let fields = bracketRe.matches(in: sksj, options: [], range: sksjRange).map { sksjNs.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespaces) }
            if fields.count < 5 { continue }
            let nodes = fields[4].replacingOccurrences(of: "第", with: "").replacingOccurrences(of: "节", with: "").components(separatedBy: "-")
            guard let start = Int(nodes.first ?? "") else { continue }
            let end = nodes.count > 1 ? (Int(nodes[1]) ?? start) : start
            for token in fields[1].components(separatedBy: ",") {
                let weeks = extractInts(token)
                if weeks.isEmpty { continue }
                let first = weeks[0]
                let second = weeks.count > 1 ? weeks[1] : first
                let type: Int
                if token.contains("单") { type = 1 }
                else if token.contains("双") { type = 2 }
                else { type = 0 }
                out.append(JwCourse(
                    name: ((row["KCWZSM"] as? String) ?? "").isEmpty ? fields[0] : ((row["KCWZSM"] as? String) ?? ""),
                    room: fields[4], teacher: fields[2],
                    day: day, startNode: start, endNode: end,
                    startWeek: first, endWeek: second, type: type))
            }
        }
        return out
    }
}

// MARK: - parseKingoTaskActivity (Kingosoft courseTable JS)

extension WakeUpCompat {

    /// Kingo TaskActivity JS grid: "activity = new TaskActivity(name,teacher,room,weeksBinary)";
    /// index=a*unitCount+b → day=a+1, node=b+1; '1'@p → week p+1, 连续段合并成组,
    /// 全奇→单周/全偶→双周.
    static func parseKingoTaskActivity(_ source: String) -> [JwCourse] {
        if !source.contains("TaskActivity") { return [] }
        guard let blockRange = source.range(of: #"var[\s]*activity[\s]*=[\s]*null;[\w\W]*(?=table0\.marshalTable)"#, options: .regularExpression) else {
            return []
        }
        let block = String(source[blockRange])
        var pending: [(name: String, room: String, teacher: String, weeks: [Int])] = []
        let stmtRe = try! NSRegularExpression(pattern: #"courseName[\s]*\+?=[\s]*[\"']([^\"']*)[\"']"#, options: [])
        let nameInLineRe = try! NSRegularExpression(pattern: #"['\"]([^'\"]*)['\"]\s*:\s*['\"]([^'\"]*)['\"]"#, options: [])
        let taskActRe = try! NSRegularExpression(pattern: #"new[\s]*TaskActivity[\s]*\("#, options: [])
        let strArgRe = try! NSRegularExpression(pattern: #"['\"]([^'\"]*)['\"]"#, options: [])
        let indexRe = try! NSRegularExpression(pattern: #"index[\s]*=[\s]*(\d+)[\s]*\*[\s]*unitCount[\s]*\+[\s]*(\d+)"#, options: [])

        var out: [JwCourse] = []
        var name = ""
        var teacher = ""
        for stmt in block.components(separatedBy: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let ns = stmt as NSString
            let r = NSRange(stmt.startIndex..., in: stmt)
            if let m = stmtRe.firstMatch(in: stmt, options: [], range: r) {
                name += ns.substring(with: m.range(at: 1))
            }
            let matches = nameInLineRe.matches(in: stmt, options: [], range: r)
            if !matches.isEmpty {
                teacher = matches.map { ns.substring(with: $0.range(at: 2)) }.joined(separator: ",")
            }
            if taskActRe.firstMatch(in: stmt, options: [], range: r) != nil {
                let args = strArgRe.matches(in: stmt, options: [], range: r)
                if args.count >= 4 {
                    let rawName = ns.substring(with: args[0].range(at: 1))
                    let tName = (rawName.components(separatedBy: "(").first ?? rawName)
                        .trimmingCharacters(in: .whitespaces)
                    let nameFinal = tName.isEmpty ? name : tName
                    if args.count > 1 {
                        let teacherArg = ns.substring(with: args[1].range(at: 1)).trimmingCharacters(in: .whitespaces)
                        if !teacherArg.isEmpty { teacher = teacherArg }
                    }
                    let room = ns.substring(with: args[2].range(at: 1))
                    let weeksBinary = ns.substring(with: args[3].range(at: 1))
                    var weeks: [Int] = []
                    for (pos, ch) in weeksBinary.enumerated() where ch == "1" {
                        weeks.append(pos + 1)
                    }
                    if !nameFinal.isEmpty && !weeks.isEmpty {
                        pending.append((nameFinal, room, teacher, weeks))
                    }
                }
            }
            if let m = indexRe.firstMatch(in: stmt, options: [], range: r) {
                // 跨仓 4 源一致: WakeUp o0000OO0.java i10=parseInt(g1)+1 / CourseHelper Swift dayOfWeek=match[1]
                // / shiguang HUNNU+UESTC day=D+1 — index 首因子是 0-based day, +1 才是星期几
                let a = Int(ns.substring(with: m.range(at: 1))) ?? 0
                let bRaw = Int(ns.substring(with: m.range(at: 2))) ?? 0
                let day = a + 1
                let b: Int
                if bRaw == 13 { b = 10 }
                else if bRaw < 9 { b = bRaw + 1 }
                else { b = bRaw + 2 }
                if let last = pending.popLast() {
                    var i = 0
                    while i < last.weeks.count {
                        var j = i
                        while j + 1 < last.weeks.count {
                            let cur = last.weeks[j]
                            let nxt = last.weeks[j + 1]
                            if nxt == cur + 1 || (nxt == cur + 2 && cur % 2 == 1 && nxt % 2 == 1) {
                                j += 1
                            } else { break }
                        }
                        let runStart = last.weeks[i]
                        let runEnd = last.weeks[j]
                        let type: Int
                        if runStart % 2 == 1 && runEnd % 2 == 1 { type = 1 }
                        else if runStart % 2 == 0 && runEnd % 2 == 0 { type = 2 }
                        else { type = 0 }
                        out.append(JwCourse(name: last.name, room: last.room, teacher: last.teacher,
                            day: day, startNode: b, endNode: b,
                            startWeek: runStart, endWeek: runEnd, type: type))
                        i = j + 1
                    }
                }
            }
        }
        return out
    }
}

// MARK: - parseXju / extractXjuCourses / parseXjuWeeksWithBrackets

extension WakeUpCompat {

    /// XJU dgData: 兼容两种表头形态。
    ///  - 形态 A: th="节次|周X" 无时间列, 节次=阿拉伯数字, 单元格 "｛名(周次)[教师:X,地点:Y]｝"
    ///  - 形态 B (真实 Gwork 学期课表信息查询, 2026-09-17 用户报修): th="时间|节次|周X",
    ///    时间列 rowspan=4, 节次=中文数字"一"..."十二", 课程名在花括号**外**,
    ///    单元格 "名｛周次[教师:X,地点:Y]｝", 课程行用 rowspan 跨节次合并.
    ///  通用通路: 还原 (col, row) 网格, rowspan 残留补齐, 映射 (day, node).
    static func parseXju(_ source: String) -> [JwCourse] {
        let doc = (try? SwiftSoup.parse(source)) ?? Document("")
        guard let els1 = try? doc.select("#ctl00_contentParent_dgData"), let table = els1.first() else { return [] }
        let rows = (try? table.select("tr")) ?? Elements()
        if rows.isEmpty() { return [] }
        guard let firstRow = rows.first(),
              let ths = try? firstRow.select("th"), ths.size() > 0 else { return [] }
        let dayRe = try! NSRegularExpression(pattern: "星期[一二三四五六日天]", options: [])
        let firstDayIdx = ths.array().firstIndex { (try? dayRe.firstMatch(in: $0.text(), options: [], range: NSRange($0.text().startIndex..., in: $0.text()))) != nil } ?? -1
        if firstDayIdx < 0 { return [] }
        let firstDayLabel = (try? ths.get(firstDayIdx).text()) ?? ""
        let dayOfFirstCol: Int = {
            if firstDayLabel.contains("星期一") { return 1 }
            if firstDayLabel.contains("星期二") { return 2 }
            if firstDayLabel.contains("星期三") { return 3 }
            if firstDayLabel.contains("星期四") { return 4 }
            if firstDayLabel.contains("星期五") { return 5 }
            if firstDayLabel.contains("星期六") { return 6 }
            return 7
        }()

        let cnMap: [String: Int] = ["一":1,"二":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9,"十":10,"十一":11,"十二":12]
        let rangeRe = try! NSRegularExpression(pattern: "第(\\d+)\\s*[-–~]\\s*\\d+节", options: [])

        func nodeLabelToInt(_ raw: String) -> Int? {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if let n = Int(trimmed), (1...20).contains(n) { return n }
            if let v = cnMap[trimmed] { return v }
            let r = NSRange(trimmed.startIndex..., in: trimmed)
            if let m = rangeRe.firstMatch(in: trimmed, options: [], range: r) {
                let ns = trimmed as NSString
                if let n = Int(ns.substring(with: m.range(at: 1))), (1...20).contains(n) { return n }
            }
            return nil
        }

        let dataRows = rows.array().dropFirst()

        var rowToNode = Array(repeating: 0, count: dataRows.count)
        var lastNode = 0
        for (rowIdx, row) in dataRows.enumerated() {
            var thisNode = 0
            let tds = (try? row.select("td")) ?? Elements()
            for td in tds.array() {
                let align = (try? td.attr("align")) ?? ""
                if align.lowercased() == "center" {
                    if let n = nodeLabelToInt((try? td.text()) ?? "") {
                        thisNode = n
                        break
                    }
                }
            }
            if thisNode == 0 { thisNode = lastNode } else { lastNode = thisNode }
            rowToNode[rowIdx] = thisNode
        }

        var cellText: [String: String] = [:]
        var colExpire: [Int: Int] = [:]
        for (rowIdx, row) in dataRows.enumerated() {
            let occupiedNow = Set(colExpire.filter { ($0.value) >= rowIdx }.keys)
            var col = 0
            let tds = (try? row.select("td")) ?? Elements()
            for td in tds.array() {
                let cs = Int((try? td.attr("colspan")) ?? "") ?? 1
                let rs = Int((try? td.attr("rowspan")) ?? "") ?? 1
                while occupiedNow.contains(col) { col += 1 }
                let align = (try? td.attr("align")) ?? ""
                let isCenter = align.lowercased() == "center"
                let rawText = (try? td.text()) ?? ""
                let raw = rawText.replacingOccurrences(of: " ", with: " ")
                    .replacingOccurrences(of: "{", with: "｛")
                    .replacingOccurrences(of: "}", with: "｝")
                    .trimmingCharacters(in: .whitespaces)
                for i in 0..<cs {
                    let c = col + i
                    if !isCenter && !raw.isEmpty {
                        cellText["\(c),\(rowIdx)"] = raw
                        for k in 1..<rs {
                            cellText["\(c),\(rowIdx + k)"] = raw
                        }
                    }
                    if rs > 1 { colExpire[c] = rowIdx + rs - 1 }
                }
                col += cs
            }
        }

        let thArr = ths.array()
        let firstDayCol = thArr.firstIndex { (try? dayRe.firstMatch(in: $0.text(), options: [], range: NSRange($0.text().startIndex..., in: $0.text()))) != nil } ?? firstDayIdx
        var grid: [String: String] = [:]
        for (key, raw) in cellText {
            if raw.isEmpty { continue }
            let parts = key.components(separatedBy: ",")
            guard parts.count == 2,
                  let col = Int(parts[0]),
                  let rowIdx = Int(parts[1]) else { continue }
            let node = rowToNode[rowIdx]
            guard (1...20).contains(node) else { continue }
            if col < firstDayCol { continue }
            let dayColIdx = col - firstDayCol
            let day = ((dayOfFirstCol - 1 + dayColIdx) % 7) + 1
            grid["\(day),\(node)"] = raw
        }
        if grid.isEmpty { return [] }

        var out: [JwCourse] = []
        var emitted: Set<String> = []
        for node in 1...20 {
            for day in 1...7 {
                let key = "\(day),\(node)"
                if emitted.contains(key) { continue }
                guard let raw = grid[key], !raw.isEmpty else { continue }
                var endNode = node
                while endNode + 1 <= 20 && grid["\(day),\(endNode + 1)"] == raw {
                    endNode += 1
                }
                for k in node...endNode { emitted.insert("\(day),\(k)") }
                out.append(contentsOf: extractXjuCourses(raw, day: day, startNode: node, endNode: endNode))
            }
        }
        return out
    }

    /// 把单格文本切成 JwCourse 列表。优先匹配形态 B「名｛周次[教师:…,地点:…],…｝」,
    /// 回退形态 A「｛名(周次)[教师:…,地点:…]｝」(旧 fixture).
    fileprivate static func extractXjuCourses(_ cellText: String, day: Int, startNode: Int, endNode: Int) -> [JwCourse] {
        var out: [JwCourse] = []
        if cellText.isEmpty { return out }
        let blocks = cellText.components(separatedBy: "；").map { $0.trimmingCharacters(in: .whitespaces) }
        let altBlocks = blocks.flatMap { b -> [String] in
            if !b.contains(";") { return [b] }
            return b.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        for block in altBlocks {
            if block.isEmpty { continue }
            if block.contains("｛") {
                let braceRe = try! NSRegularExpression(pattern: "｛([^｝]+)｝", options: [])
                let blockNs = block as NSString
                let blockRange = NSRange(block.startIndex..., in: block)
                let matches = braceRe.matches(in: block, options: [], range: blockRange)
                if !matches.isEmpty {
                    let firstInner = blockNs.substring(with: matches[0].range(at: 1))
                    let cutAt = block.index(block.startIndex, offsetBy: matches[0].range.location)
                    let namePrefix = block.substring(with: block.startIndex..<cutAt).trimmingCharacters(in: .whitespaces)
                    let isLegacy = namePrefix.isEmpty && firstInner.contains("(") && firstInner.contains("[")
                    if isLegacy {
                        let name = firstInner.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? firstInner
                        let weeksSection = innerParen(firstInner) ?? ""
                        let bracket = innerBracket(firstInner) ?? ""
                        let teacher = bracketTeacher(bracket)
                        let room = bracketRoom(bracket)
                        for entry in weeksSection.components(separatedBy: CharacterSet(charactersIn: "、,,")) {
                            for (from, to, type) in parseWeekTokens(entry) {
                                out.append(JwCourse(name: name, room: room, teacher: teacher,
                                    day: day, startNode: startNode, endNode: endNode,
                                    startWeek: from, endWeek: to, type: type))
                            }
                        }
                        continue
                    }
                    let name = namePrefix
                    for m in matches {
                        let inner = blockNs.substring(with: m.range(at: 1))
                        for (from, to, teacher, room) in parseXjuWeeksWithBrackets(inner) {
                            out.append(JwCourse(name: name, room: room, teacher: teacher,
                                day: day, startNode: startNode, endNode: endNode,
                                startWeek: from, endWeek: to))
                        }
                    }
                    continue
                }
            }
            if block.hasPrefix("｛") && block.hasSuffix("｝") {
                let inner = block.trimmingCharacters(in: CharacterSet(charactersIn: "｛｝"))
                let name = inner.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? inner
                guard let weeksSection = innerParen(inner) else { continue }
                let bracket = innerBracket(inner) ?? ""
                let teacher = bracketTeacher(bracket)
                let room = bracketRoom(bracket)
                for entry in weeksSection.components(separatedBy: CharacterSet(charactersIn: "、,,")) {
                    for (from, to, type) in parseWeekTokens(entry) {
                        out.append(JwCourse(name: name, room: room, teacher: teacher,
                            day: day, startNode: startNode, endNode: endNode,
                            startWeek: from, endWeek: to, type: type))
                    }
                }
            } else if !block.trimmingCharacters(in: .whitespaces).isEmpty {
                let name = block.components(separatedBy: "(").first?.components(separatedBy: "｛").first?.trimmingCharacters(in: .whitespaces) ?? block
                let nums = extractInts(block)
                if !name.isEmpty {
                    let first = nums.first ?? 1
                    let second = nums.count > 1 ? nums[1] : 20
                    out.append(JwCourse(name: name, day: day, startNode: startNode, endNode: endNode,
                        startWeek: first, endWeek: second))
                }
            }
        }
        return out
    }

    private static func innerParen(_ s: String) -> String? {
        let re = try! NSRegularExpression(pattern: "\\(([^)]*)\\)", options: [])
        let r = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, options: [], range: r) else { return nil }
        return (s as NSString).substring(with: m.range(at: 1))
    }
    private static func innerBracket(_ s: String) -> String? {
        let re = try! NSRegularExpression(pattern: "\\[([^\\]]*)\\]", options: [])
        let r = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, options: [], range: r) else { return nil }
        return (s as NSString).substring(with: m.range(at: 1))
    }
    private static func bracketTeacher(_ bracket: String) -> String {
        let re = try! NSRegularExpression(pattern: "教师[:：]([^,，\\]]*)", options: [])
        let r = NSRange(bracket.startIndex..., in: bracket)
        guard let m = re.firstMatch(in: bracket, options: [], range: r) else { return "" }
        return (bracket as NSString).substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
    }
    private static func bracketRoom(_ bracket: String) -> String {
        let re = try! NSRegularExpression(pattern: "地点[:：]([^,，\\]]*)", options: [])
        let r = NSRange(bracket.startIndex..., in: bracket)
        guard let m = re.firstMatch(in: bracket, options: [], range: r) else { return "" }
        return (bracket as NSString).substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
    }

    /// 形态 B 块内解析: "12-19周[教师:孙冬璞,地点:待定]"
    fileprivate static func parseXjuWeeksWithBrackets(_ inner: String) -> [(Int, Int, String, String)] {
        let bracket = innerBracket(inner) ?? ""
        let teacher = bracketTeacher(bracket)
        let room = bracketRoom(bracket)
        let beforeBracket: String
        if let r = inner.range(of: "[") {
            beforeBracket = String(inner[..<r.lowerBound])
        } else { beforeBracket = inner }
        var out: [(Int, Int, String, String)] = []
        for token in beforeBracket.components(separatedBy: CharacterSet(charactersIn: "、,,")) {
            for (from, to, _) in parseWeekTokens(token) {
                out.append((from, to, teacher, room))
            }
        }
        return out
    }
}

// MARK: - parseSuda / parseShuwei / 工具函数 / confidence / features

extension WakeUpCompat {

    /// Suda DataGrid1/MainWork_DataGrid1: th 行含 星期X 跳过; 数据行 align=center td=node 行标, 其余 td 索引+1=day;
    /// 单元格 "课程:"-名, "(x)"-教师(非辅讲), "主讲教师:"-教师, "第a-b周[单/双]"(以;/,分).
    static func parseSuda(_ source: String) -> [JwCourse] {
        let doc = (try? SwiftSoup.parse(source)) ?? Document("")
        guard let els2 = try? doc.select("#DataGrid1"), let table = els2.first() else { return [] }
        var out: [JwCourse] = []
        for row in (try? table.select("tr")) ?? Elements() {
            let tds = (try? row.select("td")) ?? Elements()
            if tds.array().contains(where: { (try? $0.text().contains("星期")) ?? false }) { continue }
            var node = 1
            for (col, td) in tds.array().enumerated() {
                let align = (try? td.attr("align")) ?? ""
                if align.lowercased() == "center" {
                    let text = (try? td.text()) ?? ""
                    let digitRe = try! NSRegularExpression(pattern: "\\d+", options: [])
                    let r = NSRange(text.startIndex..., in: text)
                    if let m = digitRe.firstMatch(in: text, options: [], range: r),
                       let n = Int((text as NSString).substring(with: m.range)) {
                        node = n
                    }
                    continue
                }
                let day = col + 1
                let text = (try? td.text()) ?? ""
                if text.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                let html = (try? td.html()) ?? ""
                let lines = html.components(separatedBy: "<br>").map { s -> String in
                    let d = (try? SwiftSoup.parse(s)) ?? Document("")
                    return (try? d.text())?.trimmingCharacters(in: .whitespaces) ?? s
                }.filter { !$0.isEmpty }
                var name = ""
                var teacher = ""
                var room = ""
                var weeks: [(Int, Int, Int)] = []
                let weekRe = try! NSRegularExpression(pattern: "第\\s*(\\d+)\\s*(-\\s*(\\d+))?\\s*周\\s*(单|双)?", options: [])
                for line in lines {
                    if line.hasPrefix("课程:") || line.hasPrefix("课程：") {
                        name = dropPrefixColon(line).trimmingCharacters(in: .whitespaces)
                    } else if line.hasPrefix("(") && !line.contains("辅讲教师") {
                        teacher = line.trimmingCharacters(in: CharacterSet(charactersIn: "()")).trimmingCharacters(in: .whitespaces)
                    } else if line.hasPrefix("主讲教师:") || line.hasPrefix("主讲教师：") {
                        teacher = dropPrefixColon(line).trimmingCharacters(in: .whitespaces)
                    } else if line.range(of: "第\\s*\\d+.*周", options: .regularExpression) != nil {
                        let r = NSRange(line.startIndex..., in: line)
                        let ms = weekRe.matches(in: line, options: [], range: r)
                        for m in ms {
                            let ns = line as NSString
                            let from = Int(ns.substring(with: m.range(at: 1))) ?? 1
                            let to = Int(ns.substring(with: m.range(at: 3))) ?? from
                            let type: Int
                            switch ns.substring(with: m.range(at: 4)) {
                            case "单": type = 1
                            case "双": type = 2
                            default: type = 0
                            }
                            weeks.append((from, to, type))
                        }
                    } else {
                        if name.isEmpty { name = line } else { room = line }
                    }
                }
                if name.isEmpty { name = lines.first ?? "" }
                if weeks.isEmpty { weeks.append((1, 20, 0)) }
                // WakeUp dex L00e9 rowspan: 纵向合并单元格占多节 — endNode = node + rowspan - 1
                let rs = Int((try? td.attr("rowspan")) ?? "") ?? 1
                let endNode = node + max(rs - 1, 0)
                for (from, to, type) in weeks {
                    out.append(JwCourse(name: name, room: room, teacher: teacher,
                        day: day, startNode: node, endNode: endNode,
                        startWeek: from, endWeek: to, type: type))
                }
            }
        }
        return out
    }

    private static func dropPrefixColon(_ s: String) -> String {
        if let idx = s.firstIndex(where: { $0 == ":" || $0 == "：" }) {
            let after = s.index(after: idx)
            return String(s[after...])
        }
        return s
    }

    static func confidence(_ source: String, markers: Set<String>) -> Int {
        if markers.contains(where: { source.range(of: $0, options: .caseInsensitive) != nil }) { return 90 }
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return 70 }
        return 0
    }

    static func features(_ source: String, markers: Set<String>) -> [String] {
        markers.compactMap { m in
            source.range(of: m, options: .caseInsensitive) != nil ? "marker=\(m)" : nil
        }
    }

    static func parseShuwei(_ source: String) -> [JwCourse] {
        guard let root = parseJson(source) else { return [] }
        var result: [JwCourse] = []
        func visit(_ value: Any) {
            if let arr = value as? [[String: Any]] {
                for item in arr { visit(item) }
            } else if let obj = value as? [String: Any] {
                for key in ["activities", "courseUnits", "unitList"] {
                    if let arr = obj[key] as? [[String: Any]] {
                        for row in arr {
                            if let r = parseActivity(row) { result.append(contentsOf: r) }
                        }
                    }
                }
                for key in obj.keys {
                    if let v = obj[key] { visit(v) }
                }
            }
        }
        visit(root)
        var seen: Set<String> = []
        return result.filter { c in
            let s = [c.name, String(c.day), String(c.startNode), String(c.startWeek), String(c.endWeek), String(c.type)].joined(separator: "|")
            return seen.insert(s).inserted
        }
    }

    fileprivate static func parseActivity(_ row: [String: Any]) -> [JwCourse]? {
        let name = first(row, "courseName", "course", "name", "kcmc")
        guard let day = firstInt(row, "weekday", "weekDay", "dayOfWeek", "classDay", "xqj", "day"),
              (1...7).contains(day) else { return nil }
        guard let start = firstInt(row, "startSection", "beginSection", "beginNumber", "startNode", "ksjc", "start"),
              start >= 1 else { return nil }
        let end = firstInt(row, "endSection", "endNumber", "endNode", "jsjc", "end") ?? start
        let weeks = parseWeekTokens(first(row, "weeksStr", "weekDescription", "week", "weeks", "zc"))
        guard !weeks.isEmpty, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let room = first(row, "room", "classroom", "classroomName", "location", "JASMC", "cdmc")
        let teacher = first(row, "teacher", "teacherName", "teachers", "attendClassTeacher", "SKJS", "xm")
        return weeks.map { (from, to, type) in
            JwCourse(name: name, room: room, teacher: teacher,
                day: day, startNode: start, endNode: end,
                startWeek: from, endWeek: to, type: type)
        }
    }

    fileprivate static func parseWeekTokens(_ value: String) -> [(Int, Int, Int)] {
        if value.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        let segments = value.replacingOccurrences(of: "周", with: "")
            .components(separatedBy: CharacterSet(charactersIn: ",，;；"))
        var out: [(Int, Int, Int)] = []
        for seg in segments {
            let token = seg.trimmingCharacters(in: .whitespaces)
            if token.isEmpty { continue }
            let type: Int
            if token.contains("单") { type = 1 }
            else if token.contains("双") { type = 2 }
            else { type = 0 }
            let nums = extractInts(token)
            if nums.isEmpty { continue }
            out.append((nums[0], nums.count > 1 ? nums[1] : nums[0], type))
        }
        return out
    }

    fileprivate static func parseJson(_ source: String) -> Any? {
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        guard let data = trimmed.data(using: .utf8) else { return nil }
        if trimmed.hasPrefix("{") {
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        if trimmed.hasPrefix("[") {
            return try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        }
        return nil
    }

    fileprivate static func parseJsonCourses(_ root: Any) -> Any {
        var result: [JwCourse] = []
        func walk(_ value: Any, _ depth: Int) {
            guard depth <= 5 else { return }
            if let arr = value as? [[String: Any]] {
                for item in arr {
                    let name = first(item, "courseName", "kcmc", "KCM", "name", "course")
                    if !name.isEmpty,
                       let day = firstInt(item, "weekday", "dayOfWeek", "xqj", "day", "classDay", "xq"),
                       let node = firstInt(item, "beginNumber", "beginSection", "startNode", "ksjc", "start") {
                        let endNode = firstInt(item, "endNumber", "endSection", "endNode", "jsjc", "end") ?? node
                        let room = first(item, "location", "room", "classroomName", "JASMC", "cdmc")
                        let teacher = first(item, "teacherName", "teacher", "teachers", "SKJS", "xm")
                        result.append(JwCourse(name: name, room: room, teacher: teacher,
                            day: max(1, min(day, 7)), startNode: node, endNode: endNode,
                            startWeek: 1, endWeek: 16))
                    }
                    walk(item, depth + 1)
                }
            } else if let obj = value as? [String: Any] {
                for key in obj.keys { if let v = obj[key] { walk(v, depth + 1) } }
            }
        }
        walk(root, 0)
        return result
    }

    fileprivate static func parseMarkedTable(_ source: String, markers: Set<String>) -> [JwCourse] {
        let doc = (try? SwiftSoup.parse(source)) ?? Document("")
        var out: [JwCourse] = []
        for row in (try? doc.select("tr")) ?? Elements() {
            let cells = (try? row.select("td,th")) ?? Elements()
            if cells.size() < 3 { continue }
            let texts = cells.array().map { (try? $0.text())?.trimmingCharacters(in: .whitespaces) ?? "" }
            let text = texts.joined(separator: " | ")
            if !markers.isEmpty && !markers.contains(where: { source.range(of: $0, options: .caseInsensitive) != nil })
                && ((try? row.attr("data-day")) ?? "").isEmpty { continue }
            let nameAttr = (try? row.attr("data-course")) ?? ""
            let name = nameAttr.isEmpty ? (texts.first ?? "") : nameAttr
            let dayAttr = Int((try? row.attr("data-day")) ?? "") ?? extractDay(text) ?? 0
            guard dayAttr > 0 else { continue }
            let nodeAttr = Int((try? row.attr("data-node")) ?? "") ?? extractNode(text) ?? 0
            guard nodeAttr > 0 else { continue }
            let roomAttr = (try? row.attr("data-room")) ?? (cells.size() > 3 ? texts[3] : "")
            let teacherAttr = (try? row.attr("data-teacher")) ?? (cells.size() > 2 ? texts[2] : "")
            if !name.isEmpty {
                out.append(JwCourse(name: name, room: roomAttr, teacher: teacherAttr,
                    day: dayAttr, startNode: nodeAttr, endNode: nodeAttr,
                    startWeek: 1, endWeek: 16))
            }
        }
        return out
    }

    fileprivate static func parseDelimited(_ source: String) -> [JwCourse] {
        source.components(separatedBy: .newlines).compactMap { line -> JwCourse? in
            let p = line.components(separatedBy: CharacterSet(charactersIn: ",\t"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard p.count >= 5,
                  let day = Int(p[1]), (1...7).contains(day),
                  let node = Int(p[2]) else { return nil }
            return JwCourse(name: p[0], room: p.count > 3 ? p[3] : "", teacher: p.count > 4 ? p[4] : "",
                day: day, startNode: node, endNode: node, startWeek: 1, endWeek: 16)
        }
    }

    fileprivate static func first(_ o: [String: Any], _ keys: String...) -> String {
        for k in keys {
            if let v = o[k] as? String, !v.isEmpty { return v }
        }
        return ""
    }
    fileprivate static func firstInt(_ o: [String: Any], _ keys: String...) -> Int? {
        for k in keys {
            if let v = o[k] {
                if let n = v as? Int { return n }
                if let s = v as? String, let n = Int(s.filter(\.isNumber)) { return n }
            }
        }
        return nil
    }
    fileprivate static func stripMarkup(_ value: String) -> String {
        let doc = (try? SwiftSoup.parse(value)) ?? Document("")
        return (try? doc.text())?.trimmingCharacters(in: .whitespaces) ?? value
    }
    fileprivate static func extractDay(_ text: String) -> Int? {
        let re = try! NSRegularExpression(pattern: "(?:星期|周)\\s*([一二三四五六日天1-7])", options: [])
        let r = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, options: [], range: r) else { return nil }
        let ns = text as NSString
        let v = ns.substring(with: m.range(at: 1))
        switch v {
        case "一": return 1
        case "二": return 2
        case "三": return 3
        case "四": return 4
        case "五": return 5
        case "六": return 6
        case "日", "天": return 7
        default: return Int(v)
        }
    }
    fileprivate static func extractNode(_ text: String) -> Int? {
        let re = try! NSRegularExpression(pattern: "(?:第\\s*)?(\\d{1,2})\\s*(?:[-~至](\\d{1,2}))?\\s*节", options: [])
        let r = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, options: [], range: r) else { return nil }
        let ns = text as NSString
        return Int(ns.substring(with: m.range(at: 1)))
    }
    fileprivate static func timeToNode(_ time: Int) -> Int {
        if time < 1230 { return ((time - 800) / 100) + 1 }
        if time < 1800 { return ((time - 1400) / 100) + 5 }
        return ((time - 1900) / 100) + 9
    }
    fileprivate static func durationToNodes(_ start: Int, _ end: Int) -> Int {
        let delta = end - start
        if (50...99).contains(delta) { return 1 }
        if (100...200).contains(delta) { return 2 }
        if (210...340).contains(delta) { return 3 }
        return 4
    }
    fileprivate static func extractInts(_ s: String) -> [Int] {
        let re = try! NSRegularExpression(pattern: "\\d+", options: [])
        let r = NSRange(s.startIndex..., in: s)
        return re.matches(in: s, options: [], range: r).compactMap { m in
            Int((s as NSString).substring(with: m.range))
        }
    }
    fileprivate static func intField(_ v: Any?) -> Int? {
        if let n = v as? Int { return n }
        if let s = v as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }
}

// MARK: - WakeUpMarkerParser 基类与 8 concrete parsers

class WakeUpMarkerParserBase: JwParser, JwParserConfidenceReporting {
    let source: String
    let markers: Set<String>
    init(_ source: String, _ markers: Set<String>) {
        self.source = source
        self.markers = markers
    }
    func generateCourseList() throws -> [JwCourse] { WakeUpCompat.parse(source, markers: markers) }
    var confidenceValue: Int { WakeUpCompat.confidence(source, markers: markers) }
    var matchedFeatureList: [String] { WakeUpCompat.features(source, markers: markers) }
}

final class JwKingoParser: WakeUpMarkerParserBase {
    init(_ source: String) { super.init(source, ["kingosoft", "courseTableForStd", "courseTableStudent", "new TaskActivity"]) }
    override func generateCourseList() throws -> [JwCourse] {
        let primary = WakeUpCompat.parseKingoTaskActivity(source)
        return primary.isEmpty ? try super.generateCourseList() : primary
    }
}

final class JwJzParser: WakeUpMarkerParserBase {
    init(_ source: String) { super.init(source, ["courseTableForStd", "courseTableStudent", "wisedu", "JinZhi"]) }
}

final class JwSouthSoftParser: WakeUpMarkerParserBase {
    init(_ source: String) { super.init(source, ["studentTableVms", "studentTableVm", "activities", "south_soft"]) }
    override func generateCourseList() throws -> [JwCourse] {
        let primary = WakeUpCompat.parseSouthSoft(source)
        return primary.isEmpty ? try super.generateCourseList() : primary
    }
}

final class JwChaoxingLegacyParser: WakeUpMarkerParserBase {
    init(_ source: String) { super.init(source, ["kckbData", "LessonArray", "queryKbForGrdb", "Powered by ChaoXing"]) }
    override func generateCourseList() throws -> [JwCourse] {
        let primary = WakeUpCompat.parseChaoxing(source)
        return primary.isEmpty ? try super.generateCourseList() : primary
    }
}

final class JwShuweiParser: WakeUpMarkerParserBase {
    init(_ source: String) { super.init(source, ["courseUnits", "unitCount", "activities", "wut_table", "shuwei"]) }
    override func generateCourseList() throws -> [JwCourse] {
        let primary = WakeUpCompat.parseShuwei(source)
        return primary.isEmpty ? try super.generateCourseList() : primary
    }
}

final class JwSudaParser: WakeUpMarkerParserBase {
    init(_ source: String) { super.init(source, ["print-schedule-table", "default2.aspx", "xskbcx.aspx", "suda"]) }
    override func generateCourseList() throws -> [JwCourse] {
        let primary = WakeUpCompat.parseSuda(source)
        return primary.isEmpty ? try super.generateCourseList() : primary
    }
}

final class JwCumtbParser: WakeUpMarkerParserBase {
    init(_ source: String) { super.init(source, ["eams5-student", "schedule-table", "course-table", "cumtb"]) }
    override func generateCourseList() throws -> [JwCourse] {
        let primary = WakeUpCompat.parseCumtb(source)
        return primary.isEmpty ? try super.generateCourseList() : primary
    }
}

final class JwXjuParser: WakeUpMarkerParserBase {
    init(_ source: String) { super.init(source, ["xjtu", "xju", "courseTable", "课程表"]) }
    override func generateCourseList() throws -> [JwCourse] {
        let primary = WakeUpCompat.parseXju(source)
        return primary.isEmpty ? try super.generateCourseList() : primary
    }
}
