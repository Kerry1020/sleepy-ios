// CourseListScreen.swift — ← ui/screen/mine/CourseListScreen.kt
// 2026-09-21 用户令: 我的页「课程数」卡 → 新页, 列出当前课表所有课程(按课程名聚合)。
// 与管理页不同: 这里以「课程组」为单位, 一个名字出现多次(同一课程多次上课安排)聚合为
// 一张卡显示, 副标题注明「X 个上课安排」; 字段: 课程名 / 老师 / 教室 / 全部周次段。

import SwiftUI

/// 课程组 — 名+老师归组; 组内再按地点分组。
private struct CourseGroup {
    let name: String
    let teacher: String
    let locations: [CourseLocation]
}

private struct CourseLocation {
    let room: String
    let rows: [CourseEntity]
}

struct CourseListScreen: View {
    let onBack: () -> Void

    @EnvironmentObject var viewModel: ScheduleViewModel

    /// 课程卡先按课程名和老师归组;同一张卡内部再按上课地点分组,
    /// 避免不同地点混在同一行,也保留同名不同老师的独立课程卡。
    private var grouped: [CourseGroup] {
        var dict: [String: [(String, [CourseEntity])]] = [:]   // name -> [(teacher, rows)]
        for row in viewModel.state.courses {
            let name = row.courseName.isBlank ? row.groupId : row.courseName
            let teacher = row.teacher.trimmingCharacters(in: .whitespacesAndNewlines)
            var teacherList = dict[name] ?? []
            if let idx = teacherList.firstIndex(where: { $0.0 == teacher }) {
                teacherList[idx].1.append(row)
            } else {
                teacherList.append((teacher, [row]))
            }
            dict[name] = teacherList
        }
        let groups: [CourseGroup] = dict.flatMap { name, teacherList in
            teacherList.map { teacher, rows -> CourseGroup in
                let displayName = rows[0].courseName.isBlank ? name : rows[0].courseName
                var locDict: [String: [CourseEntity]] = [:]
                for r in rows {
                    let room = r.room.trimmingCharacters(in: .whitespacesAndNewlines)
                    locDict[room, default: []].append(r)
                }
                let locations = locDict.map { room, locationRows in
                    CourseLocation(room: room, rows: locationRows)
                }.sorted { $0.room < $1.room }
                return CourseGroup(name: displayName, teacher: rows[0].teacher, locations: locations)
            }
        }
        return groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if grouped.isEmpty {
                Spacer()
                Text(L10n.t("course_list_empty"))
                    .font(.body)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        Text(L10n.t("course_list_subtitle"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(grouped, id: \.name) { group in
                            CourseGroupCard(group: group)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
            }
            .accessibilityLabel(Text(L10n.t("back")))
            Spacer()
            Text(L10n.t("course_list_title"))
                .font(.headline)
            Spacer()
            Color.clear.frame(width: 30, height: 30)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct CourseGroupCard: View {
    let group: CourseGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.name.isBlank ? L10n.t("course_detail_title") : group.name)
                .font(.subheadline.weight(.semibold))
            if !group.teacher.isBlank {
                MetaRow(icon: "person", text: group.teacher)
            }
            ForEach(group.locations, id: \.room) { location in
                if !location.room.isBlank {
                    MetaRow(icon: "mappin.and.ellipse", text: location.room)
                }
                Text(L10n.format("course_list_arrangements", location.rows.count))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                // 每个地点单独列出该地点的全部上课安排。
                VStack(spacing: 2) {
                    ForEach(location.rows, id: \.id) { row in
                        ArrangementRowView(row: row)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }
}

private struct MetaRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text(text)
                .font(.footnote)
        }
    }
}

private struct ArrangementRowView: View {
    let row: CourseEntity

    var body: some View {
        let dayLabel = L10n.t("day_short_\(row.day)")
        let nodeLabel = row.nodeString(isShort: true)
        let weekRangeLabel = L10n.format("course_week_range", nodeLabel, row.startWeek, row.endWeek)
        return HStack(spacing: 4) {
            Image(systemName: "book")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text("\(dayLabel) · \(weekRangeLabel)")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }
}
