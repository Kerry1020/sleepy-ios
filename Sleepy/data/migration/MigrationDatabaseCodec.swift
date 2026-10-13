// MigrationDatabaseCodec.swift — ← data/migration/MigrationDatabaseCodec.kt
// database 模块 codec — GRDB 四表结构化快照。
// DTO 与实体字段一一对应(列名稳定, Codable 缺省字段向前兼容);
// 导出冻结一次快照, 导入先完整解码再写库。
//
// Swift 适配注: GRDB 实体用合成 init,字段顺序按声明序;id 在最后。
// credit 字段 Swift 端为 Double(GRDB 持久化层精度),与 Kotlin Float 跨端时
// 接受双精度 — 数据库列类型 .double 与之对应。
// 实体 struct 没有 .copy() 方法 — 用临时 var 改字段后整体 re-init。

import Foundation
import GRDB

/// database 模块 codec — 与 Android MigrationDatabaseCodec.kt 1:1。
enum MigrationDatabaseCodec {

    // MARK: - DTO row 类型(Codable, JSON 协议稳定)

    struct CourseRow: Codable {
        var id: Int64
        var groupId: String
        var tableId: Int64
        var courseName: String
        var teacher: String = ""
        var room: String = ""
        var note: String = ""
        var alias: String = ""
        var day: Int
        var startNode: Int
        var step: Int
        var startWeek: Int
        var endWeek: Int
        var type: Int = 0
        var color: String
        var colorMode: Int = 0
        var ownTime: Bool = false
        var isIrregularNode: Bool = false
        var isIrregularTime: Bool = false
        var startTime: String = ""
        var endTime: String = ""
        var credit: Double = 0
        var level: Int = 0
    }

    struct TimeTableRow: Codable {
        var id: Int64
        var name: String
        var startDate: String
        var maxWeek: Int = 20
        var nodesPerDay: Int = 12
        var timeJson: String
        var color: String = "#FF6750A4"
        var isDefault: Bool = false
        var smartConfigJson: String = ""
        var createdAt: Int64
        var periodTableId: Int64? = nil
        var preBindSnapshotJson: String = ""
    }

    struct PeriodTableRow: Codable {
        var id: Int64
        var name: String
        var nodesPerDay: Int = 12
        var timeJson: String
        var smartConfigJson: String = ""
        var createdAt: Int64
        var updatedAt: Int64
    }

    struct ImportDraftRow: Codable {
        var id: String
        var sourceType: String = ""
        var sourceUrl: String = ""
        var payloadJson: String
        var createdAt: Int64
        var updatedAt: Int64
    }

    struct DatabaseSnapshot: Codable {
        var periodTables: [PeriodTableRow] = []
        var timeTables: [TimeTableRow] = []
        var courses: [CourseRow] = []
        var importDrafts: [ImportDraftRow] = []
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private static let decoder = JSONDecoder()

    static func encode(_ snapshot: DatabaseSnapshot) throws -> String {
        let data = try encoder.encode(snapshot)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func decode(_ text: String) throws -> DatabaseSnapshot {
        guard let data = text.data(using: .utf8) else {
            throw MigrationPackageException(message: "database snapshot not utf-8")
        }
        return try decoder.decode(DatabaseSnapshot.self, from: data)
    }

    // MARK: - 实体 ↔ DTO (与 Android extension 1:1)

    static func toRow(_ e: CourseEntity) -> CourseRow {
        return CourseRow(
            id: e.id, groupId: e.groupId, tableId: e.tableId, courseName: e.courseName,
            teacher: e.teacher, room: e.room, note: e.note, alias: e.alias, day: e.day,
            startNode: e.startNode, step: e.step, startWeek: e.startWeek, endWeek: e.endWeek,
            type: e.type, color: e.color, colorMode: e.colorMode, ownTime: e.ownTime,
            isIrregularNode: e.isIrregularNode, isIrregularTime: e.isIrregularTime,
            startTime: e.startTime, endTime: e.endTime, credit: e.credit, level: e.level
        )
    }

    static func toRow(_ e: TimeTableEntity) -> TimeTableRow {
        return TimeTableRow(
            id: e.id, name: e.name, startDate: e.startDate, maxWeek: e.maxWeek,
            nodesPerDay: e.nodesPerDay, timeJson: e.timeJson, color: e.color,
            isDefault: e.isDefault, smartConfigJson: e.smartConfigJson,
            createdAt: e.createdAt, periodTableId: e.periodTableId,
            preBindSnapshotJson: e.preBindSnapshotJson
        )
    }

    static func toRow(_ e: PeriodTableEntity) -> PeriodTableRow {
        return PeriodTableRow(
            id: e.id, name: e.name, nodesPerDay: e.nodesPerDay, timeJson: e.timeJson,
            smartConfigJson: e.smartConfigJson, createdAt: e.createdAt, updatedAt: e.updatedAt
        )
    }

    static func toRow(_ e: ImportDraftEntity) -> ImportDraftRow {
        return ImportDraftRow(
            id: e.id, sourceType: e.sourceType, sourceUrl: e.sourceUrl,
            payloadJson: e.payloadJson, createdAt: e.createdAt, updatedAt: e.updatedAt
        )
    }

    /// 实体转回 DTO — 注意字段顺序:合成 init 字段顺序与声明序一致,id 在最后。
    static func toEntity(_ r: CourseRow) -> CourseEntity {
        return CourseEntity(
            groupId: r.groupId, tableId: r.tableId, courseName: r.courseName,
            teacher: r.teacher, room: r.room, note: r.note, day: r.day,
            startNode: r.startNode, step: r.step, startWeek: r.startWeek, endWeek: r.endWeek,
            type: r.type, color: r.color, colorMode: r.colorMode,
            isIrregularNode: r.isIrregularNode, isIrregularTime: r.isIrregularTime,
            ownTime: r.ownTime, startTime: r.startTime, endTime: r.endTime,
            alias: r.alias, credit: r.credit, level: r.level,
            id: r.id
        )
    }

    static func toEntity(_ r: TimeTableRow) -> TimeTableEntity {
        return TimeTableEntity(
            name: r.name, startDate: r.startDate, maxWeek: r.maxWeek,
            nodesPerDay: r.nodesPerDay, timeJson: r.timeJson, color: r.color,
            isDefault: r.isDefault, smartConfigJson: r.smartConfigJson,
            createdAt: r.createdAt, periodTableId: r.periodTableId,
            preBindSnapshotJson: r.preBindSnapshotJson,
            id: r.id
        )
    }

    static func toEntity(_ r: PeriodTableRow) -> PeriodTableEntity {
        return PeriodTableEntity(
            name: r.name, nodesPerDay: r.nodesPerDay, timeJson: r.timeJson,
            smartConfigJson: r.smartConfigJson, createdAt: r.createdAt, updatedAt: r.updatedAt,
            id: r.id
        )
    }

    static func toEntity(_ r: ImportDraftRow) -> ImportDraftEntity {
        return ImportDraftEntity(
            id: r.id, sourceType: r.sourceType, sourceUrl: r.sourceUrl,
            payloadJson: r.payloadJson, createdAt: r.createdAt, updatedAt: r.updatedAt
        )
    }

    // MARK: - 收集与写入 (DAO 面)

    /// 收集四表全量 → 一次快照。
    /// iOS: GRDB DAO 的 getAll() throws 而非 suspend,故本函数亦 throws。
    static func collect(
        courseDao: CourseDao,
        timeTableDao: TimeTableDao,
        periodTableDao: PeriodTableDao,
        importDraftDao: ImportDraftDao
    ) throws -> DatabaseSnapshot {
        return DatabaseSnapshot(
            periodTables: try periodTableDao.getAll().map(toRow),
            timeTables: try timeTableDao.getAll().map(toRow),
            courses: try courseDao.getAllCourses().map(toRow),
            importDrafts: try importDraftDao.getAll().map(toRow)
        )
    }

    /// 覆盖导入: 四表全量替换, 保留包内原始 ID 与关系。
    /// 写入顺序遵循 FK: period_tables → time_tables → courses; import_drafts 无 FK。
    /// iOS: GRDB 没有 auto-clear + insertAll 原子操作,分步走但 wrap 在 Database.write 里
    /// (AppDatabase 提供 db queue),保证半失败不污染本机数据。
    static func applyOverwrite(
        _ snapshot: DatabaseSnapshot,
        courseDao: CourseDao,
        timeTableDao: TimeTableDao,
        periodTableDao: PeriodTableDao,
        importDraftDao: ImportDraftDao,
        dbQueue: DatabaseQueue
    ) throws {
        try dbQueue.write { db in
            try importDraftDao.deleteAllInDb(db)
            try courseDao.deleteAllInDb(db)
            try timeTableDao.deleteAllInDb(db)
            try periodTableDao.deleteAllInDb(db)
            try periodTableDao.insertAllInDb(db, snapshot.periodTables.map(toEntity))
            try timeTableDao.insertAllInDb(db, snapshot.timeTables.map(toEntity))
            // 课程行保留 ID(Android insertKeepId)
            for row in snapshot.courses {
                try courseDao.insertKeepIdInDb(db, toEntity(row))
            }
            for row in snapshot.importDrafts {
                try importDraftDao.upsertInDb(db, toEntity(row))
            }
        }
    }

    /// 合并导入: 保留本机数据, 追加包内数据。
    /// 表/课以新自增 ID 落库并重映射 FK(不与本地 ID 冲突);
    /// 草稿主键是业务字符串 ID, 同 ID 视为同一草稿 → upsert。
    static func applyMerge(
        _ snapshot: DatabaseSnapshot,
        courseDao: CourseDao,
        timeTableDao: TimeTableDao,
        periodTableDao: PeriodTableDao,
        importDraftDao: ImportDraftDao,
        dbQueue: DatabaseQueue
    ) throws {
        try dbQueue.write { db in
            var periodIdMap: [Int64: Int64] = [:]
            for row in snapshot.periodTables {
                let newId = try periodTableDao.insertInDb(db, toEntity(row).withId(0))
                periodIdMap[row.id] = newId
            }
            var tableIdMap: [Int64: Int64] = [:]
            for row in snapshot.timeTables {
                let mappedPeriod = row.periodTableId.flatMap { periodIdMap[$0] }
                let newId = try timeTableDao.insertInDb(db, toEntity(row).withPeriodId(mappedPeriod).withId(0))
                tableIdMap[row.id] = newId
            }
            for row in snapshot.courses {
                guard let newTableId = tableIdMap[row.tableId] else { continue }
                try courseDao.insertInDb(db, toEntity(row).withId(0).withTableId(newTableId))
            }
            for row in snapshot.importDrafts {
                try importDraftDao.upsertInDb(db, toEntity(row))
            }
        }
    }
}

// MARK: - Entity 派生 helpers (Swift struct 无 .copy() — 用 withX 系列方法)

private extension CourseEntity {
    func withId(_ newId: Int64) -> CourseEntity {
        return CourseEntity(
            groupId: groupId, tableId: tableId, courseName: courseName,
            teacher: teacher, room: room, note: note, day: day,
            startNode: startNode, step: step, startWeek: startWeek, endWeek: endWeek,
            type: type, color: color, colorMode: colorMode,
            isIrregularNode: isIrregularNode, isIrregularTime: isIrregularTime,
            ownTime: ownTime, startTime: startTime, endTime: endTime,
            alias: alias, credit: credit, level: level,
            id: newId
        )
    }
    func withTableId(_ newId: Int64) -> CourseEntity {
        return withId(id).replacing(tableId: newId)
    }
    func replacing(tableId: Int64) -> CourseEntity {
        return CourseEntity(
            groupId: groupId, tableId: tableId, courseName: courseName,
            teacher: teacher, room: room, note: note, day: day,
            startNode: startNode, step: step, startWeek: startWeek, endWeek: endWeek,
            type: type, color: color, colorMode: colorMode,
            isIrregularNode: isIrregularNode, isIrregularTime: isIrregularTime,
            ownTime: ownTime, startTime: startTime, endTime: endTime,
            alias: alias, credit: credit, level: level,
            id: id
        )
    }
}

private extension TimeTableEntity {
    func withId(_ newId: Int64) -> TimeTableEntity {
        return TimeTableEntity(
            name: name, startDate: startDate, maxWeek: maxWeek,
            nodesPerDay: nodesPerDay, timeJson: timeJson, color: color,
            isDefault: isDefault, smartConfigJson: smartConfigJson,
            createdAt: createdAt, periodTableId: periodTableId,
            preBindSnapshotJson: preBindSnapshotJson,
            id: newId
        )
    }
    func withPeriodId(_ pid: Int64?) -> TimeTableEntity {
        return TimeTableEntity(
            name: name, startDate: startDate, maxWeek: maxWeek,
            nodesPerDay: nodesPerDay, timeJson: timeJson, color: color,
            isDefault: isDefault, smartConfigJson: smartConfigJson,
            createdAt: createdAt, periodTableId: pid,
            preBindSnapshotJson: preBindSnapshotJson,
            id: id
        )
    }
}

private extension PeriodTableEntity {
    func withId(_ newId: Int64) -> PeriodTableEntity {
        return PeriodTableEntity(
            name: name, nodesPerDay: nodesPerDay, timeJson: timeJson,
            smartConfigJson: smartConfigJson, createdAt: createdAt, updatedAt: updatedAt,
            id: newId
        )
    }
}
