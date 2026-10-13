// MigrationPrefsCodec.swift — ← data/migration/MigrationPrefsCodec.kt
// 偏好/小部件/持久态 三模块共用的 codec。值带类型信封,导入端按信封还原,不靠运行时类型猜测。
//
// iOS 适配:
//   - Android SharedPreferences → UserDefaults (同 key-value 语义,UserDefaults 全是单 suite)
//   - 文件名 → suiteName 映射: iOS 用 UserDefaults(suiteName: <file>) 模拟多文件;
//     共享主 prefs("sleepy_prefs") 走 UserDefaults.standard 保持向后兼容
//     (UserDefaults.standard 持久化的 key 实际就在 app group-less 默认 suite 中)。

import Foundation

/// 偏好快照 codec。
/// 与 Android MigrationPrefsCodec.kt 1:1 — JSON 协议必须保持向后兼容。
enum MigrationPrefsCodec {

    /// 值的类型信封 — 未知 type 直接 skip, 不阻断导出。
    enum PrefType: String, Codable {
        case BOOL
        case INT
        case LONG
        case FLOAT
        case STRING
        case STRING_SET
    }

    /// 单个偏好值 — 一次只承载一个字段(type 决定哪个),与 Android JSON 协议一致。
    struct PrefValue: Codable {
        var type: PrefType
        var bool: Bool = false
        /// int 与 long 统一走这里 (JS 端 number 精度内, iOS 端 Int64)。
        var number: Int64 = 0
        var float: Float = 0
        var string: String = ""
        var stringSet: [String] = []

        // 兼容 Android JSON 字段名 'number'(JS 端 number 精度内) — Swift 自动 Codable
    }

    struct PrefsFileSnapshot: Codable {
        var entries: [String: PrefValue] = [:]
    }

    struct PrefsSnapshot: Codable {
        var files: [String: PrefsFileSnapshot] = [:]
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private static let decoder = JSONDecoder()

    static func encode(_ snapshot: PrefsSnapshot) throws -> String {
        let data = try encoder.encode(snapshot)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func decode(_ text: String) throws -> PrefsSnapshot {
        guard let data = text.data(using: .utf8) else {
            throw MigrationPackageException(message: "prefs snapshot not utf-8")
        }
        return try decoder.decode(PrefsSnapshot.self, from: data)
    }

    /// 从一个 UserDefaults 实例收集全量键值(类型按运行时实际值判别)。
    /// Android SharedPreferences.all 反射 — iOS UserDefaults 不暴露字典视图,
    /// 通过 dictionaryRepresentation() 拿到 key→Any,逐一判别。
    static func collect(_ defaults: UserDefaults) -> PrefsFileSnapshot {
        var entries: [String: PrefValue] = [:]
        for (key, raw) in defaults.dictionaryRepresentation() {
            // UserDefaults 内置 key (ApplePersistence / NSLanguages 等) 跳过
            if key.hasPrefix("NS") || key.hasPrefix("Apple") { continue }
            guard let value = makePrefValue(raw) else { continue }
            entries[key] = value
        }
        return PrefsFileSnapshot(entries: entries)
    }

    private static func makePrefValue(_ raw: Any) -> PrefValue? {
        // UserDefaults 中 Bool 与 Int 都以 NSNumber 持有,Swift API 区分用 is type check
        // 但 NSNumber 转换会在 Bool/Int 之间产生歧义 — 用 objCType 严格判别
        if let n = raw as? NSNumber {
            // NSNumber 的 objCType: 'B' bool, 'c'/'s'/'i'/'l'/'q'/'C'/'S'/'I'/'L'/'Q' 整数,
            // 'f'/'d' 浮点。Swift String/Date 走另一路。
            switch String(cString: n.objCType) {
            case "B":
                return PrefValue(type: .BOOL, bool: n.boolValue)
            case "c", "s", "i", "l", "q", "C", "S", "I", "L", "Q":
                // INT 与 LONG 视值大小 — 与 Android 行为一致(< Int32.max 当 INT, 否则 LONG)
                let v = n.int64Value
                if v >= Int64(Int32.min) && v <= Int64(Int32.max) {
                    return PrefValue(type: .INT, number: v)
                } else {
                    return PrefValue(type: .LONG, number: v)
                }
            case "f", "d":
                return PrefValue(type: .FLOAT, float: n.floatValue)
            default:
                return nil   // 未来新类型,跳过不阻断
            }
        }
        if let s = raw as? String {
            return PrefValue(type: .STRING, string: s)
        }
        if let arr = raw as? [String] {
            return PrefValue(type: .STRING_SET, stringSet: arr.sorted())
        }
        if let anyArr = raw as? [Any] {
            // [Any] 但 [String] cast 失败 — 尝试 string 化(谨慎)
            let strs = anyArr.compactMap { $0 as? String }
            if strs.count == anyArr.count {
                return PrefValue(type: .STRING_SET, stringSet: strs.sorted())
            }
        }
        return nil
    }

    /// 写回单个 UserDefaults。
    /// - Parameter merge: true=仅覆盖同名键; false=先 removePersistentDomain 整文件替换。
    static func apply(_ defaults: UserDefaults, _ snapshot: PrefsFileSnapshot, merge: Bool) {
        if !merge {
            // 与 Android editor.clear() 等价 — UserDefaults 没有直接 clear 单 suite
            // 用 removePersistentDomain + synchronize(后者 deprecated 但无害)
            if let bundleId = Bundle.main.bundleIdentifier {
                defaults.removePersistentDomain(forName: bundleId)
            } else {
                // 兜底 — 遍历 dictionaryRepresentation 删 key
                for key in defaults.dictionaryRepresentation().keys {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        for (key, value) in snapshot.entries {
            switch value.type {
            case .BOOL:
                defaults.set(value.bool, forKey: key)
            case .INT:
                // 还原为 Int(与 Android getInt 对应)
                defaults.set(Int(value.number), forKey: key)
            case .LONG:
                defaults.set(value.number, forKey: key)
            case .FLOAT:
                defaults.set(value.float, forKey: key)
            case .STRING:
                defaults.set(value.string, forKey: key)
            case .STRING_SET:
                defaults.set(Set(value.stringSet), forKey: key)
            }
        }
    }
}

/// 各模块覆盖的 prefs 文件清单 (debug_import 为调试通道, 永不迁移)。
/// iOS: 大多数 prefs 走 UserDefaults.standard(主文件 sleepy_prefs 直接复用);
/// 二级文件 (custom_themes / widget_bindings / ...) 走 suiteName。
enum MigrationPrefsFileMap {
    static let PREFERENCES: [String] = [
        "sleepy_prefs",     // AppPrefs 主文件(212+ 键)
        "custom_themes",    // 自定义主题
    ]
    static let WIDGETS: [String] = [
        "widget_bindings",
        "widget_scroll_prefs",
        "widget_compact_window_prefs",
        "widget_today_nav",
    ]
    static let PERSISTED_STATE: [String] = []   // iOS 端当前无独立持久态; 预留给未来扩展

    static func files(of module: MigrationModule) -> [String] {
        switch module {
        case .PREFERENCES: return PREFERENCES
        case .WIDGETS: return WIDGETS
        case .PERSISTED_STATE: return PERSISTED_STATE
        default: return []
        }
    }
}
