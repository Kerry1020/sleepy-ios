// UndoManagerTests.swift — ← UndoManagerTest.kt (对齐安卓 5 用例语义, GPL-3.0)

import XCTest
@testable import Sleepy

final class UndoManagerTests: XCTestCase {

    private func course(_ id: Int64) -> CourseEntity {
        var c = CourseEntity(groupId: "g\(id)", tableId: 1, courseName: "C\(id)",
                             day: 1, startNode: 1, step: 2, startWeek: 1, endWeek: 16, color: "")
        c.id = id
        return c
    }

    private func table(_ id: Int64, isDefault: Bool = false) -> TimeTableEntity {
        var t = TimeTableEntity(name: "T\(id)", startDate: "2026-09-01")
        t.id = id
        t.isDefault = isDefault
        return t
    }

    override func setUp() {
        super.setUp()
        UndoManager.shared.clear()
        UndoManager.shared.restoring = false
    }

    func testCaptureAndPollReturnsSnapshot() {
        let tables = [table(1, isDefault: true)]
        let courses = [course(1), course(2)]
        UndoManager.shared.capture(tables: tables, courses: courses, defaultTableId: 1)
        XCTAssertTrue(RunLoop.spin(until: { UndoManager.shared.hasSnapshot }))
        let snap = UndoManager.shared.poll()
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.tables.map { $0.id }, [1])
        XCTAssertEqual(snap?.courses.map { $0.id }, [1, 2])
        XCTAssertEqual(snap?.defaultTableId, 1)
        // poll 取走即清空
        XCTAssertFalse(UndoManager.shared.hasSnapshot)
        XCTAssertNil(UndoManager.shared.poll())
    }

    func testCaptureOverwritesSlotSingleWriteSemantics() {
        UndoManager.shared.capture(tables: [table(1)], courses: [course(1)], defaultTableId: 1)
        UndoManager.shared.capture(tables: [table(2)], courses: [course(2)], defaultTableId: 2)
        // capture 现已同步落槽 — 直接断言槽被第二次覆盖(单写动作语义),无需泵循环
        let snap = UndoManager.shared.poll()
        XCTAssertEqual(snap?.tables.first?.id, 2)
        XCTAssertEqual(snap?.courses.first?.id, 2)
    }

    func testBatchKeepsFirstCaptureOnly() {
        UndoManager.shared.beginBatch()
        UndoManager.shared.capture(tables: [table(1)], courses: [], defaultTableId: 1)
        UndoManager.shared.capture(tables: [table(2)], courses: [], defaultTableId: 2)
        UndoManager.shared.endBatch()
        _ = RunLoop.spin(until: { UndoManager.shared.hasSnapshot })
        // 批内多次 capture 只保第一次 = 复合动作回退到动作前时点
        XCTAssertEqual(UndoManager.shared.poll()?.tables.first?.id, 1)
    }

    func testRestoringSuppressesCapture() {
        UndoManager.shared.restoring = true
        UndoManager.shared.capture(tables: [table(1)], courses: [], defaultTableId: 1)
        // restoring 期间 capture 被抑制
        RunLoop.spin(until: { false }, limit: 0.1)
        XCTAssertFalse(UndoManager.shared.hasSnapshot)
        UndoManager.shared.restoring = false
    }

    func testPollWhenEmptyReturnsNil() {
        XCTAssertNil(UndoManager.shared.poll())
        XCTAssertFalse(UndoManager.shared.hasSnapshot)
    }
}

/// RunLoop 等待辅助: UndoManager.capture 走 DispatchQueue.main.async,测试需泵主循环
private func RunLoopSpin(until condition: () -> Bool, limit: TimeInterval = 1.0) -> Bool {
    let deadline = Date().addingTimeInterval(limit)
    while !condition() && Date() < deadline {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }
    return condition()
}

private extension RunLoop {
    static func spin(until condition: () -> Bool, limit: TimeInterval = 1.0) -> Bool {
        RunLoopSpin(until: condition, limit: limit)
    }
}
