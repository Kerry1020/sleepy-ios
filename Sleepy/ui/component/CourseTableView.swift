// CourseTableView.swift — ← ui/component/CourseTableView.kt (733 行)
// Cards 网格视图 + FullWeekView(7days) + 公共小组件。
//
// 架构(逐行对齐):
//   BoxWithConstraints → colW(dp) → Column(verticalScroll) → 表头 Row + 固定高 grid Box
//   时间栏/课程卡全用 offset 绝对定位 → 滚动同步。
// 布局常量: headH 52 / timeW 68 / slotH 52 / gapH 4 / gapW 5 / rowH 56。

import SwiftUI

/// 时段定义 — 5 个时段(WakeUp 默认 12 节对应 1-2/3-5/6-7/8-10/11-13) ← TimeSlot
struct TimeSlot {
    let label: String        // "1-2节"
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int
    var displayStart: String { String(format: "%02d:%02d", startHour, startMinute) }
    var displayEnd: String { String(format: "%02d:%02d", endHour, endMinute) }
    let nodeStart: Int
    var nodeEnd: Int { nodeStart }  // 派生段(段内多节由调用方展开为单节行)

    var timeString: String { "\(displayStart)-\(displayEnd)" }
}

// MARK: - CardsGridView ← CardsGridView

struct CardsGridView: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.localCoursePalette) private var palette
    @Environment(\.localNavExtraBottomPadding) private var navExtra
    let courses: [CourseEntity]
    let timeSlots: [TimeSlot]
    var visibleDays: Set<Int> = Set(1...7)
    var showDate: Bool = false
    var startDate: String = ""
    var currentWeek: Int = 1
    var today: Int = DateUtils.todayDayOfWeek()
    let onCourseClick: (CourseEntity) -> Void
    var greyDays: Set<Int> = []  // 本周应灰显的星期几 (1-7) — 节假日/周末灰显

    var body: some View {
        let maxNode = timeSlots.map { $0.nodeEnd }.max() ?? 12
        let sortedDays = visibleDays.sorted()
        let dayCount = sortedDays.count
        // issue#23: 边缘节次节点的"行号"按 timeSlots 自然顺序取(已按 node ASC 排序);
        // 前置节点(-1, 0)排到 grid 顶部, 后置节点(N+1, N+2)排到 grid 底部。
        // 返回 -1 = 该节点不在 timeSlots(数据脏); 调用方判 >= 0 再绘。
        let slotIndexOf: (Int) -> Int = { node in
            timeSlots.firstIndex { $0.nodeStart == node } ?? -1
        }

        // 布局常量(全 dp) — issue#8: 整体缩放(0.7~1.3) 字号/行高/间距/圆角/内边距等比联动
        // (← Android CourseTableView.kt d(v) = v*scale)
        let gridScale = CGFloat(AppPrefs.shared.getGridScale())
        let gridCornerRatio = CGFloat(AppPrefs.shared.getGridCornerRatio())
        let d: (CGFloat) -> CGFloat = { $0 * gridScale }
        let headH = d(52)
        let slotH = d(52)
        let gapH = d(4)
        let rowH = slotH + gapH

        GeometryReader { geo in
            // 根据容器宽度计算列宽；窄屏优先压缩时间栏和间距，避免卡片向右溢出。(× scale)
            let sideInset: CGFloat = 16
            let timeW = min(68, max(52, geo.size.width * 0.16)) * gridScale
            let gapW = min(5, max(3, geo.size.width * 0.012)) * gridScale
            let contentW = max(geo.size.width - sideInset - timeW - gapW * CGFloat(dayCount), 0)
            let colW = max(contentW / CGFloat(dayCount), 28)
            // issue#23: grid 高度按 timeSlots 行数算(maxNode 已不反映边缘节点总数)
            let gridH = rowH * CGFloat(max(timeSlots.count, 1))

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    // ---- 表头 ----
                    // 首列留白 = timeW + gapW，与下方 grid 的 cardX 对齐；高度随日期行自适应
                    let hasDateRow = showDate && !startDate.isEmpty
                    HStack(spacing: gapW) {
                        Spacer().frame(width: timeW + gapW)
                        ForEach(sortedDays, id: \.self) { day in
                            let dateStr: String? = {
                                guard showDate, !startDate.isEmpty,
                                      let d = DateUtils.dateOfWeek(startDate: startDate, week: currentWeek, dayOfWeek: day) else { return nil }
                                return DateUtils.shortDate(d)
                            }()
                            DayHeadCell(day: day, isToday: day == today,
                                        isGrey: greyDays.contains(day),
                                        courseCount: courses.filter { $0.day == day }.count,
                                        dateStr: dateStr,
                                        scale: gridScale, cornerRatio: gridCornerRatio)
                                .frame(width: colW)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(height: hasDateRow ? d(56) : headH)

                    Spacer().frame(height: gapH)

                    // ---- Grid 主体: 固定高度, 内部绝对定位 ----
                    ZStack(alignment: .topLeading) {
                        // 时间栏
                        ForEach(Array(timeSlots.enumerated()), id: \.element.nodeStart) { i, slot in
                            SingleTimeHeadCell(slot: slot, scale: gridScale, cornerRatio: gridCornerRatio)
                                .frame(width: timeW, height: slotH)
                                .offset(y: rowH * CGFloat(i))
                        }
                        // 课程卡片: 冲突簇整簇走 ConflictClusterCard, 非簇课保持原
                        // CourseOverlayCard 单卡路径(回归保护)(← CourseTableView.kt Grid 主体)
                        GridConflictLayer(
                            courses: courses, visibleDays: visibleDays, sortedDays: sortedDays,
                            maxNode: maxNode, timeSlots: timeSlots,
                            timeW: timeW, colW: colW, rowH: rowH,
                            gapW: gapW, gapH: gapH, greyDays: greyDays,
                            scale: gridScale, cornerRatio: gridCornerRatio,
                            isDark: CourseColorUtil.isPaletteDark(palette),
                            onCourseClick: onCourseClick)
                    }
                    .frame(width: max(geo.size.width - sideInset, 0),
                           height: gridH, alignment: .topLeading)
                    // 悬浮底栏额外余量(→ Android LocalNavExtraBottomPadding Spacer):
                    //   镜像 Android CourseTableView.kt "Spacer(height = navExtra)" 末行追加,
                    //   网格内最末一行课不被悬浮药丸遮住。
                    Color.clear.frame(height: navExtra)
                }
                .padding(8 * gridScale)
            }
        }
        .background(colors.surfaceContainerHigh)
        .cornerRadius(SleepyShapes.large)
    }

}

/// 冲突簇渲染层(← CourseTableView.kt Grid 内联逻辑, v7.10.16r 终态)
/// 引擎聚簇后: 簇 → ConflictClusterCard(轮换/置顶 override 通道), 非簇课 → 原单卡路径。
/// topOverrides=会话级切换态(内存), defaultTopMap=持久偏好(radio), rotationSteps=纯会话轮换。
struct GridConflictLayer: View {
    @Environment(\.localWakeUpColors) private var colors
    @ObservedObject private var defaultTopStore = AppPrefs.sharedConflictDefaultTopStore
    let courses: [CourseEntity]
    let visibleDays: Set<Int>
    let sortedDays: [Int]
    let maxNode: Int
    /// issue#23: 边缘节点行号/步长按 timeSlots 真实行序; 空 = 旧 startNode ∈ [1,maxNode] 行为
    let timeSlots: [TimeSlot]
    let timeW: CGFloat
    let colW: CGFloat
    let rowH: CGFloat
    let gapW: CGFloat
    let gapH: CGFloat
    let greyDays: Set<Int>
    /// issue#8: 网格缩放/圆角比例 — 透传给单卡路径(簇卡内部几何已由缩放后的 colW/rowH 驱动)
    var scale: Double = 1.0
    var cornerRatio: Double = 1.0
    /// 深色判定(GridConflictLayer 无 palette 环境注入,由 CardsGridView 传入)
    let isDark: Bool
    let onCourseClick: (CourseEntity) -> Void

    /// 会话级置顶切换(簇键 → courseId);App 重启清空(← topOverrides rememberSaveable 语义)
    @State private var topOverrides: [String: Int64] = [:]
    /// v7.10.16r 轮换态: 簇键 → 轮换步数,纯会话级不落盘
    @State private var rotationSteps: [String: Int] = [:]

    var body: some View {
        let conflictStyle = AppPrefs.shared.getConflictStyle()
        let defaultTopMap = defaultTopStore.map
        let clusters = ConflictLayoutEngine.findClusters(courses)
        let clusteredIds = Set(clusters.flatMap { $0.courses.map { $0.id } })
        // issue#23: 边缘节点用 slotIndexOf 兜底,数据脏返回 -1 直接过滤
        let slotIndexOf: (Int) -> Int = timeSlots.isEmpty
            ? { node in (1...maxNode).contains(node) ? node - 1 : -1 }
            : { node in timeSlots.firstIndex { $0.nodeStart == node } ?? -1 }

        ZStack(alignment: .topLeading) {
            let clusterItems = Array(clusters.enumerated())
            ForEach(clusterItems, id: \.offset) { item in
                let cluster = item.element
                // 簇内课若因 visibleDays 过滤或节点不在 timeJson 则整簇跳过
                if visibleDays.contains(cluster.day) {
                    let inGrid = cluster.courses.filter { slotIndexOf($0.startNode) >= 0 }
                    if !inGrid.isEmpty {
                        let anchor = cluster.courses.first! // 主课判定序首位,决定簇基点
                        let dayIdx = sortedDays.firstIndex(of: cluster.day) ?? 0
                        let cardX = timeW + gapW + (colW + gapW) * CGFloat(dayIdx)
                        let cardY = rowH * CGFloat(max(slotIndexOf(anchor.startNode), 0))
                        let clusterKey = ConflictLayoutEngine.conflictClusterKey(cluster)
                        ConflictClusterCard(
                            cluster: cluster,
                            style: conflictStyle,
                            topOverrideId: topOverrides[clusterKey] ?? defaultTopMap[clusterKey],
                            onPickTop: { id in setTopOverride(clusterKey, id) },
                            onCourseClick: onCourseClick,
                            colW: colW, rowH: rowH, maxNode: maxNode,
                            gapW: gapW, gapH: gapH,
                            timeSlots: timeSlots,
                            isGrey: greyDays.contains(cluster.day),
                            rotationStep: rotationSteps[clusterKey],
                            onRotate: {
                                rotationSteps[clusterKey, default: (rotationSteps[clusterKey] ?? 0)] += 1
                            },
                            onPickFromBadge: { layerPos in
                                // 气泡选课 = 换来看: 轮换步数使目标层转到首位(会话态)
                                rotationSteps[clusterKey] = layerPos
                            })
                            .offset(x: cardX, y: cardY)
                    }
                }
            }
            ForEach(courses) { course in
                if visibleDays.contains(course.day),
                   slotIndexOf(course.startNode) >= 0,
                   !clusteredIds.contains(course.id) { // 簇内课已由 ConflictClusterCard 绘制
                    let dayIdx = sortedDays.firstIndex(of: course.day) ?? 0
                    let nodeIdx = slotIndexOf(course.startNode)
                    // 步长上限按剩余行数算(边缘节点也按 timeSlots 总行数取模)
                    let steps = min(max(course.step, 1), timeSlots.count - nodeIdx)
                    let cardX = timeW + gapW + (colW + gapW) * CGFloat(dayIdx)
                    let cardY = rowH * CGFloat(nodeIdx)
                    let cardH = rowH * CGFloat(steps) - gapH
                    CourseOverlayCard(course: course, cardHeight: cardH,
                                      isDark: isDark,
                                      isGrey: greyDays.contains(course.day),
                                      groupRows: courses.filter { $0.groupId == course.groupId },
                                      scale: scale, cornerRatio: cornerRatio) {
                        onCourseClick(course)
                    }
                    .frame(width: colW, height: cardH)
                    .offset(x: cardX, y: cardY)
                }
            }
        }
        // v7.10.16r(评审#4): 详情弹窗 radio 落盘 → 本层会话态跟随 —
        // 显式选默认置顶 = 会话 override 同步为 radio 值(同帧换层) + 同簇临时轮换让位。
        // ← Android ScheduleScreen.onDefaultTopChanged
        .onChange(of: defaultTopStore.map) { newMap in
            // radio 落盘新值/改值 → 会话 override 同步 + 同簇临时轮换让位
            for (k, v) in newMap where lastDefaultTopMap[k] != v {
                topOverrides[k] = v
                rotationSteps[k] = nil
            }
            // radio 清除默认置顶(map 移除键) → 会话 override 同步清除
            for k in lastDefaultTopMap.keys where newMap[k] == nil {
                topOverrides.removeValue(forKey: k)
                rotationSteps[k] = nil
            }
            lastDefaultTopMap = newMap
        }
    }

    /// onChange 需要旧值对比 — 只处理真正被 radio 触碰的簇键
    @State private var lastDefaultTopMap: [String: Int64] = [:]

    private func setTopOverride(_ key: String, _ courseId: Int64?) {
        if let id = courseId { topOverrides[key] = id } else { topOverrides.removeValue(forKey: key) }
    }
}

// ← SingleTimeHeadCell
private struct SingleTimeHeadCell: View {
    @Environment(\.localWakeUpColors) private var colors
    let slot: TimeSlot
    var scale: Double = 1.0
    var cornerRatio: Double = 1.0

    var body: some View {
        VStack(spacing: 1 * scale) {
            Text(L10n.format("period_format_node", slot.label))
                .font(.system(size: 10 * scale, weight: .semibold))
                .foregroundColor(colors.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
            Text(slot.timeString)
                .font(.system(size: 9 * scale))
                .foregroundColor(colors.onSurfaceVariant)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)
        }
        .padding(4 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surfaceContainerLow)
        .cornerRadius(12 * scale * cornerRatio)
        .padding(2 * scale)
    }
}

// ← CourseOverlayCard
private struct CourseOverlayCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let course: CourseEntity
    var cardHeight: CGFloat = 0   // 0 = 调用方未提供, 回退旧行为
    let isDark: Bool
    var isGrey: Bool = false      // 节假日灰显
    /// issue#22: 同 groupId 全行(AUTO 模式按行序算 hue; 不传 = 退化为单行 groupRows)
    var groupRows: [CourseEntity] = []
    /// issue#8: 网格缩放/圆角比例
    var scale: Double = 1.0
    var cornerRatio: Double = 1.0
    let onClick: () -> Void

    var body: some View {
        let effRows = groupRows.isEmpty ? [course] : groupRows
        let bg = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
            course, groupRows: effRows, isDark: isDark,
            neutralColor: colors.surfaceVariant,
            colorless: AppPrefs.shared.isCourseColorless())
        let fg = CourseColorUtil.textColorOn(bg: bg, isDark: isDark, onSurface: colors.onSurface)
        // 节假日灰显：色块叠 alpha + 文字应用 strikethrough 样式 ← effectiveBg/effectiveFg/textDecoration
        let effectiveBg = isGrey ? bg.opacity(SleepyTheme.Alpha.inactive) : bg
        let effectiveFg = isGrey ? fg.opacity(SleepyTheme.Alpha.inactive) : fg
        let strikethrough = isGrey && AppPrefs.shared.getHolidayStyle() == "strikethrough"
        // 副信息(教室/教师/无) — grid_sub_info 设置决定
        // issue#8: 卡高阈值与字号随 scale 联动(← Android fontSize = 10*scale/11*scale)
        let bodyFont = (cardHeight >= 110 * scale ? 10.0 : 11.0) * scale
        let subInfo = AppPrefs.shared.getGridSubInfo()
        // issue#26: 网格场景别名 — 网格设置开且别名非空才显示别名, 否则原名
        let name = CourseDisplayUtil.displayName(course, AppPrefs.shared.isGridUseAlias())
        let subText: String = {
            switch subInfo {
            case "room": return course.room
            case "teacher": return course.teacher
            default: return ""
            }
        }()

        Button(action: onClick) {
            Group {
                if subText.isEmpty {
                    // 无副信息: 课程名整体居中(原行为); 名字长时压缩字体防横向溢出
                    Text(name)
                        .font(.system(size: bodyFont, weight: .semibold))
                        .foregroundColor(effectiveFg)
                        .strikethrough(strikethrough)
                        .lineLimit(6)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)
                        .multilineTextAlignment(.center)
                } else {
                    // 有副信息: 课程名在上半区居中, 副信息贴卡底; 两者都允许缩放
                    VStack(spacing: 2 * scale) {
                        Text(name)
                            .font(.system(size: bodyFont, weight: .semibold))
                            .foregroundColor(effectiveFg)
                            .strikethrough(strikethrough)
                            .lineLimit(4)
                            .minimumScaleFactor(0.6)
                            .allowsTightening(true)
                            .multilineTextAlignment(.center)
                            .frame(maxHeight: .infinity)
                        Text(subText)
                            .font(.system(size: 9 * scale))
                            .foregroundColor(effectiveFg.opacity(SleepyTheme.Alpha.highContent))
                            .strikethrough(strikethrough)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .allowsTightening(true)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("gridcell_\(course.id)")
        .padding(4 * scale)
        .background(effectiveBg)
        .cornerRadius(12 * scale * cornerRatio)
        .padding(2 * scale)
    }
}

// ← DayHeadCell
private struct DayHeadCell: View {
    @Environment(\.localWakeUpColors) private var colors
    let day: Int
    let isToday: Bool
    var isGrey: Bool = false
    let courseCount: Int
    var dateStr: String? = nil
    /// issue#8: 缩放(字号/内边距联动) + 圆角比例(← Android 16*scale*cornerRatio)
    var scale: Double = 1.0
    var cornerRatio: Double = 1.0

    var body: some View {
        let bg = isToday ? colors.primaryContainer : colors.surface
        let fg = isGrey ? colors.onSurfaceVariant.opacity(SleepyTheme.Alpha.inactive)
                        : (isToday ? colors.onPrimaryContainer : colors.onSurface)
        let subFg = isGrey ? colors.onSurfaceVariant.opacity(SleepyTheme.Alpha.inactive)
                           : (isToday ? colors.onPrimaryContainer.opacity(SleepyTheme.Alpha.highContent)
                                      : colors.onSurfaceVariant)

        VStack(spacing: 1 * scale) {
            // ← Android fontSize = (14*scale).sp(dayLabel 13→14 与安卓对齐)
            Text(DateUtils.localizedDay(day))
                .font(.system(size: 14 * scale, weight: .semibold))
                .foregroundColor(fg)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
            if let dateStr = dateStr {
                Text(dateStr)
                    .font(.system(size: 10 * scale))
                    .foregroundColor(subFg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
            } else {
                Text(courseCount == 0 ? L10n.format("no_course")
                                      : L10n.format("course_count_format", courseCount))
                    .font(.system(size: 9 * scale))
                    .foregroundColor(subFg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bg)
        .cornerRadius(16 * scale * cornerRatio)
        .padding(.horizontal, 1)
        .padding(.vertical, 6 * scale)
    }
}

// =====================================================================================
// 7days full 视图 — switchable.html #fullView ← FullWeekView
// =====================================================================================

struct FullWeekView: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.localCoursePalette) private var palette
    @Environment(\.localNavExtraBottomPadding) private var navExtra
    let courses: [CourseEntity]
    var visibleDays: Set<Int> = Set(1...7)
    var displayMode: String = "node"
    var timeJson: String = ""
    var today: Int = DateUtils.todayDayOfWeek()
    let onCourseClick: (CourseEntity) -> Void
    var greyDays: Set<Int> = []  // 本周应灰显的星期几 (1-7)

    var body: some View {
        let byDay = Dictionary(grouping: courses, by: { $0.day })
        // ← Android FullWeekView: 设置页改 weekScale/cornerRatio/twoColumn/hideEmptyDays/别名后即时生效
        let weekScale = AppPrefs.shared.getWeekScale()
        let cornerRatio = AppPrefs.shared.getGridCornerRatio()
        let useAlias = AppPrefs.shared.isWeekUseAlias()

        ScrollView(.vertical) {
            VStack(spacing: 0) {
                WeekStrip(byDay: byDay, visibleDays: visibleDays, today: today, greyDays: greyDays,
                          scale: weekScale, cornerRatio: cornerRatio, useAlias: useAlias)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                DetailPanel(byDay: byDay, visibleDays: visibleDays, displayMode: displayMode,
                            timeJson: timeJson, today: today, greyDays: greyDays,
                            scale: weekScale, cornerRatio: cornerRatio, useAlias: useAlias,
                            twoColumn: AppPrefs.shared.isWeekTwoColumn(),
                            twoColumnMode: AppPrefs.shared.getWeekTwoColumnMode(),
                            hideEmptyDays: AppPrefs.shared.isWeekHideEmptyDays(),
                            onCourseClick: onCourseClick)
                // (参数顺序: byDay/visibleDays/displayMode/timeJson/today/onCourseClick)
                // 悬浮底栏额外余量(→ Android LocalNavExtraBottomPadding Spacer):
                //   镜像 Android FullWeekView 末行追加 Spacer(height = navExtra),
                //   最后一张课不被悬浮药丸遮住。
                Color.clear.frame(height: navExtra)
            }
        }
    }
}

// ← WeekStrip
private struct WeekStrip: View {
    @Environment(\.localWakeUpColors) private var colors
    let byDay: [Int: [CourseEntity]]
    let visibleDays: Set<Int>
    let today: Int
    var greyDays: Set<Int> = []
    var scale: Double = 1.0
    var cornerRatio: Double = 1.0
    var useAlias: Bool = false

    var body: some View {
        HStack(spacing: 6 * scale) {
            ForEach(visibleDays.sorted(), id: \.self) { day in
                DaySummaryCell(day: day, courses: byDay[day] ?? [], isToday: day == today,
                               isGrey: greyDays.contains(day),
                               scale: scale, cornerRatio: cornerRatio, useAlias: useAlias)
            }
        }
    }
}

// ← DaySummaryCell
private struct DaySummaryCell: View {
    @Environment(\.localWakeUpColors) private var colors
    let day: Int
    let courses: [CourseEntity]
    let isToday: Bool
    var isGrey: Bool = false
    var scale: Double = 1.0
    var cornerRatio: Double = 1.0
    var useAlias: Bool = false

    var body: some View {
        let bg = isToday ? colors.primaryContainer : colors.surfaceContainer
        let fg = isGrey ? colors.onSurfaceVariant.opacity(SleepyTheme.Alpha.inactive)
                        : (isToday ? colors.onPrimaryContainer : colors.onSurface)

        VStack(spacing: 4 * scale) {
            // 日期
            Text(DateUtils.localizedDay(day))
                .font(.system(size: 13 * scale, weight: .semibold))
                .foregroundColor(fg)

            Spacer().frame(height: 6 * scale)

            // Chip: 课程数 — "N 门" 完整文字, 列宽放不下退化为纯数字。
            // ← Android textMeasurer: fullText 在列宽内换行(lineCount>1) → 只显数字。
            //   ViewThatFits 等价: fullText(单行)放得下用 fullText, 否则回退数字。
            // chipFg ← Android: onSurfaceVariant@alpha(grey ? inactive : 1)
            let chipFg = isGrey ? colors.onSurfaceVariant.opacity(SleepyTheme.Alpha.inactive)
                                : colors.onSurfaceVariant
            if courses.isEmpty {
                Spacer().frame(height: 14 * scale)
            } else {
                // iOS 15 兼容:ViewThatFits 是 iOS16+ API。原语义 = fullText 放不下
                // 回退纯数字;minimumScaleFactor 缩到 0.6 下限近似该意图(列宽极窄时
                // 缩字号仍可读,不再二选一),iOS 16+ 视觉行为不变。
                Text(L10n.format("course_count_format", courses.count))
                    .font(.system(size: 10 * scale, weight: .semibold))
                    .foregroundColor(chipFg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                .padding(.horizontal, 7 * scale)
                .padding(.vertical, 2 * scale)
                .background(colors.surfaceVariant)
                .cornerRadius(50)
            }

            Spacer().frame(height: 4 * scale)

            // Mini-list: 前 5 门课名(别名开启时显示别名 ← issue#26)
            VStack(spacing: 2 * scale) {
                ForEach(courses.prefix(5)) { c in
                    Text(CourseDisplayUtil.displayName(c, useAlias))
                        .font(.system(size: 9 * scale))
                        .foregroundColor(isToday
                            ? colors.onPrimaryContainer.opacity(SleepyTheme.Alpha.highContent)
                            : colors.onSurfaceVariant)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 132 * scale)
        .padding(.horizontal, 6 * scale)
        .padding(.vertical, 8 * scale)
        .background(bg)
        .cornerRadius(12 * scale * cornerRatio)
    }
}

// ← DetailPanel
private struct DetailPanel: View {
    @Environment(\.localWakeUpColors) private var colors
    let byDay: [Int: [CourseEntity]]
    let visibleDays: Set<Int>
    let displayMode: String
    let timeJson: String
    let today: Int
    var greyDays: Set<Int> = []
    var scale: Double = 1.0
    var cornerRatio: Double = 1.0
    var useAlias: Bool = false
    /// issue#8 周视图两栏 + 分栏标准(days=按天对半 / balance=按课程数动态平衡) + 隐藏无课日
    var twoColumn: Bool = false
    var twoColumnMode: String = "days"
    var hideEmptyDays: Bool = false
    let onCourseClick: (CourseEntity) -> Void

    var body: some View {
        let sd: (Double) -> CGFloat = { CGFloat($0 * scale) }
        // issue#8 隐藏无课日 — 两栏分栏前先过滤(Android single-column 不吃过滤: 全空周仍显示全部所选星期)
        let sortedDays = visibleDays.sorted().filter { hideEmptyDays ? !(byDay[$0] ?? []).isEmpty : true }

        // issue#8 周视图两栏, 省纵向滚动:
        //   days    = 按天对半分 — 前半周左/后半周右, 天数固定
        //   balance = 按课程数动态平衡 — 逐天放进当天卡片(约)更矮的栏, 两栏高度接近
        if twoColumn && sortedDays.count >= 2 {
            let split: ([Int], [Int]) = {
                if twoColumnMode == "balance" {
                    // 贪心: 按天序遍历, 权重 = 课程数(空天也有卡头记 1), 每天放进更矮的栏
                    var l = 0, r = 0
                    var left: [Int] = [], right: [Int] = []
                    for day in sortedDays {
                        let w = max((byDay[day] ?? []).count, 1)
                        if l <= r { left.append(day); l += w } else { right.append(day); r += w }
                    }
                    return (left, right)
                }
                let splitIdx = (sortedDays.count + 1) / 2
                return (Array(sortedDays[..<splitIdx]), Array(sortedDays[splitIdx...]))
            }()
            HStack(alignment: .top, spacing: sd(10)) {
                DetailDayColumn(days: split.0, byDay: byDay, today: today,
                                displayMode: displayMode, timeJson: timeJson,
                                greyDays: greyDays, scale: scale, cornerRatio: cornerRatio,
                                useAlias: useAlias, onCourseClick: onCourseClick)
                    .frame(maxWidth: .infinity)
                if !split.1.isEmpty {
                    DetailDayColumn(days: split.1, byDay: byDay, today: today,
                                    displayMode: displayMode, timeJson: timeJson,
                                    greyDays: greyDays, scale: scale, cornerRatio: cornerRatio,
                                    useAlias: useAlias, onCourseClick: onCourseClick)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(sd(12))
        } else {
            // 单栏(或两栏下过滤后不足 2 天) — 显示剩余星期(全空周时=全部所选星期, 不吃掉无课日)
            VStack(spacing: sd(10)) {
                ForEach(visibleDays.sorted(), id: \.self) { day in
                    let dayCourses = (byDay[day] ?? []).sorted { $0.startNode < $1.startNode }
                    DetailDayCard(day: day, courses: dayCourses, isToday: day == today,
                                  displayMode: displayMode, timeJson: timeJson,
                                  isGrey: greyDays.contains(day),
                                  scale: scale, cornerRatio: cornerRatio, useAlias: useAlias,
                                  onCourseClick: onCourseClick)
                }
            }
            .padding(sd(12))
            .background(colors.surfaceContainerHigh)
            .cornerRadius(16 * scale * cornerRatio)
        }
    }
}

// ← DayColumn: 两栏模式的单侧栏 — 半周的天卡片竖排在一个独立面板里
private struct DetailDayColumn: View {
    @Environment(\.localWakeUpColors) private var colors
    let days: [Int]
    let byDay: [Int: [CourseEntity]]
    let today: Int
    let displayMode: String
    let timeJson: String
    var greyDays: Set<Int> = []
    var scale: Double = 1.0
    var cornerRatio: Double = 1.0
    var useAlias: Bool = false
    let onCourseClick: (CourseEntity) -> Void

    var body: some View {
        VStack(spacing: 10 * scale) {
            ForEach(days, id: \.self) { day in
                let dayCourses = (byDay[day] ?? []).sorted { $0.startNode < $1.startNode }
                DetailDayCard(day: day, courses: dayCourses, isToday: day == today,
                              displayMode: displayMode, timeJson: timeJson,
                              isGrey: greyDays.contains(day),
                              scale: scale, cornerRatio: cornerRatio, useAlias: useAlias,
                              onCourseClick: onCourseClick)
            }
        }
        .padding(10 * scale)
        .background(colors.surfaceContainerHigh)
        .cornerRadius(16 * scale * cornerRatio)
    }
}

// ← DetailDayCard
private struct DetailDayCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let day: Int
    let courses: [CourseEntity]
    let isToday: Bool
    var displayMode: String = "node"
    var timeJson: String = ""
    var isGrey: Bool = false
    var scale: Double = 1.0
    var cornerRatio: Double = 1.0
    var useAlias: Bool = false
    let onCourseClick: (CourseEntity) -> Void

    // v7.10.4 冲突栏字体压缩: lane 实宽按内容区宽算(行满宽 → 与卡内边距对齐)
    @State private var contentW: CGFloat = 0

    var body: some View {
        let greyFg = colors.onSurfaceVariant.opacity(SleepyTheme.Alpha.inactive)
        VStack(spacing: 8 * scale) {
            // 头部: 星期 + 今天标记
            HStack {
                Text(DateUtils.localizedDay(day) + (isToday ? L10n.format("today_suffix") : ""))
                    .font(.system(size: 14 * scale, weight: .semibold))
                    .foregroundColor(isGrey ? greyFg : colors.onSurface)
                Spacer()
            }

            if courses.isEmpty {
                Text(DateUtils.localizedDay(day) + L10n.format("no_course_today"))
                    .font(.system(size: 12 * scale))
                    .foregroundColor(isGrey ? greyFg : colors.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // v7.10.6 行分组下沉引擎 + v7.10.10 栏间浅细竖分隔线:
                // mergeOverlapping 区域是划分(每课恰属一区域), 冲突区域整区域一行
                // (横向 laneCount 栏,同栏多门课纵向堆叠), 无冲突课一行一门全宽。
                let rows = ConflictLayoutEngine.weekLaneRows(courses)
                VStack(spacing: 7 * scale) {
                    ForEach(rows, id: \.courses.first!.id) { row in
                        if row.laneCount == 1, let only = row.courses.first {
                            LessonRow(course: only, displayMode: displayMode, timeJson: timeJson,
                                      isGrey: isGrey, groupRows: courses.filter { $0.groupId == only.groupId },
                                      scale: scale, cornerRatio: cornerRatio,
                                      useAlias: useAlias) {
                                onCourseClick(only)
                            }
                        } else {
                            // 冲突行: 按 lane 并排(每栏均分), 同栏课程纵向堆叠
                            // (栏内课互不重叠——chainGroups 独立集保证,堆叠即正确时序)
                            // v7.10.4: 栏实宽 → 字体线性压缩(两栏模式下 lane 半宽不缩则字挤)
                            let laneGap = 6 * scale
                            let laneW = contentW > 0
                                ? (contentW - laneGap * CGFloat(row.laneCount - 1)) / CGFloat(row.laneCount)
                                : 0
                            let laneScale = laneW >= 150 ? 1.0 : (laneW > 0 ? max(laneW / 150, 0.6) : 1.0)
                            let hideSide = laneW > 0 && laneW < 110
                            HStack(alignment: .top, spacing: laneGap) {
                                ForEach(0..<row.laneCount, id: \.self) { li in
                                    if li > 0 {
                                        // 栏间浅细竖线: 0.5dp 宽, onSurface hairline, 高度随行
                                        Rectangle()
                                            .fill(colors.onSurface.opacity(SleepyTheme.Alpha.hairline))
                                            .frame(width: 0.5)
                                    }
                                    let laneCourses = row.courses.filter { row.laneOf[$0.id] == li }
                                    VStack(spacing: 5 * scale) {
                                        ForEach(laneCourses) { laneCourse in
                                            LessonRow(course: laneCourse, displayMode: displayMode,
                                                      timeJson: timeJson, isGrey: isGrey,
                                                      groupRows: courses.filter { $0.groupId == laneCourse.groupId },
                                                      scale: scale, cornerRatio: cornerRatio,
                                                      laneScale: laneScale, hideSideLabel: hideSide,
                                                      useAlias: useAlias) {
                                                onCourseClick(laneCourse)
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(10 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 空课 surfaceContainerLow(← DetailDayCard L597), 无描边
        .background(courses.isEmpty ? colors.surfaceContainerLow : colors.surface)
        .cornerRadius(12 * scale * cornerRatio)
        .background(
            // 内容区宽测量 → 冲突 lane 压缩比(一次测量, 卡内全部冲突行共用)
            GeometryReader { g in
                Color.clear.preference(key: DetailDayCardWidthKey.self, value: g.size.width)
            }
        )
        .onPreferenceChange(DetailDayCardWidthKey.self) { contentW = $0 - 20 * scale }
    }
}

private struct DetailDayCardWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// ← LessonRow
private struct LessonRow: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.localCoursePalette) private var palette
    let course: CourseEntity
    let displayMode: String
    let timeJson: String
    var isGrey: Bool = false
    /// issue#22: 同 groupId 全行(AUTO 模式按行序算 hue; 不传 = 退化为单行 groupRows)
    var groupRows: [CourseEntity] = []
    /// issue#8: 周视图缩放 + 冲突栏压缩(v7.10.4: effScale = scale × laneScale)
    var scale: Double = 1.0
    var cornerRatio: Double = 1.0
    var laneScale: Double = 1.0
    /// 极窄 lane: 侧栏节次/时间标签(42+8)挤占正文 → 隐藏(← weekLaneHideSideLabel)
    var hideSideLabel: Bool = false
    /// issue#26: 周视图别名
    var useAlias: Bool = false
    let onClick: () -> Void

    var body: some View {
        let isDark = CourseColorUtil.isPaletteDark(palette)
        let effRows = groupRows.isEmpty ? [course] : groupRows
        let bg = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
            course, groupRows: effRows, isDark: isDark,
            neutralColor: colors.surfaceVariant,
            colorless: AppPrefs.shared.isCourseColorless())
        let fg = CourseColorUtil.textColorOn(bg: bg, isDark: isDark, onSurface: colors.onSurface)
        // 节假日灰显 ← effectiveBg/effectiveFg/textDecoration
        let effectiveBg = isGrey ? bg.opacity(SleepyTheme.Alpha.inactive) : bg
        let effectiveFg = isGrey ? fg.opacity(SleepyTheme.Alpha.inactive) : fg
        let strikethrough = isGrey && AppPrefs.shared.getHolidayStyle() == "strikethrough"
        let effScale = scale * laneScale
        let name = CourseDisplayUtil.displayName(course, useAlias)

        // time 模式: 时间段在连字符后折行; node 模式: 节次标签
        let timeParts: (String, String)? = displayMode == "time" && !timeJson.isEmpty
            ? TimeTableUtils.courseTimeParts(courseStartNode: course.startNode, courseStep: course.step,
                                             timeJson: timeJson, ownTime: course.ownTime,
                                             startTime: course.startTime, endTime: course.endTime)
            : nil
        let nodeLabel = course.nodeString(isShort: true)

        // meta: 教师 · 教室
        let meta: String = {
            var s = ""
            if !course.teacher.isEmpty { s += course.teacher }
            if !course.room.isEmpty {
                if !s.isEmpty { s += " · " }
                s += course.room
            }
            return s
        }()

        Button(action: onClick) {
            HStack(alignment: .top, spacing: 8 * scale) {
                if !hideSideLabel {
                    if let parts = timeParts {
                        Text("\(parts.0)-\n\(parts.1)")
                            .font(.system(size: 12 * effScale, weight: .semibold))
                            .foregroundColor(effectiveFg)
                            .strikethrough(strikethrough)
                            .frame(width: 42 * scale, alignment: .leading)
                    } else {
                        Text(nodeLabel)
                            .font(.system(size: 12 * effScale, weight: .semibold))
                            .foregroundColor(effectiveFg)
                            .strikethrough(strikethrough)
                            .frame(width: 42 * scale, alignment: .leading)
                            .lineLimit(1)
                    }
                }
                VStack(alignment: .leading, spacing: 2 * scale) {
                    Text(name)
                        .font(.system(size: 12 * effScale, weight: .semibold))
                        .foregroundColor(effectiveFg)
                        .strikethrough(strikethrough)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.system(size: 10 * effScale))
                            .foregroundColor(effectiveFg.opacity(SleepyTheme.Alpha.highContent))
                            .strikethrough(strikethrough)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(9 * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(effectiveBg)
            .cornerRadius(12 * scale * cornerRatio)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("lesson_\(course.id)")   // ← G5: 详情锚点
    }
}

// =====================================================================================
// 公共小组件
// =====================================================================================

// ← SectionHead
struct SectionHead: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    var action: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(SleepyTextStyle.sectionHead())
                .foregroundColor(colors.onSurface)
            Spacer()
            if let action = action {
                Text(action)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(colors.primary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
