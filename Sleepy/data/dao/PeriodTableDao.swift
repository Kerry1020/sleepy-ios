// PeriodTableDao.swift — ← data/dao/PeriodTableDao.kt 逐条 SQL 翻译 (GPL-3.0)

import Foundation
import GRDB

struct PeriodTableDao {
    let db: DatabaseWriter

    // @Insert(onConflict = REPLACE) → Long
    @discardableResult
    func insert(_ table: PeriodTableEntity) throws -> Int64 {
        var table = table
        try db.write { try table.insert($0, onConflict: .replace) }
        return table.id
    }

    /// 事务内直插(MigrationExecutor / 导入事务闭包用, 禁重入)
    @discardableResult
    func insertInDb(_ dbw: Database, _ table: PeriodTableEntity) throws -> Int64 {
        var table = table
        try table.insert(dbw, onConflict: .replace)
        return table.id
    }

    /// v7.10 撤回恢复用 — 整批重插
    func insertAll(_ tables: [PeriodTableEntity]) throws {
        var tables = tables
        try db.write { dbw in
            for i in tables.indices {
                try tables[i].insert(dbw, onConflict: .replace)
            }
        }
    }

    // @Update
    func update(_ table: PeriodTableEntity) throws {
        var table = table
        try db.write { try table.update($0) }
    }

    // DELETE FROM period_tables WHERE id = :id
    func deleteById(_ id: Int64) throws {
        try db.write { try $0.execute(sql: "DELETE FROM period_tables WHERE id = ?", arguments: [id]) }
    }

    /// v7.10 撤回恢复用 — 清空全表
    func deleteAll() throws {
        try db.write { try $0.execute(sql: "DELETE FROM period_tables") }
    }

    // SELECT * FROM period_tables WHERE id = :id LIMIT 1
    func getById(_ id: Int64) throws -> PeriodTableEntity? {
        try db.read { try PeriodTableEntity.fetchOne($0, sql: "SELECT * FROM period_tables WHERE id = ? LIMIT 1", arguments: [id]) }
    }

    // SELECT * FROM period_tables ORDER BY createdAt DESC
    func getAll() throws -> [PeriodTableEntity] {
        try db.read { try PeriodTableEntity.fetchAll($0, sql: "SELECT * FROM period_tables ORDER BY createdAt DESC") }
    }

    // SELECT COUNT(*) FROM period_tables
    func count() throws -> Int {
        try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM period_tables") ?? 0 }
    }

    /// 引用计数 — 时间节次表管理页"已绑定 N 张课表" + 删除守卫共用
    func boundTableCount(_ id: Int64) throws -> Int {
        try db.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM time_tables WHERE periodTableId = ?", arguments: [id]) ?? 0
        }
    }

    /// 引用此时间表的全部课程表 id — 删除守卫改绑列表用
    func boundTableIds(_ id: Int64) throws -> [Int64] {
        try db.read {
            try Int64.fetchAll($0, sql: "SELECT id FROM time_tables WHERE periodTableId = ?", arguments: [id])
        }
    }
}
