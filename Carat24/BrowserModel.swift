import Foundation
import Network
import Security
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
    @Published var availableUpdate: AppUpdate?

    let webView: WKWebView

    private let baseURL = URL(string: "https://ceremybilisim.com")!
    private let allowedHosts: Set<String> = ["ceremybilisim.com", "www.ceremybilisim.com"]
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.ceremybilisim.carat24.network")
    private var started = false
    private var showingLogin = false
    private var pendingDisplay = false
    private var attemptedAutomaticLogin = false

    nonisolated private static let loginMessageName = "carat24Login"
    nonisolated private static let keychainService = "com.ceremybilisim.carat24.login"

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.applicationNameForUserAgent = "Carat24/1.0 iOS"
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        configuration.userContentController.add(self, name: Self.loginMessageName)
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
        checkForUpdate()
    }

    func retry() {
        isOffline = false
        if webView.url == nil { loadInitialPage() } else { webView.reload() }
    }

    func openAvailableUpdate() {
        guard let url = availableUpdate?.appStoreURL else { return }
        UIApplication.shared.open(url)
    }

    private func checkForUpdate() {
        guard let url = URL(string: "https://ceremybilisim.com/api/app-version") else { return }
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
                let update = try JSONDecoder().decode(AppUpdate.self, from: data)
                let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
                if updateVersionIsNewer(update.version, than: current) {
                    availableUpdate = update
                }
            } catch {
                // Güncelleme kontrolü başarısız olsa bile uygulama normal çalışmaya devam eder.
            }
        }
    }

    private func updateVersionIsNewer(_ candidate: String, than current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
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

    private func fillRememberedLoginIfNeeded() {
        guard let credentials = Self.loadCredentials() else { return }

        let values: [String: String] = ["username": credentials.username, "password": credentials.password]
        guard let data = try? JSONSerialization.data(withJSONObject: values),
              let json = String(data: data, encoding: .utf8) else { return }

        let shouldSubmit = !attemptedAutomaticLogin
        attemptedAutomaticLogin = true
        let script = """
        (function(){
          const saved=\(json);
          const form=document.getElementById('login-form');
          if(!form)return;
          form.elements.username.value=saved.username;
          form.elements.password.value=saved.password;
          document.getElementById('remember').checked=true;
          if(\(shouldSubmit ? "true" : "false")) form.requestSubmit();
        })()
        """
        webView.evaluateJavaScript(script)
    }

    nonisolated private static func saveCredentials(username: String, password: String) {
        guard let data = try? JSONEncoder().encode(LoginCredentials(username: username, password: password)) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "remembered-login"
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    nonisolated private static func loadCredentials() -> LoginCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "remembered-login",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(LoginCredentials.self, from: data)
    }

    nonisolated private static func deleteCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "remembered-login"
        ]
        SecItemDelete(query as CFDictionary)
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
        if path == "/canli-piyasalar" || path == "/canli-piyasalar.html" {
            showingLogin = false
            pendingDisplay = false
            showsBottomBar = false
            return
        }
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
    .sub{color:#66707b;margin:0 0 24px;line-height:1.5}.choice{display:flex;align-items:center;justify-content:center;width:100%;height:54px;border-radius:12px;text-decoration:none;font-size:17px;font-weight:900}.market{background:#0d1d2d;color:#fff}.login-choice{margin-top:10px;background:#fff;color:#0d1d2d;border:1px solid #0d1d2d}.divider{display:flex;align-items:center;gap:10px;color:#92989c;font-size:11px;margin:20px 0}.divider:before,.divider:after{content:'';height:1px;background:#ded8cb;flex:1}.login-area{display:none}.login-area.open{display:block}label{display:block;font-size:13px;font-weight:800;margin:15px 0 7px}
    input{width:100%;height:52px;border:1px solid #cfc6b6;border-radius:12px;padding:0 14px;font-size:17px;background:#fff;color:#0c1720}
    input:focus{outline:3px solid #d6ad5a55;border-color:#b98220}button{width:100%;height:54px;border:0;border-radius:12px;margin-top:22px;background:#b98220;color:#fff;font-size:17px;font-weight:900}
    small{display:block;text-align:center;color:#7b8288;margin-top:18px}
    </style></head><body><main class="card"><div class="mark">CEREMY BİLİŞİM</div><div class="name">CARAT24</div>
    <p class="sub">Canlı piyasaları inceleyin veya Carat24 hesabınızla yönetim ekranlarına giriş yapın.</p>
    <a class="choice market" href="https://www.ceremybilisim.com/canli-piyasalar.html">Canlı Piyasalar</a>
    <button class="choice login-choice" type="button" onclick="document.getElementById('login-area').classList.add('open');this.style.display='none';document.querySelector('[name=username]').focus()">Kuyumcu Girişi</button>
    <section id="login-area" class="login-area"><div class="divider">GÜVENLİ GİRİŞ</div>
    <form id="login-form" method="post" action="https://ceremybilisim.com/api/login"><label>Kullanıcı adı</label>
    <input name="username" autocomplete="username" autocapitalize="none" required autofocus><label>Şifre</label>
    <input name="password" type="password" autocomplete="current-password" required>
    <label style="display:flex;align-items:center;gap:10px;font-weight:700"><input id="remember" type="checkbox" checked style="width:22px;height:22px">Beni hatırla</label>
    <button type="submit">Giriş yap</button></form>
    <small>Seçildiğinde girişiniz bu cihazda güvenli şekilde hatırlanır.</small></section>
    <a class="choice" style="height:44px;margin-top:16px;color:#a86f10;font-size:14px" href="https://wa.me/905385788136?text=Merhaba%2C%20Carat24%20i%C3%A7in%20%C3%BCcretsiz%20demo%20hesab%C4%B1%20talep%20ediyorum.">Ücretsiz Demo Talep Et</a></main>
    <script>document.getElementById('login-form').addEventListener('submit',function(){var r=document.getElementById('remember').checked;window.webkit.messageHandlers.carat24Login.postMessage({username:this.elements.username.value,password:this.elements.password.value,remember:r})})</script>
    </body></html>
    """
}

private struct LoginCredentials: Codable {
    let username: String
    let password: String
}

struct AppUpdate: Codable, Identifiable {
    var id: String { version }
    let version: String
    let required: Bool
    let appStoreURL: URL
}

extension BrowserModel: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.loginMessageName,
              let body = message.body as? [String: Any],
              let remember = body["remember"] as? Bool else { return }
        let username = body["username"] as? String ?? ""
        let password = body["password"] as? String ?? ""
        if remember && !username.isEmpty && !password.isEmpty {
            Self.saveCredentials(username: username, password: password)
        } else {
            Self.deleteCredentials()
        }
    }
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
            if self.showingLogin, webView.url?.path == "/" { self.fillRememberedLoginIfNeeded() }
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
