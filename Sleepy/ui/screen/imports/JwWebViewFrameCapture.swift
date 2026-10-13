// JwWebViewFrameCapture.swift — ← JwWebViewFrameCapture.kt (500 行)
//
// T7 — WebView 抓取结果的 frame 级分析与决策。纯 Foundation, 不 import UIKit/WebKit。
//
// 分层: WebView 内 CAPTURE_FRAMES_JS 只负责"把每个可达 frame 的 outerHTML + 路径 + 跨域标记"
// 按 JSON 回传(Swift 信任它的输出, 不在 JS 做决策); 本文件在 Swift 上重建 frame 树、
// 扫锚点、做登录页指纹判定、ready-check 重试决策。全部逻辑可被 XCTest 直接构造 JSON 驱动。

import Foundation

// MARK: - 状态枚举
enum FrameCaptureStatus {
    case ok
    case emptySemester
    case wrongPage
    case crossDomainIframeBlocked
    case containerEmptyAfterDelay
    case sessionExpired
    case iframeNavPending
    case unknown
}

// MARK: - 抓取结果
struct FrameCaptureResult {
    let selectedFramePath: [String]?       // 选中 frame 的路径; nil = 没有可达 frame
    let html: String                       // 选中 frame 的 outerHTML; 无选中时为 ""
    let matchedAnchors: [String]           // 命中的锚点子集
    let courseCount: Int
    let status: FrameCaptureStatus
    let blockedFrames: [String]            // 跨域 frame "name@domain"
    let retryCount: Int
    let maxDepthReached: Int
    let skippedFrames: [String]
    let diagnosticHint: String
    let allFrames: [(path: String, html: String)]

    init(
        selectedFramePath: [String]?,
        html: String,
        matchedAnchors: [String],
        courseCount: Int = 0,
        status: FrameCaptureStatus,
        blockedFrames: [String] = [],
        retryCount: Int = 0,
        maxDepthReached: Int = 0,
        skippedFrames: [String] = [],
        diagnosticHint: String = "",
        allFrames: [(String, String)] = []
    ) {
        self.selectedFramePath = selectedFramePath
        self.html = html
        self.matchedAnchors = matchedAnchors
        self.courseCount = courseCount
        self.status = status
        self.blockedFrames = blockedFrames
        self.retryCount = retryCount
        self.maxDepthReached = maxDepthReached
        self.skippedFrames = skippedFrames
        self.diagnosticHint = diagnosticHint
        self.allFrames = allFrames
    }
}

// MARK: - Frame 快照
struct FrameSnapshot {
    let frameName: String?    // 顶层固定 "(top)"
    let frameSrc: String?
    let depth: Int            // 顶层 0
    let parentPath: [String]  // 顶层 []
    let outerHTML: String?    // nil = 跨域或读取失败
    let blockedDomain: String?
}

struct FrameSnapshotList {
    let url: String
    let declaredMaxDepth: Int
    let frames: [FrameSnapshot]

    /**
     * 解析 CAPTURE_FRAMES_JS 回传 JSON。
     * 结构: {"ok":true,"url":"...","depth":N,"frames":[{name,src,depth,path:[],html,blocked},...]}
     * 容错: ok=false / frames 缺失 / 某 frame 的 html 为 null / blocked 非空 都不抛异常。
     */
    static func fromJson(_ json: String) -> FrameSnapshotList {
        if json.isEmpty { return FrameSnapshotList(url: "", declaredMaxDepth: 0, frames: []) }
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return FrameSnapshotList(url: "", declaredMaxDepth: 0, frames: [])
        }
        let url = obj["url"] as? String ?? ""
        let depth = (obj["depth"] as? Int) ?? 0
        let framesArr = obj["frames"] as? [[String: Any]] ?? []
        var snapshots: [FrameSnapshot] = []
        for f in framesArr {
            let htmlStr = f["html"] as? String ?? ""
            let blockedStr = f["blocked"] as? String ?? ""
            let pathArr = f["path"] as? [String] ?? []
            let nameStr = f["name"] as? String ?? ""
            let srcStr = f["src"] as? String ?? ""
            snapshots.append(FrameSnapshot(
                frameName: nameStr.isEmpty ? nil : nameStr,
                frameSrc: srcStr.isEmpty ? nil : srcStr,
                depth: (f["depth"] as? Int) ?? 0,
                parentPath: pathArr,
                outerHTML: htmlStr.isEmpty ? nil : htmlStr,
                blockedDomain: blockedStr.isEmpty ? nil : blockedStr
            ))
        }
        return FrameSnapshotList(url: url, declaredMaxDepth: depth, frames: snapshots)
    }
}

// MARK: - 树遍历与锚点判定
enum FrameTraversalTree {

    /// 锚点集 — 与 parser 容器选择器对齐(Table1/blacktab/kbtable/kbgrid_table_0/kblist_table/
    /// kbList/kbxx/timetable/_dgdata)。
    static let ANCHORS: [String] = [
        "Table1", "blacktab", "kbtable", "kbgrid_table_0", "kblist_table",
        "kbList", "kbxx", "timetable", "_dgdata"
    ]

    private static func anchorNeedle(_ anchor: String) -> [String] {
        if anchor.hasPrefix("_") {
            // 尾部子串锚点 (ASP.NET 命名容器前缀): id="..._dgdata"
            return ["\(anchor)\"", "\(anchor)'"]
        }
        return ["id=\"\(anchor)\"", "id='\(anchor)'", "class=\"\(anchor)\"", "class='\(anchor)'"]
    }

    /// 扫锚点: 返回 ANCHORS 的命中子集, 顺序保持 ANCHORS 原序
    static func findAnchors(_ html: String) -> [String] {
        if html.isEmpty { return [] }
        let lower = html.lowercased()
        return ANCHORS.filter { anchor in
            anchorNeedle(anchor).contains { lower.contains($0.lowercased()) }
        }
    }

    /// 跨域 frame 列表: "frameName@domain"
    static func findBlockedFrames(_ snapshots: FrameSnapshotList) -> [String] {
        return snapshots.frames.compactMap { f in
            guard let domain = f.blockedDomain else { return nil }
            let name = f.frameName ?? f.frameSrc?.trimmingCharacters(in: CharacterSet(charactersIn: "/")).split(separator: "/").last.map(String.init) ?? "unknown"
            return "\(name)@\(shortDomain(domain))"
        }
    }

    private static func shortDomain(_ src: String) -> String {
        if let url = URL(string: src), let host = url.host { return host }
        return String(src.prefix(80))
    }

    /// 登录页指纹表 — 关键词小写包含即命中, ≥2 条命中才判 SESSION_EXPIRED
    static let LOGIN_FINGERPRINTS: [(String, String)] = [
        ("__viewstate", "zf/ASP.NET"),
        ("type=\"password\"", "zf/ASP.NET"),
        ("checkcode.aspx", "zf"),
        ("logon.do", "qz"),
        ("verifycode.servlet", "qz"),
        ("logintoxk", "qz"),
        ("login_slogin.html", "zf_new"),
        ("/authserver/login", "cf"),
        ("/iaaa/oauth.jsp", "pku"),
        ("appid=syllabus", "pku"),
        ("action=\"default.aspx\"", "bnuz"),
        ("j_spring_security_check", "urp_new"),
        ("cas/login", "sso-cas"),
        ("请输入密码", "通用"),
        ("会话已超时", "通用"),
        ("请重新登录", "通用"),
        ("您的账号在其它地方登录", "qz-顶号")
    ]

    /// 登录页判定: 对一份 frame HTML 独立打分; ≥2 命中 → true。
    /// 硬指纹 logout-redirect 单条即判 (JwParseDiagnostics.LOGOUT_REDIRECT)。
    static func looksLikeLoginPage(_ html: String) -> Bool {
        if html.isEmpty { return false }
        let range = NSRange(html.startIndex..., in: html)
        if JwParseDiagnostics.LOGOUT_REDIRECT.firstMatch(in: html, range: range) != nil { return true }
        let lower = html.lowercased()
        var score = 0
        for (kw, _) in LOGIN_FINGERPRINTS {
            if lower.contains(kw.lowercased()) { score += 1 }
        }
        return score >= 2
    }

    /// 硬指纹 logout-redirect 帧搜索 — 单条即判, 返回最深的可达 frame
    static func findLogoutRedirectFrame(_ snapshots: FrameSnapshotList, maxDepth: Int) -> FrameSnapshot? {
        return snapshots.frames
            .filter { $0.outerHTML != nil && $0.depth <= maxDepth }
            .filter { f in
                let html = f.outerHTML!
                let range = NSRange(html.startIndex..., in: html)
                return JwParseDiagnostics.LOGOUT_REDIRECT.firstMatch(in: html, range: range) != nil
            }
            .max(by: { $0.depth < $1.depth })
    }

    struct Candidate {
        let snapshot: FrameSnapshot
        let anchors: [String]
        let order: Int
    }

    /// 候选排序: 锚点数降序 → 深度降序 → DOM 顺序升序
    static func rankedCandidates(_ snapshots: FrameSnapshotList, maxDepth: Int = 8) -> [Candidate] {
        var result: [(FrameSnapshot, [String], Int, Int, Int)] = []
        for (idx, f) in snapshots.frames.enumerated() {
            guard let html = f.outerHTML, f.depth <= maxDepth else { continue }
            let anchors = findAnchors(html)
            if anchors.isEmpty { continue }
            result.append((f, anchors, idx, anchors.count, f.depth))
        }
        // 锚点降序 → 深度降序 → DOM 顺序升序
        result.sort { a, b in
            if a.3 != b.3 { return a.3 > b.3 }
            if a.4 != b.4 { return a.4 > b.4 }
            return a.2 < b.2
        }
        return result.map { Candidate(snapshot: $0.0, anchors: $0.1, order: $0.2) }
    }

    /// 最佳 frame 选定: 调用 rankedCandidates, 候选 ≥1 → 第一个; 否则 null
    static func selectBestFrame(_ snapshots: FrameSnapshotList, maxDepth: Int = 8) -> FrameSnapshot? {
        return rankedCandidates(snapshots, maxDepth: maxDepth).first?.snapshot
    }
}
