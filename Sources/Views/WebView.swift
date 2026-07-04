import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let webView = WebViewManager.shared.webView
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// 管理單一 WKWebView 實例，確保跨視窗生命週期保持 session
class WebViewManager: NSObject, ObservableObject {
    static let shared = WebViewManager()

    let webView: WKWebView

    private override init() {
        let config = WKWebViewConfiguration()

        // 使用預設 data store 持久化 cookie（Google 登入 session）
        config.websiteDataStore = .default()

        // 允許自動播放媒體
        config.mediaTypesRequiringUserActionForPlayback = []

        // 啟用 JavaScript
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences

        // 註冊 JS → Swift message handler
        let userContentController = WKUserContentController()
        config.userContentController = userContentController

        webView = WKWebView(frame: .zero, configuration: config)

        super.init()

        // 深色背景：避免載入時與標題列下方出現白色區塊
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1)

        // 使用 Safari UA（WKWebView 本身就是 WebKit，用 Chrome UA 會被 Google 偵測不一致）
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"

        // 設定 navigation delegate 處理彈出式視窗
        webView.navigationDelegate = self
        webView.uiDelegate = self

        // 允許返回/前進手勢
        webView.allowsBackForwardNavigationGestures = true

        // 註冊 JS Bridge message handlers
        let bridge = JavaScriptBridge.shared
        userContentController.add(bridge, name: "nowPlaying")
        userContentController.add(bridge, name: "playbackState")
        userContentController.add(bridge, name: "volumeChanged")
        userContentController.add(bridge, name: "repeatState")
        userContentController.add(bridge, name: "shuffleState")
        userContentController.add(bridge, name: "queueUpdate")
        userContentController.add(bridge, name: "timeUpdate")
        userContentController.add(bridge, name: "debugLog")

        // 在 Google 登入頁面隱藏 WebView 特徵（messageHandlers）
        let hideWebViewScript = WKUserScript(
            source: """
            (function() {
                // 備份 messageHandlers 引用，Google 登入偵測用
                const realHandlers = window.webkit?.messageHandlers;
                Object.defineProperty(window, 'webkit', {
                    get: function() {
                        // 對 Google 登入頁面隱藏 messageHandlers
                        if (document.location.hostname.includes('accounts.google.com')) {
                            return undefined;
                        }
                        return { messageHandlers: realHandlers };
                    },
                    configurable: true
                });
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(hideWebViewScript)

        // 隱藏捲軸（保留捲動功能）
        // 必須在 documentStart 注入並 patch attachShadow：
        // YouTube Music 部分捲動容器在 shadow DOM 內，document 層級的 CSS 穿不進去
        let hideScrollbarScript = WKUserScript(
            source: """
            (function() {
                var css = [
                    '::-webkit-scrollbar { display: none !important; width: 0 !important; height: 0 !important; }',
                    '* { scrollbar-width: none !important; -ms-overflow-style: none !important; }',
                    /* YT Music 用此變數幫捲軸保留 12px 空位，捲軸已隱藏所以歸零 */
                    'html { --ytmusic-scrollbar-width: 0px !important; }',
                    /* 視窗紅綠燈疊在網頁 header 上：把 nav bar 加高 28px、內容下移到紅綠燈正下方。
                       版面高度綁在 --ytmusic-nav-bar-height 變數上，改變數其餘區塊會自動跟著位移。
                       注入的 CSS 一律加 !important，否則會被 YTM 較晚載入的 stylesheet 蓋掉 */
                    'html { --ytmusic-nav-bar-height: 92px !important; }',
                    'ytmusic-nav-bar { padding-top: 28px !important; }'
                ].join(' ');

                function makeStyle() {
                    var s = document.createElement('style');
                    s.textContent = css;
                    return s;
                }

                var origAttachShadow = Element.prototype.attachShadow;
                Element.prototype.attachShadow = function(init) {
                    var root = origAttachShadow.call(this, init);
                    try { root.appendChild(makeStyle()); } catch (e) {}
                    return root;
                };

                function injectDocumentStyle() {
                    var target = document.head || document.documentElement;
                    if (!target) return;
                    if (!document.getElementById('__ytmusic_hide_scrollbar')) {
                        var s = makeStyle();
                        s.id = '__ytmusic_hide_scrollbar';
                        target.appendChild(s);
                    }
                }
                injectDocumentStyle();
                new MutationObserver(injectDocumentStyle).observe(document.documentElement, { childList: true, subtree: true });
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(hideScrollbarScript)

        // 注入歌曲監聯 JS
        let monitorScript = WKUserScript(
            source: JavaScriptBridge.monitorScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(monitorScript)

        loadYouTubeMusic()
    }

    func loadYouTubeMusic() {
        guard let url = URL(string: "https://music.youtube.com") else { return }
        let request = URLRequest(url: url)
        webView.load(request)
    }
}

// MARK: - WKNavigationDelegate
extension WebViewManager: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // 允許所有導航（包含 Google OAuth 流程）
        decisionHandler(.allow)
    }
}

// MARK: - WKUIDelegate
extension WebViewManager: WKUIDelegate {
    /// 處理 JavaScript window.open()（Google 登入彈出視窗）
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // 在同一個 WebView 中打開彈出連結
        if navigationAction.targetFrame == nil || navigationAction.targetFrame?.isMainFrame == false {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
