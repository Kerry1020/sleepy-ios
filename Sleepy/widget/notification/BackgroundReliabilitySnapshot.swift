// BackgroundReliabilitySnapshot.swift — ← widget/notification/BackgroundReliabilitySnapshot.kt
// Facts observed from the current device and app state.
// This model deliberately does not claim that a vendor surface is guaranteed.

import Foundation

/// 设备/app 当前状态观测事实。
/// iOS 适配:
///  - exactAlarmAllowed → 通知授权即"精确"(UNCalendarNotificationTrigger 分钟级, 无 SCHEDULE_EXACT_ALARM 概念)
///  - batteryOptimizationIgnored → BGAppRefreshTaskRunner 可用性(近似)
///  - liveCardState → iOS 无厂商 live card, 恒 .notApplicable
///  - promotedOngoingAllowed → iOS 无 promoted ongoing(Android 16 概念), 恒 nil
struct BackgroundReliabilitySnapshot {
    let notificationPermissionGranted: Bool
    /// iOS: 通知授权即允许日历触发器(等价 Android exact alarm)。
    let exactAlarmAllowed: Bool
    /// iOS: BGAppRefresh 可用性近似(实际由系统调度, 无白名单概念)。
    let batteryOptimizationIgnored: Bool
    /// 任一 widget kind 仍在桌面(WidgetCenter 当前配置非空)。
    let widgetBound: Bool
    /// iOS 恒 notApplicable — 无厂商 live card 生态。
    let liveCardState: VendorCapabilityState
    /// iOS 恒 nil — 无 promoted ongoing 概念。
    let promotedOngoingAllowed: Bool?

    func reminderTransportState() -> ReminderTransportState {
        if !notificationPermissionGranted { return .blockedNotificationPermission }
        if !exactAlarmAllowed { return .degradedInexactAlarm }
        return .ready
    }

    func standardNotificationAllowed() -> Bool {
        return notificationPermissionGranted
    }

    func backgroundPermissionFactsSatisfied() -> Bool {
        return notificationPermissionGranted && exactAlarmAllowed && batteryOptimizationIgnored
    }

    func vendorSurfaceGuaranteed() -> Bool {
        return liveCardState == .enabled
    }
}

enum ReminderTransportState {
    case ready
    case degradedInexactAlarm
    case blockedNotificationPermission
}

/// 厂商 live card 能力 — iOS 端只有 notApplicable 一个实例。
enum VendorCapabilityState {
    case enabled
    case disabled
    case unknown
    case notApplicable
}
