// SchoolCityIndex.swift — ← data/jw/SchoolCityIndex.kt (v1.0.60)
// 城市元数据与导入目录分离 — 解析结果只影响推荐卡, 不能改变 URL 或协议。

import Foundation

// ← object SchoolCityIndex
enum SchoolCityIndex {
    /// school_cities.json → 城市 → 校名列表(过滤空白项)。 ← parse
    static func parse(_ text: String) -> [String: [String]] {
        guard let data = text.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let schools = root["schools"] as? [String: Any] else { return [:] }
        var result: [String: [String]] = [:]
        for (name, value) in schools {
            guard let cities = value as? [String] else { continue }
            result[name] = cities.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        return result
    }

    /// 去尾"市" + 去首尾空白 — "哈尔滨市"/"哈尔滨" 归一。 ← normalizeCity
    static func normalizeCity(_ city: String) -> String {
        var c = city.trimmingCharacters(in: .whitespaces)
        if c.hasSuffix("市") { c.removeLast() }
        return c
    }

    /// 同城学校: 过滤 → 校名去重 → 不支持靠后 → sortKeyFull(缺省 name)升序。 ← schoolsInCity
    static func schoolsInCity(_ schools: [JwSchoolInfo], city: String) -> [JwSchoolInfo] {
        let normalized = normalizeCity(city)
        if normalized.isEmpty { return [] }
        var seen = Set<String>()
        return schools
            .filter { school in school.cities.contains { normalizeCity($0) == normalized } }
            .filter { seen.insert($0.name).inserted }
            .sorted { a, b in
                if a.isSupported != b.isSupported { return a.isSupported }
                return (a.sortKeyFull.isEmpty ? a.name : a.sortKeyFull)
                    < (b.sortKeyFull.isEmpty ? b.name : b.sortKeyFull)
            }
    }
}
