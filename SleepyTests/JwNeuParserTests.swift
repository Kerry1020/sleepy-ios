// JwNeuParserTests.swift — ← JwNeuParserTest.kt (v1.0.61)

import XCTest
@testable import Sleepy

final class JwNeuParserTests: XCTestCase {

    // MARK: - Fixture loading

    private func loadJson(name: String) throws -> String {
        let bundle = Bundle(for: JwNeuParserTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "resources") else {
            XCTFail("测试资源 \(name).json 应存在")
            throw NSError(domain: "test", code: 1)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - A. End-to-end: neu_courses.sample.json

    func test_parses_NEU_courses_total_count_is_correct() throws {
        let courses = try JwNeuParser(try loadJson(name: "neu_courses")).generateCourseList()
        XCTAssertEqual(11, courses.count)
    }

    func test_parses_NEU_courses_高等数学_maps_to_correct_fields() throws {
        let courses = try JwNeuParser(try loadJson(name: "neu_courses")).generateCourseList()
        let math = courses.first { $0.name == "高等数学" }!
        XCTAssertEqual(1, math.day)
        XCTAssertEqual(1, math.startNode)
        XCTAssertEqual(2, math.endNode)
        XCTAssertEqual("王教授", math.teacher)
        XCTAssertEqual("浑南校区一教A楼301", math.room)
        XCTAssertEqual(1, math.startWeek)
        XCTAssertEqual(16, math.endWeek)
        XCTAssertEqual(0, math.type)
    }

    func test_parses_NEU_courses_大学物理_weekday3_nodes5to6() throws {
        let courses = try JwNeuParser(try loadJson(name: "neu_courses")).generateCourseList()
        let phys = courses.first { $0.name == "大学物理" }!
        XCTAssertEqual(3, phys.day)
        XCTAssertEqual(5, phys.startNode)
        XCTAssertEqual(6, phys.endNode)
        XCTAssertEqual(2, phys.startWeek)
        XCTAssertEqual(15, phys.endWeek)
    }

    func test_parses_NEU_courses_离散周_246810121416_expands_to_eight_entries() throws {
        let courses = try JwNeuParser(try loadJson(name: "neu_courses")).generateCourseList()
        let lab = courses.filter { $0.name == "数据结构实验" }
        XCTAssertEqual(8, lab.count)
        XCTAssertEqual(5, lab.first!.day)
        XCTAssertEqual(7, lab.first!.startNode)
        XCTAssertEqual(8, lab.first!.endNode)
        let weeks = lab.map { $0.startWeek }.sorted()
        XCTAssertEqual([2, 4, 6, 8, 10, 12, 14, 16], weeks)
        XCTAssertTrue(lab.allSatisfy { $0.startWeek == $0.endWeek })
    }

    func test_parses_NEU_courses_双周课_carries_parity_type2_with_even_endpoint_correction() throws {
        let courses = try JwNeuParser(try loadJson(name: "neu_courses")).generateCourseList()
        let eng = courses.first { $0.name == "英语口语" }!
        XCTAssertEqual(2, eng.day)
        XCTAssertEqual(9, eng.startNode)
        XCTAssertEqual(10, eng.endNode)
        XCTAssertEqual(2, eng.startWeek)  // 端点修正: 双周起点须偶数
        XCTAssertEqual(16, eng.endWeek)
        XCTAssertEqual(2, eng.type)
    }

    func test_parses_NEU_courses_parenthesized_parity_week_string_parses_fully() throws {
        let json = """
        {
          "datas": {
            "arrangedList": [{
              "courseName": "概率论",
              "dayOfWeek": 4,
              "beginSection": 3,
              "endSection": 4,
              "weeksAndTeachers": "1-16周(双)/赵老师[主讲]",
              "titleDetail": [
                "汇总: 1-16周(双) 赵老师",
                "1-16周(双) 浑南校区一教C楼105"
              ]
            }]
          }
        }
        """
        let courses = try JwNeuParser(json).generateCourseList()
        XCTAssertEqual(1, courses.count)
        let c = courses[0]
        XCTAssertEqual(2, c.type)
        XCTAssertEqual(2, c.startWeek)
        XCTAssertEqual(16, c.endWeek)
    }

    func test_parses_NEU_courses_fullwidth_parens_parity_also_stripped() throws {
        let json = """
        {
          "datas": {
            "arrangedList": [{
              "courseName": "线性代数",
              "dayOfWeek": 2,
              "beginSection": 1,
              "endSection": 2,
              "weeksAndTeachers": "3-15周（单）/钱老师[主讲]",
              "titleDetail": [
                "汇总: 3-15周（单） 钱老师",
                "3-15周（单） 南湖校区综合楼201"
              ]
            }]
          }
        }
        """
        let courses = try JwNeuParser(json).generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual(1, courses[0].type)
        XCTAssertEqual(3, courses[0].startWeek)  // 3 已奇数, 不动
        XCTAssertEqual(15, courses[0].endWeek)
    }

    // MARK: - B. Weeks extraction & teacher

    func test_parses_NEU_courses_weeksAndTeachers_extraction() throws {
        let courses = try JwNeuParser(try loadJson(name: "neu_courses")).generateCourseList()
        let math = courses.first { $0.name == "高等数学" }!
        XCTAssertEqual("王教授", math.teacher)
    }

    // MARK: - C. titleDetail fallback

    func test_parses_NEU_courses_titleDetail_fallback_when_only_summary() throws {
        let json = """
        {
          "datas": {
            "arrangedList": [{
              "courseName": "无地点课程",
              "dayOfWeek": 4,
              "beginSection": 1,
              "endSection": 2,
              "weeksAndTeachers": "1-8周/王老师[主讲]",
              "titleDetail": ["汇总: 1-8周 王老师"]
            }]
          }
        }
        """
        let courses = try JwNeuParser(json).generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual("无地点课程", courses[0].name)
        XCTAssertEqual("王老师", courses[0].teacher)
        XCTAssertEqual("", courses[0].room)
        XCTAssertEqual(1, courses[0].startWeek)
        XCTAssertEqual(8, courses[0].endWeek)
    }

    // MARK: - D. Multiple titleDetail locations

    func test_parses_NEU_courses_multiple_titleDetail_locations_keep_their_own_weeks() throws {
        let json = """
        {
          "datas": {
            "arrangedList": [{
              "courseName": "Multi-room course",
              "dayOfWeek": 3,
              "beginSection": 5,
              "endSection": 6,
              "weeksAndTeachers": "1-4/Teacher",
              "titleDetail": [
                "Summary 1-4 Teacher",
                "1-2 Room-A",
                "3-4 Room-B"
              ]
            }]
          }
        }
        """
        let courses = try JwNeuParser(json).generateCourseList()
        XCTAssertEqual(2, courses.count)
        let roomA = courses.first { $0.room == "Room-A" }!
        let roomB = courses.first { $0.room == "Room-B" }!
        XCTAssertEqual(1, roomA.startWeek)
        XCTAssertEqual(2, roomA.endWeek)
        XCTAssertEqual(3, roomB.startWeek)
        XCTAssertEqual(4, roomB.endWeek)
    }

    // MARK: - E. Lab course

    func test_parses_NEU_lab_course_with_script_specific_teacher_and_place_fields() throws {
        let json = """
        {
          "datas": {
            "arrangedList": [{
              "courseName": "[实] 数据结构实验",
              "dayOfWeek": 5,
              "beginSection": 7,
              "endSection": 8,
              "weeksAndTeachers": "2,4,6,8周[张老师]",
              "titleDetail": [
                "汇总: 2,4,6,8周 张老师",
                "2,4,6,8周 张老师"
              ],
              "placeName": "计算机楼401 其他信息"
            }]
          }
        }
        """
        let courses = try JwNeuParser(json).generateCourseList()
        XCTAssertEqual(4, courses.count)
        XCTAssertTrue(courses.allSatisfy { $0.name == "[实] 数据结构实验" })
        XCTAssertTrue(courses.allSatisfy { $0.teacher == "张老师" })
        XCTAssertTrue(courses.allSatisfy { $0.room == "计算机楼401" })
        XCTAssertEqual([2, 4, 6, 8], courses.map { $0.startWeek }.sorted())
        XCTAssertTrue(courses.allSatisfy { $0.startWeek == $0.endWeek })
    }

    func test_parses_NEU_lab_course_without_a_classroom_as_unassigned() throws {
        let json = """
        {
          "datas": {
            "arrangedList": [{
              "courseName": "[实] 实验课",
              "dayOfWeek": 1,
              "beginSection": 1,
              "endSection": 2,
              "weeksAndTeachers": "1-2周[李老师]",
              "titleDetail": ["汇总", "1-2周 李老师"],
              "placeName": "南湖校区)"
            }]
          }
        }
        """
        let courses = try JwNeuParser(json).generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual("暂未安排教室", courses[0].room)
    }

    // MARK: - F. Confidence & features

    func test_parses_NEU_courses_confidence_is_high_when_arrangedList_anchor_present() throws {
        let parser = JwNeuParser(try loadJson(name: "neu_courses"))
        XCTAssertGreaterThanOrEqual(parser.confidenceValue, 80)
    }

    func test_parses_NEU_courses_confidence_is_zero_when_arrangedList_missing() throws {
        XCTAssertEqual(0, JwNeuParser("{\"other\":{}}").confidenceValue)
    }

    func test_parses_NEU_courses_matchedFeatures_lists_arrangedList_anchor() throws {
        let features = JwNeuParser(try loadJson(name: "neu_courses")).matchedFeatureList
        XCTAssertTrue(features.contains("arrangedList"))
    }

    // MARK: - G. BUAA byxt cellDetail path

    private func loadBuaaByxtJson() throws -> String {
        return try loadJson(name: "neu_buaa_byxt")
    }

    func test_parses_BUAA_byxt_cellDetail_teacher_week_连续_高等数学() throws {
        let courses = try JwNeuParser(try loadBuaaByxtJson()).generateCourseList()
        let math = courses.first { $0.name == "高等数学" }!
        XCTAssertEqual("王教授", math.teacher)
        XCTAssertEqual("沙河校区主M101", math.room)
        XCTAssertEqual(1, math.day)
        XCTAssertEqual(1, math.startNode)
        XCTAssertEqual(2, math.endNode)
        XCTAssertEqual(1, math.startWeek)
        XCTAssertEqual(16, math.endWeek)
        XCTAssertEqual(0, math.type)
    }

    func test_parses_BUAA_byxt_cellDetail_teacher_week_离散周_展开为_8_行() throws {
        let courses = try JwNeuParser(try loadBuaaByxtJson()).generateCourseList()
        let lab = courses.filter { $0.name == "数据结构实验" }
        XCTAssertEqual(8, lab.count)
        XCTAssertEqual("张老师", lab[0].teacher)
        XCTAssertEqual("沙河校区计算机楼401", lab[0].room)
        XCTAssertEqual(5, lab[0].day)
        XCTAssertEqual(7, lab[0].startNode)
        XCTAssertEqual(8, lab[0].endNode)
        let weeks = lab.map { $0.startWeek }.sorted()
        XCTAssertEqual([2, 4, 6, 8, 10, 12, 14, 16], weeks)
        XCTAssertTrue(lab.allSatisfy { $0.startWeek == $0.endWeek })
    }

    func test_parses_BUAA_byxt_cellDetail_双周_端点修正_type2_起点偶数化() throws {
        let courses = try JwNeuParser(try loadBuaaByxtJson()).generateCourseList()
        let eng = courses.first { $0.name == "英语口语" }!
        XCTAssertEqual("Smith", eng.teacher)
        XCTAssertEqual(2, eng.day)
        XCTAssertEqual(9, eng.startNode)
        XCTAssertEqual(10, eng.endNode)
        XCTAssertEqual(2, eng.startWeek)
        XCTAssertEqual(16, eng.endWeek)
        XCTAssertEqual(2, eng.type)
    }

    func test_extractTeacherFromCellDetail_prefers_cellDetail_over_weeksAndTeachers() throws {
        let json = """
        {
          "datas": {
            "arrangedList": [{
              "courseName": "X",
              "dayOfWeek": 3,
              "beginSection": 1,
              "endSection": 2,
              "placeName": "教室A",
              "weeksAndTeachers": "",
              "cellDetail": [
                {"text": "李老师[3-8周]"},
                {"text": "教室A"}
              ],
              "titleDetail": ["汇总", "上课地点：学院路校区/教室A"]
            }]
          }
        }
        """
        let courses = try JwNeuParser(json).generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual("李老师", courses[0].teacher)
        XCTAssertEqual("教室A", courses[0].room)
        XCTAssertEqual(3, courses[0].startWeek)
        XCTAssertEqual(8, courses[0].endWeek)
    }

    func test_extractCellDetailPairs_falls_back_to_placeName_when_cellDetail_empty() throws {
        let json = """
        {
          "datas": {
            "arrangedList": [{
              "courseName": "Y",
              "dayOfWeek": 4,
              "beginSection": 5,
              "endSection": 6,
              "placeName": "教室B",
              "weeksAndTeachers": "",
              "titleDetail": ["汇总"]
            }]
          }
        }
        """
        let courses = try JwNeuParser(json).generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual("教室B", courses[0].room)
    }
}
