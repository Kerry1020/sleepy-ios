// UpdateChangelogDialog.swift — ← ui/screen/mine/UpdateChangelogDialog.kt
// 更新日志弹窗: 状态机 = Idle/Checking/NoUpdate/UpdateAvailable/Downloading/Installing/Failed。
// 平台差异(SPEC #2): Android 下载 APK 自装 → iOS 下载 IPA 后提示重新侧载(Installing 态
// 由 AboutScreen 在下载完成时切到, 在此弹窗内只显示「请重新侧载」提示)。
//
// Markdown 渲染走本仓库自研 MarkdownBlocks(Swift 端口, 无第三方依赖) — 块级/行内由
// 代码显式排版, 不依赖 Markwon 黑盒。
//
// 与 AboutScreen 关系: v1.0.51 之前 iOS 端 UpdateChangelogDialog 作为 fileprivate 内嵌
// 在 AboutScreen.swift(已存在实现); v1.0.60 1:1 移植抽成独立 Swift 组件, 行为不变。

import SwiftUI

struct UpdateChangelogDialog: View {
    @Environment(\.localWakeUpColors) private var colors
    let state: UpdateUiState
    let onDismiss: () -> Void
    let onDownload: (String, String, String) -> Void
    let onCancelDownload: () -> Void
    let onRetry: (String, String, String) -> Void

    var body: some View {
        let version = currentVersion
        let changelog = currentChangelog
        let url = currentUrl
        let progress = currentProgress
        let failMsg = currentFailMsg
        let isFailed = stateHasFailure

        VStack(alignment: .leading, spacing: 16) {
            Text(dialogTitle(version: version))
                .font(.system(size: 22, weight: .bold))   // ← Android titleLarge.copy(Bold) 22sp
                .foregroundColor(colors.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if isFailed && !failMsg.isEmpty {
                        Text(L10n.format("update_download_failed", failMsg))
                            .font(.system(size: 14))
                            .foregroundColor(colors.error)
                    }
                    if progress >= 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: Double(progress) / 100.0)
                                .tint(colors.primary)
                            Text(L10n.format("update_downloading", progress))
                                .font(.system(size: 12))
                                .foregroundColor(colors.onSurfaceVariant)
                        }
                    }
                    if case .installing = state {
                        Text(L10n.t("update_ios_sideload_hint"))
                            .font(.system(size: 14))
                            .foregroundColor(colors.primary)
                    }
                    if !changelog.isEmpty {
                        MarkdownChangelog(markdown: changelog)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Spacer()
                switch state {
                case .updateAvailable:
                    HStack(spacing: 8) {
                        // ← 2026-09-16 用户: 裸 TextButton 无边界无色块 — 次级动作换 secondary 色块, 保持等高一行
                        Button(L10n.format("update_cancel"), action: onDismiss)
                            .foregroundColor(colors.onSecondaryContainer)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(colors.secondaryContainer)
                            .cornerRadius(SleepyShapes.large)
                        Button(L10n.format("update_download")) {
                            onDownload(version, changelog, url)
                        }
                        .foregroundColor(colors.onPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(colors.primary)
                        .cornerRadius(SleepyShapes.large)
                    }
                case .downloading:
                    Button(L10n.format("update_cancel"), action: onCancelDownload)
                        .foregroundColor(colors.onSecondaryContainer)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(colors.secondaryContainer)
                        .cornerRadius(SleepyShapes.large)
                case .failed:
                    HStack(spacing: 8) {
                        Button(L10n.format("update_cancel"), action: onDismiss)
                            .foregroundColor(colors.onSecondaryContainer)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(colors.secondaryContainer)
                            .cornerRadius(SleepyShapes.large)
                        Button(L10n.format("update_retry")) {
                            onRetry(version, changelog, url)
                        }
                        .foregroundColor(colors.onPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(colors.primary)
                        .cornerRadius(SleepyShapes.large)
                    }
                case .installing:
                    Button(L10n.t("ok"), action: onDismiss)
                        .foregroundColor(colors.onPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(colors.primary)
                        .cornerRadius(SleepyShapes.large)
                case .idle, .checking, .noUpdate:
                    EmptyView()
                }
            }
            .buttonStyle(SleepyButtonStyle())
            .font(.system(size: 14, weight: .medium))   // ← M3 dialog 按钮 labelLarge 14 Medium
        }
        .padding(24)   // ← M3 AlertDialog dialogPadding 24dp
        .background(colors.surface)
    }

    // MARK: - state 派生

    private var currentVersion: String {
        switch state {
        case .updateAvailable(let v, _, _): return v
        case .failed(_, let v, _, _, _):    return v
        default: return ""
        }
    }
    private var currentChangelog: String {
        switch state {
        case .updateAvailable(_, let c, _): return c
        case .failed(_, _, let c, _, _):    return c
        default: return ""
        }
    }
    private var currentUrl: String {
        switch state {
        case .updateAvailable(_, _, let u): return u
        case .failed(_, _, _, let u, _):    return u
        default: return ""
        }
    }
    private var currentProgress: Int {
        if case .downloading(let p) = state { return p }
        return -1
    }
    private var currentFailMsg: String {
        if case .failed(let m, _, _, _, _) = state { return m }
        return ""
    }
    private var stateHasFailure: Bool {
        if case .failed = state { return true }
        return false
    }

    private func dialogTitle(version: String) -> String {
        switch state {
        case .installing:                       return L10n.t("update_ios_sideload_title")
        case .downloading(let p):               return L10n.format("update_downloading", p)
        case .updateAvailable, .failed:         return L10n.format("update_found_title", version)
        default:                                return L10n.format("update_found_title", version)
        }
    }
}

// ← MarkdownChangelog(1.0.51): changelog 按 Markdown 渲染
//   标题: L1=titleLarge 22 Bold / L2=titleMedium 16 Bold / L3+=titleSmall 14 Bold, 上 10 下 2
//   圆点: "•" primary 12sp + 间距 8, 缩进 6, 行距 2; 段落行距 2; 链接 accent+下划线
private struct MarkdownChangelog: View {
    @Environment(\.localWakeUpColors) private var colors
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(MarkdownBlocks.parse(markdown).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlocks.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    bulletRow(item)
                }
            }
        case .paragraph(let text):
            Text(inlineText(text))
                .font(.system(size: 12))   // ← Android bodySmall 12sp
                .foregroundColor(colors.onSurfaceVariant)
                .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        let size = level == 1 ? 22.0 : (level == 2 ? 16.0 : 14.0)
        Text(inlineText(text))
            .font(.system(size: size, weight: .bold))
            .foregroundColor(colors.onSurfaceVariant)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private func bulletRow(_ item: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("•")
                .font(.system(size: 12))
                .foregroundColor(colors.primary)
            Spacer().frame(width: 8)
            Text(inlineText(item))
                .font(.system(size: 12))
                .foregroundColor(colors.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 6)
        .padding(.vertical, 2)
    }

    /// ← inlineText: 链接 accent+下划线; 粗体/行内代码由 AttributedString(markdown:) 原生呈现
    private func inlineText(_ text: String) -> AttributedString {
        var attr = (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        for run in attr.runs where run.link != nil {
            attr[run.range].foregroundColor = colors.primary
            attr[run.range].underlineStyle = .single
        }
        return attr
    }
}
