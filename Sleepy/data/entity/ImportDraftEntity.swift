// ImportDraftEntity.swift — ← data/entity/ImportDraftEntity.kt (逐行翻译, GPL-3.0)

import Foundation
import GRDB

/// 导入草稿实体 — 由导入流程持有的持久化预览, 用户应用或丢弃前一直保留。
///
/// payloadJson 对数据库层刻意不透明, 解析器/UI 契约演进不需要再动 schema。
/// id 由导入流程提供, 同一草稿重试/进程重建幂等。
struct ImportDraftEntity: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "import_drafts"

    /// 主键由导入流程给定(非自增)
    var id: String
    var sourceType: String = ""
    var sourceUrl: String = ""
    var payloadJson: String
    var createdAt: Int64
    var updatedAt: Int64

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["sourceType"] = sourceType
        container["sourceUrl"] = sourceUrl
        container["payloadJson"] = payloadJson
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }
}
