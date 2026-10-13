// PeriodHeaderFormatter.swift — ← util/PeriodHeaderFormatter.kt 逐行翻译 (GPL-3.0)
// 只做可配置的左侧节次表头格式化, 不改课程数据。

import Foundation

enum PeriodHeaderFormatter {
    private static let chinese = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二", "十三", "十四", "十五", "十六"]
    private static let financial = ["壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖", "拾", "拾壹", "拾贰", "拾叁", "拾肆", "拾伍", "拾陆"]
    private static let circled = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩", "⑪", "⑫", "⑬", "⑭", "⑮", "⑯"]

    static func label(_ node: Int, _ style: String) -> String {
        func pick(_ arr: [String]) -> String {
            (node >= 1 && node <= arr.count) ? arr[node - 1] : String(node)
        }
        switch style {
        case "chinese": return pick(chinese)
        case "financial": return pick(financial)
        case "circled": return pick(circled)
        case "roman": return roman(node)
        default: return String(node)
        }
    }

    static func range(_ start: Int, _ end: Int, _ style: String) -> String {
        if start == end { return label(start, style) }
        let separator = "-"
        let suffix = style == "arabic" ? "节" : ""
        return "\(label(start, style))\(separator)\(label(end, style))\(suffix)"
    }

    static func fullLabel(_ node: Int, _ style: String) -> String {
        "第\(label(node, style))节"
    }

    private static func roman(_ number: Int) -> String {
        let compact = ["", "Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ", "Ⅶ", "Ⅷ", "Ⅸ", "Ⅹ", "Ⅺ", "Ⅻ"]
        if number >= 1 && number <= 12 { return compact[number] }
        if number < 1 || number > 39 { return String(number) }
        let values: [(Int, String)] = [(10, "Ⅹ"), (9, "Ⅸ"), (5, "Ⅴ"), (4, "Ⅳ"), (1, "Ⅰ")]
        var remaining = number
        var out = ""
        for (value, glyph) in values {
            while remaining >= value {
                out += glyph
                remaining -= value
            }
        }
        return out
    }
}
