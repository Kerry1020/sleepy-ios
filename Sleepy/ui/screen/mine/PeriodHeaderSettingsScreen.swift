// PeriodHeaderSettingsScreen.swift — ← ui/screen/mine/PeriodHeaderSettingsScreen.kt
// 节次表头设置页: 五种样式实时预览(阿拉伯/中文/财务/圈圈/罗马) + 布局切换(老式/三行式)
// + 显示节号开关 + 三行式悬挂量滑杆(-1..1, 0.1 步进)。
//
// 偏好读写: AppPrefs.getPeriodHeaderLayout/Style/Hanging + isPeriodHeaderShowX
// (v1.0.60 已落地 iOS AppPrefs — 见 AppPrefs.swift "节次表头设置" MARK)。

import SwiftUI

struct PeriodHeaderSettingsScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    let onBack: () -> Void

    private let prefs = AppPrefs.shared

    @State private var layout: String = AppPrefs.shared.getPeriodHeaderLayout()
    @State private var style: String = AppPrefs.shared.getPeriodHeaderStyle()
    @State private var hangingUnits: Float = AppPrefs.shared.getPeriodHeaderHanging()
    @State private var showX: Bool = AppPrefs.shared.isPeriodHeaderShowX()

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.t("appearance_period_header"), onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // ── 实时预览 ──
                    HeaderStylePreviews(
                        layout: layout,
                        selectedStyle: style,
                        hangingUnits: hangingUnits,
                        showX: showX,
                        onStyleSelected: { value in
                            style = value
                            prefs.setPeriodHeaderStyle(value)
                        })

                    // ── 布局切换(legacy / three_line) ──
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t("appearance_header_layout"))
                            .font(.system(size: 12, weight: .medium))   // ← labelMedium
                            .foregroundColor(colors.onSurfaceVariant)
                        SegmentedSwitcher(
                            options: [
                                ("legacy", L10n.t("appearance_layout_legacy")),
                                ("three_line", L10n.t("appearance_layout_three_line"))
                            ],
                            selected: layout) { selected in
                                layout = selected
                                prefs.setPeriodHeaderLayout(selected)
                            }
                    }

                    // ── 显示节号 + 三行式悬挂量 ──
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(L10n.t("appearance_header_show_x"), isOn: Binding(
                            get: { showX },
                            set: { newValue in
                                showX = newValue
                                prefs.setPeriodHeaderShowX(newValue)
                            }))
                        if layout == "three_line" {
                            // ← Android String.format("%+.1f", hangingUnits)
                            Text(L10n.format("appearance_header_hanging",
                                             String(format: "%+.1f", hangingUnits)))
                                .font(.system(size: 14))   // ← bodyMedium
                                .foregroundColor(colors.onSurfaceVariant)
                            Slider(
                                value: Binding(
                                    get: { Double(hangingUnits) },
                                    set: { v in
                                        hangingUnits = Float((v * 10).rounded() / 10)
                                    }),
                                in: -1...1) { _ in
                                    prefs.setPeriodHeaderHanging(hangingUnits)
                                }
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(colors.background)
        .navigationBarHidden(true)
    }
}

// MARK: - 预览网格(样式选择)

/// 五种样式的实时预览 — 每张卡 = 选中样式渲染一个 previewSlot(node 12, 08:00-08:45)。
/// 视觉对齐 Compose HeaderStylePreviews: 卡片宽 76pt+ 自适应、高 52pt;
/// 选中态 primaryContainer, 未选中 surfaceContainer, 圆角 12dp。
private struct HeaderStylePreviews: View {
    @Environment(\.localWakeUpColors) private var colors
    let layout: String
    let selectedStyle: String
    let hangingUnits: Float
    let showX: Bool
    let onStyleSelected: (String) -> Void

    /// 预览槽位(← Android previewSlot: label "12", 08:00-08:45, node 12)
    private static let previewSlot = (
        displayStart: "08:00",
        displayEnd: "08:45",
        node: 12
    )

    /// ← Android styles: 五种样式的 FlowRow 标签
    private static let styles: [(String, String)] = [
        ("arabic", "1  2  3"),
        ("chinese", "一  二  三"),
        ("financial", "壹  贰  叁"),
        ("circled", "①  ②  ③"),
        ("roman", "Ⅰ  Ⅱ  Ⅲ"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("appearance_header_preview"))
                .font(.system(size: 14, weight: .semibold))   // ← titleSmall
                .foregroundColor(colors.onSurface)

            // ← FlowRow 等价: 换行流式布局
            FlowLayout(spacing: 8) {
                ForEach(Self.styles, id: \.0) { value, label in
                    styleCard(value: value, label: label)
                }
            }
        }
    }

    private func styleCard(value: String, label: String) -> some View {
        let isSelected = value == selectedStyle
        return Button {
            onStyleSelected(value)
        } label: {
            VStack(spacing: 5) {
                // 预览卡: 宽 = max(标签宽, 46pt 防挤压下限) 高 52pt —
                // Android 用 threeLineWidthDp/legacyLineWidthDp 实测最宽样式;
                // iOS 统一给足 76pt 最小宽(卡宽有最小值, 内容自适应)。
                PeriodHeaderCellContent(
                    displayStart: Self.previewSlot.displayStart,
                    displayEnd: Self.previewSlot.displayEnd,
                    nodeStart: Self.previewSlot.node,
                    nodeEnd: Self.previewSlot.node,
                    isPlaceholder: false,
                    layout: layout,
                    style: value,
                    scale: 1,
                    hangingUnitsOverride: CGFloat(hangingUnits),
                    showXOverride: showX)
                .frame(width: 76, height: 52)
                .background(colors.surfaceContainerLow)
                .cornerRadius(SleepyShapes.small)
                .padding(periodHeaderCardPadDp)

                Text(label)
                    .font(.system(size: 11))   // ← labelSmall
                    .foregroundColor(isSelected ? colors.onPrimaryContainer : colors.onSurfaceVariant)
            }
            .padding(6)
            .frame(minWidth: 76)
            .background(isSelected ? colors.primaryContainer : colors.surfaceContainer)
            .cornerRadius(SleepyShapes.medium)
        }
        .buttonStyle(SleepyButtonStyle())
    }
}

// MARK: - 简易流式布局(← Compose FlowRow)

/// 水平流式排列, 放不下自动换行 — Compose FlowRow 的 SwiftUI 等价(轻实现)。
private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        // iOS 15 兼容: 无 Layout 协议 → 用 LazyVGrid adaptive 列近似流式换行
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: spacing)],
                  alignment: .leading, spacing: spacing) {
            content()
        }
    }
}
