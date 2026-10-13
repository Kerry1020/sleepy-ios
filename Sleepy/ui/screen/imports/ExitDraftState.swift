// ExitDraftState.swift — ← ui/screen/imports/ExitDraftState.kt
// The user's choice when leaving an import that may contain recoverable work.

import SwiftUI

/// 用户离开一个可能包含可恢复工作的导入时的选择。
enum ExitDraftChoice: Equatable {
    case continueImport
    case keepDraft
    case deleteDraft
}

/// 退出确认流程需要的最小状态; 持久化刻意不在此内。
struct ExitDraftState: Equatable {
    var activeImport: Bool = false
    var confirmationVisible: Bool = false
}

enum ExitDraftEvent: Equatable {
    case requestExit
    case choose(ExitDraftChoice)
}

enum ExitDraftOutcome: Equatable {
    case none
    case finishDirectly
    case keepDraft
    case deleteDraft
}

struct ExitDraftReduction: Equatable {
    let state: ExitDraftState
    let outcome: ExitDraftOutcome
}

/// Pure exit reducer. It does not save or delete anything; callers own those side effects.
func reduceExitDraftState(_ state: ExitDraftState, _ event: ExitDraftEvent) -> ExitDraftReduction {
    switch event {
    case .requestExit:
        if state.activeImport {
            var next = state
            next.confirmationVisible = true
            return ExitDraftReduction(state: next, outcome: .none)
        } else {
            var next = state
            next.confirmationVisible = false
            return ExitDraftReduction(state: next, outcome: .finishDirectly)
        }
    case .choose(let choice):
        var next = state
        next.confirmationVisible = false
        switch choice {
        case .continueImport:
            return ExitDraftReduction(state: next, outcome: .none)
        case .keepDraft:
            return ExitDraftReduction(state: next, outcome: .keepDraft)
        case .deleteDraft:
            return ExitDraftReduction(state: next, outcome: .deleteDraft)
        }
    }
}

/// UI-only confirmation surface. Draft persistence is supplied by the caller for later integration.
/// 2026-09-16 用户: 三键等宽一行排(继续/留草稿 secondary, 退出并删除 destructive)。
struct ExitDraftConfirmationDialog: View {
    let onContinue: () -> Void
    let onKeepDraft: () -> Void
    let onDeleteDraft: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(L10n.t("jw_import_exit_title"))
                .font(.headline)
            Text(L10n.t("jw_import_exit_message"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // 三键: 继续(secondary) / 留草稿(secondary) / 退出并删除(destructive)
            VStack(spacing: 10) {
                Button(action: onContinue) {
                    Text(L10n.t("jw_import_exit_continue"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)

                Button(action: onKeepDraft) {
                    Text(L10n.t("jw_import_exit_keep_draft"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)

                Button(action: onDeleteDraft) {
                    Text(L10n.t("jw_import_exit_delete_draft"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(24)
    }
}
