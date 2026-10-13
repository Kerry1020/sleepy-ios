// SystemCalendarManager.swift — ← data/calendar/SystemCalendarManager.kt
// Direct EventKit integration. The event-date expansion stays inside this flow.
//
// iOS 适配:
//   - Android CalendarContract ContentResolver → EventKit EKEventStore
//   - METHOD_ALARM/METHOD_ALERT 区分 → EKAlarm (相对分钟数; iOS 无 alarm method 概念,
//     全部映射为 relativeOffset 提醒; alarmFallback 语义退化为"提醒是否存在")
//   - fingerprint: SHA-256(calendarId/title/location/description/start/end/timezone/reminder)
//     与 Android 1:1 的拼接顺序, 用 \u001f 分隔
//   - marker 恢复: 描述尾部 "Sleepy import key:" 前缀, findEventByMarker 用 predicate 搜索

import Foundation
import EventKit
import GRDB

enum CalendarImportRange: String, CaseIterable {
    case NEXT_WEEK
    case NEXT_MONTH
    case SEMESTER
}

struct SystemCalendarInfo: Identifiable {
    let id: String                  // EKCalendar.calendarIdentifier
    let displayName: String
    let accountName: String         // EKSource.sourceIdentifier
    let accountType: String         // sourceType 描述
}

struct CalendarImportOptions {
    var calendarId: String
    var range: CalendarImportRange
    var applyHolidayTransfers: Bool
    var reminderMinutes: Int?
    var firstPeriodAlarmEnabled: Bool
    var firstPeriodAlarmMinutes: Int
}

struct CalendarImportPreviewRow: Identifiable {
    let date: Date
    let start: String
    let end: String
    let courseName: String
    let teacher: String
    let room: String
    let week: Int
    let transferred: Bool
    let firstPeriodAlarm: Bool
    var id: String { "\(date.timeIntervalSince1970)-\(courseName)-\(start)" }
}

struct CalendarImportPreview {
    let rows: [CalendarImportPreviewRow]
    let skippedInvalidTime: Int
    let startDate: Date
    let endDateExclusive: Date
}

struct CalendarImportResult {
    var inserted: Int = 0
    var updated: Int = 0
    var unchanged: Int = 0
    var skippedEdited: Int = 0
    var skippedInvalidTime: Int = 0
    var alarmFallback: Int = 0
    var errors: Int = 0
}

struct CalendarDeleteResult {
    let deleted: Int
    let skippedEdited: Int
    let missing: Int
}

/// 系统日历直连 — 事件日期展开留在本流程内。
enum SystemCalendarManager {
    private static let SLEEPY_MARKER_PREFIX = "Sleepy import key:"
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static var store = EKEventStore()

    // MARK: - 权限

    static func requestAccess() async -> Bool {
        // 本工具链 (Xcode 14.3 / iOS 16.4 SDK) 无 requestFullAccessToEvents;
        // requestWriteOnlyAccessToEvents 同缺。统一走 requestAccess(to: .event)
        // (iOS 17 上系统自动映射 full-access 提示)。
        return await withCheckedContinuation { cont in
            store.requestAccess(to: .event) { granted, _ in
                cont.resume(returning: granted)
            }
        }
    }

    static func hasCalendarPermissions() -> Bool {
        return EKEventStore.authorizationStatus(for: .event) == .authorized
    }

    // MARK: - 日历列表

    /// 可写日历 — allowsContentModifications + 标题不区分大小写排序。
    /// (Android isPrimary 排序在 iOS 无对应字段 — EKCalendar.isPrimary 是 macOS-only)
    static func writableCalendars() -> [SystemCalendarInfo] {
        guard hasCalendarPermissions() else { return [] }
        let writable = store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return writable.map { cal in
                SystemCalendarInfo(
                    id: cal.calendarIdentifier,
                    displayName: cal.title.isBlank ? (cal.source.title) : cal.title,
                    accountName: cal.source.title,
                    accountType: "\(cal.source.sourceType)"
                )
            }
    }

    // MARK: - 预览 (纯计算, 不触 EventKit)

    static func buildPreview(
        table: TimeTableEntity,
        courses: [CourseEntity],
        options: CalendarImportOptions,
        today: Date = Date()
    ) -> CalendarImportPreview {
        let (from, until) = selectedDateRange(table: table, range: options.range, today: today)
        let (specs, invalid) = buildEventSpecs(table: table, courses: courses, options: options, from: from, until: until)
        let alarms = firstPeriodAlarmKeys(specs)
        let rows = specs.map { spec in
            CalendarImportPreviewRow(
                date: spec.date,
                start: timeFormatter.string(from: spec.start),
                end: timeFormatter.string(from: spec.end),
                courseName: spec.title,
                teacher: spec.course.teacher,
                room: spec.location,
                week: spec.week,
                transferred: spec.description.contains("调课安排："),
                firstPeriodAlarm: alarms[spec.date] == spec.key
            )
        }
        return CalendarImportPreview(rows: rows, skippedInvalidTime: invalid, startDate: from, endDateExclusive: until)
    }

    // MARK: - 导入

    static func `import`(
        table: TimeTableEntity,
        courses: [CourseEntity],
        options: CalendarImportOptions,
        batchId: String
    ) async -> CalendarImportResult {
        guard hasCalendarPermissions() else { return CalendarImportResult(errors: 1) }
        let calendars = writableCalendars()
        guard let calendar = calendars.first(where: { $0.id == options.calendarId }),
              let ekCalendar = store.calendar(withIdentifier: options.calendarId) else {
            return CalendarImportResult(errors: 1)
        }
        let preview = buildPreview(table: table, courses: courses, options: options)
        let startInclusive = preview.startDate
        let endExclusive = preview.endDateExclusive
        let (specs, _) = buildEventSpecs(table: table, courses: courses, options: options, from: startInclusive, until: endExclusive)
        let alarmKeys = firstPeriodAlarmKeys(specs)

        let db = AppDatabase.getShared()
        let dao = CalendarImportRecordDao(db: db.dbQueue)
        var result = CalendarImportResult(skippedInvalidTime: preview.skippedInvalidTime)
        let startStr = fullDateFormatter.string(from: startInclusive)
        let endStr = fullDateFormatter.string(from: endExclusive)
        let allRecords: [CalendarImportRecordEntity] = (try? dao.forTable(table.id)) ?? []
        var existingRecords: [String: CalendarImportRecordEntity] = [:]
        for record in allRecords {
            guard record.calendarId == calendar.id, record.eventDate >= startStr, record.eventDate < endStr else {
                continue
            }
            existingRecords["\(record.courseId):\(record.eventDate)"] = record
        }

        for spec in specs {
            let key = "\(spec.course.id):\(fullDateFormatter.string(from: spec.date))"
            let record = existingRecords[key]
            let wantsAlarm = alarmKeys[spec.date] == spec.key
            let wantsReminder = wantsAlarm || options.reminderMinutes != nil
            let minutes = wantsAlarm ? min(max(options.firstPeriodAlarmMinutes, 0), 999) : options.reminderMinutes

            if let record = record {
                guard let old = readEvent(eventId: record.eventId) else {
                    try? dao.deleteById(record.id)
                    // fall through to insert below
                    if let eventId = insertEvent(spec: spec, calendar: ekCalendar, wantsReminder: wantsReminder, minutes: minutes) {
                        if let created = readEvent(eventId: eventId) {
                            try? dao.upsert(recordFor(tableId: table.id, spec: spec, calendarId: calendar.id,
                                                      eventId: eventId, batchId: batchId,
                                                      fingerprint: fingerprint(created), alarmRequested: wantsAlarm))
                            result.inserted += 1
                        } else { result.errors += 1 }
                    } else { result.errors += 1 }
                    continue
                }
                if fingerprint(old) != record.fingerprint {
                    result.skippedEdited += 1
                    continue
                }
                if eventMatchesSpec(old, spec: spec, calendarId: calendar.id)
                    && remindersMatch(old, wantsReminder: wantsReminder, minutes: minutes) {
                    result.unchanged += 1
                    continue
                }
                guard writeEvent(old: old, spec: spec, calendar: ekCalendar, wantsReminder: wantsReminder, minutes: minutes) else {
                    result.errors += 1
                    continue
                }
                // 保存后重读拿真实指纹
                if let after = readEvent(eventId: record.eventId) {
                    try? dao.upsert(recordFor(tableId: table.id, spec: spec, calendarId: calendar.id,
                                              eventId: record.eventId, batchId: batchId,
                                              fingerprint: fingerprint(after), alarmRequested: wantsAlarm))
                    result.updated += 1
                } else { result.errors += 1 }
                continue
            }

            // 进程死亡恢复 — 描述 marker 唯一定位
            if let recovered = findEventByMarker(calendarId: calendar.id, key: spec.key) {
                if !eventMatchesSpec(recovered, spec: spec, calendarId: calendar.id) {
                    result.skippedEdited += 1
                    continue
                }
                try? dao.upsert(recordFor(tableId: table.id, spec: spec, calendarId: calendar.id,
                                          eventId: recovered.eventId, batchId: batchId,
                                          fingerprint: fingerprint(recovered), alarmRequested: wantsAlarm))
                result.unchanged += 1
                continue
            }

            guard let eventId = insertEvent(spec: spec, calendar: ekCalendar, wantsReminder: wantsReminder, minutes: minutes) else {
                result.errors += 1
                continue
            }
            if let created = readEvent(eventId: eventId) {
                try? dao.upsert(recordFor(tableId: table.id, spec: spec, calendarId: calendar.id,
                                          eventId: eventId, batchId: batchId,
                                          fingerprint: fingerprint(created), alarmRequested: wantsAlarm))
                result.inserted += 1
            } else { result.errors += 1 }
        }
        return result
    }

    static func deleteManagedForTable(tableId: Int64) async -> CalendarDeleteResult {
        guard hasCalendarPermissions() else { return CalendarDeleteResult(deleted: 0, skippedEdited: 0, missing: 0) }
        let db = AppDatabase.getShared()
        let dao = CalendarImportRecordDao(db: db.dbQueue)
        let records: [CalendarImportRecordEntity] = (try? dao.forTable(tableId)) ?? []
        var deleted = 0, edited = 0, missing = 0
        for record in records {
            guard let snapshot = readEvent(eventId: record.eventId) else {
                try? dao.deleteById(record.id)
                missing += 1
                continue
            }
            if fingerprint(snapshot) == record.fingerprint,
               let liveEvent = store.event(withIdentifier: record.eventId) {
                do {
                    try store.remove(liveEvent, span: .thisEvent)
                    try? dao.deleteById(record.id)
                    deleted += 1
                } catch {
                    edited += 1
                }
            } else {
                edited += 1
            }
        }
        return CalendarDeleteResult(deleted: deleted, skippedEdited: edited, missing: missing)
    }

    // MARK: - EventKit 原语

    private struct EventSpec {
        let course: CourseEntity
        let date: Date
        let week: Int
        let start: Date
        let end: Date
        let title: String
        let location: String
        let description: String
        let key: String
        let reminderMinutes: Int?
        let wantsAlarm: Bool
    }

    private struct ExistingEvent {
        let eventId: String
        let calendarId: String
        let title: String
        let location: String
        let descriptionText: String
        let startDate: Date
        let endDate: Date
        let timezone: String
        let hasReminder: Bool
    }

    private static func insertEvent(spec: EventSpec, calendar: EKCalendar, wantsReminder: Bool, minutes: Int?) -> String? {
        let event = EKEvent(eventStore: store)
        applySpec(event, spec: spec, calendar: calendar)
        applyReminder(event, wantsReminder: wantsReminder, minutes: minutes)
        do {
            try store.save(event, span: .thisEvent)
            return event.calendarItemExternalIdentifier
        } catch { return nil }
    }

    private static func writeEvent(old: ExistingEvent, spec: EventSpec, calendar: EKCalendar, wantsReminder: Bool, minutes: Int?) -> Bool {
        guard let event = store.event(withIdentifier: old.eventId) else { return false }
        applySpec(event, spec: spec, calendar: calendar)
        applyReminder(event, wantsReminder: wantsReminder, minutes: minutes)
        do {
            try store.save(event, span: .thisEvent)
            return true
        } catch { return false }
    }

    private static func applySpec(_ event: EKEvent, spec: EventSpec, calendar: EKCalendar) {
        event.calendar = calendar
        event.title = spec.title
        event.location = spec.location
        event.notes = spec.description
        event.startDate = spec.start
        event.endDate = spec.end
        event.isAllDay = false
        event.availability = .busy
        event.timeZone = .current
    }

    private static func applyReminder(_ event: EKEvent, wantsReminder: Bool, minutes: Int?) {
        event.alarms = nil
        if wantsReminder, let minutes = minutes {
            // EKAlarm relativeOffset 负值 = 提前 N 秒
            event.addAlarm(EKAlarm(relativeOffset: -Double(minutes) * 60))
        }
    }

    private static func readEvent(eventId: String) -> ExistingEvent? {
        guard let event = store.event(withIdentifier: eventId) else { return nil }
        return existingFrom(event)
    }

    private static func existingFrom(_ event: EKEvent) -> ExistingEvent {
        return ExistingEvent(
            eventId: event.calendarItemExternalIdentifier,
            calendarId: event.calendar?.calendarIdentifier ?? "",
            title: event.title ?? "",
            location: event.location ?? "",
            descriptionText: event.notes ?? "",
            startDate: event.startDate,
            endDate: event.endDate,
            timezone: event.timeZone?.identifier ?? TimeZone.current.identifier,
            hasReminder: !(event.alarms ?? []).isEmpty
        )
    }

    private static func findEventByMarker(calendarId: String, key: String) -> ExistingEvent? {
        let marker = "\(SLEEPY_MARKER_PREFIX)\(key)"
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -400, to: Date()) ?? Date.distantPast
        let end = cal.date(byAdding: .day, value: 400, to: Date()) ?? Date.distantFuture
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        return events
            .filter { $0.calendar?.calendarIdentifier == calendarId && ($0.notes ?? "").contains(marker) }
            .map(existingFrom)
            .first
    }

    private static func recordFor(tableId: Int64, spec: EventSpec, calendarId: String, eventId: String,
                                  batchId: String, fingerprint: String, alarmRequested: Bool) -> CalendarImportRecordEntity {
        return CalendarImportRecordEntity(
            tableId: tableId,
            courseId: spec.course.id,
            eventDate: fullDateFormatter.string(from: spec.date),
            calendarId: calendarId,
            eventId: eventId,
            batchId: batchId,
            fingerprint: fingerprint,
            alarmRequested: alarmRequested
        )
    }

    private static func fingerprint(_ event: ExistingEvent) -> String {
        let raw = [
            event.calendarId, event.title, event.location, event.descriptionText,
            "\(event.startDate.timeIntervalSince1970)", "\(event.endDate.timeIntervalSince1970)",
            event.timezone, event.hasReminder ? "1" : "0"
        ].joined(separator: "\u{1f}")
        return sha256Hex(raw)
    }

    private static func sha256Hex(_ text: String) -> String {
        let data = Data(text.utf8)
        // CryptoKit iOS 13+; 项目 deployment 15.6 → 可用
        let digest = CryptoKitSHA256.hex(data)
        return digest
    }

    private static func eventMatchesSpec(_ event: ExistingEvent, spec: EventSpec, calendarId: String) -> Bool {
        return event.calendarId == calendarId && event.title == spec.title && event.location == spec.location
            && event.descriptionText == spec.description
            && event.startDate == spec.start && event.endDate == spec.end
            && event.timezone == TimeZone.current.identifier
    }

    private static func remindersMatch(_ event: ExistingEvent, wantsReminder: Bool, minutes: Int?) -> Bool {
        if !wantsReminder || minutes == nil { return !event.hasReminder }
        return event.hasReminder
    }

    // MARK: - 日期展开

    private static func selectedDateRange(table: TimeTableEntity, range: CalendarImportRange, today: Date) -> (Date, Date) {
        let cal = Calendar.current
        let semesterStart = mondayOf(DateUtils.parseDate(table.startDate) ?? today)
        let semesterEnd = cal.date(byAdding: .weekOfYear, value: table.maxWeek, to: semesterStart) ?? semesterStart
        let start = max(today, semesterStart)
        let requestedEnd: Date
        switch range {
        case .NEXT_WEEK: requestedEnd = cal.date(byAdding: .day, value: 7, to: today) ?? today
        case .NEXT_MONTH: requestedEnd = cal.date(byAdding: .month, value: 1, to: today) ?? today
        case .SEMESTER: requestedEnd = semesterEnd
        }
        return (start, min(requestedEnd, semesterEnd))
    }

    private static func mondayOf(_ date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? date
    }

    private static func buildEventSpecs(
        table: TimeTableEntity,
        courses: [CourseEntity],
        options: CalendarImportOptions,
        from: Date,
        until: Date
    ) -> ([EventSpec], Int) {
        if !(from < until) { return ([], 0) }
        let transfers = options.applyHolidayTransfers
            ? AppPrefs.shared.getHolidayTransfers(table.id) : []
        var specs: [EventSpec] = []
        var invalid = 0
        let cal = Calendar.current
        var date = from
        while date < until {
            let week = DateUtils.currentWeek(startDate: table.startDate, today: date)
            let nativeDow = cal.component(.weekday, from: date)             // 1=Sun..7=Sat
            let isoDow = nativeDow == 1 ? 7 : nativeDow - 1                 // 1=Mon..7=Sun
            let classDay = transfers.isEmpty ? isoDow
                : HolidayTransferOps.effectiveDayOfWeek(date, transfers)
            for course in courses where course.day == classDay && course.inWeek(week) {
                let interval = TimeTableUtils.effectiveCourseTime(
                    isIrregularTime: course.isIrregularTime,
                    startTime: course.startTime, endTime: course.endTime,
                    startNode: course.startNode, step: course.step,
                    timeJson: table.timeJson
                )
                guard let startStr = interval?.0, let endStr = interval?.1,
                      let start = parseHHmm(startStr, on: date),
                      let end = parseHHmm(endStr, on: date), end > start else {
                    invalid += 1
                    continue
                }
                let transferred = classDay != isoDow
                let markerKey = "\(table.id):\(course.id):\(fullDateFormatter.string(from: date))"
                let marker = "\(SLEEPY_MARKER_PREFIX)\(markerKey)"
                var description = "第\(week)周 · 第\(course.startNode)—\(course.startNode + course.step - 1)节"
                if !course.teacher.isBlank { description += "\n教师：\(course.teacher)" }
                if !course.note.isBlank { description += "\n备注：\(course.note)" }
                if transferred { description += "\n调课安排：按\(DateUtils.chineseDay(classDay))课程" }
                description += "\n\(marker)"
                specs.append(EventSpec(
                    course: course, date: date, week: week, start: start, end: end,
                    title: course.courseName, location: course.room,
                    description: description, key: markerKey,
                    reminderMinutes: options.reminderMinutes.map { min(max($0, 0), 999) },
                    wantsAlarm: options.firstPeriodAlarmEnabled && course.startNode <= 1
                        && course.startNode + course.step > 1 && start < noon(of: date)
                ))
            }
            date = cal.date(byAdding: .day, value: 1, to: date) ?? until
        }
        return (specs, invalid)
    }

    private static func firstPeriodAlarmKeys(_ specs: [EventSpec]) -> [Date: String] {
        // 同日多节都要早课提醒 → 取开始时间最早(并列取 course.id 小)的那节
        var byDate: [Date: [EventSpec]] = [:]
        for spec in specs where spec.wantsAlarm {
            byDate[spec.date, default: []].append(spec)
        }
        var out: [Date: String] = [:]
        for (date, rows) in byDate {
            let winner = rows.min { a, b in
                if a.start != b.start { return a.start < b.start }
                return a.course.id < b.course.id
            }
            if let w = winner { out[date] = w.key }
        }
        return out
    }

    private static func parseHHmm(_ s: String, on date: Date) -> Date? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour = h; comps.minute = m
        return cal.date(from: comps)
    }

    private static func noon(of date: Date) -> Date {
        return parseHHmm("12:00", on: date) ?? date
    }
}

// MARK: - CryptoKit SHA-256 hex

import CryptoKit

enum CryptoKitSHA256 {
    static func hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Sequence.associateBy (Kotlin stdlib)

private extension Sequence {
    func associateBy<K: Hashable>(_ keyFor: (Element) -> K) -> [K: Element] {
        var out: [K: Element] = [:]
        for element in self { out[keyFor(element)] = element }
        return out
    }
}
