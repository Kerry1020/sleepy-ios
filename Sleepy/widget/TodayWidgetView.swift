// TodayWidgetView.swift — ← TodayWidget.kt (Receiver) + WidgetBitmapRenderers.renderToday
// 桌面 Today 小组件 — 今日课程列表。
// 布局: bg 圆角 20 / pad 14 / 标题行(今天·周X + 日期) / 课程胶囊 38dp 高 + 10dp 间距。
// Canvas 手绘坐标 → SwiftUI 等价布局(间距/字号/取色逐项对齐)。

import SwiftUI
import WidgetKit

// MARK: - Entry

struct TodayWidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

struct TodayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry {
        WidgetArchiveLog.append(kind: "TodayWidgetRV", family: context.family.description, result: "success")
        return TodayWidgetEntry(date: Date(), data: TodayWidgetLoader.loadDataSync(kind: "TodayWidgetRV"))
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayWidgetEntry) -> Void) {
        WidgetArchiveLog.append(kind: "TodayWidgetRV", family: context.family.description, result: "success")
        completion(TodayWidgetEntry(date: Date(), data: TodayWidgetLoader.loadDataSync(kind: "TodayWidgetRV")))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWidgetEntry>) -> Void) {
        // 次日 00:05 刷新(日期变化 + 课表数据变化都覆盖 — 后者由 App 端 WidgetCenter.reloadAllTimelines 触发)
        let data = TodayWidgetLoader.loadDataSync(kind: "TodayWidgetRV")
        let entry = TodayWidgetEntry(date: Date(), data: data)
        var cal = DateUtils.isoCalendar
        cal.timeZone = .current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        let refresh = cal.date(bySettingHour: 0, minute: 5, second: 0, of: tomorrow) ?? tomorrow
        WidgetArchiveLog.append(kind: "TodayWidgetRV", family: context.family.description, result: "success")
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - View ← renderToday

struct TodayWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    let entry: TodayWidgetEntry

    var body: some View {
        // SMALL 紧凑档 ← renderTodayCompact: 日期小字(顶) + 状态/首课程名(居中), 纯文本无胶囊
        if widgetFamily == .systemSmall {
            let s = resolveWidgetScheme(themeKey: entry.data.themeKey, isDark: entry.data.isDark)
            WidgetCompactFace(scheme: s, dateLabel: entry.data.dateLabel,
                              lines: Self.todayCompactTexts(data: entry.data,
                                                            useAlias: AppPrefs.shared.isWidgetUseAlias()))
                .widgetURL(URL(string: "sleepy://open"))
        } else {
            regularBody
        }
    }

    // ← renderTodayRegular: 常规/中大档全量排版
    @ViewBuilder
    private var regularBody: some View {
        let data = entry.data
        let s = resolveWidgetScheme(themeKey: data.themeKey, isDark: data.isDark)
        let prefs = AppPrefs.shared
        let colorless = prefs.isWidgetColorless()
        // ★ 用户显示设置 (决策 D5-12)
        let displayMode = prefs.getDisplayMode()
        let showDate = prefs.isShowDate()
        // issue#26: widget 全局一档别名开关
        let useAlias = prefs.isWidgetUseAlias()

        VStack(alignment: .leading, spacing: 0) {
            // 标题行: 今天 · 周X  +  日期 (★ showDate=false 时隐藏右侧日期)
            HStack(alignment: .firstTextBaseline) {
                Text("\(L10n.format("today_today")) · \(data.dayName)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(s.primary)
                    .lineLimit(1) // 安卓 ellipsize 单行 (min 预算 40dp)
                Spacer()
                if showDate {
                    Text(data.dateLabel)
                        .font(.system(size: 12))
                        .foregroundColor(s.onSurfaceVariant)
                }
            }
            .padding(.bottom, 8.5) // 安卓头部前进 24dp: pad14+行高≈15.5+8.5≈38

            if !data.hasTable {
                Text(L10n.format("widget_create_schedule"))
                    .font(.system(size: 15))
                    .foregroundColor(s.onSurface)
                Spacer()
            } else if data.semesterStatus != .inRange {
                // ★ 学期外: 状态标题 + 提示行, 不画课程 (loadDataSync 侧课程已按周过滤, 此处为标题语义)
                Text(data.semesterStatus == .beforeStart
                     ? L10n.format("semester_not_started")
                     : L10n.format("semester_ended"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(s.onSurface)
                    .padding(.bottom, 6)
                Text(L10n.format("today_semester_out_hint"))
                    .font(.system(size: 11))
                    .foregroundColor(s.onSurfaceVariant)
                Spacer()
            } else if data.courses.isEmpty {
                // 今日无课 → 大字提示 + 副文案
                Text(L10n.format("today_no_course"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(s.onSurface)
                    .padding(.bottom, 6)
                Text(L10n.format("today_rest"))
                    .font(.system(size: 12))
                    .foregroundColor(s.onSurfaceVariant)
                Spacer()
            } else {
                // ★ 课程列表 — WidgetKit 不支持 ScrollView 归档;按 family 取前 N 门,
                // 溢出由 widget 容器自然裁切,与 Android bitmap 行为一致
                let maxCount = courseLimitForFamily()
                let visible = Array(data.courses.prefix(maxCount))
                VStack(spacing: 10) {
                    ForEach(visible) { course in
                        WidgetCourseCard(course: course, timeJson: data.timeJson, scheme: s,
                                         colorless: colorless, fontSizeSp: 12,
                                         displayMode: displayMode,
                                         groupRows: data.courses.filter { $0.groupId == course.groupId },
                                         useAlias: useAlias)
                            .frame(height: 38)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(s.bg)
        .widgetURL(URL(string: "sleepy://open"))
    }

    /// 不同 widget family 显示的最大课程数。WidgetKit 不支持 ScrollView 归档,
    /// 所以按容器尺寸裁剪,与 Android bitmap 渲染时由容器 clip 行为一致。
    private func courseLimitForFamily() -> Int {
        switch widgetFamily {
        case .systemSmall: return 2
        case .systemMedium: return 3
        case .systemLarge: return 6
        default: return 3
        }
    }

    // ← todayCompactTexts(resolve, useAlias, data): 紧凑档纯文本行(渲染与单测单一事实来源)。
    // 空课表/学期外/无课也各有对应一行; useAlias: true 时显示别名(空回退原名)。
    static func todayCompactTexts(data: WidgetData, useAlias: Bool) -> [String] {
        if !data.hasTable { return [L10n.format("widget_create_schedule")] }
        if data.semesterStatus != .inRange {
            return [data.semesterStatus == .beforeStart
                    ? L10n.format("semester_not_started")
                    : L10n.format("semester_ended")]
        }
        if data.courses.isEmpty { return [L10n.format("today_no_course")] }
        return data.courses.map { CourseDisplayUtil.displayName($0, useAlias) }
    }
}

// MARK: - SMALL 紧凑面 ← renderTodayCompact 布局(Today/TwoDay/WeekList/WeekGrid 共用)

/// 紧凑档渲染面 — 布局常量逐值对照 Android renderTodayCompact:
/// 背景圆角 20 / pad 10 / 日期行 11sp 顶部左侧 / 正文 15sp bold 居中,
/// 首行基线 ≈ h/2, 行距 pitch 20, 最多 2 行, 超宽省略号截断(w - pad*2)。
struct WidgetCompactFace: View {
    let scheme: WidgetScheme
    let dateLabel: String?
    let lines: [String]

    var body: some View {
        ZStack {
            Rectangle()
                .fill(scheme.bg)
                .cornerRadius(20)
            VStack(spacing: 0) {
                if let dateLabel = dateLabel {
                    Text(dateLabel)
                        .font(.system(size: 11))
                        .foregroundColor(scheme.onSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                }
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    ForEach(Array(lines.prefix(2).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(scheme.onSurface)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 10)
                    }
                }
                // 首行基线 ≈ h/2: 两行块高≈38, 居中后基线偏上 ~5, 下移补偿 (← Android y=h/2)
                .offset(y: 4)
                Spacer(minLength: 0)
            }
        }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidgetRV", provider: TodayWidgetProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(L10n.format("widget_today_label"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
