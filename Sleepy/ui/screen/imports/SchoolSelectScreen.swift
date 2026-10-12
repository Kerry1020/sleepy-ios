// SchoolSelectScreen.swift — ← ui/screen/imports/SchoolSelectScreen.kt (514 行)
// 学校选择页 — 教务直连第一步。
// schools.json 145 所 + 拼音搜索(PinyinMatcher) + URL 直连识别(detectProtocolFromUrl)
// + 首字母分组(sortKeyFull 拼音排序) + 右侧字母索引栏(点击/滑动跳转)。

import SwiftUI
import CoreLocation
import UIKit

// ← looksLikeUrl
func looksLikeUrl(_ s: String) -> Bool {
    let t = s.trimmingCharacters(in: .whitespaces)
    if t.hasPrefix("http://") || t.hasPrefix("https://") { return true }
    // 域名形态
    if t.range(of: #"^[a-zA-Z0-9][-a-zA-Z0-9]{0,62}\.[a-zA-Z]{2,}([/:].*)?$"#,
               options: .regularExpression) != nil { return true }
    // IP 形态
    if t.range(of: #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?(/.*)?$"#,
               options: .regularExpression) != nil { return true }
    return false
}

// ← normalizeUrl
func normalizeUrl(_ s: String) -> String {
    let t = s.trimmingCharacters(in: .whitespaces)
    return t.hasPrefix("http://") || t.hasPrefix("https://") ? t : "https://\(t)"
}

/// 学校首字母分组 ← SchoolSection
struct SchoolSection {
    let letter: String
    let schools: [JwSchoolInfo]
}

/// 完整拼音排序键(sortKeyFull 预生成; 缺失 fallback name) ← schoolSortKey
func schoolSortKey(_ s: JwSchoolInfo) -> String {
    let firstLetter = !s.sortKey.isEmpty && s.sortKey.first!.isLetter
        ? String(s.sortKey.first!).uppercased()
        : "★"
    return "\(firstLetter)|\(s.sortKeyFull.isEmpty ? s.name : s.sortKeyFull)"
}

/// 扁平列表 → 拼音排序 → 首字母分组 ← groupByLetter
func groupByLetter(_ schools: [JwSchoolInfo]) -> [SchoolSection] {
    if schools.isEmpty { return [] }
    let sorted = schools.sorted { schoolSortKey($0) < schoolSortKey($1) }
    var groups: [String: [JwSchoolInfo]] = [:]
    var order: [String] = []
    for s in sorted {
        let letter = !s.sortKey.isEmpty && s.sortKey.first!.isLetter
            ? String(s.sortKey.first!).uppercased()
            : "★"
        if groups[letter] == nil { order.append(letter) }
        groups[letter, default: []].append(s)
    }
    return order.map { SchoolSection(letter: $0, schools: groups[$0]!) }
}

struct SchoolSelectScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.scenePhase) private var scenePhase
    let onSchoolSelected: (JwSchoolInfo) -> Void
    let onDismiss: () -> Void

    @StateObject private var viewModel = JwImportViewModel()
    @State private var query = ""
    @State private var selectedLetter: String? = nil
    // ← resumeLocationAfterSettings: 仅当「设置」按钮打开过系统设置, 返回时才续定位
    @State private var resumeLocationAfterSettings = false
    @State private var expandedCity = ""   // ← rememberSaveable(city) expanded 键控

    private var filtered: [JwSchoolInfo] {
        let schools = viewModel.schools
        if query.trimmingCharacters(in: .whitespaces).isEmpty { return schools }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matched = schools.filter { PinyinMatcher.match($0.name, $0.sortKey, query, aliases: $0.aliases) }
        // 别名精确匹配优先
        return matched.sorted { a, b in
            let aExact = a.aliases.contains { $0.lowercased() == q }
            let bExact = b.aliases.contains { $0.lowercased() == q }
            if aExact != bExact { return aExact }
            return false
        }
    }

    private var isUrl: Bool { looksLikeUrl(query) }
    private var urlProtocol: String? { isUrl ? JwImportViewModel.detectProtocolFromUrl(query) : nil }

    private var sections: [SchoolSection] { groupByLetter(filtered) }
    private var showIndexBar: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty && sections.count > 1 }
    private var showRecommendations: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var recommendedSchools: [JwSchoolInfo] {
        guard case .ready(let city) = viewModel.schoolLocation else { return [] }
        return SchoolCityIndex.schoolsInCity(viewModel.schools, city: city)
    }
    private var hasLocationPermission: Bool {
        CLLocationManager.authorizationStatus() == .authorizedWhenInUse
            || CLLocationManager.authorizationStatus() == .authorizedAlways
    }
    private var openPermissionSettings: () -> Void {
        {
            // ← Android openPermissionSettings 不碰 resume 标志(仅 locationDisabled 分支设)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }
    private var retryLocation: () -> Void {
        {
            // ← Android retryLocation: LocationDisabled → 开系统设置 + resume 标志;
            //   其余 → requestLocation(): 有权限直接定位, 无权限走授权结果回调定位。
            if CLLocationManager.locationServicesEnabled() {
                if hasLocationPermission {
                    viewModel.locateSchoolCity()
                } else {
                    // ← launcher.launch 等价: 授权回调(granted)里直接 locateSchoolCity,
                    //   不设 resume 标志 — 授权框不离开本 app, 无需「返回续定位」
                    viewModel.locator.requestPermission { granted in
                        if granted { viewModel.locateSchoolCity() }
                    }
                }
            } else {
                resumeLocationAfterSettings = true
                // iOS 无公开 API 打开「定位服务」总开关页; app 设置页是最近可达点
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("select_school"), onBack: onDismiss)

            // 搜索框
            TextField(L10n.format("search_school_url"), text: $query)
                .accessibilityIdentifier("school_search")
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(colors.surfaceContainerHighest)   // ← fieldColors 容器色 surfaceContainerHighest
                .cornerRadius(SleepyTheme.fieldShape)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            Text(L10n.format("school_pinyin_hint"))
                .font(.system(size: 12))   // ← M3 supportingText bodySmall 12sp
                .foregroundColor(colors.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                // ← M3 supporting 文案缩进 = 字段内 16 + 屏幕边 16 = 32
                .padding(.leading, 32)
                .padding(.trailing, 16)
                .padding(.bottom, 2)

            // 计数行
            HStack {
                Text(L10n.format("school_count_total", viewModel.schools.count))
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
                Spacer()
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("匹配 \(filtered.count)")
                        .font(.system(size: 12))
                        .foregroundColor(colors.primary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)

            if isUrl {
                UrlDirectRow(url: query.trimmingCharacters(in: .whitespaces),
                             protocolType: urlProtocol) {
                    let school = JwSchoolInfo(
                        sortKey: "",
                        name: "自定义教务",
                        url: normalizeUrl(query.trimmingCharacters(in: .whitespaces)),
                        type: urlProtocol,
                        status: JwSchoolInfo.STATUS_SUPPORTED)
                    onSchoolSelected(school)
                }
            }

            if filtered.isEmpty && !isUrl {
                Text(viewModel.schools.isEmpty ? L10n.format("loading") : L10n.format("no_school_found"))
                    .font(.system(size: 16))   // ← Android 无 style 参数 = bodyLarge 16
                    .foregroundColor(colors.onSurfaceVariant)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !(isUrl && filtered.isEmpty) {
                HStack(alignment: .top, spacing: 0) {
                    // 学校列表
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                if showRecommendations {
                                    PossibleSchoolsCard(
                                        state: viewModel.schoolLocation,
                                        schools: recommendedSchools,
                                        isLoadingSchools: viewModel.schools.isEmpty,
                                        onLocate: retryLocation,
                                        onPermissionSettings: openPermissionSettings,
                                        onSchoolSelected: onSchoolSelected,
                                        expanded: $expandedCity
                                    )
                                    .padding(.vertical, 8)
                                }
                                ForEach(sections, id: \.letter) { section in
                                    SchoolSectionHeader(letter: section.letter)
                                        .id("header_\(section.letter)")
                                    ForEach(section.schools, id: \.name) { school in
                                        SchoolRow(school: school) {
                                            onSchoolSelected(school)
                                        }
                                        DividerRow()
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                        .onChange(of: selectedLetter) { letter in
                            if let letter = letter {
                                withAnimation {
                                    proxy.scrollTo("header_\(letter)", anchor: .top)
                                }
                            }
                        }
                    }

                    // 字母索引栏(点击+滑动)
                    if showIndexBar {
                        AlphabetIndexBar(letters: sections.map { $0.letter },
                                         activeLetter: selectedLetter,
                                         onLetterTap: { selectedLetter = $0 })
                            .frame(width: 32)
                    }
                }
            }
        }
        .background(colors.background)
        // ← Android DisposableEffect: ON_STOP 取消; ON_RESUME 且来自设置页 → 续定位
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                viewModel.cancelSchoolLocation()
            } else if resumeLocationAfterSettings {
                resumeLocationAfterSettings = false
                viewModel.locateSchoolCity()
            }
        }
        .onDisappear {
            viewModel.cancelSchoolLocation()
            // 清掉未完成的授权回调(引用 viewModel, 滞留会挡 VM 释放)
            viewModel.locator.requestPermission(completion: nil)
        }
    }
}

// ← PossibleSchoolsCard(Android 434-530): 同城推荐单卡 — 标题/8 态副标题/定位按钮/
// Ready 空表→loading|no_matches/有表→city_hint+行(expanded?全部:take 5)+分隔线/
// 底部 FlowRow: Ready&&>5 展开/收起 + 恒显权限设置。行走 SchoolRow 原点击路径。
private struct PossibleSchoolsCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let state: SchoolLocationState
    let schools: [JwSchoolInfo]
    let isLoadingSchools: Bool
    let onLocate: () -> Void
    let onPermissionSettings: () -> Void
    let onSchoolSelected: (JwSchoolInfo) -> Void
    @Binding var expanded: String

    // expanded 键控城市(rememberSaveable(city) 语义): 城市变了就回到收起态
    private var isExpanded: Bool { expanded == cityKey }
    private var cityKey: String {
        if case .ready(let city) = state { return city }
        return ""
    }

    private var subtitle: String {
        switch state {
        case .ready(let city):
            let count = schools.count
            return L10n.plural("school_location_city", count, city, count)
        case .locating: return L10n.t("school_location_loading")
        case .permissionDenied: return L10n.t("school_location_denied")
        case .accuracyInsufficient: return L10n.t("school_location_accuracy_insufficient")
        case .locationDisabled: return L10n.t("school_location_disabled")
        case .positionUnavailable: return L10n.t("school_location_no_fix")
        case .unavailable: return L10n.t("school_location_unavailable")
        case .idle: return L10n.t("school_location_hint")
        }
    }

    private var actionLabel: String {
        switch state {
        case .idle: return L10n.t("school_location_locate")
        case .permissionDenied: return L10n.t("school_location_enable")
        case .locationDisabled: return L10n.t("school_location_settings")
        default: return L10n.t("school_location_retry")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("possible_schools"))
                        .font(.system(size: 16, weight: .medium))   // ← titleMedium 16sp
                        .foregroundColor(colors.primary)
                    Text(subtitle)
                        .font(.system(size: 12))                    // ← bodySmall 12sp
                        .foregroundColor(colors.onSurfaceVariant)
                }
                Spacer()
                if state == .locating {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)                           // ← 20dp 圈
                        .padding(8)
                } else {
                    Button(action: onLocate) {
                        Text(actionLabel)
                    }
                    .buttonStyle(SleepyButtonStyle())
                }
            }

            if case .ready = state {
                if schools.isEmpty {
                    Text(isLoadingSchools ? L10n.t("loading") : L10n.t("school_location_no_matches"))
                        .font(.system(size: 12))
                        .padding(.top, 8)
                } else {
                    Text(L10n.t("school_location_city_hint"))
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                        .padding(.top, 8)
                    let visible = isExpanded ? schools : Array(schools.prefix(5))
                    ForEach(visible, id: \.name) { school in
                        // ← Android 卡内行走共享 SchoolRow(含 badge/URL 行), 非独立 inline
                        SchoolRow(school: school) {
                            onSchoolSelected(school)
                        }
                        DividerRow()
                    }
                }
            }

            let showFlowRow: Bool = {
                switch state {
                case .permissionDenied, .accuracyInsufficient: return true
                case .ready: return true
                default: return false
                }
            }()
            if showFlowRow {
                HStack(spacing: 8) {
                    if case .ready = state, schools.count > 5 {
                        Button(action: { expanded = isExpanded ? "" : cityKey }) {
                            Text(isExpanded ? L10n.t("school_location_collapse")
                                            : L10n.t("school_location_show_all"))
                        }
                        .buttonStyle(SleepyButtonStyle())
                    }
                    Button(action: onPermissionSettings) {
                        Text(L10n.t("school_location_permission_settings"))
                    }
                    .buttonStyle(SleepyButtonStyle())
                }
            }
        }
        .padding(12)
        .background(colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: SleepyShapes.medium)
                .stroke(colors.outline.opacity(SleepyTheme.Alpha.hairline), lineWidth: 1)
        )
        .cornerRadius(SleepyShapes.medium)   // ← OutlinedCard
    }
}

// ← SectionHeader(首字母)
private struct SchoolSectionHeader: View {
    @Environment(\.localWakeUpColors) private var colors
    let letter: String

    var body: some View {
        Text(letter)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(colors.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(colors.primaryContainer.opacity(SleepyTheme.Alpha.hairline))
            .cornerRadius(SleepyShapes.extraSmall)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
    }
}

// ← AlphabetIndexBar
private struct AlphabetIndexBar: View {
    @Environment(\.localWakeUpColors) private var colors
    let letters: [String]
    let activeLetter: String?
    let onLetterTap: (String) -> Void

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ForEach(letters, id: \.self) { letter in
                    let isActive = letter == activeLetter
                    Text(letter)
                        .font(.system(size: 11, weight: isActive ? .bold : .regular))
                        .foregroundColor(isActive ? colors.primary : colors.onSurfaceVariant)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(isActive
                            ? colors.primaryContainer.opacity(SleepyTheme.Alpha.inactive)
                            : Color.clear)
                        .cornerRadius(SleepyShapes.extraSmall)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        // 触摸 Y → index 精准对应(每字母 1/N)
                        let ratio = min(max(g.location.y / geo.size.height, 0), 0.999)
                        let idx = Int(ratio * Double(letters.count))
                        if letters.indices.contains(idx) {
                            onLetterTap(letters[idx])
                        }
                    }
            )
        }
        .padding(.trailing, 4)
    }
}

// ← SchoolRow
private struct SchoolRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let school: JwSchoolInfo
    let onClick: () -> Void

    private var isClickable: Bool {
        school.isSupported && !school.url.isEmpty
    }

    var body: some View {
        Group {
            if isClickable {
                Button(action: onClick) {
                    rowContent
                }
                .buttonStyle(SleepyButtonStyle())
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "graduationcap")   // ← Android Icons.Outlined.School
                .font(.system(size: 20))
                .foregroundColor(colors.onPrimaryContainer)
                .frame(width: 36, height: 36)
                .background(colors.primaryContainer)
                .cornerRadius(SleepyShapes.small)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    schoolStatusBadge
                    Text(school.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isClickable ? colors.onSurface : colors.onSurfaceVariant)
                }
                if !school.url.isEmpty {
                    Text(JwProtocol.displayName(school.type) + " · " +
                         school.url.replacingOccurrences(of: "https://", with: "")
                             .replacingOccurrences(of: "http://", with: "")
                             .trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var schoolStatusBadge: some View {
        switch school.status {
        case JwSchoolInfo.STATUS_PENDING:
            badge(label: L10n.t("jw_pending_pending"),
                  background: colors.tertiaryContainer,
                  foreground: colors.onTertiaryContainer)
        case JwSchoolInfo.STATUS_GRAD_PENDING:
            badge(label: L10n.t("jw_pending_pending") + " · " + L10n.t("jw_pending_grad"),
                  background: colors.tertiaryContainer,
                  foreground: colors.onTertiaryContainer)
        case JwSchoolInfo.STATUS_GRAD_SUPPORTED:
            badge(label: L10n.t("jw_pending_grad"),
                  background: colors.secondaryContainer,
                  foreground: colors.onSecondaryContainer)
        case JwSchoolInfo.STATUS_LEGACY:
            badge(label: L10n.t("jw_pending_legacy"),
                  background: colors.surfaceVariant,
                  foreground: colors.onSurfaceVariant)
        default:
            EmptyView()
        }
    }

    private func badge(label: String, background: Color, foreground: Color) -> some View {
        Text(label)
            .font(.system(size: 11))
            .foregroundColor(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background)
            .cornerRadius(SleepyShapes.small)
    }
}

// ← UrlDirectRow
private struct UrlDirectRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let url: String
    let protocolType: String?
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: 20))
                    .foregroundColor(colors.onPrimary)
                    .frame(width: 36, height: 36)
                    .background(colors.primary)
                    .cornerRadius(SleepyShapes.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.format("url_direct_login"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colors.primary)
                        .accessibilityIdentifier("url_direct_row")
                    Text(url)
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                        .lineLimit(1)
                    if let proto = protocolType {
                        Text("\(L10n.format("url_detected")) \(JwProtocol.displayName(proto))")
                            .font(.system(size: 11))   // ← labelSmall 11sp 常规
                            .foregroundColor(colors.primary)
                    } else {
                        Text(L10n.format("url_auto_detect"))
                            .font(.system(size: 11))   // ← labelSmall 11sp 常规
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 4)
        }
        .buttonStyle(SleepyButtonStyle())
    }
}

private struct DividerRow: View {
    @Environment(\.localWakeUpColors) private var colors
    var body: some View {
        Rectangle()
            .fill(colors.outlineVariant.opacity(SleepyTheme.Alpha.hairline))
            .frame(height: 1)
    }
}
