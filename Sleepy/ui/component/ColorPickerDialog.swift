// ColorPickerDialog.swift — ← ui/component/ColorPickerDialog.kt 平台差异说明
//
// 平台差异: Android Compose Canvas 自制 SV/Hue 面板 + 预览 + 按钮行 → iOS 14+ 直接接
// UIColorPickerViewController 原生, 在 NativeColorPicker.swift 落地 (2026-09-11 移植时决策,
// 详见 NativeColorPicker.swift 顶部关于块)。本文件不产出 Swift View, 仅记录等价关系 + 保留
// HSV 纯函数给 NativeColorPicker 复用 (后续可迁移到独立 util)。
//
// Android 端 ColorPickerDialog.kt 翻译要素对照(便于审计/回查):
//   @Composable fun ColorPickerDialog(initialHex, onConfirm, onDismiss)
//   = iOS NativeColorPicker(initialHex, onSelect) + 标题(course_color) + 取消按钮
//   internal fun SVPanel / HueSlider
//   = iOS UIColorPickerViewController (色盘 + 吸管 + 历史色, UIKit 自带)
//   HSV ↔ RGB 换算
//   = iOS UIColor.init(hex:) / toHexString() 扩展, 已位于 NativeColorPicker.swift 内
//   String.format("#%08X") 8 位 hex 输出(含 alpha=FF)
//   = iOS String(format: "#%08X", (0xFF << 24) | (r << 16) | (g << 8) | b), 与 NativeColorPicker 现行实现一致
//
// 1:1 翻译不适用原因: iOS 14+ UIKit 自带取色面板比 Android 自制 SV/Hue 面板更精炼
// (吸管 + 历史色 + 透明度滑杆), 行为一致且代码量从 ~188 行 → ~50 行。SPEC 平台差异表
// "原生化控件"类。
//
// 接入方 (AddCourseScreen) 已切到 NativeColorPicker; 任何新调用方应直接使用 NativeColorPicker,
// 不应再回退到本文件名的旧接口。本文件保留为「移植差量文档」+ HSV 工具枚举。

import Foundation

/// HSV 换算工具枚举 — 留作 NativeColorPicker / 自定义主题编辑器复用的纯函数集。
/// Android 端 ColorPickerDialog.kt 内部 colorToHSV / HSVToColor 等价;
/// NativeColorPicker 当前直接走 UIColor.init(hex:) / toHexString(), 本枚举备用。
enum ColorPickerHSV {
    /// h ∈ [0, 360), s,v ∈ [0, 1] → #RRGGBB 大写 hex (与 Android #%08X 同形, alpha=FF 占位)
    static func hex(h: Double, s: Double, v: Double) -> String {
        let hh = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let c = v * s
        let x = c * (1 - abs((hh.truncatingRemainder(dividingBy: 2)) - 1))
        let m = v - c
        let (r1, g1, b1): (Double, Double, Double)
        switch Int(hh) {
        case 0: (r1, g1, b1) = (c, x, 0)
        case 1: (r1, g1, b1) = (x, c, 0)
        case 2: (r1, g1, b1) = (0, c, x)
        case 3: (r1, g1, b1) = (0, x, c)
        case 4: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        let r = Int((r1 + m) * 255)
        let g = Int((g1 + m) * 255)
        let b = Int((b1 + m) * 255)
        return String(format: "#%08X", (0xFF << 24) | (r << 16) | (g << 8) | b)
    }

    /// 解析 #RRGGBB / #AARRGGBB → (h, s, v) — 与 Android Color.colorToHSV 等价。
    static func hsv(from hex: String) -> (h: Double, s: Double, v: Double) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        let r, g, b: UInt64
        switch cleaned.count {
        case 6: (r, g, b) = ((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF)
        case 8: (r, g, b) = ((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF) // alpha 丢弃
        default: return (0, 0, 1)
        }
        let rf = Double(r) / 255
        let gf = Double(g) / 255
        let bf = Double(b) / 255
        let mx = max(rf, gf, bf)
        let mn = min(rf, gf, bf)
        let d = mx - mn
        var h: Double = 0
        if d > 0 {
            if mx == rf { h = (gf - bf) / d }
            else if mx == gf { h = 2 + (bf - rf) / d }
            else { h = 4 + (rf - gf) / d }
            h *= 60
            if h < 0 { h += 360 }
        }
        let s = mx == 0 ? 0 : d / mx
        return (h, s, mx)
    }
}
