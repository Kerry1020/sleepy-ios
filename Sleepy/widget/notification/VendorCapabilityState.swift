// VendorCapabilityState.swift — ← Android VendorCapabilityState enum
// iOS 端能力枚举与 Android 不完全同构:
// - Android NOTIFICATION_PERMISSION_REQUIRED → iOS notApplicable (iOS 无厂商 ROM 通知通道概念)
// - iOS 端仅保留语义可移植的子集。

/// 厂商增强通知surface的能力状态 (← Android VendorCapabilityState)
enum VendorCapabilityState {
    case enabled
    case disabled
    case notApplicable   // ← Android NOTIFICATION_PERMISSION_REQUIRED
    case settingsRequired // ← Android SETTINGS_REQUIRED
    case notSupported    // ← Android NOT_SUPPORTED
    case unknown
}
