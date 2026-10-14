// NotificationScheduler.swift — ← CourseNotificationScheduler.kt (v1.0.60)
// 课程通知调度器 — 支持每日提醒 + 次日预告 + 每节课前提醒(7 天幂等重同步 + 账本)。
//
// 平台映射: AlarmManager+BroadcastReceiver → UNUserNotificationCenter+UNCalendarNotificationTrigger
// (iOS 无 exact alarm;日历触发器在锁屏也能到,精度分钟级 — 等价适配)
//
// v1.0.60 升级:
//  - 课前提醒: 未来 7 天全窗口幂等重同步(requestCode=NOTIFY_BEFORE_CLASS_PREFIX+courseId
//    同 id 重排原地替换; 上次排过这次不再需要的按账本精确撤销)
//  - 次日预告提醒 (TomorrowNotifyReceiver 语义)
//  - 节假日提醒策略门控 (HolidayReminderPolicyAdapter.decide.allowReminder)
//  - 调休映射 (effectiveDayOfWeek)
//
// OPPO Fluid Cloud(SDK≥26 前台服务 + ProgressStyle)整体跳过(平台差异,iOS 无对应物);
// banner 通知完整移植。

import Foundation
import UserNotifications

final class NotificationScheduler {
    static let shared = NotificationScheduler()

    // ← companion object 常量
    static let CHANNEL_DAILY = "sleepy_daily"
    static let CHANNEL_BEFORE_CLASS = "sleepy_before_class"
    static let CHANNEL_FLUID = "sleepy_fluid_v2"

    // Notification identifiers(= Android request codes 语义:按 id 撤销)
    static let NOTIFY_DAILY = "sleepy_daily_1001"
    static let NOTIFY_TOMORROW_DAILY = "sleepy_daily_1002"
    static let NOTIFY_BEFORE_CLASS_PREFIX = "sleepy_bc_2000_"  // + courseId
    static let NOTIFY_RESYNC = "sleepy_resync_0002"            // 每日 00:05 全窗口重同步

    /// 课前提醒预排窗口: 今天起 7 个日历天(参照 shiguang WIDGET_SYNC_DAYS=7)
    static let BEFORE_CLASS_WINDOW_DAYS = 7

    private let center = UNUserNotificationCenter.current()
    private let prefs = AppPrefs.shared

    var repositoryProvider: (() -> ScheduleRepository?)?

    // 进程级锁 — Mutex 不可重入, 持锁路径只调 *Locked
    private let scheduleLock = NSLock()

    // MARK: - 生产实现 (协议定义在文件底部顶层 — Swift 不允许协议嵌套在类内)

    /// prefs/时钟/独立账本文件(闹钟是本机状态, 不随 sleepy_prefs 云备份迁移)。
    private final class ProdEnv: NotificationSchedulerBeforeClassEnv {
        private let ledger = UserDefaults(suiteName: "sleepy_alarm_ledger")
        func isBeforeClassEnabled() -> Bool { AppPrefs.shared.isBeforeClassEnabled() }
        func beforeClassMinutes() -> Int { AppPrefs.shared.getBeforeClassMinutes() }
        func nowEpochMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
        func todayDate() -> Date { Date() }
        func loadArmedIds() -> Set<String> {
            guard let raw = ledger?.stringArray(forKey: "before_class_armed_ids") else { return [] }
            return Set(raw)
        }
        func saveArmedIds(_ ids: Set<String>) {
            ledger?.set(Array(ids), forKey: "before_class_armed_ids")
        }
    }

    private final class ProdDataSource: NotificationSchedulerBeforeClassDataSource {
        func resolveCurrentTable() -> TimeTableEntity? {
            guard let repo = NotificationScheduler.shared.repositoryProvider?() else { return nil }
            return WidgetTableResolver.resolveCurrentTable(repo)
        }
        func coursesForDay(tableId: Int64, dayOfWeek: Int) -> [CourseEntity] {
            guard let repo = NotificationScheduler.shared.repositoryProvider?() else { return [] }
            return (try? repo.getCoursesByDay(tableId, day: dayOfWeek)) ?? []
        }
        func allCourseIds() -> [Int64] {
            guard let repo = NotificationScheduler.shared.repositoryProvider?() else { return [] }
            let tables = (try? repo.getAllTables()) ?? []
            var ids: [Int64] = []
            for t in tables {
                ids += ((try? repo.getCourses(t.id)) ?? []).map { $0.id }
            }
            return ids
        }
        func effectiveDayOfWeek(tableId: Int64?, date: Date) -> Int {
            return HolidayTransferHelper.effectiveDayOfWeek(tableId, date)
        }
        func allowsReminder(tableId: Int64, date: Date) async -> Bool {
            return await HolidayReminderPolicyAdapter.decide(date: date, tableId: tableId).allowReminder
        }
    }

    private final class ProdAlarmPort: NotificationSchedulerBeforeClassAlarmPort {
        func setExact(id: String, epochMs: Int64, extras: [String: Any?]) {
            Task {
                let content = UNMutableNotificationContent()
                let courseName = extras["courseName"] as? String ?? ""
                let room = (extras["room"] as? String) ?? ""
                let teacher = (extras["teacher"] as? String) ?? ""
                let startTime = (extras["startTime"] as? String) ?? ""
                let roomStr = room.isEmpty ? L10n.t("notif_room_unknown") : room
                if teacher.isEmpty {
                    content.title = L10n.t("notif_before_class_title")
                    content.body = L10n.format("notif_before_class_text", courseName, startTime, roomStr)
                } else {
                    content.title = L10n.t("notif_before_class_title")
                    content.body = L10n.format("notif_before_class_text_with_teacher", courseName, startTime, roomStr, teacher)
                }
                content.sound = .default
                let date = Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000)
                let comps = DateUtils.isoCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                try? await UNUserNotificationCenter.current().add(req)
            }
        }
        func cancel(id: String) {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        }
    }

    private let env: NotificationSchedulerBeforeClassEnv
    private let dataSource: NotificationSchedulerBeforeClassDataSource
    private let alarmPort: NotificationSchedulerBeforeClassAlarmPort

    init() {
        self.env = ProdEnv()
        self.dataSource = ProdDataSource()
        self.alarmPort = ProdAlarmPort()
    }

    /// 测试构造器 — 注入 fake 端口。
    init(env: NotificationSchedulerBeforeClassEnv, dataSource: NotificationSchedulerBeforeClassDataSource, alarmPort: NotificationSchedulerBeforeClassAlarmPort) {
        self.env = env
        self.dataSource = dataSource
        self.alarmPort = alarmPort
    }

    // ==================== scheduleAll ← ====================

    func scheduleAll() {
        createChannels()
        Task {
            scheduleLock.lock(); defer { scheduleLock.unlock() }
            cancelRecurringLocked()

            guard prefs.isReminderEnabled() else {
                await cancelBeforeClassLocked()
                return
            }

            if prefs.isDailyReminderEnabled() {
                scheduleDaily()
                scheduleTomorrowReminder()
            }
            guard prefs.isBeforeClassEnabled() else {
                await cancelBeforeClassLocked()
                return
            }
            scheduleBeforeClassDailyResync()
            await resyncBeforeClassLocked()
        }
    }

    func cancelAll() async {
        scheduleLock.lock(); defer { scheduleLock.unlock() }
        cancelRecurringLocked()
        await cancelBeforeClassLocked()
    }

    private func cancelRecurringLocked() {
        alarmPort.cancel(id: Self.NOTIFY_DAILY)
        alarmPort.cancel(id: Self.NOTIFY_TOMORROW_DAILY)
        alarmPort.cancel(id: Self.NOTIFY_RESYNC)
    }

    private func cancelBeforeClassLocked() async {
        alarmPort.cancel(id: Self.NOTIFY_RESYNC)
        await cancelBeforeClassCourseAlarmsLocked()
    }

    private func cancelBeforeClassCourseAlarmsLocked() async {
        // 账本覆盖已删课程/已换掉的课表; 现存课程 id 覆盖账本上线前旧版本排下的闹钟
        let courseIds = dataSource.allCourseIds()
        let armed = env.loadArmedIds()
        var all = armed
        for id in courseIds {
            all.insert(Self.NOTIFY_BEFORE_CLASS_PREFIX + String(id))
        }
        for id in all {
            alarmPort.cancel(id: id)
        }
        env.saveArmedIds([])
    }

    /// 取消指定课程 id 的课前通知(ScheduleRepository.deleteTable 调 — 孤儿清理)。
    func cancelCourseAlarms(courseIds: [Int64]) {
        for id in courseIds {
            alarmPort.cancel(id: Self.NOTIFY_BEFORE_CLASS_PREFIX + String(id))
        }
    }

    // ==================== Daily ====================

    private func scheduleDaily() {
        scheduleDailyAlarm(
            timeStr: prefs.getDailyReminderTime(),
            fallbackHour: 7, fallbackMinute: 0,
            identifier: Self.NOTIFY_DAILY,
            isTomorrowPreview: false
        )
    }

    private func scheduleTomorrowReminder() {
        guard prefs.isTomorrowReminderEnabled() else { return }
        scheduleDailyAlarm(
            timeStr: prefs.getTomorrowReminderTime(),
            fallbackHour: 22, fallbackMinute: 0,
            identifier: Self.NOTIFY_TOMORROW_DAILY,
            isTomorrowPreview: true
        )
    }

    private func scheduleDailyAlarm(
        timeStr: String, fallbackHour: Int, fallbackMinute: Int,
        identifier: String, isTomorrowPreview: Bool
    ) {
        let parts = timeStr.split(separator: ":").map(String.init)
        // 钳制到合法范围, 避免破损 pref 触发崩溃
        let hour = min(max(Int(parts.count > 0 ? parts[0] : "") ?? fallbackHour, 0), 23)
        let minute = min(max(Int(parts.count > 1 ? parts[1] : "") ?? fallbackMinute, 0), 59)

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        let content = UNMutableNotificationContent()
        Task {
            await fillDailyContent(content, targetDate: isTomorrowPreview
                ? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                : Date(),
                isTomorrowPreview: isTomorrowPreview)
            content.sound = .default
            let req = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await center.add(req)
        }
    }

    // ==================== Before-class 7 天幂等重同步 ====================

    /// 每日 00:05 的全窗口重同步触发器(幂等) — 静默通知, 到点后 UNUserNotificationCenter
    /// delegate 收到即调 scheduleNext7DaysExactAlarms()。
    private func scheduleBeforeClassDailyResync() {
        var comps = DateComponents()
        comps.hour = 0
        comps.minute = 5
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = "Sleepy"
        content.body = ""   // 静默 — delegate 侧 handleResync
        content.userInfo = ["sleepy_resync": true]
        let req = UNNotificationRequest(identifier: Self.NOTIFY_RESYNC, content: content, trigger: trigger)
        try? center.add(req)
    }

    /// 兼容入口 — 语义已升级为「未来 7 天全窗口重同步」(幂等)。
    func scheduleTodayBeforeClassAlarms() async {
        await scheduleNext7DaysExactAlarms()
    }

    /// 预排未来 7 个日历天(含今天)的课前通知, 幂等重同步。
    /// id = NOTIFY_BEFORE_CLASS_PREFIX + course.id, 同 id 重排由 iOS 原地替换,
    /// 只需撤销"上次排过、这次不再需要"的 id。上次排过的集合持久化在账本里。
    /// 学期范围外的天跳过(防呆: currentWeek 钳制会误匹配第 1 周的课)。
    func scheduleNext7DaysExactAlarms() async {
        scheduleLock.lock(); defer { scheduleLock.unlock() }
        await resyncBeforeClassLocked()
    }

    private func resyncBeforeClassLocked() async {
        let previous = env.loadArmedIds()
        let table = env.isBeforeClassEnabled() ? dataSource.resolveCurrentTable() : nil
        if table == nil {
            for id in previous { alarmPort.cancel(id: id) }
            env.saveArmedIds([])
            return
        }
        guard let table = table else { return }
        let minutes = env.beforeClassMinutes()
        let nowEpoch = env.nowEpochMs()
        let today = env.todayDate()
        let nodes = TimeTableUtils.parseNodes(table.timeJson)
        let cal = DateUtils.isoCalendar

        // 1) 枚举窗口内的天, 收集课程行(仅学期内且允许提醒的天)
        var days: [(Date, [CourseEntity])] = []
        for offset in 0..<Self.BEFORE_CLASS_WINDOW_DAYS {
            guard let date = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            if !semesterInRange(table: table, date: date) {
                days.append((date, []))
                continue
            }
            if !(await dataSource.allowsReminder(tableId: table.id, date: date)) {
                days.append((date, []))
                continue
            }
            let week = DateUtils.currentWeek(startDate: table.startDate, today: date)
            let dow = dataSource.effectiveDayOfWeek(tableId: table.id, date: date)
            let courses = dataSource.coursesForDay(tableId: table.id, dayOfWeek: dow).filter { $0.inWeek(week) }
            days.append((date, courses))
        }

        // 2) 逐天收集未来槽位; 同 courseId 保留最早的未来触发(先到先得)
        var desired: [(String, Int64, [String: Any?])] = []
        var desiredIds = Set<String>()
        for (date, courses) in days {
            for course in courses {
                let startTimeStr: String?
                if course.ownTime && !course.startTime.isEmpty {
                    startTimeStr = course.startTime
                } else if let node = nodes.first(where: { $0.node == course.startNode }) {
                    startTimeStr = TimeTableUtils.formatTime(node.start)
                } else {
                    startTimeStr = nil
                }
                guard let startStr = startTimeStr else { continue }
                let parts = startStr.split(separator: ":").map(String.init)
                guard let h = Int(parts.count > 0 ? parts[0] : ""),
                      let m = Int(parts.count > 1 ? parts[1] : ""),
                      (0...23).contains(h), (0...59).contains(m) else { continue }

                var comps = cal.dateComponents([.year, .month, .day], from: date)
                comps.hour = h; comps.minute = m
                guard let classStart = cal.date(from: comps) else { continue }
                let notifyTime = classStart.addingTimeInterval(-Double(minutes) * 60)
                let epoch = Int64(notifyTime.timeIntervalSince1970 * 1000)
                if epoch <= nowEpoch { continue }   // 已过触发点

                let id = Self.NOTIFY_BEFORE_CLASS_PREFIX + String(course.id)
                if desiredIds.contains(id) { continue }
                desiredIds.insert(id)

                let endTimeStr: String = {
                    if course.ownTime && !course.endTime.isEmpty { return course.endTime }
                    guard let node = nodes.first(where: { $0.node == course.startNode + course.step - 1 }) else { return "" }
                    return TimeTableUtils.formatTime(node.end)
                }()
                desired.append((id, epoch, [
                    "courseName": course.courseName,
                    "room": course.room,
                    "teacher": course.teacher,
                    "startTime": String(format: "%02d:%02d", h, m),
                    "endTime": endTimeStr,
                    "startNode": course.startNode,
                    "notifyEpoch": epoch,
                    "classEpoch": Int64(classStart.timeIntervalSince1970 * 1000),
                    "tableId": table.id,
                    "reminderDate": DateUtils.fullDate(date)
                ]))
            }
        }

        // 3) 撤销不再需要的: 账本里的 + 窗口内出现过的
        var toCancel = previous
        for (date, courses) in days {
            for c in courses {
                toCancel.insert(Self.NOTIFY_BEFORE_CLASS_PREFIX + String(c.id))
            }
        }
        for id in toCancel where !desiredIds.contains(id) {
            alarmPort.cancel(id: id)
        }
        for (id, epoch, extras) in desired {
            alarmPort.setExact(id: id, epochMs: epoch, extras: extras)
        }
        env.saveArmedIds(desiredIds)
    }

    private func semesterInRange(table: TimeTableEntity, date: Date) -> Bool {
        return DateUtils.semesterStatus(startDate: table.startDate, maxWeek: table.maxWeek, today: date) == .inRange
    }

    // ==================== Channels / 权限 ====================

    private func createChannels() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // ==================== Daily content 快照 ====================

    private func fillDailyContent(_ content: UNMutableNotificationContent, targetDate: Date, isTomorrowPreview: Bool) async {
        let dowRaw = DateUtils.isoCalendar.component(.weekday, from: targetDate)
        let dow = dowRaw == 1 ? 7 : dowRaw - 1
        let dayOfMonth = DateUtils.isoCalendar.component(.day, from: targetDate)

        guard let repo = repositoryProvider?(),
              let table = WidgetTableResolver.resolveCurrentTable(repo) else {
            content.title = L10n.format(isTomorrowPreview ? "notif_tomorrow_title_no_course" : "notif_daily_title_no_course", dayOfMonth)
            content.body = L10n.t(isTomorrowPreview ? "notif_tomorrow_text_no_course" : "notif_daily_text_no_course")
            return
        }
        // 节假日提醒策略门控 — 放假日不发摘要
        if !(await HolidayReminderPolicyAdapter.decide(date: targetDate, tableId: table.id)).allowReminder {
            content.title = ""
            content.body = ""
            return
        }
        let effDow = HolidayTransferHelper.effectiveDayOfWeek(table.id, targetDate)
        let week = DateUtils.currentWeek(startDate: table.startDate, today: targetDate)
        let inSemester = DateUtils.semesterStatus(startDate: table.startDate, maxWeek: table.maxWeek, today: targetDate) == .inRange
        let courses: [CourseEntity] = inSemester
            ? ((try? repo.getCoursesByDay(table.id, day: effDow)) ?? []).filter { $0.inWeek(week) }.sorted { $0.startNode < $1.startNode }
            : []

        if courses.isEmpty {
            content.title = L10n.format(isTomorrowPreview ? "notif_tomorrow_title_no_course" : "notif_daily_title_no_course", dayOfMonth)
            content.body = L10n.t(isTomorrowPreview ? "notif_tomorrow_text_no_course" : "notif_daily_text_no_course")
            return
        }
        content.title = L10n.format(isTomorrowPreview ? "notif_tomorrow_title" : "notif_daily_title", dayOfMonth, courses.count)
        let first = courses[0]
        let firstTime = Self.courseStartTime(first, table)
        let firstRoom = first.room.isEmpty ? L10n.t("notif_room_unknown") : first.room
        content.body = L10n.format("notif_daily_text_first", first.courseName, firstTime, firstRoom)
    }

    /// ← getCourseStartTime(course, table)
    static func courseStartTime(_ course: CourseEntity, _ table: TimeTableEntity) -> String {
        if course.ownTime && !course.startTime.isEmpty { return course.startTime }
        let nodes = TimeTableUtils.parseNodes(table.timeJson)
        guard let node = nodes.first(where: { $0.node == course.startNode }) else { return "" }
        return TimeTableUtils.formatTime(node.start)
    }
}

// MARK: - 可注入端口(JVM 单测接缝, 顶层 — Swift 不允许协议嵌套在类内)

/// 课前通知环境值 — prefs/时钟/账本读取接缝。
protocol NotificationSchedulerBeforeClassEnv {
    func isBeforeClassEnabled() -> Bool
    func beforeClassMinutes() -> Int
    func nowEpochMs() -> Int64
    func todayDate() -> Date
    func loadArmedIds() -> Set<String>
    func saveArmedIds(_ ids: Set<String>)
}

/// 课前通知数据源 — 课表/课程查询接缝。
protocol NotificationSchedulerBeforeClassDataSource {
    func resolveCurrentTable() -> TimeTableEntity?
    func coursesForDay(tableId: Int64, dayOfWeek: Int) -> [CourseEntity]
    func allCourseIds() -> [Int64]
    func effectiveDayOfWeek(tableId: Int64?, date: Date) -> Int
    func allowsReminder(tableId: Int64, date: Date) async -> Bool
}

/// 课前通知落地端口 — UNUserNotificationCenter 接缝。
protocol NotificationSchedulerBeforeClassAlarmPort {
    func setExact(id: String, epochMs: Int64, extras: [String: Any?])
    func cancel(id: String)
}
