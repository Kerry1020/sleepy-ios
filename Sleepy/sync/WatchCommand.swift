// WatchCommand.swift — 手表 → iPhone 回写通道信封 (2026-10 watch 伴侣 App)
// ← plan 阶段五: WatchCommand 信封 {type, id, issuedAt, args} 走 transferUserInfo
//   (系统队列保序 + 断连重投); 手机 coordinator 按 id 去重幂等消费。
//
// V1 纪律 (与已落地的 ack-context 设计共存, 不推翻):
//   - 「已同步回执」(syncAck) 仍走 updateApplicationContext[watchAck] —— 那是
//     「最近意图」语义, 断连由系统代存, 已在 WatchSyncSnapshot/Coordinator 注释
//     详尽说明理由, 本信封不接管它。
//   - requestContents 仍走 sendMessage (现状保留, 即时可达语义)。
//   - 本信封 = 为「二期编辑类命令」预留的统一载体 + 幂等消费骨架; V1 提供
//     编解码/幂等基础设施与 .requestContents/.syncAck 两个占位 type, 不开放
//     任何数据修改命令 (决策 2: 改课表永远只在手机)。
//
// 幂等: 信封 id (UUID) 全局唯一; 手机侧 WatchCommandConsumer 按 id 去重,
// 同一 id 重投 (transferUserInfo 断连重发) 只消费一次。

import Foundation

/// 命令类型。V1 仅 .requestContents / .syncAck 两个占位 (实际发送仍走各自
/// 既有通道); 编辑类 (.editCourse 等) 留二期, 枚举先占位让 Codable 向前兼容。
enum WatchCommandType: String, Codable {
    case requestContents
    case syncAck
    // 二期预留 (V1 不发送、不消费):
    case editCourse
    case deleteCourse
}

/// 回写命令信封。args 用 [String: String] 保持 Codable 简洁 + WCSession
/// userInfo 的 PropertyList 兼容 (跨端 JSON 稳定)。
struct WatchCommand: Codable, Equatable {
    let type: WatchCommandType
    /// 全局唯一 id — 幂等去重键 (transferUserInfo 断连重投时同 id 重发)
    let id: String
    /// 发送端时刻 (epoch ms) — 排序/过期判定, 不参与幂等
    let issuedAt: Int64
    let args: [String: String]

    init(type: WatchCommandType, args: [String: String] = [:],
         id: String = UUID().uuidString,
         issuedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.type = type
        self.id = id
        self.issuedAt = issuedAt
        self.args = args
    }

    /// 编码为 WCSession.transferUserInfo 可承载的 PropertyList 字典
    /// (key = "watchCommand", value = JSON Data 转 base64 字符串 — 避免嵌套
    /// dict 在 userInfo 里的类型歧义)。
    func toUserInfo() -> [String: Any] {
        let data = (try? JSONEncoder().encode(self)) ?? Data()
        return [WatchCommand.userInfoKey: data.base64EncodedString()]
    }

    /// 从 userInfo 解出信封; 缺键 / 非 base64 / JSON 坏 → nil (静默丢弃,
    /// 与 Coordinator 既有「坏载荷保留旧镜像」纪律一致)。
    static func from(userInfo: [String: Any]) -> WatchCommand? {
        guard let b64 = userInfo[userInfoKey] as? String,
              let data = Data(base64Encoded: b64) else { return nil }
        return try? JSONDecoder().decode(WatchCommand.self, from: data)
    }

    static let userInfoKey = "watchCommand"
}

/// 手机侧幂等消费器 — 按命令 id 去重。线程安全 (WCSession 回调可能在后台队列)。
/// V1 仅记录已见 id; 真实命令分派留二期 (目前 requestContents/syncAck 各走
/// 既有通道, 本消费器作为 transferUserInfo 入口的去重闸存在)。
final class WatchCommandConsumer {
    static let shared = WatchCommandConsumer()
    private var seen: Set<String> = []
    private let lock = NSLock()

    /// 返回 true = 新命令 (应消费); false = 重复 id (已消费过, 跳过)。
    @discardableResult
    func consume(_ command: WatchCommand) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if seen.contains(command.id) { return false }
        seen.insert(command.id)
        return true
    }

    /// 测试用: 重置去重集
    func resetForTesting() {
        lock.lock(); defer { lock.unlock() }
        seen.removeAll()
    }

    var seenCountForTesting: Int {
        lock.lock(); defer { lock.unlock() }
        return seen.count
    }
}
