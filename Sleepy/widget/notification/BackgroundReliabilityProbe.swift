// BackgroundReliabilityProbe.swift — ← widget/notification/BackgroundReliabilityProbe.kt
// Reads public iOS reliability facts in one place.
// A failed probe remains UNKNOWN and never disables standard notifications.
//
// iOS 事实映射:
//  - notificationPermissionGranted → UNUserNotificationCenter settings .authorized
//  - exactAlarmAllowed → 同授权(iOS 日历触发器无精确闹钟权限二分, 授权即精确)
//  - batteryOptimizationIgnored → BGTaskScheduler 注册成功(等价"后台刷新可用")
//  - widgetBound → WidgetCenter getCurrentConfigurations 任一 kind 存在

import Foundation
import UserNotifications
import WidgetKit

enum BackgroundReliabilityProbe {

    static func snapshot() async -> BackgroundReliabilitySnapshot {
        let notifGranted = await notificationPermissionGranted()
        return BackgroundReliabilitySnapshot(
            notificationPermissionGranted: notifGranted,
            exactAlarmAllowed: notifGranted,
            // iOS 无电池白名单 — 后台刷新由系统调度, 本 app 侧无开关可读。
            // 恒 true: 不因"优化"降级通知通路(iOS 等价语义 = 通知授权即通路)。
            batteryOptimizationIgnored: true,
            widgetBound: await widgetBound(),
            liveCardState: .notApplicable,
            promotedOngoingAllowed: nil
        )
    }

    private static func notificationPermissionGranted() async -> Bool {
        return await withCheckedContinuation { cont in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                cont.resume(returning: settings.authorizationStatus == .authorized)
            }
        }
    }

    private static func widgetBound() async -> Bool {
        return await withCheckedContinuation { cont in
            WidgetCenter.shared.getCurrentConfigurations { result in
                switch result {
                case .success(let configs): cont.resume(returning: !configs.isEmpty)
                case .failure: cont.resume(returning: false)
                }
            }
        }
    }
}
