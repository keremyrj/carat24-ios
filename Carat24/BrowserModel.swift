import Foundation
import Network
import SwiftUI
import UIKit
import WebKit

enum AppSection {
    case settings
    case display
    case management
}

@MainActor
final class BrowserModel: NSObject, ObservableObject {
    @Published var showsBottomBar = false
    @Published var section: AppSection = .settings
    @Published var isOffline = false

    let webView: WKWebView

    private let baseURL = URL(string: "https://ceremybilisim.com")!
    private let allowedHosts: Set<String> = ["ceremybilisim.com", "www.ceremybilisim.com"]
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.ceremybilisim.carat24.network")
    private var started = false
    private var showingLogin = false
    private var pendingDisplay = false

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.applicationNameForUserAgent = "Carat24/1.0 iOS"
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(refreshPage(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
    }

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let offline = path.status != .satisfied
                self.isOffline = offline
                if !offline && self.webView.url == nil { self.loadInitialPage() }
            }
        }
        monitor.start(queue: monitorQueue)
        loadInitialPage()
    }

    func retry() {
        isOffline = false
        if webView.url == nil { loadInitialPage() } else { webView.reload() }
    }

    func open(_ destination: AppSection) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch destination {
        case .settings:
            pendingDisplay = false
            load(path: "/panel")
        case .management:
            pendingDisplay = false
            load(path: "/carat24")
        case .display:
            pendingDisplay = true
            let path = webView.url?.path ?? ""
            if path == "/panel" {
                savePanelAndOpenDisplay()
            } else if path == "/carat24" || path == "/carat24/" {
                openConfiguredDisplay()
            } else {
                load(path: "/panel")
            }
        }
    }

    private func loadInitialPage() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self else { return }
                if cookies.contains(where: { $0.name == "ceremy_session" && self.allowedHosts.contains($0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) }) {
                    self.load(path: "/panel")
                } else {
                    self.showLogin()
                }
            }
        }
    }

    private func load(path: String) {
        guard let url = URL(string: path, relativeTo: baseURL) else { return }
        webView.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 30))
    }

    private func showLogin() {
        showingLogin = true
        pendingDisplay = false
        showsBottomBar = false
        webView.loadHTMLString(Self.loginHTML, baseURL: baseURL)
    }

    private func savePanelAndOpenDisplay() {
        let script = """
        (function(){
          var form=document.getElementById('settings-form');
          if(!form)return 'missing';
          if(!form.reportValidity())return 'invalid';
          if(typeof form.requestSubmit==='function')form.requestSubmit();else form.submit();
          return 'submitted';
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                if result as? String == "missing" { self.load(path: "/carat24") }
                if result as? String == "invalid" { self.pendingDisplay = false }
            }
        }
    }

    private func openDisplayFromPanel() {
        pendingDisplay = false
        let script = """
        (function(){
          var launch=document.getElementById('display-options-button');
          if(!launch)return 'missing';
          var originalOpen=window.open;
          window.open=function(url){window.location.href=url;return{closed:false,focus:function(){}}};
          launch.click();
          var primary=document.getElementById('screen-open-primary');
          if(primary)primary.click();
          window.open=originalOpen;
          return primary?'opened':'missing';
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                if result as? String != "opened" {
                    self.pendingDisplay = true
                    self.load(path: "/carat24")
                }
            }
        }
    }

    private func openConfiguredDisplay() {
        webView.evaluateJavaScript("window.CARAT24_CONFIG&&window.CARAT24_CONFIG.displayUrl||''") { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                self.pendingDisplay = false
                if let path = result as? String, path.hasPrefix("/display/") {
                    self.load(path: path)
                } else {
                    self.load(path: "/panel")
                }
            }
        }
    }

    private func updateState(for url: URL) {
        let path = url.path
        if showingLogin && path == "/" {
            showsBottomBar = false
            return
        }
        if path == "/api/login" {
            showsBottomBar = false
            return
        }
        if path == "/" {
            showLogin()
            return
        }

        showingLogin = false
        showsBottomBar = true
        if path == "/panel" { section = .settings }
        else if path.hasPrefix("/display/") { section = .display }
        else if path == "/carat24" || path == "/carat24/" { section = .management }

        if pendingDisplay && path == "/panel" {
            openDisplayFromPanel()
        } else if pendingDisplay && (path == "/carat24" || path == "/carat24/") {
            openConfiguredDisplay()
        }
    }

    @objc private func refreshPage(_ sender: UIRefreshControl) {
        webView.reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { sender.endRefreshing() }
    }

    private static let loginHTML = """
    <!doctype html><html lang="tr"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,viewport-fit=cover">
    <style>
    *{box-sizing:border-box}html,body{margin:0;min-height:100%;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}
    body{min-height:100vh;display:grid;place-items:center;padding:24px;background:#f7f2e8;color:#0c1720}
    .card{width:min(100%,420px);background:#fff;border:1px solid #dfd4bf;border-radius:22px;padding:30px;box-shadow:0 18px 50px #3b2a1217}
    .mark{font-weight:900;letter-spacing:3px;color:#b47b17;font-size:14px}.name{font-size:34px;font-weight:900;letter-spacing:2px;margin:8px 0 4px}
    .sub{color:#66707b;margin:0 0 24px;line-height:1.5}label{display:block;font-size:13px;font-weight:800;margin:15px 0 7px}
    input{width:100%;height:52px;border:1px solid #cfc6b6;border-radius:12px;padding:0 14px;font-size:17px;background:#fff;color:#0c1720}
    input:focus{outline:3px solid #d6ad5a55;border-color:#b98220}button{width:100%;height:54px;border:0;border-radius:12px;margin-top:22px;background:#b98220;color:#fff;font-size:17px;font-weight:900}
    small{display:block;text-align:center;color:#7b8288;margin-top:18px}
    </style></head><body><main class="card"><div class="mark">CEREMY BİLİŞİM</div><div class="name">CARAT24</div>
    <p class="sub">Hesabınıza giriş yaparak fiyat, kârlandırma ve kuyumcu yönetim ekranlarını kullanın.</p>
    <form method="post" action="https://ceremybilisim.com/api/login"><label>Kullanıcı adı</label>
    <input name="username" autocomplete="username" autocapitalize="none" required autofocus><label>Şifre</label>
    <input name="password" type="password" autocomplete="current-password" required><button type="submit">Giriş yap</button></form>
    <small>Girişiniz bu cihazda güvenli şekilde hatırlanır.</small></main></body></html>
    """
}

extension BrowserModel: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let trustedHosts: Set<String> = ["ceremybilisim.com", "www.ceremybilisim.com"]
        if url.scheme == "https", let host = url.host, trustedHosts.contains(host) {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        if ["http", "https", "tel", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            Task { @MainActor in UIApplication.shared.open(url) }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            webView.scrollView.refreshControl?.endRefreshing()
            self.isOffline = false
            if let url = webView.url { self.updateState(for: url) }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.isOffline = true }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.isOffline = true }
    }
}

extension BrowserModel: WKUIDelegate {
    nonisolated func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let requestURL = navigationAction.request.url {
            Task { @MainActor in webView.load(URLRequest(url: requestURL)) }
        }
        return nil
    }
}
