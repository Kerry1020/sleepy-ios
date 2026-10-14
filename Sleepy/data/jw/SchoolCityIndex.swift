// SchoolCityIndex.swift — ← data/jw/SchoolCityIndex.kt
// City metadata is separate from the import directory, so it cannot alter URLs or protocols.

import Foundation

enum SchoolCityIndex {
    /// 解析 school_cities.json → 学校名 → 城市列表。
    static func parse(_ text: String) throws -> [String: [String]] {
        guard let data = text.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schools = root["schools"] as? [String: Any] else {
            return [:]
        }
        var out: [String: [String]] = [:]
        for (name, raw) in schools {
            if let cities = raw as? [String] {
                out[name] = cities.filter { !$0.isBlank }
            }
        }
        return out
    }

    /// 城市名归一: 去首尾空白 + 去"市"后缀。
    static func normalizeCity(_ city: String) -> String {
        return city.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "市", with: "", options: .backwards, range: nil)
    }

    /// 同城学校列表 — 按 supported 优先 + sortKeyFull 字典序。
    /// normalizeCity 后缀"市"的剥离是单向的: "北京市"→"北京", "北京"→"北京"。
    static func schoolsInCity(_ schools: [JwSchoolInfo], city: String) -> [JwSchoolInfo] {
        let normalized = normalizeCity(city)
        if normalized.isEmpty { return [] }
        var seen = Set<String>()
        let matched = schools.filter { school in
            guard !seen.contains(school.name) else { return false }
            if school.cities.contains(where: { normalizeCity($0) == normalized }) {
                seen.insert(school.name)
                return true
            }
            return false
        }
        return matched.sorted { a, b in
            if a.isSupported != b.isSupported { return a.isSupported }
            let ka = a.sortKeyFull.isEmpty ? a.name : a.sortKeyFull
            let kb = b.sortKeyFull.isEmpty ? b.name : b.sortKeyFull
            return ka < kb
        }
    }
}
