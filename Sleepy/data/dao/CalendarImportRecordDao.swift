// CalendarImportRecordDao.swift — ← data/dao/CalendarImportRecordDao.kt 逐条 SQL 翻译 (GPL-3.0)

import Foundation
import GRDB

struct CalendarImportRecordDao {
    let db: DatabaseWriter

    // @Insert(onConflict = REPLACE) → Long
    @discardableResult
    func upsert(_ record: CalendarImportRecordEntity) throws -> Int64 {
        var record = record
        try db.write { try record.insert($0, onConflict: .replace) }
        return record.id
    }

    // SELECT * FROM calendar_import_records WHERE tableId = :tableId
    func forTable(_ tableId: Int64) throws -> [CalendarImportRecordEntity] {
        try db.read {
            try CalendarImportRecordEntity.fetchAll($0, sql: "SELECT * FROM calendar_import_records WHERE tableId = ?", arguments: [tableId])
        }
    }

    // SELECT * … WHERE tableId=:t AND courseId=:c AND eventDate=:d AND calendarId=:cal LIMIT 1
    func find(tableId: Int64, courseId: Int64, eventDate: String, calendarId: String) throws -> CalendarImportRecordEntity? {
        try db.read {
            try CalendarImportRecordEntity.fetchOne(
                $0,
                sql: "SELECT * FROM calendar_import_records WHERE tableId = ? AND courseId = ? AND eventDate = ? AND calendarId = ? LIMIT 1",
                arguments: [tableId, courseId, eventDate, calendarId])
        }
    }

    // DELETE FROM calendar_import_records WHERE id = :id
    func deleteById(_ id: Int64) throws {
        try db.write { try $0.execute(sql: "DELETE FROM calendar_import_records WHERE id = ?", arguments: [id]) }
    }

    // DELETE FROM calendar_import_records WHERE tableId = :tableId
    func deleteForTable(_ tableId: Int64) throws {
        try db.write { try $0.execute(sql: "DELETE FROM calendar_import_records WHERE tableId = ?", arguments: [tableId]) }
    }
}
