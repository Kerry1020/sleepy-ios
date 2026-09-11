// WeekListWidgetView.swift — ← WeekListWidget.kt + WidgetBitmapRenderers.renderWeekList
// 本周课表(列表) widget — 7 列日列(列数随 visibleDays)。
// 列卡片: primaryContainer(今天) / surfaceContainer(其他), 14dp 圆角。
// 课程: 彩色胶囊背景 + BOLD 课名。

import SwiftUI
import WidgetKit

struct WeekListWidgetEntry: TimelineEntry {
    let date: Date
    let data: WeekData
}

struct WeekListWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekListWidgetEntry {
        WidgetArchiveLog.append(kind: "WeekListWidgetRV", family: context.family.description, result: "success")
        return WeekListWidgetEntry(date: Date(), data: WeekListWidgetLoader.loadDataSync(kind: "WeekListWidgetRV"))
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekListWidgetEntry) -> Void) {
        WidgetArchiveLog.append(kind: "WeekListWidgetRV", family: context.family.description, result: "success")
        completion(WeekListWidgetEntry(date: Date(), data: WeekListWidgetLoader.loadDataSync(kind: "WeekListWidgetRV")))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekListWidgetEntry>) -> Void) {
        let entry = WeekListWidgetEntry(date: Date(), data: WeekListWidgetLoader.loadDataSync(kind: "WeekListWidgetRV"))
        let refresh = Date().addingTimeInterval(6 * 3600)  // 半天兜底;数据变化由 App 端 reloadAllTimelines 触发
        WidgetArchiveLog.append(kind: "WeekListWidgetRV", family: context.family.description, result: "success")
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// 星期标题(英缩写 — Android dayLabels arrayOf("", "Mon"...))
let weekDayLabels = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

/// 列数过滤(决策 D5-12, 对齐 renderWeekList L238-240): visibleDays 空集回退全周防御
func shownDays(_ data: WeekData) -> [DayData] {
    let visibleDays = AppPrefs.shared.getVisibleDays()
    if visibleDays.isEmpty { return data.days }
    return data.days.filter { visibleDays.contains($0.dayOfWeek) }.sorted { $0.dayOfWeek < $1.dayOfWeek }
}

// MARK: - View ← renderWeekList

struct WeekListWidgetEntryView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    let entry: WeekListWidgetEntry

    var body: some View {
        // SMALL 紧凑档 ← renderWeekListCompact: 无日期行, 今天+明天各一行"周X 课名"居中
        if widgetFamily == .systemSmall {
            let s = resolveWidgetScheme(themeKey: entry.data.themeKey, isDark: entry.data.isDark)
            WidgetCompactFace(scheme: s, dateLabel: nil,
                              lines: Self.weekListCompactTexts(data: entry.data,
                                                               todayDow: DateUtils.todayDayOfWeek(today: Date()),
                                                               useAlias: AppPrefs.shared.isWidgetUseAlias()))
                .widgetURL(URL(string: "sleepy://open"))
        } else {
            regularBody
        }
    }

    // ← renderWeekList: 常规/中大档 7 列日列排版
    @ViewBuilder
    private var regularBody: some View {
        let data = entry.data
        let s = resolveWidgetScheme(themeKey: data.themeKey, isDark: data.isDark)
        let colorless = AppPrefs.shared.isWidgetColorless()
        let days = shownDays(data)
        // issue#26: widget 全局一档别名开关
        let useAlias = AppPrefs.shared.isWidgetUseAlias()

        Group {
            if !data.hasTable || days.isEmpty {
                Text(L10n.format("widget_create_schedule"))
                    .font(.system(size: 15))
                    .foregroundColor(s.onSurface)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                let todayDow = DateUtils.todayDayOfWeek(today: Date())
                VStack(spacing: 0) {
                    // ★ 学期外: 顶部全宽状态行(学期前=第1周课照常预习 / 学期后=课程已清空)
                    if data.semesterStatus != .inRange {
                        Text(data.semesterStatus == .beforeStart
                             ? L10n.format("semester_not_started")
                             : L10n.format("semester_ended"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(s.onSurfaceVariant)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 4)
                    }
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(days, id: \.dayOfWeek) { day in
                            WeekListDayColumn(day: day, scheme: s, colorless: colorless,
                                              isToday: day.dayOfWeek == todayDow, useAlias: useAlias)
                        }
                    }
                }
            }
        }
        .padding(6)
        .background(s.bg)
        .widgetURL(URL(string: "sleepy://open"))
    }
}

private struct WeekListDayColumn: View {
    let day: DayData
    let scheme: WidgetScheme
    let colorless: Bool
    let isToday: Bool
    /// issue#26: widget 场景别名 — 课名展示名
    let useAlias: Bool

    var body: some View {
        let s = scheme
        VStack(alignment: .center, spacing: 0) {
            // 星期标题
            Text(weekDayLabels[day.dayOfWeek])
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isToday ? s.onPrimaryContainer : s.onSurface)
                .padding(.top, 1)   // 安卓标题基线 colTop+12 (字形顶≈+4)
                .padding(.bottom, 11) // chip 顶 colTop+26

            if !day.courses.isEmpty {
                // 课程数量 chip
                Text("\(day.courses.count) 门")
                    .font(.system(size: 9))
                    .foregroundColor(s.onSurfaceVariant)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(s.surfaceVariant)
                    .cornerRadius(50)
                    .padding(.bottom, 6)

                // 课程列表 — 每门课带颜色胶囊背景
                VStack(spacing: 3) {
                    ForEach(day.courses, id: \.id) { course in
                        // ★ 课程颜色背景 (对齐 WeekGrid 风格) — 统一入口 CourseColorUtil (决策 D3)
                        // issue#22: 同名课程多地点 — 用 day.courses 同 groupId 全行, 支持 AUTO/CUSTOM 按行判
                        let bgColor = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
                            course, groupRows: day.courses.filter { $0.groupId == course.groupId },
                            isDark: s.isDark, neutralColor: s.surfaceVariant, colorless: colorless)
                        Text(CourseDisplayUtil.displayName(course, useAlias))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(CourseColorUtil.textColorOn(bg: bgColor, isDark: s.isDark,
                                                                         onSurface: s.onSurface))
                            .lineLimit(1)
                            .padding(.horizontal, 2) // 文字距胶囊左/右 2dp (安卓 x+coursePad+2, 截断预算 colW-10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 16)
                            .background(bgColor)
                            .cornerRadius(4)
                            .padding(.horizontal, 3) // 胶囊两侧内缩 3dp (安卓 x+3 ~ x+colW-3)
                    }
                }
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 列背景: 今天 primaryContainer / 其他 surfaceContainer, 14dp 圆角
        .background(isToday ? s.primaryContainer : s.surfaceContainer)
        .cornerRadius(14)
    }
}

struct WeekListWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekListWidgetRV", provider: WeekListWidgetProvider()) { entry in
            WeekListWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(L10n.format("widget_week_list_label"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// ← weekListCompactTexts(resolve, dayName, useAlias, today, data): SMALL 紧凑档纯文本行。
// 今天+明天(周循环)有课的列各一行"周X 首课名", 按今天→明天目标序排(禁 ISO 排序:
// 周日锚点时 ISO 会把"明天=周一"排到"今天"前面); 空回退"无课"。
extension WeekListWidgetEntryView {
    static func weekListCompactTexts(data: WeekData, todayDow: Int, useAlias: Bool) -> [String] {
        if !data.hasTable || data.days.isEmpty { return [L10n.format("widget_create_schedule")] }
        if data.semesterStatus != .inRange {
            return [data.semesterStatus == .beforeStart
                    ? L10n.format("semester_not_started")
                    : L10n.format("semester_ended")]
        }
        let targetDows = [todayDow, todayDow % 7 + 1]   // 今天 + 明天(周循环)
        let lines = data.days
            .filter { targetDows.contains($0.dayOfWeek) && !$0.courses.isEmpty }
            .sorted { targetDows.firstIndex(of: $0.dayOfWeek)! < targetDows.firstIndex(of: $1.dayOfWeek)! }
            .prefix(2)
            .map { "\(DateUtils.localizedDay($0.dayOfWeek)) \(CourseDisplayUtil.displayName($0.courses.first!, useAlias))" }
        return lines.isEmpty ? [L10n.format("no_course")] : Array(lines)
    }
}
