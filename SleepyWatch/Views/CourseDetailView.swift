// CourseDetailView.swift — 课程详情 (2026-10 watch 伴侣 App)
// 手表 List→push 详情: 时间/节次/星期/周次/教师/教室/备注。
// 名: 恒原名 — iOS CourseDetailSheet:44/72 直读 courseName 不套别名
//     (别名只活在周视图/网格场景, issue#26 口径), 手表详情同规格。

import SwiftUI

struct CourseDetailView: View {
    let course: CourseEntity
    let table: TimeTableEntity
    var groupRows: [CourseEntity] = []

    @Environment(\.colorScheme) private var envScheme
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        let scheme = WatchPalette.scheme(envDark: envScheme == .dark)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // 节次/时间双模式 = 镜像 display_mode (手表零独有开关)
                Text(store.slotLabel(course, table: table))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundColor(scheme.onSurfaceVariant)
                Text(course.courseName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(scheme.onSurface)
                infoRow(L10n.t("course_field_week"), course.nodeString(), scheme)
                infoRow(L10n.t("watch_detail_day"), DateUtils.localizedDay(course.day), scheme)
                infoRow(L10n.t("week_range"), "\(course.startWeek)-\(course.endWeek)", scheme)
                if !course.teacher.isEmpty {
                    infoRow(L10n.t("course_field_teacher"), course.teacher, scheme)
                }
                if !course.room.isEmpty {
                    infoRow(L10n.t("course_field_room"), course.room, scheme)
                }
                if !course.note.isEmpty {
                    infoRow(L10n.t("course_field_note"), course.note, scheme)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .navigationTitle(Text(course.courseName))
    }

    private func infoRow(_ label: String, _ value: String, _ scheme: WidgetScheme) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(scheme.onSurfaceVariant)
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(scheme.onSurface)
        }
    }
}
