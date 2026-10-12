// OfflineSchoolCityIndex.swift — ← data/jw/OfflineSchoolCityIndex.kt (v1.0.60)
// 离线城市边界 SCB1 二进制格式解析 + 点在多边形内查找(缩放 1e4 整数环)。
// 绝不按"最近的城市中心"猜城市 — 只做严格的 point-in-polygon。

import Foundation
import Compression

// ← Ring (private data class)
struct ScbRing {
    let coordinates: [Int32]
    let minX: Int32, maxX: Int32, minY: Int32, maxY: Int32

    init(coordinates: [Int32]) {
        self.coordinates = coordinates
        var left = Int32.max, right = Int32.min, bottom = Int32.max, top = Int32.min
        var i = 0
        while i + 1 < coordinates.count {
            left = min(left, coordinates[i]); right = max(right, coordinates[i])
            bottom = min(bottom, coordinates[i + 1]); top = max(top, coordinates[i + 1])
            i += 2
        }
        minX = left; maxX = right; minY = bottom; maxY = top
    }

    // ← contains (ray casting + on-edge short-circuit)
    func contains(_ x: Double, _ y: Double) -> Bool {
        if x < Double(minX) || x > Double(maxX) || y < Double(minY) || y > Double(maxY) { return false }
        var inside = false
        var previous = coordinates.count - 2
        var current = 0
        while current < coordinates.count {
            let ax = Double(coordinates[previous])
            let ay = Double(coordinates[previous + 1])
            let bx = Double(coordinates[current])
            let by = Double(coordinates[current + 1])
            let cross = (x - ax) * (by - ay) - (y - ay) * (bx - ax)
            if abs(cross) < 1e-6 && x >= min(ax, bx) && x <= max(ax, bx) &&
                y >= min(ay, by) && y <= max(ay, by) { return true }
            if (ay > y) != (by > y) && x < (bx - ax) * (y - ay) / (by - ay) + ax { inside.toggle() }
            previous = current
            current += 2
        }
        return inside
    }
}

// ← Polygon (private data class)
struct ScbPolygon {
    let rings: [ScbRing]

    // 第一环=外环, 其余=洞
    func contains(_ x: Double, _ y: Double) -> Bool {
        guard let outer = rings.first, outer.contains(x, y) else { return false }
        for hole in rings.dropFirst() where hole.contains(x, y) { return false }
        return true
    }
}

// ← Area (private data class)
struct ScbArea {
    let name: String
    let polygons: [ScbPolygon]
}

// ← OfflineSchoolCityIndex
final class OfflineSchoolCityIndex {
    private let areas: [ScbArea]

    private init(_ areas: [ScbArea]) { self.areas = areas }

    var cityNames: Set<String> { Set(areas.map(\.name)) }

    // ← cityAt
    func cityAt(latitude: Double, longitude: Double) -> String? {
        guard latitude.isFinite, longitude.isFinite, (-90.0...90.0).contains(latitude),
              (-180.0...180.0).contains(longitude) else { return nil }
        for area in areas {
            for polygon in area.polygons where
                polygon.contains(longitude * 10000, latitude * 10000) { return area.name }
        }
        return nil
    }

    // 解析错误 ← require(...){...} 抛 IllegalArgumentException
    enum ParseError: Error, LocalizedError {
        case format, count, coordinate, trailingData, tooLarge, missingName
        var errorDescription: String? {
            switch self {
            case .format: return "Unsupported city boundary format"
            case .count: return "Invalid city boundary count"
            case .coordinate: return "Invalid city boundary coordinate"
            case .trailingData: return "Trailing city boundary data"
            case .tooLarge: return "City boundary data too large"
            case .missingName: return "Missing city name"
            }
        }
    }

    /// SCB1 直接流式解析为缩放整数环,无 JSON 树、无点对象。
    /// 调用方拥有输入流;每环与每 256 点检查一次取消。
    // ← parse(InputStream, checkCancelled)
    static func parse(_ data: Data, checkCancelled: () throws -> Void = {}) throws -> OfflineSchoolCityIndex {
        var offset = 0
        func readInt32() throws -> Int32 {
            guard offset + 4 <= data.count else { throw ParseError.format }
            let v = data[offset..<offset + 4].reduce(Int32(0)) { ($0 << 8) | Int32($1) }
            offset += 4
            return v
        }
        func count(_ minimum: Int32, _ maximum: Int32) throws -> Int32 {
            let c = try readInt32()
            guard c >= minimum, c <= maximum else { throw ParseError.count }
            return c
        }
        try checkCancelled()
        guard try readInt32() == 0x53434231 else { throw ParseError.format } // "SCB1"
        var totalPoints = 0
        var areas: [ScbArea] = []
        let areaCount = try count(1, 10000)
        for _ in 0..<areaCount {
            try checkCancelled()
            let nameLen = Int(try count(1, 256))
            guard offset + nameLen <= data.count else { throw ParseError.format }
            guard let name = String(data: data[offset..<offset + nameLen], encoding: .utf8),
                  !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw ParseError.missingName }
            offset += nameLen
            var polygons: [ScbPolygon] = []
            let polygonCount = try count(1, 10000)
            for _ in 0..<polygonCount {
                var rings: [ScbRing] = []
                let ringCount = try count(1, 10000)
                for _ in 0..<ringCount {
                    try checkCancelled()
                    let points = Int(try count(3, 1000000))
                    totalPoints += points
                    guard totalPoints <= 2000000 else { throw ParseError.tooLarge }
                    var coordinates: [Int32] = []
                    coordinates.reserveCapacity(points * 2)
                    for point in 0..<points {
                        if point % 256 == 0 { try checkCancelled() }
                        let lon = try readInt32()
                        let lat = try readInt32()
                        guard (-1800000...1800000).contains(lon), (-900000...900000).contains(lat)
                            else { throw ParseError.coordinate }
                        coordinates.append(lon)
                        coordinates.append(lat)
                    }
                    rings.append(ScbRing(coordinates: coordinates))
                }
                polygons.append(ScbPolygon(rings: rings))
            }
            areas.append(ScbArea(name: name, polygons: polygons))
        }
        guard offset == data.count else { throw ParseError.trailingData }
        try checkCancelled()
        return OfflineSchoolCityIndex(areas)
    }

    /// .bin.gz → gunzip → SCB1 解析。iOS 不像 Android AAPT 会解开 gz,需自行解压。
    static func parseGzip(_ gzipData: Data, checkCancelled: () throws -> Void = {}) throws -> OfflineSchoolCityIndex {
        let raw = try Self.gunzip(gzipData)
        return try parse(raw, checkCancelled: checkCancelled)
    }

    /// RFC1952 gzip 容器: 剥头取裸 DEFLATE 载荷(COMPRESSION_ZLIB 只解 RFC1951)。
    private static func gunzip(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 10, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8
            else { throw ParseError.format }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard offset + 2 <= bytes.count else { throw ParseError.format }
            let xlen = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2 + xlen
        }
        if flags & 0x08 != 0 { // FNAME
            guard let end = bytes[offset...].firstIndex(of: 0) else { throw ParseError.format }
            offset = end + 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            guard let end = bytes[offset...].firstIndex(of: 0) else { throw ParseError.format }
            offset = end + 1
        }
        if flags & 0x02 != 0 { offset += 2 } // FHCRC
        guard offset < bytes.count - 8 else { throw ParseError.format }
        return try inflate(bytes[offset..<(bytes.count - 8)])
    }

    /// 裸 DEFLATE (RFC1951) 解压。
    private static func inflate(_ input: ArraySlice<UInt8>) throws -> Data {
        let bufferSize = 65536
        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dstBuffer.deallocate() }
        return try input.withContiguousStorageIfAvailable { src in
            // compression_stream 是 C 结构体: 成员逐一初始化, 无部分参构造
            var stream = compression_stream(
                dst_ptr: dstBuffer, dst_size: bufferSize,
                src_ptr: src.baseAddress!, src_size: src.count, state: nil)
            let status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
            guard status == COMPRESSION_STATUS_OK else { throw ParseError.format }
            defer { compression_stream_destroy(&stream) }
            var out = Data()
            while true {
                stream.dst_ptr = dstBuffer
                stream.dst_size = bufferSize
                let status = compression_stream_process(&stream, 0)
                let produced = bufferSize - stream.dst_size
                if produced > 0 { out.append(dstBuffer, count: produced) }
                if status == COMPRESSION_STATUS_END { return out }
                guard status == COMPRESSION_STATUS_OK else { throw ParseError.format }
            }
        } ?? { throw ParseError.format }()
    }
}
