import SwiftUI

// SleepyMaterialTransition — Android ui/nav/SleepyMaterialTransition.kt →
// iOS 参数表等价. Android 侧官方 predictive-back 由 NavDisplay 三槽位消费
// (transitionSpec/popTransitionSpec/predictivePopTransitionSpec);
// iOS 侧 overlay 转场由 PresentOverlay 的 .transition + .animation 承担,
// 本文件集中导出"改时长改一处"的常量表 + 消费指引.
//
// 物理 (Android 原文 1:1 翻译):
//   forward (push):  入页 fadeIn(110ms) + scaleIn(0.92→1, Center) 220ms FastOutSlowIn
//                    (新页从中心浮起, 不从边缘滑入)
//                    出页 fadeOut + scaleOut(1→0.92, Center) 220ms
//   pop:             入页 None (目标页原地不动); 出页 fadeOut + scaleOut(→0.92) 220ms
//   predictive commit: tween(200ms, CubicBezier(0.2,0,0,1)) scale 0.92 + fade
//   predictive cancel: spring(NoBouncy, StiffnessMediumLow) — 拉回弹
//
// FastOutSlowIn(0.4,0.0,0.2,1) 是 Material 标准曲线;
// predictive commit 的 (0.2,0,0,1) 即 SwiftUI .easeIn 同族曲线.

enum SleepyMaterialTransition {
    static let forwardDuration: Double = 0.220
    static let forwardFadeIn: Double = 0.110
    static let predictiveDuration: Double = 0.200
    static let scaleFrom: Double = 0.92

    /// forward 入页: 淡入 + 从 0.92 放大 (对应 Android fadeIn+scaleIn).
    static let forwardEnter: AnyTransition =
        .opacity
        .combined(with: .scale(scale: scaleFrom, anchor: .center))

    /// forward 出页 / pop 出页: 淡出 + 缩向 0.92 (Android fadeOut+scaleOut).
    static let forwardExit: AnyTransition =
        .opacity
        .combined(with: .scale(scale: scaleFrom, anchor: .center))

    /// forward 推入的驱动曲线 (Android FastOutSlowIn 220ms tween).
    static var forwardAnimation: Animation {
        .timingCurve(0.4, 0.0, 0.2, 1.0, duration: forwardDuration)
    }

    /// predictive commit (手势放行 = 程序化 pop 微弹, 200ms 缓入, Android 曲线 1:1).
    static var predictiveCommitAnimation: Animation {
        .timingCurve(0.2, 0.0, 0.0, 1.0, duration: predictiveDuration)
    }

    /// predictive cancel 拉回 (Android NoBouncy+StiffnessMediumLow spring).
    /// iOS 15.6 无直接档位 — 用临界阻尼短响应近似「无回弹拉回」.
    static var predictiveCancelAnimation: Animation {
        .spring(response: 0.4, dampingFraction: 1.0)
    }
}

// ── 消费点说明 (PresentOverlay, SleepyApp.swift) ──
// 现状: overlay 出现/消失统一 .transition(.move(edge: .trailing)) 跟手侧滑,
// 与 Android predictive-back 手势语义同构 (右滑跟手=手势进度, 释放=commit/cancel).
// 若需贴 Android 视觉 (新页"中心浮起"而非边缘滑入):
//   推入:  content.transition(SleepyMaterialTransition.forwardEnter)
//          + .animation(SleepyMaterialTransition.forwardAnimation, value: shownScreen)
//   退出:  .transition(SleepyMaterialTransition.forwardExit)
// predictive 手势跟手部分 = 原生 (PresentOverlay dragX 跟手, 无 15.6 API 缺口).
// predictive cancel 弹回若需独立曲线 →
//   .animation(SleepyMaterialTransition.predictiveCancelAnimation, value: dragX)
