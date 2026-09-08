// JwProtocol.swift — ← JwProtocol.kt
// 教务系统协议类型枚举。
//
// 基于 dIT8Zv/WakeupSchedule_BUPT (Apache-2.0) 的 Common.kt 协议类型常量
// 简化而来,保留 sleepy v1.0.8 实际用到的子集:
//   - QZ 强智 5 变体(HEU 用 QZ_CRAZY)
//   - ZF 正方 3 变体
//   - URP 2 变体
//   - PKU 北大 / CF 青果 / BNUZ 北师珠
//   - HELP / LOGIN / MAINTAIN 标记
//
// 完整 17 类 + 强智变体的语义见 https://github.com/dIT8Zv/WakeupSchedule_BUPT
// 中 `app/src/main/java/com/suda/yzune/wakeupschedule/schedule_import/Common.kt`。

enum JwProtocol {
    static let TYPE_HELP = "help"
    static let TYPE_ZF = "zf"
    static let TYPE_ZF_1 = "zf_1"
    static let TYPE_ZF_NEW = "zf_new"
    static let TYPE_URP = "urp"
    static let TYPE_URP_NEW = "urp_new"
    static let TYPE_QZ = "qz"
    static let TYPE_QZ_OLD = "qz_old"
    static let TYPE_QZ_CRAZY = "qz_crazy"
    static let TYPE_QZ_BR = "qz_br"
    static let TYPE_QZ_WITH_NODE = "qz_with_node"
    static let TYPE_CF = "cf"
    static let TYPE_PKU = "pku"
    static let TYPE_BNUZ = "bnuz"
    static let TYPE_LOGIN = "login"
    static let TYPE_MAINTAIN = "maintain"

    /// 金智 Wisedu jwapp 微应用平台(JSON API 直连,非 HTML 解析)。如:哈尔滨工程大学 jwgl.hrbeu.edu.cn
    static let TYPE_WISEDU = "wisedu"

    /// 重庆大学自建统一门户 my.cqu.edu.cn(REST API + Bearer token,非 HTML 解析)。
    /// WebView 登录统一身份认证后从 localStorage 取 cqu_edu_ACCESS_TOKEN,fetch 四个接口。
    /// 外部佐证:时光课程表 cqu.js 适配器(茵符草)、321CQU/pymycqu。
    static let TYPE_CQU = "cqu"

    /// 合肥工业大学教务(金智 EAMS5, eams5-student 系列, jxglstu.hfut.edu.cn)。
    /// 上游协议形态: Chiu-xaH/HFUT-Schedule (MIT) 全链路参考。
    static let TYPE_EAMS5 = "eams5"

    /// 东南大学教务(正方 URP 系, newxk.urp.seu.edu.cn, 用户粘 JSON)。
    /// 字段集 {KCM,SKJS,JASMC,SKXQ,KSJC,JSJC,ZCMC,KCH,JXBQH}。
    /// 上游协议形态: sakimidare/SEUTimetable (Apache-2.0) parseWeekRange 算法参考。
    static let TYPE_SEU = "seu"

    /// 浙江大学教务(正方新版 zf_new, zdbk.zju.edu.cn)。
    /// 字段集 {xkkh, xqj, dsz, djj, skcd, kcb, xxq} — kcb 含 \n 分隔的课名/周次串/老师/教室。
    /// 上游协议形态: Xecades/zju-ical-py (LGPL-2.1) 字段映射参考, kcb 解析代码自写。
    static let TYPE_ZJU = "zju"

    /// 中国科学技术大学教务(自研新版, jw.ustc.edu.cn)。
    /// JSON 路径: x.studentTableVm.activities[]。
    /// 上游协议形态: 1970633640/USTC-timetable-to-ics (无 license) — 算法参考。
    static let TYPE_USTC = "ustc"

    /// 四川大学教务(scu.edu.cn 自建门户, 强智框架但走 mobile JSON 接口)。
    /// JSON 路径: x.dateList[0].selectCourseList[].timeAndPlaceList[]。
    /// 单/双信息 upstream 协议丢失 → 本 parser 强制 type=0 (上游限制)。
    /// 上游协议形态: Z-P-J/ScuTimetable (无 license) TimetableHelper.java — 算法自写。
    static let TYPE_SCU = "scu"

    /// 东北大学教务(jwxt.neu.edu.cn 强智新版 mobile JSON)。
    /// JSON 路径: x.datas.arrangedList[]。单/双周 upstream 协议层丢失, 强制 type=0。
    /// 上游协议形态: CreamPig233/neu_wisedu2wakeup (无 license) extract_schedule.js — 算法自写。
    static let TYPE_NEU = "neu"

    /// 强智 iEAS 网络版 (/ieas2.1/...) — ASP.NET MVC, 课表 endpoint = /ieas2.1/kbcx/queryGrkb 返回 HTML(非 JSON)。
    /// 学校样本: 北京航空航天大学 jwxt.buaa.edu.cn:7001/ieas2.1。
    /// 与 TYPE_QZ (/jsxsd/ 强智 jxb) 同源, 但 URL 路径不同, 需独立锚点。
    static let TYPE_QZ_IEAS = "qz_ieas"

    /// 中国科学院大学选课系统: personSchedule 服务端 HTML 课表网格 + JSON courseTimeList。
    static let TYPE_UCAS = "ucas"

    /// 协议显示名(用于 UI 提示) ← displayName
    static func displayName(_ type: String?) -> String {
        switch type {
        case TYPE_QZ, TYPE_QZ_OLD, TYPE_QZ_CRAZY, TYPE_QZ_BR, TYPE_QZ_WITH_NODE:
            return "强智教务"
        case TYPE_QZ_IEAS:
            return "强智教务(iEAS 网络版)"
        case TYPE_UCAS:
            return "国科大选课系统"
        case TYPE_ZF, TYPE_ZF_1, TYPE_ZF_NEW:
            return "正方教务"
        case TYPE_URP, TYPE_URP_NEW:
            return "URP 教务"
        case TYPE_CF:
            return "青果教务"
        case TYPE_PKU:
            return "北京大学"
        case TYPE_BNUZ:
            return "北师珠"
        case TYPE_WISEDU:
            return "金智教务(直连)"
        case TYPE_CQU:
            return "重庆大学门户"
        case TYPE_EAMS5:
            return "合工大教务 (EAMS5)"
        case TYPE_SEU:
            return "东南大学"
        case TYPE_ZJU:
            return "浙江大学"
        case TYPE_USTC:
            return "中国科学技术大学"
        case TYPE_SCU:
            return "四川大学"
        case TYPE_NEU:
            return "东北大学"
        case TYPE_LOGIN:
            return "特殊登录(v1 暂不支持)"
        case TYPE_HELP:
            return "如何选择教务类型"
        case TYPE_MAINTAIN:
            return "维护中"
        default:
            return type ?? ""
        }
    }

    /// 协议大类,用于 WebViewLogin UI 上的提示文案分类 ← category
    static func category(_ type: String?) -> String {
        switch type {
        case TYPE_QZ, TYPE_QZ_OLD, TYPE_QZ_CRAZY, TYPE_QZ_BR, TYPE_QZ_WITH_NODE, TYPE_QZ_IEAS:
            return "qz"
        case TYPE_ZF, TYPE_ZF_1, TYPE_ZF_NEW:
            return "zf"
        case TYPE_URP, TYPE_URP_NEW:
            return "urp"
        case TYPE_WISEDU:
            return "wisedu"
        case TYPE_CQU:
            return "cqu"
        case TYPE_EAMS5:
            return "eams5"
        case TYPE_SEU, TYPE_ZJU, TYPE_USTC, TYPE_SCU, TYPE_NEU:
            return "other"
        default:
            return "other"
        }
    }
}
