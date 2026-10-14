// SleepyMaterialTransition.swift — ← ui/nav/SleepyMaterialTransition.kt
// issue#45: 官方 androidx.navigation3 的 Material Classic predictive-back 动效 → iOS 平台说明。
//
// ★ 平台差异(转场):
//   Android 端自产 ContentTransform(fade+scale 0.92) 供 NavDisplay 三槽位
//   (transitionSpec/popTransitionSpec/predictivePopTransitionSpec) 消费;
//   iOS 端 SleepyNavHost 用 NavigationStack 默认转场(系统 push/pop 滑动),
//   系统手势返回即 iOS 原生 predictive back — 不重实现。
//   此文件移植 Android 的**动画常量**(时长/曲线/缩放比), 供:
//     - SleepyNavHost 内 tab 切换 AnimatedContent 等价物(fade 200ms)复用
//     - 后续自定义转场对齐参数时一处改
//
// 物理原文 (InstallerX Revived ClassicNavTransition 的 Material 化翻译):
//  - 推进(forward): 入页 fadeIn + scaleIn(0.92, Center) 220ms FastOutSlowIn
//  - 退出(forward): 出页 fadeOut + scaleOut(0.92, Center) 220ms FastOutSlowIn
//  - 返回(pop): 入页 None + 出页 fadeOut + scaleOut(0.92, Center) spring
//  - 预测性手势: commit 200ms CubicBezier(0.2,0,0,1); cancel spring(NoBouncy, MediumLow)

import SwiftUI

// ← Android internal const 集中导出 (改时长改一处)
enum SleepyTransition {
    /// ← ForwardDuration = 220 (ms)
    static let forwardDuration: TimeInterval = 0.22
    /// ← ForwardFadeIn = 110 (ms) — 入页淡入比缩放快一倍结束
    static let forwardFadeIn: TimeInterval = 0.11
    /// ← PredictiveDuration = 200 (ms)
    static let predictiveDuration: TimeInterval = 0.20
    /// ← scaleIn/scaleOut 的 0.92 起止缩放比
    static let scaleOrigin: CGFloat = 0.92
    /// ← predictiveCommitTween 的 CubicBezierEasing(0.2f, 0f, 0f, 1f)
    ///   SwiftUI 等价 = .easeIn cubic 曲线簇中最接近的平滑加速-减速; 精确贝塞尔
    ///   需 UnitCurve(iOS 17+), 部署目标 15.6 → 用 timingCurve 近似(0.2, 0, 0, 1)
    static let predictiveCurve = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.20)
    /// ← predictiveCancelSpring: dampingRatio=NoBouncy(1.0), stiffness=MediumLow(400)
    ///   Spring.StiffnessMediumLow = 400f; SwiftUI 等价 response ≈ 2π/√400×2 …
    ///   换算: stiffness 400 + damping 1.0 → response≈0.5, dampingFraction=1.0
    static let predictiveCancelSpring = Animation.spring(response: 0.5, dampingFraction: 1.0)
    /// ← forwardTween: 220ms FastOutSlowIn (M3 标准缓动; SwiftUI 无命名等价,
    ///   CubicBezier(0.4,0,0.2,1) 近似 → .easeInOut 族)
    static let forwardEase = Animation.easeInOut(duration: 0.22)
}

// ← RightHalfContent AnimatedContent(tab 切换 200ms 渐隐渐显) 的 SwiftUI 等价
extension Animation {
    /// fadeIn/fadeOut(tween(200)) — 平板 Master-Detail 右半 tab 切换 / 等价处复用
    static let sleepyTabFade = Animation.easeInOut(duration: 0.20)
}
