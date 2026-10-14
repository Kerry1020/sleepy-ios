// JwWebViewConfigBuilder.swift — ← ui/screen/imports/JwWebViewClientBuilder.kt (v1.0.60, 151 行)
//
// WebView 客户端配置装配器 — WKWebView 形态移植。
//
// ## Android 原架构 (HEBZYHJ 闪退根因, 2026-09-09)
// 旧实现 inline 在 JwWebViewLoginScreen factory 闭包内 new 出 WebViewClient,
// callback 体内触碰 view.settings.userAgentString → WebView.checkThread() →
// RuntimeException → 进程终止。修复 = 架构边界:
//   1. 工厂期(主线程)一次性读 userAgent / schoolHost → 缓存进 JwInterceptorContext
//   2. callback 体内只读 ctx 注入的字符串/单例, 不再触碰任何 view.* 方法
//   3. interceptor 按 school.url 装配, 默认 client 不感知协议特例
//   4. JwWebViewCallbackThreadAffinenessTest 锁死架构边界
//
// ## iOS 平台差异 (装配件对照表)
//   Android WebViewClient              → WKNavigationDelegate / WKUIDelegate /
//                                         WKURLSchemeHandler (无单点 client 对象)
//   shouldInterceptRequest 拦截链       → WKWebView 不暴露逐请求同步拦截 API。
//         WKURLSchemeHandler 只对自定义 scheme 生效(教务是 http/https, 挂不上)。
//         SEP XRW 剥离的等价杠杆在 iOS 是 **customUserAgent**:
//         WKWebView 不像 chromium 强注 X-Requested-With 头, iOS 侧 SEP 401 根因
//         本就不存在 → interceptor 链在 iOS 缩为「按 school 预备 UA 覆盖」,
//         与 JwWebViewLoginScreen.applyDesktopUserAgent 同一杠杆。
//         (新建 SepXrwSchemeInterceptor 若未来 iOS 也出现 XRW 类问题:
//          WKURLSchemeHandler + scheme 重写, 见 assembleInterceptors 注释。)
//   onReceivedSslError + SslBypassRegistry → WKNavigationDelegate didReceiveAuthChallenge
//         (WKWebView 默认拒绝; ATS 例外需 Info.plist, 保守不放开 — 与登录屏
//          既有决策一致)。SslBypassRegistry 纯逻辑 1:1 移植在下方, 供
//         challenge 回调按注册域放行自签(如果未来 Info.plist 放开 ATS)。
//   doUpdateVisitedHistory / onPageFinished → didCommit/didFinish navigation 回调
//   DESKTOP_VIEWPORT_JS 双注入(立即+300ms) → WKWebView 同样适用(evaluateJavaScript
//         主线程约束等价), 由 config 注入 WKUserScript(injectionTime: .atDocumentEnd)
//         + didFinish 二次注入兜底 SPA 迟挂 meta。
//   CookieManager.getInstance()       → WKWebsiteDataStore.default().httpCookieStore
//         (async API; 工厂期捕获 store 引用, callback 体内只读该引用)
//
// ## 生命周期
// 装配完成后 config 不持有 webView 引用。userAgent / schoolHost / cookieStore
// 都是 immutable 引用, 无 GC/线程问题(WKWebView 所有 delegate 回调本身就在主线程)。

import Foundation
import WebKit

/// 拦截器上下文 — 工厂期(主线程)一次性捕获的平台资源。
/// (← Android JwInterceptorContext; cookieManager 类型换成 WKHTTPCookieStore)
struct JwInterceptorContext {
    /// 工厂期读到的 UA 字符串(默认 UA 或登录屏已设的 customUserAgent)
    let userAgent: String
    /// WKWebsiteDataStore.default().httpCookieStore — 主线程捕获的共享单例引用
    let cookieStore: WKHTTPCookieStore
    /// school.url 提取的 host(工厂期解析, callback 内不再碰 webView.url)
    let schoolHost: String
}

/// WebViewClient 装配器 — iOS 对应产出 WKWebViewConfiguration + WKWebView 现场配置。
/// (object → enum: 无状态纯装配)
enum JwWebViewClientBuilder {

    /// 装配 WKWebViewConfiguration, 配套给即将创建的 WKWebView。
    ///
    /// - Parameters:
    ///   - school: 学校信息 — 决定 interceptor 装配 + 提取 schoolHost。
    ///   - desktopMode: 桌面 UA 模式 (issue #18 PCUA)。true 时附加 viewport 覆盖
    ///     WKUserScript(钉布局宽 1024px, 触发 Bootstrap 桌面分支 — UA 字符串本身
    ///     对布局零影响)。全协议启用(2026-09-13 Android 侧同步决策: 只换 UA 不注
    ///     viewport 时非 UCAS 校切换毫无反应)。
    ///   - messageHandlerName: JS 桥名(默认 __sleepyBridge, 桥接约定)。
    /// - Returns: 已完成全部静态配置(桥/UA/脚本)的 configuration + ctx。
    static func build(
        school: JwSchoolInfo,
        desktopMode: Bool = false,
        messageHandlerName: String = "__sleepyBridge"
    ) -> (config: WKWebViewConfiguration, ctx: JwInterceptorContext) {
        let config = WKWebViewConfiguration()

        // 主线程读: userAgent 工厂期一次捕获 (← webView.settings.userAgentString)
        // WKWebView 无同步读当前 UA 的公开 API — 默认 UA 之外的自定义 UA 由
        // 调用方显式传入后再进本工厂; 此处读 desktopMode 决定装配 UA。
        let userAgent = desktopMode ? JwWebViewClientBuilder.desktopUserAgent : ""
        if !userAgent.isEmpty {
            config.applicationNameForUserAgent = userAgent
        }
        let schoolHost = host(of: school.url)
        let ctx = JwInterceptorContext(
            userAgent: userAgent,
            cookieStore: WKWebsiteDataStore.default().httpCookieStore,
            schoolHost: schoolHost
        )

        let prefs = WKPreferences()
        prefs.javaScriptCanOpenWindowsAutomatically = true
        config.preferences = prefs

        // 桌面 viewport 覆盖全协议启用(同 Android 2026-09-13 决策):
        // 桌面 UA + 1024px 视口 = 响应式门户真正切桌面分支。
        // WKUserScript atDocumentEnd ≈ Android onPageFinished 首注入;
        // didFinish 二次注入兜底由 config 消费方(NavDelegate)执行 — 双注入模式
        // (chromium 对 meta 变更重排时机不定, SO 19953717 重复注入模式)。
        if desktopMode {
            config.userContentController.addUserScript(WKUserScript(
                source: desktopViewportJs,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true))
        }
        _ = messageHandlerName  // ScriptMessageHandler 注册由持有 WKScriptMessageHandler
                                // 的 coordinator 完成(config 不持 handler 引用,
                                // 避免环; 见 JwWebViewLoginScreen.WebViewCoordinator)
        return (config, ctx)
    }

    /// 按 school 协议族装配拦截器链。当前 Android 侧只挂 SEP XRW 剥离 (UCAS #18) —
    /// iOS 无 chromium 强注 XRW 头的根因, 链为空但保留结构: 新协议在这里加一行即可。
    /// (← assembleInterceptors; 返回 UA 覆盖建议而非 response 改写器)
    static func assembleInterceptors(_ school: JwSchoolInfo) -> [String] {
        var list: [String] = []
        // UCAS #18: Android SEP SSO 域 (sep.ucas.ac.cn) 剥 X-Requested-With;
        // iOS WKWebView 不强注该头, 无操作。保留分支注释作装配点。
        if school.url.lowercased().contains(UCAS_DOMAIN) {
            // list.append(...) — 未来 iOS 特有协议问题在此装配
        }
        return list
    }

    /// school.url → host(工厂期一次性解析)。(← school.url.toUri().host)
    static func host(of url: String) -> String {
        guard let u = URL(string: url) else { return "" }
        return u.host ?? ""
    }

    /// ← DESKTOP_USER_AGENT (JwWebViewLoginScreen.kt): Chrome 121 / Windows 10
    /// 桌面 UA — 无 Android/iPhone 词汇, 触发门户桌面版布局。
    /// (登录屏 jwDesktopUserAgent 为 private; 此处独立常量, 值逐字一致)
    static let desktopUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) " +
        "Chrome/121.0.0.0 Safari/537.36"

    /// ← DESKTOP_VIEWPORT_JS: meta viewport 钉 1024px + 回顶。
    /// (与 Android JwWebViewLoginScreen.kt 顶部常量逐字一致)
    static let desktopViewportJs =
        "(function(){var m=document.querySelector('meta[name=\"viewport\"]');" +
        "if(m){m.setAttribute('content','width=1024');}" +
        "else{m=document.createElement('meta');m.setAttribute('name','viewport');" +
        "m.setAttribute('content','width=1024');document.head.appendChild(m);}" +
        "setTimeout(function(){window.scrollTo(0,0);},0);})()"

    private static let UCAS_DOMAIN = "ucas.ac.cn"
}

// MARK: - SSL 豁免注册表 (← SslBypassRegistry, JwWebViewLoginScreen.kt 2115)
//
// 仅对学校 URL 的注册域 (含其子域) 放行自签/私有 CA 证书 —
// 部分高校教务确用私有 CA。除此之外的 SSL 错误一律 cancel (中间人防护)。
//
// iOS 消费点: WKNavigationDelegate webView(_:didReceive challenge:) 的
// serverTrust 分支(如果 Info.plist ATS 例外放开)。纯逻辑, JVM/单测可直跑。

enum SslBypassRegistry {

    /// 取注册域: 无公共后缀库, 用启发式 — 取末两段 (xx.edu.cn 形态取末三段)。
    static func registrableDomain(_ host: String) -> String {
        let h = host.lowercased().trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if h.isEmpty { return "" }
        let parts = h.components(separatedBy: ".")
        if parts.count <= 2 { return h }
        let secondLevel = parts[parts.count - 2]
        // 多段公共后缀 (edu.cn / edu.hk / ac.uk 等): 公共后缀 + 域名 = 末三段
        let tld = parts.last ?? ""
        if (tld == "cn" || tld == "hk" || tld == "uk" || tld == "tw" || tld == "jp"),
           ["edu", "ac", "gov", "org"].contains(secondLevel) {
            return parts.suffix(3).joined(separator: ".")
        }
        return parts.suffix(2).joined(separator: ".")
    }

    /// host 是否与 schoolHost 同注册域 (或为其子域)。
    static func isAllowed(host: String, schoolHost: String) -> Bool {
        if host.trimmingCharacters(in: .whitespaces).isEmpty
            || schoolHost.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return registrableDomain(host) == registrableDomain(schoolHost)
    }
}
