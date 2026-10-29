// CourseRowView.swift — 课程行卡 (2026-10 watch 伴侣 App)
// ← WidgetCourseCard 显示语义的 watch 重排: 左色条 + 时段/课名/教师·地点。
// 色: CourseColorUtil issue#22 三态取色同源 (组行传入同 groupId 行集;
//     无色模式镜像 course_colorless → 隐色条)。时段: slotLabel 镜像 display_mode。
// 名: 恒原名 — iOS 今日页 (TodayScreen:303 ← Android TodayScreen.kt:480) 不套
//     别名, 手表今日页同口径; 别名只活在周视图/网格 (见 WeekView)。
// meta「教师 · 地点」← TodayCourseCard 同拼接 (空段自动跳过)。

import SwiftUI

struct CourseRowView: View {
    let course: CourseEntity
    let table: TimeTableEntity
    let scheme: WidgetScheme
    var mark: CourseMark?
    var groupRows: [CourseEntity] = []

    @EnvironmentObject private var store: WatchStore

    private var color: Color {
        CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
            course, groupRows: groupRows.isEmpty ? [course] : groupRows,
            isDark: scheme.isDark, neutralColor: scheme.secondaryContainer)
    }

    /// 「教师 · 地点」← TodayCourseCard 同拼接: 空段跳过, 两段之间中点分隔
    private func metaText(_ c: CourseEntity) -> String {
        [c.teacher, c.room].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if !store.neutralColor {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 3)
                    .padding(.vertical, 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(store.slotLabel(course, table: table))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(scheme.onSurfaceVariant)
                Text(course.courseName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(scheme.onSurface)
                    .lineLimit(2)
                let meta = metaText(course)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 11))
                        .foregroundColor(scheme.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let mark = mark {
                // 进行中/下一节角标 ← today_screen 实时态的手表降维
                Capsule()
                    .fill(mark == .current ? scheme.primary : scheme.primary.opacity(0.25))
                    .frame(width: 6, height: 6)
                    .padding(.top, 4)
                    .accessibilityLabel(mark == .current ? L10n.t("watch_mark_now") : L10n.t("watch_mark_next"))
            }
        }
        .padding(.vertical, 2)
    }
}
