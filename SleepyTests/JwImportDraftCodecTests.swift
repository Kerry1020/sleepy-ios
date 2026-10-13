// JwImportDraftCodecTests.swift — Android JwImportDraftCodec 契约测试 (GPL-3.0)
// round-trip + 逐条拒绝规则 (schemaVersion/phase/school/courses/periods 校验)。

import XCTest
@testable import Sleepy

final class JwImportDraftCodecTests: XCTestCase {
    private func validSnapshot() -> JwImportDraftSnapshot {
        JwImportDraftSnapshot(
            school: JwSchoolInfo(sortKey: "Q", name: "示例大学", url: "https://jw.example",
                                 status: JwSchoolInfo.STATUS_SUPPORTED,
                                 aliases: ["示例"], sortKeyFull: "QINGDAI"),
            courses: [JwCourse(name: "高数", room: "101", teacher: "张", day: 1,
                               startNode: 1, endNode: 2, startWeek: 1, endWeek: 16)],
            periods: [JwImportDraftPeriod(node: 1, start: "08:00", end: "08:45"),
                      JwImportDraftPeriod(node: 2, start: "", end: "")],
            termStartDate: "2026-02-23",
            tableName: "春季",
            phase: .webViewLogin
        )
    }

    func testRoundTrip() throws {
        let snapshot = validSnapshot()
        let json = JwImportDraftCodec.toJson(snapshot)
        let back = try XCTUnwrap(JwImportDraftCodec.fromJson(json))
        XCTAssertEqual(snapshot.school, back.school)
        XCTAssertEqual(snapshot.courses, back.courses)
        XCTAssertEqual(snapshot.periods, back.periods)
        XCTAssertEqual(snapshot.termStartDate, back.termStartDate)
        XCTAssertEqual(snapshot.tableName, back.tableName)
        XCTAssertEqual(snapshot.phase, back.phase)
    }

    func testDefaultsAndUnknownPhaseRejected() {
        // 缺省 phase = CONFIGURE_CONFIRM
        let json = """
        {"schemaVersion":1,"school":{"sortKey":"Q","name":"X","aliases":[]},"courses":[],"periods":[]}
        """
        XCTAssertEqual(JwImportDraftCodec.fromJson(json)?.phase, .configureConfirm)

        let badPhase = json.replacingOccurrences(of: "\"school\"", with: "\"phase\":\"NOPE\",\"school\"")
        XCTAssertNil(JwImportDraftCodec.fromJson(badPhase), "未知 phase → nil")
    }

    func testSchemaVersionGate() {
        let json = """
        {"schemaVersion":2,"school":{"sortKey":"Q","name":"X"},"courses":[],"periods":[]}
        """
        XCTAssertNil(JwImportDraftCodec.fromJson(json), "schemaVersion != 1 → nil")
        let missingVersion = """
        {"school":{"sortKey":"Q","name":"X"},"courses":[],"periods":[]}
        """
        XCTAssertNil(JwImportDraftCodec.fromJson(missingVersion), "缺省 schemaVersion (-1) → nil")
    }

    func testSchoolValidation() {
        func schoolJson(keys: String = "") -> String {
            let k = keys.isEmpty ? "" : "," + keys
            return "{\"schemaVersion\":1,\"school\":{\"sortKey\":\"Q\",\"name\":\"X\"" + k + "},\"courses\":[],\"periods\":[]}"
        }
        // sortKey 空白 → nil
        let blankKey = "{\"schemaVersion\":1,\"school\":{\"sortKey\":\"  \",\"name\":\"X\"},\"courses\":[],\"periods\":[]}"
        XCTAssertNil(JwImportDraftCodec.fromJson(blankKey))
        // 空白 alias → 整包 nil
        let badAlias = schoolJson(keys: "\"aliases\":[\"OK\",\"\"]")
        XCTAssertNil(JwImportDraftCodec.fromJson(badAlias))
        // 空白 type 在 Kotlin 里 = 合法存 null (ifBlank{null}), 整包不 nil
        let blankType = schoolJson(keys: "\"type\":\" \"")
        let parsed = JwImportDraftCodec.fromJson(blankType)
        XCTAssertNotNil(parsed)
        XCTAssertNil(parsed?.school.type)
        // type 缺省 = nil; 非空白 = 原样保留
        XCTAssertNil(JwImportDraftCodec.fromJson(schoolJson())?.school.type)
        let withType = schoolJson(keys: "\"type\":\"qt\"")
        XCTAssertEqual(JwImportDraftCodec.fromJson(withType)?.school.type, "qt")
    }

    func testCourseValidation() {
        func courseJson(_ course: String) -> String {
            "{\"schemaVersion\":1,\"school\":{\"sortKey\":\"Q\",\"name\":\"X\"},\"courses\":[\(course)],\"periods\":[]}"
        }
        XCTAssertNil(JwImportDraftCodec.fromJson(courseJson(#"{"name":" "}"#)))
        XCTAssertNil(JwImportDraftCodec.fromJson(courseJson(#"{"name":"C","day":8,"startNode":1,"endNode":2,"startWeek":1,"endWeek":1}"#)))
        XCTAssertNil(JwImportDraftCodec.fromJson(courseJson(#"{"name":"C","day":0,"startNode":1,"endNode":2,"startWeek":1,"endWeek":1}"#)))
        XCTAssertNil(JwImportDraftCodec.fromJson(courseJson(#"{"name":"C","day":1,"startNode":3,"endNode":2,"startWeek":1,"endWeek":1}"#)))
        XCTAssertNil(JwImportDraftCodec.fromJson(courseJson(#"{"name":"C","day":1,"startNode":1,"endNode":2,"startWeek":5,"endWeek":1}"#)))
        XCTAssertNil(JwImportDraftCodec.fromJson(courseJson(#"{"name":"C","day":1,"startNode":1,"endNode":2,"type":-1}"#)))
        // 缺 name = 空串 → 非法
        XCTAssertNil(JwImportDraftCodec.fromJson(courseJson(#"{"day":1,"startNode":1,"endNode":2,"startWeek":1,"endWeek":1}"#)))
        // 合法课程
        let ok = JwImportDraftCodec.fromJson(courseJson(#"{"name":"C","day":1,"startNode":1,"endNode":2,"startWeek":1,"endWeek":16,"type":0}"#))
        XCTAssertEqual(1, ok?.courses.count)
    }

    func testPeriodValidation() {
        func periodJson(_ p: String) -> String {
            "{\"schemaVersion\":1,\"school\":{\"sortKey\":\"Q\",\"name\":\"X\"},\"courses\":[],\"periods\":[\(p)]}"
        }
        XCTAssertNil(JwImportDraftCodec.fromJson(periodJson(#"{"node":0,"start":"08:00","end":"08:45"}"#)))
        XCTAssertNil(JwImportDraftCodec.fromJson(periodJson(#"{"node":1,"start":"8:00","end":"08:45"}"#)))
        XCTAssertNil(JwImportDraftCodec.fromJson(periodJson(#"{"node":1,"start":"08:00","end":"07:00"}"#)))
        XCTAssertNil(JwImportDraftCodec.fromJson(periodJson(#"{"node":1,"start":"","end":"08:45"}"#)), "单边空 = 非法")
        // 双空合法 (自定义时间)
        let bothBlank = JwImportDraftCodec.fromJson(periodJson(#"{"node":1,"start":"","end":""}"#))
        XCTAssertNotNil(bothBlank)
        // 完整合法
        let ok = JwImportDraftCodec.fromJson(periodJson(#"{"node":2,"start":"08:50","end":"09:35"}"#))
        XCTAssertEqual([JwImportDraftPeriod(node: 2, start: "08:50", end: "09:35")], ok?.periods)
    }
}
