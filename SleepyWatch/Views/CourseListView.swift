// CourseListView.swift — 课程清单 (2026-10 watch 伴侣 App)
// 语义 ← CourseListScreen: 名+老师归组 (同名不同老师=两张卡, 复合 id 同源),
// 组内计数「N个上课安排」(course_list_arrangements)。
// 名 = 原名 courseName — iOS 清单页不套别名 (:34/46 实况), 手表同口径;
// 空名回退 groupId ← CourseListScreen:34 isBlank 分支。
// 点组 → 详情 (复用 CourseDetailView, groupRows = 组内全行 ← 取色按组判定)。

import SwiftUI

struct CourseListView: View {
    let table: TimeTableEntity

    @EnvironmentObject private var store: WatchStore
    @Environment(\.colorScheme) private var envScheme

    /// 归组行 ← CourseListScreen.CourseGroup (name+teacher 复合键)。
    /// 命名 CourseGroup 而非 Group — 避免遮蔽 SwiftUI.Group (body 里要用)。
    private struct CourseGroup: Identifiable {
        let name: String
        let teacher: String
        let rows: [CourseEntity]
        var id: String { name + "\u{1F}" + teacher }
    }

    private var groups: [CourseGroup] {
        // 累加用「key → 行数组」可变字典 (CourseGroup.rows 是 let, 不能就地 append);
        // 收齐后一次性构造不可变组。order 保留首次出现顺序, 末了按名排序。
        var rowsByKey: [String: [CourseEntity]] = [:]
        var metaByKey: [String: (name: String, teacher: String)] = [:]
        var order: [String] = []
        for row in store.allCourses(table: table) {
            let name = row.courseName.isEmpty ? row.groupId : row.courseName
            let teacher = row.teacher.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = name + "\u{1F}" + teacher
            if rowsByKey[key] == nil {
                order.append(key)
                metaByKey[key] = (name, teacher)
            }
            rowsByKey[key, default: []].append(row)
        }
        return order.map { key in
            let m = metaByKey[key]!
            return CourseGroup(name: m.name, teacher: m.teacher, rows: rowsByKey[key]!)
        }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        let scheme = WatchPalette.scheme(envDark: envScheme == .dark)
        Group {
            if groups.isEmpty {
                Text(L10n.t("course_list_empty"))
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundColor(scheme.onSurfaceVariant)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups) { g in
                        NavigationLink {
                            CourseDetailView(course: g.rows[0], table: table, groupRows: g.rows)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(scheme.onSurface)
                                    .lineLimit(2)
                                if !g.teacher.isEmpty {
                                    Text(g.teacher)
                                        .font(.system(size: 11))
                                        .foregroundColor(scheme.onSurfaceVariant)
                                        .lineLimit(1)
                                }
                                // 「N个上课安排」← CourseGroupCard 同键
                                Text(L10n.format("course_list_arrangements", g.rows.count))
                                    .font(.system(size: 9))
                                    .foregroundColor(scheme.onSurfaceVariant)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .navigationTitle(Text(L10n.t("course_list_title")))
    }
}
