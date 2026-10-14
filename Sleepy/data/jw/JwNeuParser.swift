// JwNeuParser.swift — ← data/jw/JwNeuParser.kt (v1.0.60, 269 行)
// 东北大学 (NEU) 强智新版教务 mobile JSON 解析器 — 全量移植版。
//
// 数据源: jwxt.neu.edu.cn mobile 接口
//   /jwapp/sys/homeapp/api/home/student/getMyScheduleDetail.do
// JSON 路径: x.datas.arrangedList[]
// 字段集: {courseName, dayOfWeek, beginSection, endSection, weeksAndTeachers, titleDetail[], placeName}
//   weeksAndTeachers: "周数串/老师[主讲]" 形式
//   titleDetail[0]: 汇总字符串 (无 location 信息)
//   titleDetail[1..]: "周数串 教室" 形式, 按空格 split 末段为 location
//   实验课 ([实] 前缀): 教师取 titleDetail[1] 第二段, 地点取 placeName 首段
//
// 上游协议形态参考: CreamPig233/neu_wisedu2wakeup (无 license) extract_schedule.js
// (https://github.com/CreamPig233/neu_wisedu2wakeup/blob/master/extract_schedule.js)
// teacher 提取规则 (split "/", 取末段剥 [主讲]) 与 weeksAndTeachers 解析参考,
// 代码自写, 仅复用字段映射。
//
// 单/双周: 线协议 JSON 的周次串自带单/双信息 ("1-16双周" / "1-16周(双)" /
// "3-15周（单）"), 上游 CSV 导出才 replace(/[()]/g) 剥括号丢弃 — Sleepy 不丢,
// 保留 type=1/2 并按 Sleepy 语义做端点修正 (单周奇数化/双周偶数化)。
//
// Swift 移植差异说明:
//   - Kotlin class JwNeuParser(source) : JwParser(source) 抽象基类 → Swift
//     final class + JwParser 协议(仓库既有模式, 见 JwJsonParsers.swift)。
//   - kotlinx.serialization JsonElement 树 → JSONSerialization [String: Any],
//     经由 JwJsonParsers.swift 模块级 jsonObj/jsonArr/jstr/jint 辅助(等价 Kotlin
//     JsonObject.str() 扩展)。".size" 在 Swift 侧是 .count(方法→属性差异)。
//   - Kotlin Regex → NSRegularExpression(经辅助函数)。

import Foundation

final class JwNeuParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    func generateCourseList() throws -> [JwCourse] {
        guard let data = source.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let datas = jsonObj(root["datas"]),
              let arranged = jsonArr(datas["arrangedList"]) else { return [] }
        var out: [JwCourse] = []
        for el in arranged {
            guard let obj = jsonObj(el) else { continue }
            let name = jstr(obj, "courseName")
            if name.isEmpty { continue }
            guard let day = jint(obj, "dayOfWeek") else { continue }
            guard let begin = jint(obj, "beginSection") else { continue }
            let end = jint(obj, "endSection") ?? begin
            let weeksAndTeachers = jstr(obj, "weeksAndTeachers")
            let titleDetail = jsonArr(obj["titleDetail"])
            let cellDetail = jsonArr(obj["cellDetail"])
            let placeName = jstr(obj, "placeName")
            let isLab = name.hasPrefix("[实]")
            let entries: [(weeks: String, room: String)]
            if isLab {
                // 实验课的接口结构不同：脚本从 titleDetail[1] 取教师，
                // 从 placeName 取地点，并从 weeksAndTeachers 中剥出周次。
                entries = [extractLabWeeksAndRoom(obj, weeksAndTeachers)]
            } else {
                // 普通课程每一条 titleDetail 明细都是独立的周次/地点安排。
                // 优先 cellDetail (BUAA byxt 形态), titleDetail (NEU 形态) 兜底。
                entries = extractWeeksAndRooms(titleDetail, weeksAndTeachers, cellDetail, placeName)
            }
            let teacher: String
            if isLab {
                teacher = extractLabTeacher(titleDetail)
            } else if !extractTeacherFromCellDetail(cellDetail).isEmpty {
                // cellDetail 有 `教师[周次]` → 首对教师优先; 无则走 NEU "/" 末段
                teacher = extractTeacherFromCellDetail(cellDetail)
            } else {
                teacher = extractTeacher(weeksAndTeachers)
            }
            for entry in entries {
                let weeksStr = entry.weeks
                if weeksStr.isEmpty { continue }
                let (parity, cleanedWeeks) = extractParity(weeksStr)
                for (sw, ew) in parseWeeks(cleanedWeeks) {
                    // Sleepy 语义: 单周(1)起点须奇数/双周(2)起点须偶数，
                    // 同时避免单条周次在修正后出现倒挂区间。
                    let adjusted = JwParity.adjustedRange(sw, ew, parity: parity)
                    out.append(JwCourse(
                        name: name,
                        room: entry.room,
                        teacher: teacher,
                        day: day,
                        startNode: begin,
                        endNode: end,
                        startWeek: adjusted.start,
                        endWeek: adjusted.end,
                        type: parity))
                }
            }
        }
        return out
    }

    /// 从 "1-16周/王教授[主讲]" 提取 teacher: 取 "/" 末段, 剥 [主讲] 标记。
    /// 若无 "/" 或剥离后为空, 返回空串。
    func extractTeacher(_ s: String) -> String {
        if s.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
        let parts = s.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last else { return "" }
        return last
            .replacingOccurrences(of: "[主讲]", with: "")
            .replacingOccurrences(of: "[主讲 ", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// 优先按 cellDetail 形态（BUAA byxt 9 仓 cross-verified: CoolwindHF/buaa2wakeup +
    /// Alyssumira/BUAA-Schedule + Krignd/KAgenda）取 `教师[周次]` / `地点行` 对；
    /// cellDetail 缺失/不含周次时回退 NEU titleDetail[1..] 的"周数串 教室"形态。
    func extractWeeksAndRooms(
        _ titleDetail: [Any]?,
        _ weeksAndTeachers: String,
        _ cellDetail: [Any]? = nil,
        _ placeName: String? = nil
    ) -> [(weeks: String, room: String)] {
        let byCell = extractCellDetailPairs(cellDetail, placeName)
        if !byCell.isEmpty { return byCell }

        var details: [(weeks: String, room: String)] = []
        if let titleDetail = titleDetail {
            // ← Kotlin: for (i in 1 until titleDetail.size) — 跳过 [0] 汇总串
            if titleDetail.count > 1 {
                for i in 1..<titleDetail.count {
                    var s = ""
                    if let str = titleDetail[i] as? String { s = str.trimmingCharacters(in: .whitespaces) }
                    else if let n = titleDetail[i] as? NSNumber { s = n.stringValue }
                    if s.isEmpty || !s.first!.isNumber { continue }
                    let parts = s.components(separatedBy: " ").filter { !$0.isEmpty }
                    if parts.count >= 2 {
                        let weeks = parts.first!.trimmingCharacters(in: .whitespaces)
                        let rawRoom = parts.last!.trimmingCharacters(in: .whitespaces)
                        let room = rawRoom.hasSuffix("校区") ? "待定" : rawRoom
                        details.append((weeks, room))
                    } else {
                        details.append((parts.first!.trimmingCharacters(in: .whitespaces), ""))
                    }
                }
            }
        }
        if !details.isEmpty { return details }
        let fallbackWeeks = weeksAndTeachers.components(separatedBy: "/").first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if !fallbackWeeks.isEmpty { return [(fallbackWeeks, "")] }
        // cellDetail/titleDetail/weeksAndTeachers 全空 → placeName 兜底 (整学期 1-16 周)
        if let placeName = placeName, !placeName.trimmingCharacters(in: .whitespaces).isEmpty {
            return [("1-16周", placeName)]
        }
        return []
    }

    /// 从 cellDetail 提取 (周次, 地点) 配对 — BUAA byxt 形态:
    ///   cellDetail = [{"text": "教师名[1-16周]"}, {"text": "教室名"}, ...]
    ///   - 周次项 = 含 `[数字...周...]` 方括号且首字符为汉字/拉丁字母
    ///   - 地点项 = 余下文本（无方括号周次）, 含校区/楼/教室关键词
    /// 容忍教研形态: cellDetail 单项即可同时含 "曾煜[1周] 沙河主M101"。
    private func extractCellDetailPairs(
        _ cellDetail: [Any]?,
        _ placeName: String?
    ) -> [(weeks: String, room: String)] {
        guard let cellDetail = cellDetail, !cellDetail.isEmpty else { return [] }
        let texts = cellDetail.compactMap { jsonObj($0) }
            .map { jstr($0, "text").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // 第一趟: 收集全部周次对 (教师[周次] 可能同一行多对)
        var out: [(weeks: String, room: String)] = []
        for text in texts {
            for m in Self.teacherWeekMatches(in: text) {
                let weeks = m.2.trimmingCharacters(in: .whitespaces)
                if weeks.contains(where: { $0.isNumber }) { out.append((weeks, "")) }
            }
        }
        if out.isEmpty { return [] }

        // 第二趟: 地点 = 第一条不含周次方括号的文本 (BUAA 形态: cellDetail[1]
        // 为教室行; 顺序不定, 所以按"非周次行"识别而非位置)
        let room = texts.first { Self.teacherWeekMatches(in: $0).isEmpty } ?? ""
        return out.map { ($0.weeks, room) }
    }

    /// 从 cellDetail 取首位教师名 — 与 weeksAndTeachers "/" 末段并列,
    /// cellDetail 形态更可靠 (BUAA byxt 9 仓 cross-verified)。
    func extractTeacherFromCellDetail(_ cellDetail: [Any]?) -> String {
        guard let cellDetail = cellDetail, !cellDetail.isEmpty else { return "" }
        for el in cellDetail {
            guard let obj = jsonObj(el) else { continue }
            let text = jstr(obj, "text").trimmingCharacters(in: .whitespaces)
            guard let m = Self.teacherWeekMatches(in: text).first else { continue }
            return m.1.trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    /// 实验课的教师规则与上游脚本保持一致：titleDetail[1] 的第二个空白字段。
    private func extractLabTeacher(_ titleDetail: [Any]?) -> String {
        var detail = ""
        if let td = titleDetail, td.count > 1 {
            if let str = td[1] as? String { detail = str.trimmingCharacters(in: .whitespaces) }
            else if let n = td[1] as? NSNumber { detail = n.stringValue }
        }
        // ← Kotlin split(Regex("\\s+")).getOrNull(1) — 空白段切分取第 2 段
        let fields = detail.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
        return fields.count > 1 ? String(fields[1]) : ""
    }

    /// 实验课：weeksAndTeachers 取 '[' 前内容，地点取 placeName 的首段。
    private func extractLabWeeksAndRoom(
        _ obj: [String: Any],
        _ weeksAndTeachers: String
    ) -> (weeks: String, room: String) {
        let rawPlace = jstr(obj, "placeName")
        let place = rawPlace.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }).first.map(String.init) ?? ""
        let room = place.hasSuffix(")") ? "暂未安排教室" : place
        let weeks = String(weeksAndTeachers.prefix(while: { $0 != "[" })).trimmingCharacters(in: .whitespaces)
        return (weeks, room)
    }

    /// 提取单/双周限定并剥净: 返回 (parity, 已剥限定词与括号的串)。
    /// parity: 0=每周 1=单周 2=双周。线协议形态 "1-16双周" / "1-16周(双)" /
    /// "3-15周（单）" / "2-15单周" — ASCII/全角括号与"单/双"标记全部剥除。
    func extractParity(_ s: String) -> (Int, String) {
        let parity: Int
        if s.contains("单") { parity = 1 }
        else if s.contains("双") { parity = 2 }
        else { parity = 0 }
        let clean = s
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "(单)", with: "")
            .replacingOccurrences(of: "(双)", with: "")
        return (parity, clean)
    }

    /// 解析周次串 (已剥单/双标记与括号): "1-16周" / "2,4,6,8"。
    /// 形如 "X-Y周" / "X,Y,Z周"。单/双限定由 extractParity 先行剥离。
    func parseWeeks(_ s: String) -> [(Int, Int)] {
        if s.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        let clean = s
            .replacingOccurrences(of: "周", with: "")
            .replacingOccurrences(of: "单周", with: "")
            .replacingOccurrences(of: "双周", with: "")
            .replacingOccurrences(of: "单", with: "")
            .replacingOccurrences(of: "双", with: "")
            .trimmingCharacters(in: .whitespaces)
        if clean.isEmpty { return [] }
        var out: [(Int, Int)] = []
        // ← Kotlin: clean.split(",", "，", "、")
        for seg in clean.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "、" })
            .map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }) {
            if seg.contains("-") {
                let parts = seg.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard let a = Int(parts[0]) else { continue }
                let b = parts.count > 1 ? (Int(parts[1]) ?? a) : a
                out.append((a, b))
            } else if let v = Int(seg) {
                out.append((v, v))
            }
        }
        return out
    }

    var confidenceValue: Int {
        guard !source.trimmingCharacters(in: .whitespaces).isEmpty else { return 0 }
        guard let data = source.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let datas = jsonObj(root["datas"]),
              datas["arrangedList"] is [Any] else { return 0 }
        return 90
    }

    var matchedFeatureList: [String] {
        guard let data = source.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let datas = jsonObj(root["datas"]),
              datas["arrangedList"] is [Any] else { return [] }
        return ["arrangedList"]
    }

    // MARK: - `教师[周次]` 正则辅助 (← Kotlin Regex("""([^\[\]]+)\[(\d[^\]]*?周?)\]"""))

    /// 教师[周次] 对: (整段匹配, 教师组, 周次组)。惰性 `周?` 尾与 NSRegularExpression
    /// 兼容形态 ([^\\]]*? 非贪婪到右括号), 多对同行全收。
    private static let teacherWeekRegex = try! NSRegularExpression(
        pattern: "([^\\[\\]]+)\\[(\\d[^\\]]*?周?)\\]")

    static func teacherWeekMatches(in text: String) -> [(String, String, String)] {
        let ns = text as NSString
        let results = teacherWeekRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return results.map { m in
            (ns.substring(with: m.range),
             ns.substring(with: m.range(at: 1)),
             ns.substring(with: m.range(at: 2)))
        }
    }
}
