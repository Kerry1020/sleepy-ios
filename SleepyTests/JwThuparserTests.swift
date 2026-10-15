// JwThuparserTests.swift — ← JwThuparserTest.kt (v1.0.61)

import XCTest
@testable import Sleepy

final class JwThuparserTests: XCTestCase {

    // MARK: - Fixture loading

    private func loadHtml() throws -> String {
        let bundle = Bundle(for: JwThuparserTests.self)
        guard let url = bundle.url(forResource: "thu_courses.sample", withExtension: "html")
            ?? bundle.url(forResource: "thu_courses.sample", withExtension: "html", subdirectory: "resources") else {
            XCTFail("测试资源 thu_courses.sample.html 应存在")
            throw NSError(domain: "test", code: 1)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: A. Big node mapping

    func test_thu_big_to_start_end_node_mapping() throws {
        XCTAssertEqual(0, JwThuparser.START_NODE_MAP[0])
        XCTAssertEqual(1, JwThuparser.START_NODE_MAP[1])
        XCTAssertEqual(2, JwThuparser.END_NODE_MAP[1])
        XCTAssertEqual(3, JwThuparser.START_NODE_MAP[2])
        XCTAssertEqual(5, JwThuparser.END_NODE_MAP[2])
        XCTAssertEqual(6, JwThuparser.START_NODE_MAP[3])
        XCTAssertEqual(7, JwThuparser.END_NODE_MAP[3])
        XCTAssertEqual(12, JwThuparser.START_NODE_MAP[6])
        XCTAssertEqual(14, JwThuparser.END_NODE_MAP[6])
    }

    // MARK: B. 14 section times

    func test_thu_14_section_times_have_14_entries_starting_08_00() throws {
        XCTAssertEqual(14, JwThuparser.THU_TIME_SLOTS.count)
        XCTAssertEqual("08:00", JwThuparser.THU_TIME_SLOTS[0].0)
        XCTAssertEqual("21:45", JwThuparser.THU_TIME_SLOTS[13].1)
    }

    // MARK: C. End-to-end: 5 courses (from sample HTML)

    func test_thu_parses_5_courses_with_exact_fields_from_fixture() throws {
        let courses = try JwThuparser(try loadHtml()).generateCourseList()
        XCTAssertEqual(5, courses.count)

        let math = courses.first { $0.name == "高等数学" }!
        XCTAssertEqual(1, math.day)
        XCTAssertEqual(1, math.startNode)
        XCTAssertEqual(2, math.endNode)
        XCTAssertEqual(1, math.startWeek)
        XCTAssertEqual(8, math.endWeek)
        XCTAssertEqual(0, math.type)
        XCTAssertEqual("张三", math.teacher)
        XCTAssertEqual("六教6A201", math.room)

        let phys = courses.first { $0.name == "大学物理" }!
        XCTAssertEqual(3, phys.day)
        XCTAssertEqual(3, phys.startNode)
        XCTAssertEqual(5, phys.endNode)
        XCTAssertEqual(1, phys.startWeek)
        XCTAssertEqual(16, phys.endWeek)
        XCTAssertEqual(0, phys.type)
        XCTAssertEqual("李四", phys.teacher)
        XCTAssertEqual("主楼401", phys.room)

        let eng = courses.first { $0.name == "英语" }!
        XCTAssertEqual(5, eng.day)
        XCTAssertEqual(10, eng.startNode)
        XCTAssertEqual(11, eng.endNode)
        XCTAssertEqual(1, eng.startWeek)
        XCTAssertEqual(16, eng.endWeek)
        XCTAssertEqual(1, eng.type)
        XCTAssertEqual("王五", eng.teacher)
        XCTAssertEqual("三教305", eng.room)

        let pe = courses.first { $0.name == "体育" }!
        XCTAssertEqual(2, pe.day)
        XCTAssertEqual(6, pe.startNode)
        XCTAssertEqual(7, pe.endNode)
        XCTAssertEqual(2, pe.startWeek)
        XCTAssertEqual(16, pe.endWeek)
        XCTAssertEqual(2, pe.type)
        XCTAssertEqual("赵六", pe.teacher)
        XCTAssertEqual("操场", pe.room)

        let ds = courses.first { $0.name == "数据结构" }!
        XCTAssertEqual(4, ds.day)
        XCTAssertEqual(6, ds.startNode)
        XCTAssertEqual(7, ds.endNode)
        XCTAssertEqual(3, ds.startWeek)
        XCTAssertEqual(15, ds.endWeek)
        XCTAssertEqual(1, ds.type)
        XCTAssertEqual("孙七", ds.teacher)
        XCTAssertEqual("主楼510", ds.room)
    }

    // MARK: D. confidence + matchedFeatures

    func test_thu_sample_yields_high_confidence_with_anchor_features() throws {
        let parser = JwThuparser(try loadHtml())
        XCTAssertEqual(5, try parser.generateCourseList().count)
        XCTAssertGreaterThanOrEqual(parser.confidenceValue, 80)
        let features = parser.matchedFeatureList
        XCTAssertTrue(features.contains("thu:p_xnxq-form"))
        XCTAssertTrue(features.contains("thu:setInitValue-block"))
        XCTAssertTrue(features.contains("thu:strHTML-course-link"))
        XCTAssertTrue(features.contains("thu:aN_M-innerHTML"))
        XCTAssertTrue(features.contains("thu:xktype-必修/限选/任选"))
        XCTAssertTrue(features.contains("thu:week-text-grammar"))
    }

    // MARK: E. negatives

    func test_thu_empty_html_yields_zero_courses() throws {
        let parser = JwThuparser("<html><body></body></html>")
        XCTAssertEqual(0, try parser.generateCourseList().count)
        XCTAssertEqual(0, parser.confidenceValue)
    }

    func test_thu_login_only_page_yields_zero_with_guard_feature() throws {
        let html = """
            <html><body>
            <div id='login-form'>
                <input type='text' name='username' />
                <form action='/login' method='post'>TUNET CAS 登录</form>
            </div>
            </body></html>
        """
        let parser = JwThuparser(html)
        XCTAssertEqual(0, try parser.generateCourseList().count)
        XCTAssertEqual(0, parser.confidenceValue)
        XCTAssertTrue(parser.matchedFeatureList.contains("guard:login-only-no-setInitValue"))
    }

    // MARK: F. parseWeekText grammar

    func test_thu_parseWeekText_全周_to_1_16_0() throws {
        let r = JwThuparser.parseWeekText("全周")
        XCTAssertEqual(1, r.startWeek)
        XCTAssertEqual(16, r.endWeek)
        XCTAssertEqual(0, r.parity)
    }

    func test_thu_parseWeekText_前八周_to_1_8_0() throws {
        let r = JwThuparser.parseWeekText("前八周")
        XCTAssertEqual(1, r.startWeek)
        XCTAssertEqual(8, r.endWeek)
        XCTAssertEqual(0, r.parity)
    }

    func test_thu_parseWeekText_后八周_to_9_16_0() throws {
        let r = JwThuparser.parseWeekText("后八周")
        XCTAssertEqual(9, r.startWeek)
        XCTAssertEqual(16, r.endWeek)
        XCTAssertEqual(0, r.parity)
    }

    func test_thu_parseWeekText_单周_to_1_16_1() throws {
        let r = JwThuparser.parseWeekText("单周")
        XCTAssertEqual(1, r.startWeek)
        XCTAssertEqual(16, r.endWeek)
        XCTAssertEqual(1, r.parity)
    }

    func test_thu_parseWeekText_双周_to_2_16_2() throws {
        let r = JwThuparser.parseWeekText("双周")
        XCTAssertEqual(2, r.startWeek)
        XCTAssertEqual(16, r.endWeek)
        XCTAssertEqual(2, r.parity)
    }

    func test_thu_parseWeekText_第1_16周_to_1_16_0() throws {
        let r = JwThuparser.parseWeekText("第1-16周")
        XCTAssertEqual(1, r.startWeek)
        XCTAssertEqual(16, r.endWeek)
        XCTAssertEqual(0, r.parity)
    }

    func test_thu_parseWeekText_第X_Y周单_to_parity1() throws {
        let r = JwThuparser.parseWeekText("第3-8周(单)")
        XCTAssertEqual(3, r.startWeek)
        XCTAssertEqual(8, r.endWeek)
        XCTAssertEqual(1, r.parity)
    }

    func test_thu_parseWeekText_第X_Y周双_to_parity2() throws {
        let r = JwThuparser.parseWeekText("第2-14周(双)")
        XCTAssertEqual(2, r.startWeek)
        XCTAssertEqual(14, r.endWeek)
        XCTAssertEqual(2, r.parity)
    }

    func test_thu_parseWeekText_第X周_single() throws {
        let r = JwThuparser.parseWeekText("第3周")
        XCTAssertEqual(3, r.startWeek)
        XCTAssertEqual(3, r.endWeek)
        XCTAssertEqual(0, r.parity)
    }

    // MARK: G. registry routing

    func test_thu_registry_routes_type_thu_to_JwThuparser() throws {
        let parser = try JwParserRegistry.parserFor(JwProtocol.TYPE_THU, try loadHtml())
        XCTAssertNotNil(parser)
    }

    func test_thu_selectBest_with_declared_thu_type_returns_5_courses() throws {
        let (courses, attempts) = JwParserRegistry.selectBest(try loadHtml(), declaredType: JwProtocol.TYPE_THU)
        XCTAssertEqual(5, courses.count)
        let thu = attempts.first { $0.type == JwProtocol.TYPE_THU }
        XCTAssertNotNil(thu)
        XCTAssertEqual(5, thu!.courseCount)
        XCTAssertGreaterThanOrEqual(thu!.confidence, 80)
    }
}
