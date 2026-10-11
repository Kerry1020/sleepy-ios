// SchoolLocationPolicy.swift — ← data/jw/SchoolLocationPolicy.kt (v1.0.60)
// 定位质量策略(纯逻辑, 无平台 API): 权限→模式、可用 provider 过滤、
// fix 有效性、近似模式降精度、8 方向不确定性采样消边界歧义。

import Foundation

// ← enum SchoolLocationMode
enum SchoolLocationMode {
    case precise
    case approximate
}

// ← data class SchoolLocationFix(瞬时样本, 绝不持久化; age 用单调时钟)
struct SchoolLocationFix {
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double
    let ageNanos: Int64
}

// ← object SchoolLocationPolicy
enum SchoolLocationPolicy {
    static let maxAgeNanos: Int64 = 30 * 1_000_000_000

    // ← modeForPermissions
    static func modeForPermissions(coarse: Bool, fine: Bool) -> SchoolLocationMode? {
        if !coarse { return nil }
        return fine ? .precise : .approximate
    }

    // ← providers: 排除 passive; 近似模式再排除 gps
    static func providers(_ mode: SchoolLocationMode, available: [String]) -> [String] {
        available.filter { $0 != "passive" && (mode == .precise || $0 != "gps") }.deduplicated()
    }

    // ← usable: 缓存的与新请求的 fix 共用质量检查
    static func usable(_ mode: SchoolLocationMode, _ fix: SchoolLocationFix) -> Bool {
        fix.latitude.isFinite && (-90.0...90.0).contains(fix.latitude) &&
            fix.longitude.isFinite && (-180.0...180.0).contains(fix.longitude) &&
            (0...maxAgeNanos).contains(fix.ageNanos) && fix.accuracyMeters.isFinite &&
            fix.accuracyMeters > 0 &&
            fix.accuracyMeters <= (mode == .precise ? 1_000.0 : 10_000.0)
    }

    // ← forCityLookup: 更早的 fine 授权不得让近似选择使用精细坐标
    static func forCityLookup(_ mode: SchoolLocationMode, _ fix: SchoolLocationFix) -> SchoolLocationFix {
        guard mode != .precise else { return fix }
        return SchoolLocationFix(
            latitude: (fix.latitude * 100).rounded() / 100,
            longitude: (fix.longitude * 100).rounded() / 100,
            accuracyMeters: fix.accuracyMeters + 800.0,
            ageNanos: fix.ageNanos)
    }

    // ← city: 8 方向采样报告的不确定性范围,任一方向出城即放弃
    static func city(_ index: OfflineSchoolCityIndex, _ fix: SchoolLocationFix) -> String? {
        guard let c = index.cityAt(latitude: fix.latitude, longitude: fix.longitude) else { return nil }
        let latitudeRadius = fix.accuracyMeters / 111_320.0
        let longitudeRadius = latitudeRadius / max(cos(fix.latitude * .pi / 180), 0.01)
        for step in 0..<8 {
            let angle = Double(step) * .pi / 4
            if index.cityAt(latitude: fix.latitude + latitudeRadius * sin(angle),
                            longitude: fix.longitude + longitudeRadius * cos(angle)) != c { return nil }
        }
        return c
    }
}

extension Array where Element == String {
    // ← .distinct()
    func deduplicated() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
