// SchoolLocationLookup.swift — ← data/jw/SchoolLocationLookup.kt
// Provider race independent of platform APIs, including cancellation and city quality checks.
//
// iOS 适配: Kotlin coroutineScope/Channel → Swift async/await + TaskGroup。
// 语义 1:1 — 先用缓存的可用 fix(按年龄→精度排序), 再等并发请求的 fix;
// 每个结果都过 usable 质量闸 + city 8 方向采样; 拒绝原因记入 rejected,
// 全部失败时返回最具体的拒绝原因。

import Foundation

enum SchoolLocationState: Equatable {
    case idle
    case locating
    case ready(city: String)
    case permissionDenied
    case accuracyInsufficient
    case locationDisabled
    case positionUnavailable
    case unavailable
}

enum SchoolLocationLookup {

    static func findCity(
        mode: SchoolLocationMode,
        availableProviders: [String],
        cached: [SchoolLocationFix],
        loadIndex: @escaping () async -> OfflineSchoolCityIndex?,
        requestFix: @escaping (_ provider: String) async -> SchoolLocationFix?
    ) async -> SchoolLocationState {
        let providers = SchoolLocationPolicy.providers(mode: mode, available: availableProviders)
        if providers.isEmpty { return .positionUnavailable }

        // 索引加载与定位请求并发
        let indexTask = Task.detached(priority: .userInitiated) {
            await loadIndex()
        }
        // 每个 provider 一个并发请求; 错误吞成 nil(与 Android catch → null 一致)
        let requestTasks = providers.map { provider in
            Task.detached(priority: .userInitiated) {
                await requestFix(provider)
            }
        }

        guard let index = await indexTask.value else {
            requestTasks.forEach { $0.cancel() }
            return .unavailable
        }

        // 拒绝原因跟踪: accuracyInsufficient > unavailable > positionUnavailable
        var rejected = SchoolLocationState.positionUnavailable

        func resolve(_ fix: SchoolLocationFix?) -> SchoolLocationState? {
            guard let fix = fix else { return nil }
            if !SchoolLocationPolicy.usable(mode: mode, fix: fix) {
                if fix.ageNanos >= 0 && fix.ageNanos <= 30_000_000_000 {
                    rejected = .accuracyInsufficient
                }
                return nil
            }
            let cityFix = SchoolLocationPolicy.forCityLookup(mode: mode, fix: fix)
            if let city = SchoolLocationPolicy.city(index: index, fix: cityFix) {
                return .ready(city: city)
            }
            if index.cityAt(latitude: cityFix.latitude, longitude: cityFix.longitude) != nil {
                rejected = .accuracyInsufficient
            } else if case .accuracyInsufficient = rejected {
                // keep
            } else {
                rejected = .unavailable
            }
            return nil
        }

        // 1. 先扫缓存 (年龄升序 → 精度升序)
        let recent = cached
            .filter { SchoolLocationPolicy.usable(mode: mode, fix: $0) }
            .sorted { a, b in
                if a.ageNanos != b.ageNanos { return a.ageNanos < b.ageNanos }
                return a.accuracyMeters < b.accuracyMeters
            }
        for fix in recent {
            if let result = resolve(fix) {
                requestTasks.forEach { $0.cancel() }
                return result
            }
        }
        // 2. 再等并发请求结果 (按 provider 顺序收)
        for task in requestTasks {
            let fix = await task.value
            if let result = resolve(fix) {
                requestTasks.forEach { $0.cancel() }
                return result
            }
        }
        return rejected
    }
}
