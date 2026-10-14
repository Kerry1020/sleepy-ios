// ScheduleDisplayScreen.swift — ← ui/screen/mine/ScheduleDisplayScreen.kt
// 课表显示设置页 — 网格/周缩放 + 圆角比例 + 冲突样式三档 + 参数滑杆。
// Reusable body used directly at the bottom of AppearanceScreen.

import SwiftUI

/// 复用主体 — AppearanceScreen 底部直接嵌入。
struct ScheduleDisplayContent: View {
    @Environment(\.localWakeUpColors) private var colors
    @State private var gridScale: Double = AppPrefs.shared.getGridScale()
    @State private var weekScale: Double = AppPrefs.shared.getWeekScale()
    @State private var cornerRatio: Double = AppPrefs.shared.getGridCornerRatio()
    @State private var conflictStyle: String = AppPrefs.shared.getConflictStyle()
    @State private var conflictStackInset: Double = AppPrefs.shared.getConflictStackInset()
    @State private var conflictRailInset: Double = AppPrefs.shared.getConflictRailInset()
    @State private var conflictFoldSize: Double = AppPrefs.shared.getConflictFoldSize()

    var body: some View {
        VStack(spacing: 8) {
            DisplaySlider(
                label: L10n.t("settings_pill_scale"), value: gridScale,
                valueText: "\(Int(gridScale * 100))%", range: 0.7...1.3,
                onValueChange: { gridScale = Double(Int($0 * 20)) / 20 },
                onFinished: { AppPrefs.shared.setGridScale(gridScale) }
            )
            DisplaySlider(
                label: L10n.t("settings_pill_week_scale"), value: weekScale,
                valueText: "\(Int(weekScale * 100))%", range: 0.7...1.3,
                onValueChange: { weekScale = Double(Int($0 * 20)) / 20 },
                onFinished: { AppPrefs.shared.setWeekScale(weekScale) }
            )
            DisplaySlider(
                label: L10n.t("settings_pill_corner"), value: cornerRatio,
                valueText: "\(Int(cornerRatio * 100))%", range: 0...2,
                onValueChange: { cornerRatio = Double(Int($0 * 20)) / 20 },
                onFinished: { AppPrefs.shared.setGridCornerRatio(cornerRatio) }
            )
            // 冲突课程样式 — 课表显示 Section 的下级分组: 子标题降级区分
            Text(L10n.t("settings_conflict_style"))
                .font(.footnote)
                .foregroundColor(colors.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            conflictStylePicker
            conflictStyleSlider
        }
    }

    private var conflictStylePicker: some View {
        let styles = [("stack", L10n.t("settings_conflict_stack")),
                      ("fold", L10n.t("settings_conflict_fold")),
                      ("rail", L10n.t("settings_conflict_rail"))]
        return Picker("", selection: $conflictStyle) {
            ForEach(styles, id: \.0) { style, label in
                Text(label).tag(style)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: conflictStyle) { v in
            AppPrefs.shared.setConflictStyle(v)
        }
    }

    @ViewBuilder
    private var conflictStyleSlider: some View {
        switch conflictStyle {
        case "stack":
            DisplaySlider(
                label: L10n.t("settings_conflict_stack_inset"), value: conflictStackInset,
                valueText: "\(Int(conflictStackInset))dp",
                range: AppPrefs.CONFLICT_TOP_INSET_RANGE.lowerBound...AppPrefs.CONFLICT_TOP_INSET_RANGE.upperBound,
                onValueChange: { conflictStackInset = $0.rounded() },
                onFinished: { AppPrefs.shared.setConflictStackInset(conflictStackInset) }
            )
        case "rail":
            DisplaySlider(
                label: L10n.t("settings_conflict_rail_inset"), value: conflictRailInset,
                valueText: "\(Int(conflictRailInset))dp",
                range: AppPrefs.CONFLICT_TOP_INSET_RANGE.lowerBound...AppPrefs.CONFLICT_TOP_INSET_RANGE.upperBound,
                onValueChange: { conflictRailInset = $0.rounded() },
                onFinished: { AppPrefs.shared.setConflictRailInset(conflictRailInset) }
            )
        case "fold":
            DisplaySlider(
                label: L10n.t("settings_conflict_fold_size"), value: conflictFoldSize,
                valueText: "\(Int(conflictFoldSize))dp",
                range: AppPrefs.CONFLICT_FOLD_SIZE_RANGE.lowerBound...AppPrefs.CONFLICT_FOLD_SIZE_RANGE.upperBound,
                onValueChange: { conflictFoldSize = $0.rounded() },
                onFinished: { AppPrefs.shared.setConflictFoldSize(conflictFoldSize) }
            )
        default:
            EmptyView()
        }
    }
}

struct ScheduleDisplayScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                }
                .accessibilityLabel(Text(L10n.t("back")))
                Spacer()
                Text(L10n.t("appearance_section_schedule_display"))
                    .font(.headline)
                Spacer()
                Color.clear.frame(width: 30, height: 30)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            ScheduleDisplayContent()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            Spacer()
        }
        .navigationBarHidden(true)
    }
}

private struct DisplaySlider: View {
    let label: String
    @State var value: Double  // 由父 view 的 @State 双向传递
    let valueText: String
    let range: ClosedRange<Double>
    let onValueChange: (Double) -> Void
    let onFinished: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text("\(label)  \(valueText)")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Slider(
                value: Binding(
                    get: { value },
                    set: {
                        value = $0
                        onValueChange($0)
                    }
                ),
                in: range,
                onEditingChanged: { editing in
                    if !editing { onFinished() }
                }
            )
        }
    }
}
