// ImportDraftDao.swift — ← data/dao/ImportDraftDao.kt 逐条 SQL 翻译 (GPL-3.0)

import Foundation
import GRDB

struct ImportDraftDao {
    let db: DatabaseWriter

    // @Insert(onConflict = REPLACE)
    func insert(_ draft: ImportDraftEntity) throws {
        var draft = draft
        try db.write { try draft.insert($0, onConflict: .replace) }
    }

    // @Update
    func update(_ draft: ImportDraftEntity) throws {
        var draft = draft
        try db.write { try draft.update($0) }
    }

    // @Insert(onConflict = REPLACE) — upsert 语义
    func upsert(_ draft: ImportDraftEntity) throws {
        var draft = draft
        try db.write { try draft.save($0) }
    }

    // SELECT * FROM import_drafts WHERE id = :id LIMIT 1
    func getById(_ id: String) throws -> ImportDraftEntity? {
        try db.read { try ImportDraftEntity.fetchOne($0, sql: "SELECT * FROM import_drafts WHERE id = ? LIMIT 1", arguments: [id]) }
    }

    // SELECT * FROM import_drafts ORDER BY updatedAt DESC
    func getAll() throws -> [ImportDraftEntity] {
        try db.read { try ImportDraftEntity.fetchAll($0, sql: "SELECT * FROM import_drafts ORDER BY updatedAt DESC") }
    }

    // DELETE FROM import_drafts WHERE id = :id
    func deleteById(_ id: String) throws {
        try db.write { try $0.execute(sql: "DELETE FROM import_drafts WHERE id = ?", arguments: [id]) }
    }

    // DELETE FROM import_drafts
    func deleteAll() throws {
        try db.write { try $0.execute(sql: "DELETE FROM import_drafts") }
    }
}
