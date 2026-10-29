// WatchCommandTests.swift — 回写通道信封单测 (2026-10 watch 伴侣 App)
// 借 iOS host (SleepyTests) 跑 — watchOS 无 XCTest runtime, 同
// WatchSyncSnapshotTests 模式。WatchCommand/WatchCommandConsumer 是纯逻辑
// (不依赖 WCSession runtime), 可在此验证。
//
// 锁三件事 (plan 阶段五第 3 点): 命令编解码 round-trip / 重复 id 幂等 /
// userInfo PropertyList 形态可往返。

import XCTest
@testable import Sleepy

final class WatchCommandTests: XCTestCase {

    override func setUp() {
        super.setUp()
        WatchCommandConsumer.shared.resetForTesting()
    }

    // MARK: - 编解码 round-trip

    func test_jsonRoundTrip_preservesAllFields() throws {
        let cmd = WatchCommand(type: .requestContents,
                               args: ["reason": "coldStart"],
                               id: "fixed-id-001", issuedAt: 1_700_000_000_000)
        let data = try JSONEncoder().encode(cmd)
        let decoded = try JSONDecoder().decode(WatchCommand.self, from: data)
        XCTAssertEqual(decoded, cmd)
        XCTAssertEqual(decoded.type, .requestContents)
        XCTAssertEqual(decoded.id, "fixed-id-001")
        XCTAssertEqual(decoded.issuedAt, 1_700_000_000_000)
        XCTAssertEqual(decoded.args["reason"], "coldStart")
    }

    func test_userInfoRoundTrip_propertyListSafe() {
        // transferUserInfo 要求 PropertyList 兼容; toUserInfo/from(userInfo:) 往返保真
        let cmd = WatchCommand(type: .syncAck, args: [:], id: "ack-7", issuedAt: 42)
        let info = cmd.toUserInfo()
        // userInfo 顶层值必须是 PropertyList 类型 (String/Data/Dict/Array/...)
        XCTAssertTrue(info[WatchCommand.userInfoKey] is String,
                      "userInfo 载荷须为 String (base64), 否则 WCSession 拒收")
        let back = WatchCommand.from(userInfo: info)
        XCTAssertEqual(back, cmd)
    }

    func test_fromUserInfo_garbage_returnsNil() {
        // 坏载荷静默丢弃 (与 Coordinator「坏载荷保留旧镜像」纪律一致)
        XCTAssertNil(WatchCommand.from(userInfo: [:]))
        XCTAssertNil(WatchCommand.from(userInfo: [WatchCommand.userInfoKey: "not-base64!@#"]))
        XCTAssertNil(WatchCommand.from(userInfo: [WatchCommand.userInfoKey:
            Data("not-json".utf8).base64EncodedString()]))
    }

    // MARK: - 重复 id 幂等

    func test_consumer_dedupesRepeatedId() {
        let cmd = WatchCommand(type: .requestContents, id: "dup-1", issuedAt: 1)
        XCTAssertTrue(WatchCommandConsumer.shared.consume(cmd), "首次应消费")
        XCTAssertFalse(WatchCommandConsumer.shared.consume(cmd), "同 id 重投应跳过")
        XCTAssertFalse(WatchCommandConsumer.shared.consume(cmd), "第三次仍跳过")
        XCTAssertEqual(WatchCommandConsumer.shared.seenCountForTesting, 1)
    }

    func test_consumer_distinctIds_bothConsumed() {
        let a = WatchCommand(type: .requestContents, id: "id-a", issuedAt: 1)
        let b = WatchCommand(type: .syncAck, id: "id-b", issuedAt: 2)
        XCTAssertTrue(WatchCommandConsumer.shared.consume(a))
        XCTAssertTrue(WatchCommandConsumer.shared.consume(b))
        XCTAssertEqual(WatchCommandConsumer.shared.seenCountForTesting, 2)
    }

    func test_defaultInit_generatesUniqueIds() {
        // 默认 id = UUID(), 两条命令不应撞 id (幂等键唯一性前提)
        let a = WatchCommand(type: .requestContents)
        let b = WatchCommand(type: .requestContents)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertTrue(WatchCommandConsumer.shared.consume(a))
        XCTAssertTrue(WatchCommandConsumer.shared.consume(b), "不同 id 都应消费")
    }
}
