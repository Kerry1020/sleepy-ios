// HighRefreshRate.swift — ← util/HighRefreshRate.kt
// 高刷新率(流畅优先) — 用户 2026-09-04 指令: 能上高刷就上高刷。
// 位置: app/ 而非 util/ — UIApplication.shared 在 widget extension 不可用,
// 此文件仅主 app 编译,SleepyWidget target 通过 Sleepy/util/ excludes: ["app"] 排除。
//
// 平台映射:
//   Android: window.attributes.preferredDisplayModeId 钉最高档(同分辨率 supportedModes 取 max refreshRate)
//   iOS 15+: UIScreen.maximumFramesPerSecond 只读,无法钉特定刷率。
//            iOS 公开 API 没有 window/layer 级 preferredFramesPerSecond setter;
//            CADisplayLink.preferredFrameRateRange 是 per-link 的;Apple ProMotion
//            调度在系统层尊重屏幕能力,只要不人为把动画 stagger 到 30fps,系统即自动用 120Hz。
//
// 与 Android 语义对齐:
//   - 选定最高档即把目标刷率(用于诊断/未来 CADisplayLink 链路)记下来;
//   - 非 ProMotion 设备(60Hz 屏)maximumFramesPerSecond == 60,开关 off 与 on 视觉等价(此时仍允许
//     系统调度,等价 Android 无高刷档不动)。

import UIKit

@available(iOS 15.0, *)
enum HighRefreshRate {

    /// 按开关状态应用 — iOS 没有公开的窗口级刷率 setter,记录生效目标刷率,
    /// 供 AnimationLayer / CADisplayLink 链路后续使用。
    /// 返回实际生效的目标刷率(0 = 系统默认/不可用)。
    @MainActor
    @discardableResult
    static func apply(enabled: Bool) -> Int {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else { return 0 }

        let target = enabled ? Int(window.screen.maximumFramesPerSecond) : 0
        // 诊断日志(开发期确认设备实际能力;非 ProMotion = 60)
        NSLog("[Sleepy] highRefresh=%@ target=%d fps (screen.max=%d)",
              enabled ? "on" : "off",
              target,
              Int(window.screen.maximumFramesPerSecond))
        return target
    }
}
