// ReminderCapabilityFlow.swift — ← ui/screen/mine/ReminderCapabilityFlow.kt
// 纯决定函数: 通知设置 UI 与 JVM 测试共享同一份判定逻辑。
// iOS 端能力枚举与 Android 不完全同构(VendorLiveNotificationCapability 对应
// VendorCapabilityState.notApplicable), 仅保留语义可移植的子集。

import Foundation

/// 能力检查顺序: 通知权限是否已批决定先看"权限"还是先看"厂商"。
/// Android 侧映射为 `notification` / `vendor` 两阶段。
func capabilityInspectionOrder(notificationPermissionGranted: Bool) -> [String] {
    notificationPermissionGranted ? ["notification", "vendor"] : ["notification"]
}

/// 三种跳转意图的兜底: 排除已不可用的(API 31+ 厂商 intent / 系统渠道设置 / app 设置)，
/// 返回最后一个仍可解析的 action。Android 上对应 SettingsIntent 候选集。
func lastResolvableActionFor(unavailableActions: Set<String>) -> String? {
    let candidates = [
        "com.vendor.notification.SETTINGS",
        "android.settings.CHANNEL_NOTIFICATION_SETTINGS",
        "android.settings.APP_NOTIFICATION_SETTINGS"
    ]
    return candidates.last { !unavailableActions.contains($0) }
}

/// 标准通知是否可用 — Android 端把 NOTIFICATION_PERMISSION_REQUIRED 单列为阻断态。
/// iOS 端 VendorCapabilityState 没有这个 case, 但语义对应关系成立, 函数保留。
func standardNotificationAllowed(_ state: VendorCapabilityState) -> Bool {
    state != .notApplicable  // ← iOS 端:notApplicable 等价 Android 的 NOTIFICATION_PERMISSION_REQUIRED
}
