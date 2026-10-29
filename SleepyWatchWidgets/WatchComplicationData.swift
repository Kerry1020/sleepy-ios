// WatchComplicationData.swift — 表盘复杂功能数据装载 (2026-10 watch 伴侣 App)
// SleepyWatchWidgets extension 进程独立, 不能 import 主 app 的 @StateObject WatchStore;
// 此处用纯函数直读手表本地 GRDB (AppDatabase.getShared() — 经 App Group 与主 app
// 同容器, PR#16 给两端配同 group.com.lingion.sleepy)。
//
// 「下一节」口径 ← WidgetWindowCore.courseStartEndMin / nowMinutes 同源:
// 今天 inRange 课程里, 起始分钟 > 当前分钟 的最早一门 = 下一节; 无 → nil。
// 倒计时分钟 = next.start - now (≥0)。课名恒原名 (今日页口径, 不套别名)。

import Foundation

/// 表盘用的「下一节」快照。nil = 今天无未开始课 (semester 外 / 全上完 / 无表)。
struct WatchNextClass {
    let courseName: String
    let room: String
    let startLabel: String   // slotLabel 同口径 (节次 or 时间)
    let minutesUntil: Int    // 距开课分钟 (≥0)
    let startDate: Date      // 开课绝对时刻 (Timeline 刷新锚点)
}

enum WatchComplicationData {
    /// 装载当前表 + 今天 + 下一节。任一环节缺失 → (table: nil, next: nil)。
    static func load(now: Date = Date()) -> (table: TimeTableEntity?, next: WatchNextClass?) {
        guard let repo = makeRepo(),
              let table = WidgetTableResolver.resolveCurrentTable(repo) else {
            return (nil, nil)
        }
        let next = computeNext(table: table, repo: repo, now: now)
        return (table, next)
    }

    private static func makeRepo() -> ScheduleRepository? {
        ScheduleRepository(AppDatabase.getShared())
    }

    /// 今天 inRange 课程 → 最早未开始的一门。调休换日 + 学期过滤复用 WatchStore 同口径
    /// (effectiveDayOfWeek + inWeek + semesterStatus)。
    private static func computeNext(table: TimeTableEntity, repo: ScheduleRepository,
                                    now: Date) -> WatchNextClass? {
        let status = DateUtils.semesterStatus(startDate: table.startDate,
                                              maxWeek: table.maxWeek, today: now)
        guard status == .inRange else { return nil }
        let week = DateUtils.currentWeek(startDate: table.startDate, today: now)
        let dow = HolidayTransferHelper.effectiveDayOfWeek(table.id, now)
        let courses = ((try? repo.getCoursesByDay(table.id, day: dow)) ?? [])
            .filter { $0.inWeek(week) }
            .sorted { $0.startNode < $1.startNode }

        let nowMin = nowMinutes(now)
        let cal = Calendar(identifier: .gregorian)
        let dayStart = cal.startOfDay(for: now)

        for c in courses {
            guard let se = courseStartEndMin(c, table.timeJson),
                  se.start > nowMin else { continue }
            let startLabel = slotLabel(c, table: table)
            let startDate = dayStart.addingTimeInterval(TimeInterval(se.start * 60))
            return WatchNextClass(
                courseName: c.courseName,
                room: c.room,
                startLabel: startLabel,
                minutesUntil: se.start - nowMin,
                startDate: startDate)
        }
        return nil
    }

    // MARK: - 与 WatchStore / WidgetWindowCore 同源的纯函数副本
    // (extension 不能依赖主 app 实例方法, 此处内联同口径实现, 注释标真源)

    /// ← WidgetWindowCore.nowMinutes
    private static func nowMinutes(_ date: Date) -> Int {
        let c = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// ← WidgetWindowCore.courseStartEndMin: ownTime/irregular 直读时钟, 否则 timeJson 反解
    private static func courseStartEndMin(_ c: CourseEntity, _ timeJson: String?) -> (start: Int, end: Int)? {
        guard let eff = TimeTableUtils.effectiveCourseTime(
            isIrregularTime: c.isIrregularTime || c.ownTime,
            startTime: c.startTime, endTime: c.endTime,
            startNode: c.startNode, step: c.step, timeJson: timeJson ?? ""),
              let s = TimeTableUtils.hmMinutes(eff.0),
              let e = TimeTableUtils.hmMinutes(eff.1) else { return nil }
        return (s, e)
    }

    /// ← WatchStore.slotLabel: display_mode node→节次短串, 否则时间区间
    private static func slotLabel(_ c: CourseEntity, table: TimeTableEntity) -> String {
        AppPrefs.shared.getDisplayMode() == "node"
            ? c.nodeString(isShort: true)
            : timeRange(c, table: table)
    }

    /// ← WatchStore.timeRange
    private static func timeRange(_ c: CourseEntity, table: TimeTableEntity) -> String {
        let nodes = TimeTableUtils.parseNodes(table.timeJson)
        let start: String, end: String
        if (c.ownTime || c.isIrregularTime), !c.startTime.isEmpty, !c.endTime.isEmpty {
            start = c.startTime; end = c.endTime
        } else if c.isIrregularNode {
            return c.nodeString()
        } else {
            guard let s = nodes.first(where: { $0.node == c.startNode }),
                  let e = nodes.first(where: { $0.node == c.startNode + c.step - 1 })
            else { return "" }
            start = TimeTableUtils.formatTime(s.start)
            end = TimeTableUtils.formatTime(e.end)
        }
        return "\(start)–\(end)"
    }
}
