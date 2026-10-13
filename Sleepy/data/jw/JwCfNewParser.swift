// JwCfNewParser.swift — ← JwCfNewParser.kt
//
// 新青果 NTSS (FullCalendar 形态) 课表 JSON 解析器 (type=cf_new)。
//
// 适配学校:江西中医药大学 (jiaowu.jxutcm.edu.cn, 2026-09 采集包实锤)。
//
// source 是抓取侧 (CF_NEW_FETCH_JS) 组装的组合 JSON 信封 —
//   {
//     "sleepyCfNtss": true, "xnxqdm":"202601", "startDate":"2026-09-07",
//     "weeks": [{"week": 1, "rows": [{...}]}, ...],
//     "periods": [{"node": 1, "start": "08:30", "end": "09:10"}, ...]
//   }
//
// rows 为 POST /new/student/xsgrkb/getCalendarWeekDatas 原始行(JS 只透传不解码,跨语言 invariant)。
// 字段语义(2026-09-16 真实响应实锚):
//   kcmc=课名  teaxms=教师  jxcdmc=教学场地  xq=星期(1-7)
//   ps/pe=起止节(零填充且可为空串,空串时以行内 qssj/jssj 对 periods 节次时间反推节点)
//   zc=单周次("2",与所在请求周一致 — 全学期周次归属由逐周请求的 week 决定;
//        兼容旧假设的全学期串形态:zc 展开多于 1 个周次时以其为准)
//   kcbh=课号  jxbmc=教学班  bapjxcd='1'=排课不用场地(jxcdmc 空)
//
// 抓取侧优先单请求全量(zc 空时服务端回整学期,bucket week=0):同一门课在其 occurring
// 的每周各有一行,本 parser 按唯一键 (kcbh|kcmc|teaxms|jxcd|xq|ps|pe|jxbmc) 聚合
// 合并周次集合,周次归属优先取行自身 zc(两种形态下都正确),缺失才回退所在请求周;
// 复用 JwChengFangParser.weekIntList2WeekBeanList 折叠为 (start, end, type) 三元组。

import Foundation

final class JwCfNewParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    private struct Period {
        let node: Int
        let start: String
        let end: String
    }

    private struct Acc {
        let name: String
        let room: String
        let teacher: String
        let day: Int
        let startNode: Int
        let endNode: Int
        var weeks: [Int]
    }

    // MARK: - T8

    func generateCourseList() throws -> [JwCourse] {
        guard let data = source.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let weeksArr = root["weeks"] as? [[String: Any]] else {
            return []
        }

        let periods = parsePeriods(root["periods"] as? [[String: Any]])

        // 两遍扫描。第一遍: 收集全部行 + 从行自身派生 节次时间→节点 回退映射 —
        // ps/pe 空串的行(如 操作系统)依赖 periods (businessHours) 反推, 但真机上
        // 该变量可能抠不到; 此时用同响应里带 ps+qssj / pe+jssj 的行锚定时间→节点。
        var flatRows: [(o: [String: Any], bucketWeekNo: Int)] = []
        var startByTime: [String: Int] = [:]
        var endByTime: [String: Int] = [:]
        for week in weeksArr {
            let weekNo = (week["week"] as? Int) ?? 0
            guard let rows = week["rows"] as? [[String: Any]] else { continue }
            for o in rows {
                flatRows.append((o, weekNo))
                let qssj = normTime((o["qssj"] as? String) ?? "")
                if let ps = (o["ps"] as? String).flatMap({ s -> Int? in Int(s.trimmingCharacters(in: .whitespaces)) }), !qssj.isEmpty {
                    if startByTime[qssj] == nil { startByTime[qssj] = ps }
                }
                let jssj = normTime((o["jssj"] as? String) ?? "")
                if let pe = (o["pe"] as? String).flatMap({ s -> Int? in Int(s.trimmingCharacters(in: .whitespaces)) }), !jssj.isEmpty {
                    if endByTime[jssj] == nil { endByTime[jssj] = pe }
                }
            }
        }

        var acc: [String: Acc] = [:]
        for (o, weekNo) in flatRows {
            guard let nameRaw = (o["kcmc"] as? String) else { continue }
            let name = nameRaw.trimmingCharacters(in: .whitespaces)
            if name.isEmpty { continue }
            let teacher = (o["teaxms"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let roomRaw = (o["jxcdmc"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let room: String
            if roomRaw.isEmpty {
                if (o["bapjxcd"] as? String ?? "") == "1" { room = "不用场地" } else { room = "" }
            } else { room = roomRaw }
            guard let day = Int((o["xq"] as? String ?? "").trimmingCharacters(in: .whitespaces)) else { continue }

            let qssjN = normTime((o["qssj"] as? String) ?? "")
            let jssjN = normTime((o["jssj"] as? String) ?? "")
            guard let startNode = intField(o["ps"]) ?? periods.first(where: { $0.start == qssjN })?.node ?? startByTime[qssjN] else { continue }
            let endNode = intField(o["pe"])
                ?? periods.first(where: { $0.end == jssjN })?.node
                ?? endByTime[jssjN]
                ?? startNode
            let endNodeCo = max(endNode, startNode)

            let zcList = Self.parseWeekList((o["zc"] as? String) ?? "")
            let addWeeks: [Int]
            if zcList.count > 1 { addWeeks = zcList }
            else if zcList.count == 1 { addWeeks = [zcList[0]] }
            else if weekNo >= 1 { addWeeks = [weekNo] }
            else { continue }
            if addWeeks.isEmpty { continue }

            let key = [
                (o["kcbh"] as? String ?? ""), name, teacher, room,
                String(day), String(startNode), String(endNodeCo),
                (o["jxbmc"] as? String ?? "")
            ].joined(separator: "|")

            if var existing = acc[key] {
                existing.weeks.append(contentsOf: addWeeks)
                acc[key] = existing
            } else {
                acc[key] = Acc(name: name, room: room, teacher: teacher, day: day,
                               startNode: startNode, endNode: endNodeCo, weeks: addWeeks)
            }
        }

        var result: [JwCourse] = []
        for a in acc.values {
            let sorted = Array(Set(a.weeks)).sorted()
            for wb in JwChengFangParser.weekIntList2WeekBeanList(sorted) {
                result.append(JwCourse(
                    name: a.name,
                    room: a.room,
                    teacher: a.teacher,
                    day: max(1, min(a.day, 7)),
                    startNode: max(1, a.startNode),
                    endNode: max(a.startNode, a.endNode),
                    startWeek: max(1, wb.0),
                    endWeek: max(wb.0, wb.1),
                    type: wb.2
                ))
            }
        }
        return result
    }

    private func parsePeriods(_ arr: [[String: Any]]?) -> [Period] {
        guard let arr = arr else { return [] }
        var list: [Period] = []
        for o in arr {
            guard let node = o["node"] as? Int, node >= 1 else { continue }
            list.append(Period(node: node,
                               start: normTime((o["start"] as? String) ?? ""),
                               end: normTime((o["end"] as? String) ?? "")))
        }
        return list
    }

    /// "10:15:00"/"10:15" → "10:15" (小时位补零, 兼容 periods 与行内时间格式差异)
    private func normTime(_ t: String) -> String {
        let parts = t.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count >= 2 else { return t.trimmingCharacters(in: .whitespaces) }
        guard let h = Int(parts[0].trimmingCharacters(in: .whitespaces)) else {
            return t.trimmingCharacters(in: .whitespaces)
        }
        let m = String(parts[1])
        let mFmt = m.count == 1 ? "0\(m)" : String(m.prefix(2))
        return String(format: "%02d:%@", h, mFmt)
    }

    /**
     * 周次串 → 周次列表。逗号分隔的数字为主形态("1,2,3"),
     * 兼容区间段("1-16")与混合("1-8,10,12-16");非法 token 跳过。
     */
    /// JSON 字段读取为 Int: NSNumber 直接转,字符串 trim 后 parse。
    private func intField(_ v: Any?) -> Int? {
        if let n = v as? Int { return n }
        if let s = v as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func parseWeekList(_ zcs: String) -> [Int] {
        let rangeRe = try! NSRegularExpression(pattern: "^(\\d+)\\s*[-~—]\\s*(\\d+)$", options: [])
        var result: [Int] = []
        for tok in zcs.split(separator: ",") {
            let t = tok.trimmingCharacters(in: .whitespaces)
            let nsRange = NSRange(t.startIndex..., in: t)
            if let m = rangeRe.firstMatch(in: t, options: [], range: nsRange) {
                let ns = t as NSString
                guard let a = Int(ns.substring(with: m.range(at: 1))),
                      let b = Int(ns.substring(with: m.range(at: 2))) else { continue }
                if a <= b { result.append(contentsOf: a...b) }
            } else if let n = Int(t) {
                result.append(n)
            }
        }
        return result.filter { $0 >= 1 }
    }

    // MARK: - T9

    var confidenceValue: Int {
        if !source.contains("sleepyCfNtss") { return 0 }
        let hasFields = source.contains("kcmc") && source.contains("\"zc\"")
        return hasFields ? 100 : 70
    }

    var matchedFeatureList: [String] {
        if !source.contains("sleepyCfNtss") { return [] }
        var out: [String] = ["sleepyCfNtss"]
        if source.contains("weeks") { out.append("weeks") }
        if source.contains("kcmc") { out.append("字段=kcmc") }
        if source.contains("teaxms") { out.append("字段=teaxms") }
        if source.contains("jxcdmc") { out.append("字段=jxcdmc") }
        if source.contains("\"ps\"") && source.contains("\"pe\"") { out.append("字段=ps/pe") }
        return out
    }
}