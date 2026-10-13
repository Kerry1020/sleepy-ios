import SwiftUI

// DiagDumpProgress — Android ui/screen/imports/DiagDumpProgress.kt → 1:1 移植.
//
// Android 侧: [DumpStage] 枚举顺序 = JwImportActivity.exportDiagnosticDump 管线
// 的真实采集顺序 (枚举序即 UI 展示序); [DiagDumpProgress.percent] 按
// 已完成步骤数/总步骤数计算, 单调不减、终态 100%、超 100 钳位.
// 纯数据 + 纯函数 — 2026-09-21 用户: 点导出后必须看到每个原子步骤的进度在哪,
// 禁止无止境"正在生成"黑箱等待.

/// 管线 9 段, 顺序 = JwImportFlow.exportDiagnosticDump 真实执行序.
enum DumpStage: Int, CaseIterable, Codable {
    case domInventory
    case storage
    case links
    case networkSnapshot
    case networkReplay
    case resourceReplay
    case cookies
    case zipAssembly
    case saveShare

    var labelKey: String {
        switch self {
        case .domInventory: return "jw_diag_stage_dom_inventory"
        case .storage: return "jw_diag_stage_storage"
        case .links: return "jw_diag_stage_links"
        case .networkSnapshot: return "jw_diag_stage_network_snapshot"
        case .networkReplay: return "jw_diag_stage_network_replay"
        case .resourceReplay: return "jw_diag_stage_resource_replay"
        case .cookies: return "jw_diag_stage_cookies"
        case .zipAssembly: return "jw_diag_stage_zip"
        case .saveShare: return "jw_diag_stage_save_share"
        }
    }

    var label: String { L10n.t(labelKey) }
}

/// 单一进度快照. stepsDone = 已完成的原子步骤数 (0..DumpStage.allCases.count).
/// 纯数据 — 单测直接跑 (Android 侧 JVM 单测 1:1 语义).
struct DiagDumpProgress: Equatable {
    let stage: DumpStage
    let stepsDone: Int
    let totalCount: Int

    init(stage: DumpStage, stepsDone: Int, totalCount: Int = DumpStage.allCases.count) {
        self.stage = stage
        self.stepsDone = stepsDone
        self.totalCount = totalCount
    }

    /// Android percent 公式 1:1: (stepsDone*100/total).coerceIn(0,100), 单调不减、终态 100.
    var percent: Int {
        guard totalCount > 0 else { return 0 }
        return min(max(stepsDone * 100 / totalCount, 0), 100)
    }

    /// 当前正在跑的段序号 (1-based, "步骤 x/n").
    var stepIndex: Int { min(stepsDone + 1, totalCount) }
}

/// 进度卡片 — Android JwImportActivity 错误弹窗内的展开进度区 等价:
/// 步骤 x/n + 阶段文案 + 进度条 + 百分比, 用户在问题上下文内不离开即可看见进度.
struct DiagDumpProgressCard: View {
    let progress: DiagDumpProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.format("jw_diag_progress_step", progress.stepIndex, progress.totalCount))
                .font(.footnote)
            Text(progress.stage.label)
                .font(.subheadline)
            ProgressView(value: Double(progress.percent), total: 100)
            Text(L10n.format("jw_diag_progress_percent", progress.percent))
                .font(.footnote)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
