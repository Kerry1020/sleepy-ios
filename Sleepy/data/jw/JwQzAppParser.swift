// JwQzAppParser.swift — ← JwQzAppParser.kt
//
// 强智移动教务 SPA 课表 JSON 解析器 (type=qz_app)。
//
// 适配学校: 河北资源环境职业技术学院 (jwpt.hebzyhj.edu.cn:1233, 2026-09-09 学生回传
// 采集包实锤)。与其它 JwParser 子类不同: source 不是 HTML, 而是移动端 JSON API 的
// 响应体 —
//
//   POST {ApiUrl}/student/curriculum?week=&kbjcmsid=   header: token: <JWT>
//   → {"code":"1","Msg":"success~","data":[{date:[…7 天],courses:[…]}],needClassName,needClassRoomNub}
//
// 抓取方式: WebView 登录 SPA 后, JwWebViewLoginScreen 注入 QZ_APP_FETCH_JS 先 GET
// /dist/serverconfig.json (免鉴权) 发现 ApiUrl, 再带 sessionStorage.Token 请求课表;
// 结果经 __sleepyBridge.onWiseduResult({ok,data}) 桥回 (与 wisedu/NEU/CQU 同通道)。
// JS 侧只做 fetch 与透传, 禁止在 JS 里解码协议字段 (跨语言 invariant:
// 解码语义唯一落点 = 本 parser, 契约测试锁死)。
//
// 字段映射 (强智移动教务 → JwCourse):
//   courseName    → name
//   teacherName   → teacher
//   classroomNub  → room (楼-房完整房号, 回退 classroomName → location)
//   classTime     → day/startNode/endNode — 编码 = 星期+起止节, 如 "10304" =
//                   周一 3-4 节 (首位=星期 1-7, 后 4 位 = SS EE 各 2 位补零)
//   classWeek     → 周次集合 "1-4,6-19" (区间+单周混合), 带洞 → 拆连续段
//                   (整体等差 2 → 单/双周 type 1/2, 与 JwWiseduParser.weekRuns 同语义)
//
// date[] (本周 7 天 mxrq/zc) 深埋开学日期锚点, v1 不消费 (确认页手填学期开始日期,
// 与 NEU/CQU fetch 流程一致); needClassName/needClassRoomNub 为 SPA 显示开关,
// 与数据本体无关, 不消费。
//
// 未登录形态 {"code":"401","Msg":"非法访问：/student/curriculum"} → data 非数组 →
// emptyList (Registry 按 0 课空学期处理, 真实登录态由 WebView 会话保证)。

import Foundation

final class JwQzAppParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    func generateCourseList() throws -> [JwCourse] {
        guard let data = source.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        guard let arr = root["data"] as? [[String: Any]] else { return [] }
        guard let grid = arr.first, let rows = grid["courses"] as? [[String: Any]] else { return [] }

        var result: [JwCourse] = []
        for o in rows {
            func str(_ k: String) -> String {
                ((o[k] as? String) ?? (o[k] as? NSNumber)?.stringValue ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let name = str("courseName")
            if name.isEmpty { continue }
            let teacher = str("teacherName")
            let room = [str("classroomNub"), str("classroomName"), str("location")]
                .first { !$0.isEmpty } ?? ""
            guard let timeSpec = Self.parseClassTime(str("classTime")) else { continue }
            let weeks = Self.parseWeekSpec(str("classWeek").isEmpty ? str("classWeekDetails") : str("classWeek"))

            for (sw, ew, type) in Self.weekRuns(weeks) {
                result.append(JwCourse(
                    name: name,
                    room: room,
                    teacher: teacher,
                    day: timeSpec.0,
                    startNode: timeSpec.1,
                    endNode: timeSpec.2,
                    startWeek: sw,
                    endWeek: ew,
                    type: type))
            }
        }
        return result
    }

    /// classTime "10304" → (day=1, start=3, end=4)。
    /// 首位 = 星期 (1-7, 禁 0); 后 4 位 = 起止节各 2 位补零; 非数字/长度不足 → nil。
    static func parseClassTime(_ v: String) -> (Int, Int, Int)? {
        let chars = Array(v)
        if chars.count != 3 && chars.count != 5 { return nil }
        if chars.contains(where: { $0 < "0" || $0 > "9" }) { return nil }
        let day = Int(String(chars[0]))!
        if !(1...7).contains(day) { return nil }
        guard let start = Int(v[v.index(v.startIndex, offsetBy: 1)..<v.index(v.startIndex, offsetBy: 3)]) else { return nil }
        let end: Int
        if chars.count == 5 {
            guard let e = Int(v.suffix(2)) else { return nil }
            end = e
        } else {
            end = start
        }
        if start < 1 || end < start { return nil }
        return (day, start, end)
    }

    /// 周次集合 "1-4,6-19" → 周次列表。区间 "a-b" + 单周 "a" 混合; 域外/非法 token 忽略。
    /// classWeek 为空时回退 classWeekDetails 逗号位图串 (",1,2,3,…")。
    static func parseWeekSpec(_ spec: String) -> [Int] {
        var weeks = Set<Int>()
        for token in spec.components(separatedBy: ",") {
            let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            if let r = t.range(of: #"^(\d+)-(\d+)$"#, options: .regularExpression) {
                _ = r
                let parts = t.components(separatedBy: "-")
                guard let lo = Int(parts[0]), let hi = Int(parts[1]) else { continue }
                if (1...30).contains(lo) && (lo...30).contains(hi) {
                    for w in lo...hi { weeks.insert(w) }
                }
            } else if t.range(of: #"^(\d+)$"#, options: .regularExpression) != nil,
                      let one = Int(t), (1...30).contains(one) {
                weeks.insert(one)
            }
        }
        return weeks.sorted()
    }

    /// 周次列表 → 连续段 [(startWeek, endWeek, type)]。语义与 JwWiseduParser.weekRuns
    /// 一致: 单一连续段 → type=0; 整体等差 step=2 → 单周(1)/双周(2); 多段 → 逐段 type=0。
    static func weekRuns(_ weeks: [Int]) -> [(Int, Int, Int)] {
        if weeks.isEmpty { return [] }
        var runs: [(Int, Int)] = []
        var start = weeks[0]
        var prev = weeks[0]
        for w in weeks.dropFirst() {
            if w == prev + 1 {
                prev = w
            } else {
                runs.append((start, prev))
                start = w
                prev = w
            }
        }
        runs.append((start, prev))
        if runs.count == 1 { return [(runs[0].0, runs[0].1, 0)] }
        if weeks.count >= 2 && (1..<weeks.count).allSatisfy({ weeks[$0] - weeks[$0 - 1] == 2 }) {
            let type = weeks.first! % 2 == 1 ? 1 : 2
            return [(weeks.first!, weeks.last!, type)]
        }
        return runs.map { ($0.0, $0.1, 0) }
    }

    var confidenceValue: Int {
        if source.contains("\"classWeekDetails\"") && source.contains("\"classTime\"") { return 90 }
        if source.contains("\"classWeek\"") && source.contains("\"classTime\"") { return 85 }
        return 0
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains("\"classWeekDetails\"") { out.append("classWeekDetails") }
        if source.contains("\"classTime\"") { out.append("classTime") }
        if source.contains("\"courses\":[") { out.append("courses[]") }
        if source.contains("\"code\"") && source.contains("\"Msg\"") { out.append("code/Msg envelope") }
        return out
    }
}
