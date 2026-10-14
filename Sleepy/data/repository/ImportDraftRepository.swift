// ImportDraftRepository.swift — ← ImportDraftRepository.kt (GPL-3.0, 逐行翻译)
//
// 可恢复教务导入的持久化边界。Kotlin Flow/挂起 → iOS 同步 throws
// (与 ScheduleRepository 一致的平台映射; observeAll 对应 getAll, 无 Flow)。

import Foundation
import GRDB

final class ImportDraftRepository {
    private let db: AppDatabase
    private let dao: ImportDraftDao

    init(_ db: AppDatabase) {
        self.db = db
        self.dao = db.importDraftDao
    }

    /// Kotlin observeAll(): Flow<List<ImportDraftEntity>> → 同步全量读取。
    func getAll() throws -> [ImportDraftEntity] {
        try dao.getAll()
    }

    func get(_ id: String) throws -> JwImportDraftSnapshot? {
        guard let entity = try dao.getById(id) else { return nil }
        return JwImportDraftCodec.fromJson(entity.payloadJson)
    }

    @discardableResult
    func save(_ snapshot: JwImportDraftSnapshot,
              sourceType: String = "",
              sourceUrl: String = "") throws -> String {
        let id = UUID().uuidString
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        try dao.insert(ImportDraftEntity(
            id: id,
            sourceType: sourceType,
            sourceUrl: sourceUrl,
            payloadJson: JwImportDraftCodec.toJson(snapshot),
            createdAt: now,
            updatedAt: now
        ))
        return id
    }

    func update(_ id: String, _ snapshot: JwImportDraftSnapshot) throws {
        guard let existing = try dao.getById(id) else { return }
        try dao.update(ImportDraftEntity(
            id: existing.id,
            sourceType: existing.sourceType,
            sourceUrl: existing.sourceUrl,
            payloadJson: JwImportDraftCodec.toJson(snapshot),
            createdAt: existing.createdAt,
            updatedAt: Int64(Date().timeIntervalSince1970 * 1000)
        ))
    }

    func delete(_ id: String) throws {
        try dao.deleteById(id)
    }
}
