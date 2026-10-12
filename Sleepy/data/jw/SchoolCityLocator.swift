// SchoolLocationLookup.swift — ← data/jw/SchoolLocationLookup.kt (v1.0.60) + SchoolCityLocator.kt
// 单次用户发起的前台定位查找。坐标绝不存储、绝不记日志。
// 平台映射: Android LocationManager providers → iOS CLLocationManager 单一 provider;
// 缓存 fix = manager.getLastKnownLocation → CLLocation(新鲜时)。

import Foundation
import CoreLocation

// ← sealed interface SchoolLocationState
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

// ← object SchoolLocationLookup(provider race 与城市质量检查, 与平台 API 解耦)
enum SchoolLocationLookup {
    static func findCity(
        mode: SchoolLocationMode,
        availableProviders: [String],
        cached: [SchoolLocationFix],
        loadIndex: @escaping () async -> OfflineSchoolCityIndex?,
        requestFix: @escaping (String) async -> SchoolLocationFix?
    ) async -> SchoolLocationState {
        let providers = SchoolLocationPolicy.providers(mode, available: availableProviders)
        if providers.isEmpty { return .positionUnavailable }
        async let indexRequest = loadIndex()
        // 顺序消费各 provider 的结果(Android 端为并发竞态, iOS 单 provider 场景顺序等价)
        let index = await indexRequest
        guard let index else { return .unavailable }
        var rejected: SchoolLocationState = .positionUnavailable
        func resolve(_ fix: SchoolLocationFix?) -> SchoolLocationState? {
            guard let fix else { return nil }
            if !SchoolLocationPolicy.usable(mode, fix) {
                if (0...SchoolLocationPolicy.maxAgeNanos).contains(fix.ageNanos) {
                    rejected = .accuracyInsufficient
                }
                return nil
            }
            let cityFix = SchoolLocationPolicy.forCityLookup(mode, fix)
            if let city = SchoolLocationPolicy.city(index, cityFix) { return .ready(city: city) }
            if index.cityAt(latitude: cityFix.latitude, longitude: cityFix.longitude) != nil {
                rejected = .accuracyInsufficient
            } else if rejected != .accuracyInsufficient {
                rejected = .unavailable
            }
            return nil
        }
        // ← 缓存的 fix 按新到旧、精度好到差排序后先试
        let recent = cached
            .filter { SchoolLocationPolicy.usable(mode, $0) }
            .sorted { a, b in
                if a.ageNanos != b.ageNanos { return a.ageNanos < b.ageNanos }
                return a.accuracyMeters < b.accuracyMeters
            }
        for fix in recent {
            if let ready = resolve(fix) { return ready }
        }
        for provider in providers {
            let fix = await requestFix(provider)
            if let ready = resolve(fix) { return ready }
        }
        return rejected
    }
}

// ← class SchoolCityLocator(平台桥接: CoreLocation 版)
final class SchoolCityLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    /// 测试注入: 非 nil 时完全绕过 CoreLocation
    var testHook: ((SchoolLocationMode) async -> SchoolLocationState)? = nil

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    // ← requestLocation(): launcher.launch 等价 — 未决定时弹系统授权框,
    //   授权变更回调里一次性触发 completion(granted); 已授权/已拒绝立即回调。
    //   Android launcher 回调 granted → locateSchoolCity; iOS 由调用方完成同样接线。
    private let authLock = NSLock()
    private var authCompletion: ((Bool) -> Void)? = nil

    func requestPermission(completion: ((Bool) -> Void)? = nil) {
        authLock.lock()
        authCompletion = completion ?? authCompletion
        authLock.unlock()
        manager.requestWhenInUseAuthorization()
    }

    // iOS 14+ 授权状态变更(含 delegate 初始回调): 有 pending 回调才上报, 一次性消费
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authLock.lock()
        let pending = authCompletion
        authCompletion = nil
        authLock.unlock()
        guard let pending else { return }
        let s = manager.authorizationStatus
        pending(s == .authorizedWhenInUse || s == .authorizedAlways)
    }

    // ← locate()
    func locate() async -> SchoolLocationState {
        // ← modeForPermissions: iOS 无 fine/coarse 授权细分, 授权即 precise
        let status = manager.authorizationStatus
        let coarse = status == .authorizedAlways || status == .authorizedWhenInUse
        guard let mode = SchoolLocationPolicy.modeForPermissions(coarse: coarse, fine: coarse) else {
            return .permissionDenied
        }
        if await MainActor.run(body: { CLLocationManager.locationServicesEnabled() }) == false {
            return .locationDisabled
        }
        if let hook = testHook { return await hook(mode) }
        let providers = SchoolLocationPolicy.providers(mode, available: ["gps"])
        let cached = Self.cachedFix()
        return await withTimeout(nanoseconds: 12_000_000_000) {
            await SchoolLocationLookup.findCity(
                mode: mode,
                availableProviders: providers,
                cached: cached,
                loadIndex: { await Self.offlineIndex() },
                requestFix: { [weak self] _ in await self?.requestFix() ?? nil })
        } ?? .positionUnavailable
    }

    // ← cancelSchoolLocation 由 ViewModel 层调 Task.cancel; 取消/超时时续体必须安全结束
    private let continuationLock = NSLock()
    private var continuation: CheckedContinuation<SchoolLocationFix?, Never>? = nil

    private func takeContinuation() -> CheckedContinuation<SchoolLocationFix?, Never>? {
        continuationLock.lock()
        defer { continuationLock.unlock() }
        let pending = continuation
        continuation = nil
        return pending
    }

    private func requestFix() async -> SchoolLocationFix? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<SchoolLocationFix?, Never>) in
                continuationLock.lock()
                // 取消可能发生在处理器注册之前
                if Task.isCancelled {
                    continuationLock.unlock()
                    cont.resume(returning: nil)
                    return
                }
                continuation = cont
                continuationLock.unlock()
                manager.requestLocation()
            }
        } onCancel: {
            if let pending = takeContinuation() { pending.resume(returning: nil) }
        }
    }

    // CLLocationManagerDelegate: 一次性续体(取出即清空, 天然防双 resume)
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let cont = takeContinuation() else { return }
        guard let location = locations.last else { cont.resume(returning: nil); return }
        let fix = SchoolLocationFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracyMeters: location.horizontalAccuracy,
            ageNanos: Int64(-location.timestamp.timeIntervalSinceNow * 1_000_000_000))
        cont.resume(returning: fix)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let cont = takeContinuation() else { return }
        cont.resume(returning: nil)
    }

    // ← getLastKnownLocation 等价: 系统缓存位置(30 秒内才可用)
    static func cachedFix() -> [SchoolLocationFix] {
        guard let location = CLLocationManager().location else { return [] }
        let age = Int64(-location.timestamp.timeIntervalSinceNow * 1_000_000_000)
        return [SchoolLocationFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracyMeters: location.horizontalAccuracy,
            ageNanos: age)]
    }

    // ← offlineIndex(): 单例缓存, gz → SCB1 流式解析
    // Swift 5.8 无 nonisolated(unsafe): 静态可变状态一律经 indexLock 访问(快路径也加锁)。
    private static let indexLock = NSLock()
    private static var cachedIndex: OfflineSchoolCityIndex?

    static func offlineIndex() async -> OfflineSchoolCityIndex? {
        indexLock.lock()
        if let cached = cachedIndex {
            indexLock.unlock()
            return cached
        }
        indexLock.unlock()
        return await Task.detached(priority: .userInitiated) {
            indexLock.lock()
            defer { indexLock.unlock() }
            if let cached = cachedIndex { return cached }
            guard let url = Bundle.main.url(forResource: "school_city_boundaries.bin", withExtension: "gz")
                ?? Bundle.main.url(forResource: "school_city_boundaries.bin", withExtension: nil),
                  let data = try? Data(contentsOf: url) else { return nil }
            guard let parsed = try? OfflineSchoolCityIndex.parseGzip(data) else { return nil }
            cachedIndex = parsed
            return parsed
        }.value
    }

    // ← withTimeoutOrNull(12s)
    // 超时/外层取消/正常结果 三方竞争同一续体 — TimeoutGate 保证只 resume 一次。
    private final class TimeoutGate {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<SchoolLocationState?, Never>? = nil
        private var worker: Task<Void, Never>? = nil
        private var done = false

        func begin(_ cont: CheckedContinuation<SchoolLocationState?, Never>,
                   nanoseconds: UInt64,
                   body: @escaping () async -> SchoolLocationState) {
            lock.lock()
            if done {  // 取消发生在 begin 之前
                lock.unlock()
                cont.resume(returning: nil)
                return
            }
            continuation = cont
            let w = Task { [weak self] in
                let result = await body()
                self?.finish(with: result)
            }
            worker = w
            lock.unlock()
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: nanoseconds)
                self?.finish(with: nil)  // 超时 = 取消
            }
        }

        func cancel() { finish(with: nil) }

        private func finish(with value: SchoolLocationState?) {
            lock.lock()
            if done {
                lock.unlock()
                return
            }
            done = true
            let cont = continuation
            let w = worker
            continuation = nil
            worker = nil
            lock.unlock()
            w?.cancel()
            cont?.resume(returning: value)
        }
    }

    private func withTimeout(nanoseconds: UInt64, _ body: @escaping () async -> SchoolLocationState) async -> SchoolLocationState? {
        let gate = TimeoutGate()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<SchoolLocationState?, Never>) in
                gate.begin(cont, nanoseconds: nanoseconds, body: body)
            }
        } onCancel: {
            gate.cancel()
        }
    }
}

