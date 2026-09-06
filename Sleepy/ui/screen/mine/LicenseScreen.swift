// LicenseScreen.swift — ← ui/screen/mine/LicenseScreen.kt
// 开源许可与致谢二级页 (v1.0.46 用户令: 从 AboutScreen 长卡分离)。
// AboutScreen 只留一行入口 (title + detail 副题), 本页承载全部内容:
//   许可证区块 (GPL 声明) + 逐条致谢卡 (项目名 / 作者+license 元信息 / 适配用途)。
// 布局: SettingsTopBar 返回 + ScrollView LazyVStack + InfoCard 分组。

import SwiftUI

// ← AttributionEntry (项目名 / (作者,license) 元信息 / 适配用途)
private struct AttributionEntry: Identifiable {
    let id = UUID()
    let project: String
    let meta: String       // "作者, license" 或仅 license, 空串=无
    let usage: String
}

private let attributionEntries: [AttributionEntry] = [
    AttributionEntry(
        project: "WakeUp 课程表 (YZune)",
        meta: "Apache-2.0",
        usage: "JwCourse / JwParser 中间结构语义与强智系 HTML 解析的参考实现"
    ),
    AttributionEntry(
        project: "WakeupSchedule_BUPT (dIT8Zv)",
        meta: "Apache-2.0",
        usage: "十二个教务解析器的上游: 强智全家族 (qz / qz_with_node / qz_br / qz_crazy / qz_old)、老版正方、URP、青果、新正方、HNUST 与 Parser 设计"
    ),
    AttributionEntry(
        project: "WakeupSchedule_Kotlin (YZune)",
        meta: "Apache-2.0",
        usage: "经典金智 EAMS 导入实现 (TaskActivity 位图解析) 的参考"
    ),
    AttributionEntry(
        project: "时光课程表 cqu.js",
        meta: "",
        usage: "重庆大学门户 REST 协议 (session / 课表 / 作息三接口) 的分析依据"
    ),
    AttributionEntry(
        project: "HFUT-Schedule (Chiu-xaH)",
        meta: "MIT",
        usage: "合工大 EAMS5 全协议: course-table → schedule-table/datum 三段 fetch"
    ),
    AttributionEntry(
        project: "SEUTimetable (sakimidare)",
        meta: "Apache-2.0",
        usage: "东南大学 URP JSON 字段映射与 ZCMC 周次串解析语义"
    ),
    AttributionEntry(
        project: "zju-ical-py (Xecades)",
        meta: "LGPL-2.1",
        usage: "浙江大学本研课表 (UGR) kbList JSON 形态佐证"
    ),
    AttributionEntry(
        project: "USTC-timetable-to-ics (1970633640)",
        meta: "",
        usage: "中科大 studentTableVm activities 字段映射与周次串解析"
    ),
    AttributionEntry(
        project: "ScuTimetable (Z-P-J)",
        meta: "",
        usage: "四川大学 dateList / selectCourseList 协议形态与 day 映射"
    ),
    AttributionEntry(
        project: "neu_wisedu2wakeup (CreamPig233)",
        meta: "",
        usage: "东北大学 arrangedList 字段映射、教师提取与周次串括号处理参考"
    ),
    AttributionEntry(
        project: "shiguang_warehouse (XingHeYuZhuan)",
        meta: "MIT",
        usage: "武汉理工大学 kcbcxby 协议、经典金智 EAMS (hunnu/uestc/hpu) 与新正方网格视图 (zhengfang_01) 的协议形态参考"
    ),
    AttributionEntry(
        project: "iwut (TokenTeam)",
        meta: "AGPL-3.0 (仅参考协议形态)",
        usage: "武汉理工大学节次 DM 映射的协议佐证 (未引用代码)"
    ),
    AttributionEntry(
        project: "zfn_api (openschoolcn)",
        meta: "MPL-2.0",
        usage: "新正方 jwglxt kbList 接口形态交叉验证"
    ),
    AttributionEntry(
        project: "FlowCourse (jiaweiyaya)",
        meta: "GPL-3.0",
        usage: "新正方 kbList 主流形态与 jc 多形态交叉验证"
    ),
]

struct LicenseScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("license_page_title"), onBack: onDismiss)
            ScrollView {
                LazyVStack(spacing: 12) {
                    // ---- 许可证区块 ----
                    InfoCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.format("license_gpl_section"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colors.onSurface)
                            Text(L10n.format("license_gpl_body"))
                                .font(.system(size: 14))
                                .foregroundColor(colors.onSurfaceVariant)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // ---- 致谢总述区块 ----
                    InfoCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.format("license_attribution_section"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colors.onSurface)
                            Text(L10n.format("license_attribution_note"))
                                .font(.system(size: 14))
                                .foregroundColor(colors.onSurfaceVariant)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // ---- 逐条致谢卡 ----
                    ForEach(attributionEntries) { entry in
                        InfoCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.project)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(colors.onSurface)
                                if !entry.meta.isEmpty {
                                    Text(entry.meta)
                                        .font(.system(size: 12))
                                        .foregroundColor(colors.primary)
                                }
                                Text(entry.usage)
                                    .font(.system(size: 13))
                                    .foregroundColor(colors.onSurfaceVariant)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Spacer().frame(height: 32)
                }
                .padding(.horizontal, 20)
            }
        }
        .background(colors.background)
    }
}
