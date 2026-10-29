// SettingsView.swift — 手表设置页 (2026-10 watch 伴侣 App)
// 只读镜像: 全部开关态来自 prefs 快照 (真源在 iPhone, 避免双向同步);
// 手动重新同步 = requestContents 补拉; 「手表已同步」= 镜像 ackSentAt 回执。
// 开关集对位 iOS ReminderScreen 主可见区 (master/每日/今日/明日/课前+分钟/
// 流体/上课免打扰), master 关时子项灰显 — 同 iOS「if masterEnabled」语义。
// 手表零写入: Toggle 一律静态圆点表达状态, footer 注明「请在 iPhone 管理」。

import SwiftUI
import WatchConnectivity

struct SettingsView: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.colorScheme) private var envScheme

    var body: some View {
        let scheme = WatchPalette.scheme(envDark: envScheme == .dark)
        let prefs = AppPrefs.shared
        let master = prefs.isReminderEnabled()
        List {
            // 提醒组 — 镜像 iOS ReminderScreen 主开关集 (只读)
            Section {
                ToggleRow(title: L10n.t("reminder_master_title"), on: master, scheme: scheme)
                // 子项 master 关时灰显 (← iOS if masterEnabled 才显示子卡)
                ToggleRow(title: L10n.t("reminder_daily_title"),
                          on: master && prefs.isDailyReminderEnabled(), dimmed: !master, scheme: scheme)
                ToggleRow(title: L10n.t("reminder_daily_today_toggle_title"),
                          on: master && prefs.isTodayReminderEnabled(), dimmed: !master, scheme: scheme)
                ToggleRow(title: L10n.t("reminder_tomorrow_toggle_title"),
                          on: master && prefs.isTomorrowReminderEnabled(), dimmed: !master, scheme: scheme)
                ToggleRow(title: L10n.t("reminder_before_class_title"),
                          on: master && prefs.isBeforeClassEnabled(), dimmed: !master, scheme: scheme)
                // 课前分钟数 — 仅课前开时显示 (← iOS if beforeClassEnabled)
                if master && prefs.isBeforeClassEnabled() {
                    HStack {
                        Text(L10n.t("reminder_before_minutes_label"))
                        Spacer()
                        Text("\(prefs.getBeforeClassMinutes())\(L10n.t("unit_minutes"))")
                            .foregroundColor(scheme.onSurfaceVariant)
                    }
                }
                ToggleRow(title: L10n.t("reminder_fluid_title"),
                          on: master && prefs.isBeforeClassFluidEnabled(), dimmed: !master, scheme: scheme)
                ToggleRow(title: L10n.t("reminder_class_dnd_title"),
                          on: master && prefs.isClassDndEnabled(), dimmed: !master, scheme: scheme)
            } header: {
                Text(L10n.t("watch_settings_reminders_header"))
            } footer: {
                Text(L10n.t("watch_open_on_phone"))
                    .font(.system(size: 10))
            }

            // 同步组 — 上次同步 / 手表已同步回执 / 立即同步
            Section {
                HStack {
                    Text(L10n.t("watch_last_sync"))
                    Spacer()
                    Text(store.lastSyncDate.map(Self.fmt) ?? L10n.t("watch_never_sync"))
                        .foregroundColor(scheme.onSurfaceVariant)
                }
                HStack {
                    Text(L10n.t("watch_synced_ack"))
                    Spacer()
                    Text(store.ackDate.map(Self.fmt) ?? L10n.t("watch_not_synced"))
                        .foregroundColor(store.ackDate == nil ? scheme.onSurfaceVariant : scheme.primary)
                }
                Button {
                    store.requestSync()
                } label: {
                    Text(L10n.t("watch_resync_now"))
                }
                .disabled(!isSessionReady())
            } header: {
                Text(L10n.t("watch_settings_sync_header"))
            }

            // 当前表
            Section {
                if let table = store.currentTable() {
                    HStack {
                        Text(L10n.t("manage_current_table"))
                        Spacer()
                        Text(table.name).foregroundColor(scheme.onSurfaceVariant).lineLimit(1)
                    }
                }
            }
        }
        .navigationTitle(Text(L10n.t("tab_mine")))
    }

    private func isSessionReady() -> Bool {
        WCSession.isSupported() && WCSession.default.isReachable
    }

    private static func fmt(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }
}

/// 只读开关行 — 静态圆点表达镜像值 (改在 iPhone)。dimmed=true 时整体降对比
/// (← iOS master 关时子卡不显示; 手表改为灰显保留信息密度)。
private struct ToggleRow: View {
    let title: String
    let on: Bool
    var dimmed: Bool = false
    let scheme: WidgetScheme
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Circle()
                .fill(on ? scheme.primary : scheme.surfaceVariant)
                .frame(width: 10, height: 10)
                .accessibilityLabel(on ? L10n.t("watch_mark_on") : L10n.t("watch_mark_off"))
        }
        .opacity(dimmed ? 0.4 : 1)
    }
}
