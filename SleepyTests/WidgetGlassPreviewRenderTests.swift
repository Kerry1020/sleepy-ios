// WidgetGlassPreviewRenderTests.swift — 生产 EntryView 离屏渲染实证
//
// 「小部件在透明的主题下很多字/图标无法正常显示」(用户 2026-10-28 报告) 的修复
// 无法用纯逻辑单测断言颜色, 本测试把 **生产视图树** (5 个 EntryView) 经
// ImageRenderer 渲染成 PNG 落盘:
//   · fullColor 档 (不注入) — 正常主题基线
//   · accented 档 (注入 environment(\.widgetRenderingMode, .accented)) —
//     iOS 26 「透明/着色」主屏样式的系统渲染态, 与生产宿主 chrono 注入同键,
//     WidgetGlassModeContent 读到 → 白 alpha 玻璃档
// 背景垫半透明 systemTeal 伪壁纸: 玻璃档下容器底透明处应透出壁纸色, 供目测核对。
// 输出目录 tmp/PreviewRender (模拟器沙盒), 宿主 simctl 取回目测。
// 断言只锁「渲染成功 + 非空图」; 像素级对比不在 CI 范围。

import XCTest
import SwiftUI
import WidgetKit
@testable import Sleepy

@available(iOS 16.0, *)
final class WidgetGlassPreviewRenderTests: XCTestCase {

    private var outDir: URL!

    override func setUpWithError() throws {
        outDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PreviewRender", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    }

    // MARK: - fixtures

    private func course(_ id: Int64, _ name: String, _ room: String, day: Int,
                        startNode: Int, step: Int, color: String = "#6750A4") -> CourseEntity {
        CourseEntity(groupId: "g\(id)", tableId: 1, courseName: name, teacher: "王老师",
                     room: room, day: day, startNode: startNode, step: step,
                     startWeek: 1, endWeek: 20, color: color, id: id)
    }

    /// 周三 4 门 (含连排/单节) + 周四 2 门 + 周五冲突 2 门 (同节次异教室 → 分栏)
    private func weekCourses() -> [CourseEntity] {
        [course(1, "高等数学", "A101", day: 3, startNode: 1, step: 2),
         course(2, "线性代数B", "教学楼3-502", day: 3, startNode: 4, step: 1),
         course(3, "大学英语", "外院201", day: 3, startNode: 5, step: 2),
         course(4, "毛概", "B302", day: 3, startNode: 8, step: 1),
         course(10, "数据结构", "C105", day: 4, startNode: 2, step: 2, color: "#625B71"),
         course(11, "操作系统", "实验楼A-203", day: 4, startNode: 6, step: 1, color: "#7D5260"),
         course(12, "编译原理", "D201", day: 5, startNode: 1, step: 2, color: "#0B6E4F"),
         course(13, "计算机网络", "D202", day: 5, startNode: 1, step: 2, color: "#B3261E")]
    }

    private func days(_ courses: [CourseEntity], greyWeekend: Bool = true) -> [DayData] {
        let cal = Calendar(identifier: .iso8601)
        let monday = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        return (1...7).map { dow in
            DayData(date: cal.date(byAdding: .day, value: dow - 1, to: monday)!,
                    dayOfWeek: dow, courses: courses.filter { $0.day == dow },
                    timeJson: TimeTableUtils.DEFAULT_TIME_JSON,
                    isGrey: greyWeekend && dow >= 6)
        }
    }

    private func weekData(themeKey: String, isDark: Bool, visible: Set<Int>) -> WeekData {
        WeekData(days: days(weekCourses()), hasTable: true, isDark: isDark,
                 themeKey: themeKey, themeMode: "system", visibleDays: visible,
                 semesterStatus: .inRange)
    }

    private func widgetData(themeKey: String, isDark: Bool) -> WidgetData {
        let cs = weekCourses().filter { $0.day == 3 }
        let cal = Calendar(identifier: .iso8601)
        // Today 数据面「今天」— 课程表按今天星期几重标 day
        let dowISO = { let w = cal.component(.weekday, from: Date()); return w == 1 ? 7 : w - 1 }()
        let today = cs.map { c in var x = c; x.day = dowISO; return x }
        _ = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))
        return WidgetData(date: Date(), courses: today,
                          timeJson: TimeTableUtils.DEFAULT_TIME_JSON, hasTable: true,
                          isDark: isDark, themeKey: themeKey, themeMode: "system",
                          semesterStatus: .inRange, isToday: true)
    }

    // MARK: - render helper

    @MainActor
    private func render(_ view: AnyView, size: CGSize, tag: String) throws {
        let host = view
            .frame(width: size.width, height: size.height)
            .background(Color(uiColor: .systemTeal).opacity(0.6))  // 伪壁纸: 玻璃档穿透可见
            .environment(\.colorScheme, tag.contains("dark") ? .dark : .light)
        let r = ImageRenderer(content: host)
        r.proposedSize = ProposedViewSize(size)
        r.scale = 2
        guard let ui = r.uiImage, let png = ui.pngData() else {
            XCTFail("渲染失败: \(tag)"); return
        }
        XCTAssertGreaterThan(png.count, 1000, "疑似空图: \(tag)")
        try png.write(to: outDir.appendingPathComponent(tag + ".png"))
        NSLog("PREVIEW_WRITTEN %@ bytes=%d", tag, png.count)
    }

    private func glassed(_ v: AnyView) -> AnyView {
        AnyView(v.environment(\.widgetRenderingMode, WidgetRenderingMode.accented))
    }
    private static func plain(_ v: AnyView) -> AnyView { v }

    // MARK: - cases

    @MainActor
    func testRenderTodayAllModes() throws {
        for (key, dark) in [("default", false), ("default", true), ("system", false), ("system", true)] {
            let entry = TodayWidgetEntry(date: Date(), data: widgetData(themeKey: key, isDark: dark))
            let base = AnyView(TodayWidgetEntryView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemMedium)))
            let sz = CGSize(width: 328, height: 155)
            let t = "today_\(key)_\(dark ? "dark" : "light")"
            try render(Self.plain(base), size: sz, tag: t + "_full")
            try render(glassed(base), size: sz, tag: t + "_glass")
        }
    }

    @MainActor
    func testRenderTwoDayAllModes() throws {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        let cs = weekCourses().filter { $0.day == 3 }
            .map { c in var x = c; x.day = DateUtils.todayDayOfWeek(today: today); return x }
        let dd = [DayData(date: today, dayOfWeek: DateUtils.todayDayOfWeek(today: today),
                          courses: cs, timeJson: TimeTableUtils.DEFAULT_TIME_JSON),
                  DayData(date: cal.date(byAdding: .day, value: 1, to: today)!,
                          dayOfWeek: 5, courses: [], timeJson: TimeTableUtils.DEFAULT_TIME_JSON)]
        let entry = TwoDayWidgetEntry(date: Date(),
                                      data: TwoDayData(days: dd, hasTable: true, isDark: false,
                                                       themeKey: "default", themeMode: "system"))
        let base = AnyView(TwoDayWidgetEntryView(entry: entry)
            .previewContext(WidgetPreviewContext(family: .systemMedium)))
        let sz = CGSize(width: 328, height: 155)
        try render(Self.plain(base), size: sz, tag: "twoday_default_full")
        try render(glassed(base), size: sz, tag: "twoday_default_glass")
    }

    @MainActor
    func testRenderWeekGridAllModes() throws {
        let entry = WeekGridWidgetEntry(date: Date(), data: weekData(themeKey: "default", isDark: false, visible: Set(1...5)))
        let base = AnyView(WeekGridWidgetEntryView(entry: entry)
            .previewContext(WidgetPreviewContext(family: .systemLarge)))
        let sz = CGSize(width: 328, height: 345)
        try render(Self.plain(base), size: sz, tag: "weekgrid_default_full")
        try render(glassed(base), size: sz, tag: "weekgrid_default_glass")
    }

    @MainActor
    func testRenderWeekListAndWeekViewGlass() throws {
        let w = weekData(themeKey: "system", isDark: false, visible: Set(1...7))
        let listBase = AnyView(WeekListWidgetEntryView(entry: WeekListWidgetEntry(date: Date(), data: w))
            .previewContext(WidgetPreviewContext(family: .systemLarge)))
        let viewBase = AnyView(WeekViewWidgetEntryView(entry: WeekViewWidgetEntry(date: Date(), data: w))
            .previewContext(WidgetPreviewContext(family: .systemLarge)))
        let sz = CGSize(width: 328, height: 345)
        try render(Self.plain(listBase), size: sz, tag: "weeklist_system_full")
        try render(glassed(listBase), size: sz, tag: "weeklist_system_glass")
        try render(Self.plain(viewBase), size: sz, tag: "weekview_system_full")
        try render(glassed(viewBase), size: sz, tag: "weekview_system_glass")
    }
}
