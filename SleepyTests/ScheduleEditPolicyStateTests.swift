// ScheduleEditPolicyStateTests.swift — ← ScheduleEditPolicyStateTest.kt
// 甲案 作息冲突三选项 — 编辑会话状态模型契约
// (docs/superpowers/specs/2026-09-24-period-table-conflict-resolution-design.md §2.1/§2.2)。
//
// 锁不变量:
//   1. 未改作息 → hasScheduleChanged=false, 普通保存不弹窗
//   3. 选择任一选项 → 只记录 pendingSchedulePolicy, 不改草稿
//   4. 三个选项始终显示 (不变量 7): 状态机必须接受策略全集
//   5. 选择后又改作息 → 旧策略失效 (重新弹三选项)
//   6. 取消 → 草稿恢复 originalEffectiveSchedule + 策略清空
// + 未绑定共享表 (original=null) 的自洽性

import XCTest
@testable import Sleepy

final class ScheduleEditPolicyStateTests: XCTestCase {

    private func pt(id: Int64 = 7,
                    name: String = "2024 秋季作息",
                    timeJson: String = #"[{"node":1,"start":"08:00","end":"08:45"}]"#,
                    nodesPerDay: Int = 12) -> PeriodTableEntity {
        // ← MigrationV7toV10Tests 同构: memberwise init(name:) + 余字段可变赋值
        //   (PeriodTableEntity() 零参形态在本测试 target 与协议扩展 init 冲突)
        var e = PeriodTableEntity(name: name)
        e.id = id
        e.nodesPerDay = nodesPerDay
        e.timeJson = timeJson
        return e
    }

    func testInvariant1_initial_state_has_no_policy_and_counts_as_unchanged() {
        let original = pt()
        let s = ScheduleEditPolicyState(tableId: 1, originalEffectiveSchedule: original)

        XCTAssertEqual(.none, s.pendingSchedulePolicy)
        XCTAssertFalse(s.hasScheduleChanged())
        XCTAssertEqual(original, s.draftEffectiveSchedule)
    }

    func testInvariant1_draft_change_detected_by_value_equality_not_identity() {
        let original = pt()
        let s = ScheduleEditPolicyState(tableId: 1, originalEffectiveSchedule: original)

        s.updateDraft(pt(timeJson: #"[{"node":1,"start":"08:30","end":"09:15"}]"#))

        XCTAssertTrue(s.hasScheduleChanged())
    }

    func testInvariant1_draft_content_equal_to_original_counts_as_unchanged() {
        let original = pt()
        let s = ScheduleEditPolicyState(tableId: 1, originalEffectiveSchedule: original)

        // 用户改了又改回原样: 草稿值回到 original → 视为未改
        s.updateDraft(pt(name: "临时名"))
        s.updateDraft(original)

        XCTAssertFalse(s.hasScheduleChanged())
    }

    func testInvariant3_selectPolicy_records_without_touching_draft() {
        let original = pt()
        let s = ScheduleEditPolicyState(tableId: 1, originalEffectiveSchedule: original)
        s.updateDraft(pt(timeJson: "edited-json"))

        s.selectPolicy(.detachCopy)

        XCTAssertEqual(SchedulePolicy.detachCopy, s.pendingSchedulePolicy)
        XCTAssertEqual("edited-json", s.draftEffectiveSchedule!.timeJson)
    }

    func testInvariant4_all_three_options_are_selectable_states() {
        // 三个选项始终显示 (不变量 7): 状态机必须接受策略全集
        for p in [SchedulePolicy.detachCopy, .createNew, .sync] {
            let s = ScheduleEditPolicyState(tableId: 3, originalEffectiveSchedule: pt())
            s.updateDraft(pt(timeJson: "x"))
            s.selectPolicy(p)
            XCTAssertEqual(p, s.pendingSchedulePolicy)
        }
    }

    func testInvariant5_re_edit_after_selection_invalidates_policy() {
        let original = pt()
        let s = ScheduleEditPolicyState(tableId: 1, originalEffectiveSchedule: original)
        s.updateDraft(pt(timeJson: "a"))
        s.selectPolicy(.createNew)
        XCTAssertEqual(SchedulePolicy.createNew, s.pendingSchedulePolicy)

        s.updateDraft(pt(timeJson: "b")) // 选择后又改了作息

        XCTAssertEqual(SchedulePolicy.none, s.pendingSchedulePolicy)
        XCTAssertTrue(s.hasScheduleChanged())
    }

    func testInvariant6_cancel_restores_original_draft_and_clears_policy() {
        let original = pt()
        let s = ScheduleEditPolicyState(tableId: 1, originalEffectiveSchedule: original)
        s.updateDraft(pt(name: "别的作息", nodesPerDay: 14))
        s.selectPolicy(.sync)

        s.cancelPolicy()

        XCTAssertEqual(original, s.draftEffectiveSchedule)
        XCTAssertEqual(SchedulePolicy.none, s.pendingSchedulePolicy)
        XCTAssertFalse(s.hasScheduleChanged())
    }

    func testUnbound_table_original_null_tracks_null_draft() {
        // 未绑定共享表的课表不触发弹窗, 但状态机本身对 null 快照保持自洽
        let s = ScheduleEditPolicyState(tableId: 2, originalEffectiveSchedule: nil)

        XCTAssertFalse(s.hasScheduleChanged())
        s.updateDraft(pt())
        XCTAssertTrue(s.hasScheduleChanged())
        s.cancelPolicy()
        XCTAssertEqual(nil, s.draftEffectiveSchedule)
        XCTAssertEqual(SchedulePolicy.none, s.pendingSchedulePolicy)
    }
}
