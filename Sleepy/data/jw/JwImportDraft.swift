// JwImportDraft.swift — ← data/jw/JwImportDraft.kt
// The resumable part of the JW import confirmation flow.
//
// This is deliberately independent of GRDB, SwiftUI, and UIKit state so a
// future screen or persistence adapter can consume it without changing the import model.

import Foundation

struct JwImportDraftSnapshot: Equatable {
    var school: JwSchoolInfo
    var courses: [JwCourse]
    var periods: [JwImportDraftPeriod]
    var termStartDate: String = ""
    var tableName: String = ""
    /// Serialized SmartPeriodConfig; kept opaque to avoid coupling this contract to UI/entity classes.
    var smartConfigJson: String = ""
    var phase: JwImportDraftPhase = .configureConfirm
}

struct JwImportDraftPeriod: Equatable {
    var node: Int
    var start: String
    var end: String
}

enum JwImportDraftPhase: String {
    case webViewLogin = "WEBVIEW_LOGIN"
    case configureConfirm = "CONFIGURE_CONFIRM"
}

/// Versioned JSON boundary for JwImportDraftSnapshot.
enum JwImportDraftCodec {
    static let SCHEMA_VERSION = 1

    static func toJson(_ snapshot: JwImportDraftSnapshot) -> String {
        var root: [String: Any] = [
            "schemaVersion": SCHEMA_VERSION,
            "phase": snapshot.phase.rawValue,
            "school": schoolToJson(snapshot.school),
            "courses": snapshot.courses.map(courseToJson),
            "periods": snapshot.periods.map(periodToJson),
            "termStartDate": snapshot.termStartDate,
            "tableName": snapshot.tableName,
            "smartConfigJson": snapshot.smartConfigJson
        ]
        if let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "{}"
        _ = root
    }

    /// Returns nil for an unsupported schema or any invalid/incomplete external payload.
    static func fromJson(_ json: String) -> JwImportDraftSnapshot? {
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let schema = (root["schemaVersion"] as? Int) ?? -1
        if schema != SCHEMA_VERSION { return nil }

        let phaseRaw = (root["phase"] as? String) ?? JwImportDraftPhase.configureConfirm.rawValue
        guard let phase = JwImportDraftPhase(rawValue: phaseRaw) else { return nil }

        guard let schoolJson = root["school"] as? [String: Any],
              let school = schoolFromJson(schoolJson) else { return nil }
        guard let coursesJson = root["courses"] as? [[String: Any]] else { return nil }
        guard let periodsJson = root["periods"] as? [[String: Any]] else { return nil }

        var courses: [JwCourse] = []
        for cj in coursesJson {
            guard let c = courseFromJson(cj) else { return nil }
            courses.append(c)
        }
        var periods: [JwImportDraftPeriod] = []
        for pj in periodsJson {
            guard let p = periodFromJson(pj) else { return nil }
            periods.append(p)
        }

        return JwImportDraftSnapshot(
            school: school,
            courses: courses,
            periods: periods,
            termStartDate: (root["termStartDate"] as? String) ?? "",
            tableName: (root["tableName"] as? String) ?? "",
            smartConfigJson: (root["smartConfigJson"] as? String) ?? "",
            phase: phase
        )
    }

    // MARK: - school

    private static func schoolToJson(_ school: JwSchoolInfo) -> [String: Any] {
        return [
            "sortKey": school.sortKey,
            "name": school.name,
            "url": school.url,
            "type": school.type ?? NSNull(),
            "status": school.status,
            "aliases": school.aliases,
            "sortKeyFull": school.sortKeyFull,
            "enableFetch": school.enableFetch
        ]
    }

    private static func schoolFromJson(_ json: [String: Any]) -> JwSchoolInfo? {
        let sortKey = (json["sortKey"] as? String) ?? ""
        let name = (json["name"] as? String) ?? ""
        if sortKey.isBlank || name.isBlank { return nil }
        var aliases: [String] = []
        if let aliasesJson = json["aliases"] as? [String] {
            for alias in aliasesJson {
                if alias.isBlank { return nil }
                aliases.append(alias)
            }
        }
        let typeStr = (json["type"] as? String) ?? ""
        return JwSchoolInfo(
            sortKey: sortKey,
            name: name,
            url: (json["url"] as? String) ?? "",
            type: typeStr.isBlank ? nil : typeStr,
            status: (json["status"] as? String) ?? JwSchoolInfo.STATUS_SUPPORTED,
            aliases: aliases,
            sortKeyFull: (json["sortKeyFull"] as? String) ?? "",
            enableFetch: (json["enableFetch"] as? Bool) ?? false
        )
    }

    // MARK: - course

    private static func courseToJson(_ course: JwCourse) -> [String: Any] {
        return [
            "name": course.name,
            "room": course.room,
            "teacher": course.teacher,
            "day": course.day,
            "startNode": course.startNode,
            "endNode": course.endNode,
            "startWeek": course.startWeek,
            "endWeek": course.endWeek,
            "type": course.type
        ]
    }

    private static func courseFromJson(_ json: [String: Any]) -> JwCourse? {
        let course = JwCourse(
            name: (json["name"] as? String) ?? "",
            room: (json["room"] as? String) ?? "",
            teacher: (json["teacher"] as? String) ?? "",
            day: (json["day"] as? Int) ?? 0,
            startNode: (json["startNode"] as? Int) ?? 0,
            endNode: (json["endNode"] as? Int) ?? 0,
            startWeek: (json["startWeek"] as? Int) ?? 0,
            endWeek: (json["endWeek"] as? Int) ?? 0,
            type: (json["type"] as? Int) ?? 0
        )
        guard !course.name.isBlank, (1...7).contains(course.day),
              course.startNode >= 1, course.endNode >= course.startNode,
              course.startWeek >= 1, course.endWeek >= course.startWeek,
              course.type >= 0 else { return nil }
        return course
    }

    // MARK: - period

    private static func periodToJson(_ period: JwImportDraftPeriod) -> [String: Any] {
        return [
            "node": period.node,
            "start": period.start,
            "end": period.end
        ]
    }

    private static func periodFromJson(_ json: [String: Any]) -> JwImportDraftPeriod? {
        let period = JwImportDraftPeriod(
            node: (json["node"] as? Int) ?? 0,
            start: (json["start"] as? String) ?? "",
            end: (json["end"] as? String) ?? ""
        )
        let hhmm = "^\\d{2}:\\d{2}$"
        guard period.node >= 1,
              (period.start.isBlank && period.end.isBlank)
                  || (period.start.range(of: hhmm, options: .regularExpression) != nil
                      && period.end.range(of: hhmm, options: .regularExpression) != nil
                      && period.start < period.end) else { return nil }
        return period
    }
}
