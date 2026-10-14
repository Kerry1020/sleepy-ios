// ImportDraftRepository.swift — ← data/repository/ImportDraftRepository.kt
// Persistence boundary for resumable academic imports.

import Foundation
import GRDB
import Combine

final class ImportDraftRepository {
    private let dao: ImportDraftDao

    init(db: DatabaseWriter) {
        self.dao = ImportDraftDao(db: db)
    }

    convenience init() {
        self.init(db: AppDatabase.getShared().dbQueue)
    }

    /// 变更流 — GRDB ValueObservation 桥 Combine(对齐 Android Flow)。
    func observeAll() -> AnyPublisher<[ImportDraftEntity], Never> {
        let subject = CurrentValueSubject<[ImportDraftEntity], Never>([])
        // GRDB ValueObservation → Future 拉首帧 + 后续变更由调用方重新 observe;
        // 简化: 首帧 + 手动 refresh 通知(onDataChanged 语义由调用方触发)
        if let initial = try? dao.getAll() {
            subject.send(initial)
        }
        return subject.eraseToAnyPublisher()
    }

    func get(id: String) -> JwImportDraftSnapshot? {
        guard let entity = try? dao.getById(id) else { return nil }
        return JwImportDraftCodec.fromJson(entity.payloadJson)
    }

    @discardableResult
    func save(snapshot: JwImportDraftSnapshot, sourceType: String = "", sourceUrl: String = "") throws -> String {
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

    func update(id: String, snapshot: JwImportDraftSnapshot) {
        guard var existing = try? dao.getById(id) else { return }
        existing.payloadJson = JwImportDraftCodec.toJson(snapshot)
        existing.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        try? dao.update(existing)
    }

    func delete(id: String) {
        try? dao.deleteById(id)
    }
}
