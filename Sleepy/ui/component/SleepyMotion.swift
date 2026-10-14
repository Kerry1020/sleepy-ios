// SleepyMotion.swift — ← ui/component/SleepyMotion.kt 逐行翻译 (GPL-3.0)
// 动效常量: 全 app 跟手类 spring 的单一事实来源。

import SwiftUI

/**
 * [intentional custom] 官方 MotionScheme.expressive() 已是全局默认(MD3E), 但其空间类
 * spring 带回弹(MediumBouncy) — thumb 类「跟手不弹」交互是用户实测定参
 * (高硬度+无回弹, MediumLow 拖沓不跟手), 官方 motionScheme 无对应档位。
 * 使用处: SegmentedSwitcher thumb / PillNavigationBar 贴底+Dock thumb(均为薄层组件)。
 * 注释里的「同款」即指此常量; 改参数三处同步生效。
 *
 * 参数换算 (Compose spring → SwiftUI Animation.spring):
 *   Compose: spring(dampingRatio = DampingRatioNoBouncy /*1.0*/,
 *                   stiffness = StiffnessHigh /*10_000f*/)
 *   无回弹 dampingRatio 1.0 → SwiftUI dampingFraction 1.0 (语义 1:1);
 *   stiffness 10_000 (settling ~0.1s 量级, 近乎即时跟手) → response 0.18
 *   (SegmentedSwitcher/PillNavigationBar 既有实机验证档位, 视觉等价)。
 */
let sleepyThumbSpring: Animation = .spring(response: 0.18, dampingFraction: 1.0)
