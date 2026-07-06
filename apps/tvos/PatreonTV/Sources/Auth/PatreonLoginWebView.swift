//
//  PatreonLoginWebView.swift
//  PatreonTV
//
//  WKWebView wrapper that loads patreon.com/login and watches for the
//  session_id cookie. When the cookie appears, we hand it back and dismiss.
//
//  Design: this uses a non-persistent WKWebsiteDataStore so that logging
//  out clears state cleanly, and so that we're the *only* holder of the
//  session_id (not the system-wide cookie jar).
//

import SwiftUI
import UIKit
import WebKit

struct PatreonLoginWebView: UIViewControllerRepresentable {

    let onCookieCaptured: (String) -> Void
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> LoginWebViewController {
        let vc = LoginWebViewController()
        vc.onCookieCaptured = onCookieCaptured
        vc.onDismiss = onDismiss
        return vc
    }

    func updateUIViewController(_ uiViewController: LoginWebViewController, context: Context) {}
}

final class LoginWebViewController: UIViewController, WKNavigationDelegate {

    var onCookieCaptured: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    private var webView: WKWebView!
    private var cookiePollTimer: Timer?
    private var captured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let config = WKWebViewConfiguration()
        // Non-persistent store — this app is the sole owner of session state.
        config.websiteDataStore = .nonPersistent()

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        view.addSubview(webView)

        if let url = URL(string: "https://www.patreon.com/login") {
            webView.load(URLRequest(url: url))
        }

        startCookiePolling()
        setupCancelGesture()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cookiePollTimer?.invalidate()
    }

    /// Polls the WKWebView's cookie store every second for a Patreon session_id.
    private func startCookiePolling() {
        cookiePollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, !self.captured else { return }
            self.checkForSessionCookie()
        }
    }

    private func checkForSessionCookie() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self, !self.captured else { return }
            for cookie in cookies {
                guard cookie.name == "session_id",
                      cookie.domain.hasSuffix("patreon.com"),
                      !cookie.value.isEmpty
                else { continue }

                self.captured = true
                self.cookiePollTimer?.invalidate()
                Task { @MainActor in
                    self.onCookieCaptured?(cookie.value)
                }
                return
            }
        }
    }

    // MARK: - Cancel gesture (Menu button on Siri Remote)

    private func setupCancelGesture() {
        // On tvOS, the Menu button (or Back on Siri Remote 2nd gen) sends
        // UIPress.PressType.menu. We map it to dismiss the sign-in flow.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleMenuPress))
        tap.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        view.addGestureRecognizer(tap)
    }

    @objc private func handleMenuPress() {
        onDismiss?()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Re-check cookies on every navigation — catches successful logins
        // faster than the timer alone.
        checkForSessionCookie()
    }
}
