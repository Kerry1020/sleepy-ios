import SwiftUI

// ExitDraftState — Android ui/screen/imports/ExitDraftState.kt → 1:1 纯逻辑移植.
//
// Android 侧: 纯 exit reducer (reduceExitDraftState) — 不存不删, 调用方拥有副作用;
// 2026-09-16 用户: 三个裸 TextButton 既不同排又无色块背景 → 换 DialogActionButtons
// 三键等宽色块一行排. iOS 无 DialogActionButtons 组件 → 确认面 = 内嵌三键 HStack,
// 键序/破坏性语义 1:1 (删除=破坏性 errorContainer 色, 继续/留草稿=次要).

/// 用户离开 import 时的选择 (Android enum 1:1).
enum ExitDraftChoice: Equatable, Codable {
    case continueImport
    case keepDraft
    case deleteDraft
}

/// 退出确认流所需最小状态; 持久化刻意放在 reducer 之外.
struct ExitDraftState: Equatable {
    var activeImport: Bool = false
    var confirmationVisible: Bool = false
}

/// 退出事件 (Android sealed interface 1:1).
enum ExitDraftEvent {
    case requestExit
    case choose(ExitDraftChoice)
}

enum ExitDraftOutcome {
    case none
    case finishDirectly
    case keepDraft
    case deleteDraft
}

struct ExitDraftReduction {
    let state: ExitDraftState
    let outcome: ExitDraftOutcome
}

/// 纯 exit reducer — 不保存/不删除, 调用方拥有副作用 (Android 注释 1:1).
/// iOS 侧现状: 草稿数据切片未落地 (JwCourse/JwSchoolInfo 非 Codable, 无
/// JwImportDraftCodec) → KeepDraft/DeleteDraft 的持久化钩子由 JwImportFlow
/// 调用方侧以标记 TODO 承接 (ImportDraftDao 仅有 id 级 upsert/delete,
/// 可用, 待草稿数据切片提供 payloadJson).
func reduceExitDraftState(
    _ state: ExitDraftState,
    _ event: ExitDraftEvent
) -> ExitDraftReduction {
    switch event {
    case .requestExit:
        if state.activeImport {
            return ExitDraftReduction(
                state: ExitDraftState(activeImport: state.activeImport, confirmationVisible: true),
                outcome: .none)
        } else {
            return ExitDraftReduction(
                state: ExitDraftState(activeImport: state.activeImport, confirmationVisible: false),
                outcome: .finishDirectly)
        }

    case .choose(let choice):
        switch choice {
        case .continueImport:
            return ExitDraftReduction(
                state: ExitDraftState(activeImport: state.activeImport, confirmationVisible: false),
                outcome: .none)
        case .keepDraft:
            return ExitDraftReduction(
                state: ExitDraftState(activeImport: state.activeImport, confirmationVisible: false),
                outcome: .keepDraft)
        case .deleteDraft:
            return ExitDraftReduction(
                state: ExitDraftState(activeImport: state.activeImport, confirmationVisible: false),
                outcome: .deleteDraft)
        }
    }
}

/// 退出确认面 — Android ExitDraftConfirmationDialog 的 iOS 等价.
/// 三键一行: 继续 (次要) / 留草稿 (次要) / 退出并删除草稿 (破坏性).
struct ExitDraftConfirmationCard: View {
    let onContinue: () -> Void
    let onKeepDraft: () -> Void
    let onDeleteDraft: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(L10n.t("jw_import_exit_title")).font(.headline)
            Text(L10n.t("jw_import_exit_message"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(action: onKeepDraft) {
                    Text(L10n.t("jw_import_exit_keep_draft"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onContinue) {
                    Text(L10n.t("jw_import_exit_continue"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive, action: onDeleteDraft) {
                    Text(L10n.t("jw_import_exit_delete_draft"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }
}
