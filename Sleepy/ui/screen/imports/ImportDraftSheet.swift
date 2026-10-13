// ImportDraftSheet.swift — ← ui/screen/imports/ImportDraftSheet.kt
// 导入草稿恢复 sheet — UI-only representation; persistence belongs to the caller.

import SwiftUI

/// UI-only representation of an import draft; persistence belongs to the caller.
struct ImportDraftRowModel: Identifiable, Equatable {
    let id: String
    let name: String
    let details: String
    let savedAt: String?
}

struct ImportDraftSheet: View {
    let drafts: [ImportDraftRowModel]
    let onDismiss: () -> Void
    let onRestore: (String) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            Text(L10n.t("import_drafts"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)

            if drafts.isEmpty {
                VStack {
                    Spacer(minLength: 40)
                    Text(L10n.t("import_drafts_empty"))
                        .font(.body)
                        .foregroundColor(.secondary)
                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(drafts) { draft in
                            ImportDraftRow(
                                draft: draft,
                                onRestore: { onRestore(draft.id) },
                                onDelete: { onDelete(draft.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .frame(maxHeight: 520)
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

private struct ImportDraftRow: View {
    let draft: ImportDraftRowModel
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.name)
                    .font(.subheadline.weight(.medium))
                Text(draft.details)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                if let savedAt = draft.savedAt, !savedAt.isEmpty {
                    Text(L10n.format("import_draft_saved_at", savedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }
            Spacer()
            Button(action: onRestore) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
            }
            .accessibilityLabel(Text(L10n.t("import_draft_restore")))
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.red)
            }
            .accessibilityLabel(Text(L10n.t("import_draft_delete")))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }
}
