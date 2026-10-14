// WidgetWeekSource.swift — ← widget/WidgetWeekDataLoader.kt
// 小部件统一读取课表并计算展示日,避免各 provider 各自判定"今天之后最近一节有课的天"。
//
// v2 (用户 2026-09-20 改向):
//   - display.targetDate 是 widget 应该呈现的"今天"(可能是被自动跳到的那一天)。
//   - dateFor(dayOfWeek) 给的是展示周里 dayOfWeek 的真实日期(基于 targetWeek 计算)。
//
// ★ 平台差异 (WidgetBindingStore.swift 头注同源): Android per-appWidgetId → iOS per-kind。
//   此处 appWidgetId 参数 = kind 字符串 (iOS 等价粒度, 详见 WidgetBindingStore)。

import Foundation

struct WidgetWeekSource {
    let table: TimeTableEntity
    let courses: [CourseEntity]
    let display: WeekDisplayContext

    func coursesFor(dayOfWeek: Int, week: Int? = nil) -> [CourseEntity] {
        let w = week ?? display.targetWeek
        return courses
            .filter { $0.day == dayOfWeek && $0.inWeek(w) }
            .sorted { $0.startNode < $1.startNode }
    }

    func dateFor(dayOfWeek: Int) -> Date {
        // ← Kotlin: DateUtils.dateOfWeek(table.startDate, display.targetWeek, dayOfWeek)
        DateUtils.dateOfWeek(startDate: table.startDate, week: display.targetWeek, dayOfWeek: dayOfWeek) ?? Date()
    }

    /// 返回 widget 应展示的"今天"语义日期:
    /// - NORMAL 档:原 today
    /// - NEAREST_BUSY_DAY 档:被自动跳到的最近有课那一天
    func resolvedToday(_ now: Date = Date()) -> Date {
        if display.status == .nearestBusyDay { return display.targetDate }
        return now
    }
}

enum WidgetWeekDataLoader {

    /// 解析 → (table, courses, display) 三元组;无表 → nil (对齐 Android runBlocking + nullable)
    /// - Parameter appWidgetId: iOS = widget kind 字符串(per-kind 粒度)
    static func resolve(_ appWidgetId: String) async -> WidgetWeekSource? {
        guard let repo = WidgetLoader.makeRepo() else { return nil }
        // ← WidgetTableResolver.resolveBoundTable(id) ?: resolveCurrentTable() ?: return null
        guard let table = WidgetBindingStore.resolveBoundTable(appWidgetId, repo: repo)
                ?? WidgetTableResolver.resolveCurrentTable(repo) else { return nil }
        let courses = (try? repo.getCourses(table.id)) ?? []
        let now = Date()
        let display = WeekDisplayResolver.resolve(
            startDate: table.startDate,
            maxWeek: table.maxWeek,
            now: now,
            courses: courses,
            timeJson: table.timeJson,
            enabled: AppPrefs.shared.isNearestBusyDay()
        )
        return WidgetWeekSource(table: table, courses: courses, display: display)
    }
}
