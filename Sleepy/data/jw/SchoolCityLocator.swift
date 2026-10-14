// SchoolCityLocator.swift — ← data/jw/SchoolCityLocator.kt
// One user-initiated foreground lookup. Coordinates are never stored or logged.
//
// iOS 适配 (CoreLocation):
//   - Android ACCESS_COARSE/FINE → iOS whenInUse authorization + desiredAccuracy
//   - LocationManager providers → CLLocationManager 单一源, 用 desiredAccuracy 语义
//     区分 precise (kCLLocationAccuracyBest) / approximate (kCLLocationAccuracyKilometer);
//     providers 列表对 Android 契约保留 "gps"/"network" 名以复用 SchoolLocationPolicy
//   - getLastKnownLocation → CLLocationManager.location (最后一次 fix)
//   - getCurrentLocation + CancellationSignal → requestLocation + continuation
//   - SystemClock.elapsedRealtimeNanos → systemUptime (ProcessInfo.systemUptime)
//   - 12s 超时 → withTimeout 自实现 (Task sleep race)

import Foundation
import CoreLocation

final class SchoolCityLocator: NSObject, CLLocationManagerDelegate {

    private let locationManager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    // MARK: - callback 式授权 (SchoolSelectScreen 用 — 授权回调里直接续定位)

    private var permissionCompletion: ((Bool) -> Void)?

    /// 请求 WhenInUse 授权; 已授权则 completion(true) 同步回调。
    /// completion 传 nil = 清掉滞留回调(onDisappear 防泄漏)。
    func requestPermission(completion: ((Bool) -> Void)?) {
        guard let completion = completion else {
            permissionCompletion = nil
            return
        }
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            completion(true)
        case .notDetermined:
            permissionCompletion = completion
            locationManager.requestWhenInUseAuthorization()
        default:
            completion(false)
        }
    }

    /// 单次前台定位 → 城市。坐标永不落盘、永不记日志。
    func locate() async -> SchoolLocationState {
        // 权限模式判定 — coarse/在 iOS 端 = whenInUse 已授权;fine = 也只有 whenInUse
        // (iOS 无 coarse/fine 二分; 精度由 desiredAccuracy 决定)
        let status = await authorizationStatus()
        let granted: Bool
        if #available(iOS 14.0, *) {
            granted = status == .authorizedWhenInUse || status == .authorizedAlways
        } else {
            granted = status == .authorizedWhenInUse || status == .authorizedAlways
        }
        guard granted else {
            return .permissionDenied
        }
        // iOS: 已授权即视为两档都有 — mode 走 precise(用户授权定位时 iOS 系统给到设备精度)
        let mode = SchoolLocationMode.precise

        guard CLLocationManager.locationServicesEnabled() else {
            return .locationDisabled
        }

        // 12s 超时 — 与 Android withTimeoutOrNull(12_000) 1:1
        return await withTimeout(seconds: 12) {
            await self.findCity(mode: mode)
        } ?? .positionUnavailable
    }

    // MARK: - 定位到城市

    private func findCity(mode: SchoolLocationMode) async -> SchoolLocationState {
        // providers — Android 契约名; iOS CLLocationManager 是单一源
        let providers = ["gps", "network"]
        let cached: [SchoolLocationFix] = {
            guard let last = locationManager.location else { return [] }
            return [last.toFix()]
        }()
        return await SchoolLocationLookup.findCity(
            mode: mode,
            availableProviders: providers,
            cached: cached,
            loadIndex: { await self.offlineIndex() },
            requestFix: { _ in
                await self.requestOneFix()
            }
        )
    }

    private func requestOneFix() async -> SchoolLocationFix? {
        let location = await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
            self.locationContinuation = continuation
            self.locationManager.desiredAccuracy =
                kCLLocationAccuracyNearestTenMeters
            self.locationManager.requestLocation()
        }
        return location?.toFix()
    }

    private func authorizationStatus() async -> CLAuthorizationStatus {
        // 未决策时等回调; 已决策直接返回
        let current: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            current = locationManager.authorizationStatus
        } else {
            current = CLLocationManager.authorizationStatus()
        }
        if current == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            return await withCheckedContinuation { continuation in
                self.authorizationContinuation = continuation
            }
        }
        return current
    }

    private func offlineIndex() async -> OfflineSchoolCityIndex? {
        // 双检锁单例 — Android companion object @Volatile + Mutex;
        // 解析在后台线程 (750KB gunzip + 200 万点扫描)
        if let cached = await SchoolCityLocator.cachedOfflineIndex.read() {
            return cached
        }
        let parsed: OfflineSchoolCityIndex? = await Task.detached(priority: .utility) {
            guard let url = Bundle.main.url(forResource: "school_city_boundaries", withExtension: "bin.gz")
                ?? Bundle.main.url(forResource: "school_city_boundaries", withExtension: "bin")
            else { return nil }
            do {
                let raw = try Data(contentsOf: url)
                let decompressed = url.pathExtension == "gz" ? (raw.gunzipped() ?? raw) : raw
                let stream = InputStream(data: decompressed)
                return try OfflineSchoolCityIndex.parse(stream)
            } catch {
                return nil
            }
        }.value
        if let parsed = parsed {
            await SchoolCityLocator.cachedOfflineIndex.write(parsed)
        }
        return parsed
    }

    /// 线程安全缓存盒 — 对齐 Android @Volatile var + Mutex。
    private actor OfflineIndexCache {
        private var value: OfflineSchoolCityIndex?
        func read() -> OfflineSchoolCityIndex? { value }
        func write(_ v: OfflineSchoolCityIndex) { value = v }
    }
    private static let cachedOfflineIndex = OfflineIndexCache()

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if #available(iOS 14.0, *) {
            let status = manager.authorizationStatus
            if let cont = authorizationContinuation, status != .notDetermined {
                authorizationContinuation = nil
                cont.resume(returning: status)
            }
            if let completion = permissionCompletion, status != .notDetermined {
                permissionCompletion = nil
                completion(status == .authorizedWhenInUse || status == .authorizedAlways)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locationContinuation?.resume(returning: locations.last)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(returning: nil)
        locationContinuation = nil
    }
}

// MARK: - helpers

private extension CLLocation {
    /// 年龄用单调钟 — iOS 等价 elapsedRealtimeNanos 是 systemUptime。
    func toFix() -> SchoolLocationFix {
        let ageNanos = Int64(max(0, ProcessInfo.processInfo.systemUptime - timestamp.timeIntervalSince1970) * 1_000_000_000)
        return SchoolLocationFix(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            accuracyMeters: horizontalAccuracy.isFinite && horizontalAccuracy > 0
                ? Double(horizontalAccuracy) : Double.nan,
            ageNanos: ageNanos
        )
    }
}

/// withTimeout — Kotlin withTimeoutOrNull 的 Swift 实现 (nil = 超时)。
private func withTimeout<T: Sendable>(seconds: Double, _ body: @escaping () async -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await body() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

// MARK: - gzip 解压 (libcompression)

import Compression

private extension Data {
    /// gunzip: 剥 gzip 容器 (RFC 1952) → raw deflate (RFC 1951) → libcompression inflate。
    /// 校验 magic; 不校验尾 CRC(与 Android GZIPInputStream 行为一致 — 解出即可用)。
    func gunzipped() -> Data? {
        guard count > 18, self[startIndex] == 0x1f, self[startIndex + 1] == 0x8b else {
            return nil
        }
        // gzip header: [1f 8b] [CM] [FLG] [mtime×4] [XFL] [OS] = 10 字节
        var offset = 10
        let flags = self[startIndex + 3]
        if flags & 0x04 != 0 { // FEXTRA: xlen + extra
            guard startIndex + offset + 1 < endIndex else { return nil }
            let xlen = Int(self[startIndex + offset]) | (Int(self[startIndex + offset + 1]) << 8)
            offset += 2 + xlen
        }
        if flags & 0x08 != 0 { // FNAME: 零结尾
            while offset < count && self[startIndex + offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT: 零结尾
            while offset < count && self[startIndex + offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 } // FHCRC
        guard offset + 8 <= count else { return nil }
        // 尾 8 字节 = crc32 + isize; 中间为 raw deflate
        let deflateStart = startIndex + offset
        let deflateEnd = endIndex - 8
        guard deflateStart < deflateEnd else { return nil }
        let deflateData = subdata(in: deflateStart..<deflateEnd)
        return deflateData.inflateRawDeflate()
    }

    private func inflateRawDeflate() -> Data? {
        var src = [UInt8](self)
        let srcSize = src.count
        let bufferSize = 64 * 1024
        // 指针必须在整个解压期间保持有效 — withUnsafeMutableBufferPointer 持有
        return src.withUnsafeMutableBufferPointer { srcPtr -> Data? in
            var dstBuffer = [UInt8](repeating: 0, count: bufferSize)
            return dstBuffer.withUnsafeMutableBufferPointer { dstPtr -> Data? in
                var stream = compression_stream(
                    dst_ptr: dstPtr.baseAddress!,
                    dst_size: bufferSize,
                    src_ptr: srcPtr.baseAddress!,
                    src_size: srcSize,
                    state: nil
                )
                let status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
                guard status == COMPRESSION_STATUS_OK else {
                    compression_stream_destroy(&stream)
                    return nil
                }
                defer { compression_stream_destroy(&stream) }
                var output = Data()
                let flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
                let base = dstPtr.baseAddress!
                while true {
                    let result = compression_stream_process(&stream, flags)
                    let produced = bufferSize - stream.dst_size
                    if produced > 0 {
                        output.append(base, count: produced)
                    }
                    if result == COMPRESSION_STATUS_END { return output }
                    if result == COMPRESSION_STATUS_ERROR { return nil }
                    // OK (需要更多输出空间) — 重置 dst 继续
                    stream.dst_ptr = base
                    stream.dst_size = bufferSize
                }
            }
        }
    }
}
