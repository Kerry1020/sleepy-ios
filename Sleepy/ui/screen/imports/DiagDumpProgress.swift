// DiagDumpProgress.swift — ← ui/screen/imports/DiagDumpProgress.kt
// 排查全量包导出进度模型 — 2026-09-21 用户: 点导出后必须看到每个原子步骤的
// 进度在哪、百分之多少, 禁止无止境"正在生成"黑箱等待。
//
// DumpStage 枚举顺序 = JwImportActivity.exportDiagnosticDump 管线的真实采集
// 顺序(枚举序即 UI 展示序); percent 按 已完成步骤数/总步骤数 计算,
// 单调不减、终态 100%、超 100 钳位。

import Foundation

enum DumpStage: String, CaseIterable {
    /// 现抓 DOM 可点元素清单 (DOM_INVENTORY_JS)
    case domInventory = "jw_diag_stage_dom_inventory"
    /// Web Storage 全键值 (STORAGE_JS)
    case storage = "jw_diag_stage_storage"
    /// 页面链接 + select 下拉枚举 (LINKS_JS)
    case links = "jw_diag_stage_links"
    /// 运行时 fetch/XHR 快照 (DIAGNOSTIC_NETWORK_SNAPSHOT_JS)
    case networkSnapshot = "jw_diag_stage_network_snapshot"
    /// 网络请求重放 (DIAGNOSTIC_NETWORK_EXPORT_JS, 30s 上限)
    case networkReplay = "jw_diag_stage_network_replay"
    /// 同源资源重取 (RESOURCE_REPLAY_JS, 16s 上限)
    case resourceReplay = "jw_diag_stage_resource_replay"
    /// Cookie 全量值 (WKHTTPCookieStore)
    case cookies = "jw_diag_stage_cookies"
    /// zip 组装 (JwCaptureDump.buildZip)
    case zipAssembly = "jw_diag_stage_zip"
    /// 落盘 tmp/Sleepy/教务日志 + 拉系统分享面板
    case saveShare = "jw_diag_stage_save_share"

    var label: String { L10n.t(rawValue) }
}

/// 单一进度快照。stepsDone = 已完成的原子步骤数(0..DumpStage.allCases.count)。
/// 纯数据 + 纯函数, 单测直接跑。
struct DiagDumpProgress: Equatable {
    let stage: DumpStage
    let stepsDone: Int
    let totalCount: Int

    init(stage: DumpStage, stepsDone: Int, totalCount: Int = DumpStage.allCases.count) {
        self.stage = stage
        self.stepsDone = stepsDone
        self.totalCount = totalCount
    }

    var percent: Int {
        guard totalCount > 0 else { return 0 }
        return min(max(stepsDone * 100 / totalCount, 0), 100)
    }
}
