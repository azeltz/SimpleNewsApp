//
//  SocialView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/18/26.
//

import SwiftUI
import WebKit

// MARK: - SocialView

struct SocialView: View {
    @ObservedObject var viewModel: NewsViewModel

    var body: some View {
        NavigationStack {
            List {
                let hasAnySource =
                    viewModel.settings.showInstagram ||
                    viewModel.settings.showX ||
                    viewModel.settings.showReddit ||
                    viewModel.settings.showTikTok ||
                    viewModel.settings.showLinkedIn

                if hasAnySource {
                    if viewModel.settings.showInstagram {
                        NavigationLink {
                            InstagramCleanerView()
                        } label: {
                            Label("Instagram", systemImage: "camera")
                        }
                    }

                    if viewModel.settings.showX {
                        NavigationLink {
                            XCleanerView()
                        } label: {
                            Label("X (Twitter)", systemImage: "bird")
                        }
                    }

                    if viewModel.settings.showReddit {
                        NavigationLink {
                            RedditCleanerView()
                        } label: {
                            Label("Reddit", systemImage: "bubble.left.and.bubble.right")
                        }
                    }

                    if viewModel.settings.showTikTok {
                        NavigationLink {
                            TikTokCleanerView()
                        } label: {
                            Label("TikTok", systemImage: "music.note")
                        }
                    }

                    if viewModel.settings.showLinkedIn {
                        NavigationLink {
                            LinkedInCleanerView()
                        } label: {
                            Label("LinkedIn", systemImage: "briefcase")
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No social sources enabled")
                            .font(.headline)

                        Text("Turn on social apps under Social sources settings to see them here.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        NavigationLink {
                            SocialSourcesSettingsView(viewModel: viewModel)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "slider.horizontal.3")
                                Text("Open Social sources settings")
                            }
                            .font(.footnote)
                        }
                    }
                }
            }
            .navigationTitle("Social")
        }
    }
}

// MARK: - Setting up the WebView for each app

final class WebEnvironment {
    static let shared = WebEnvironment()

    func makeConfig() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        // Uses WKWebsiteDataStore.default() implicitly, which persists cookies
        return config
    }
}

final class WebViewCoordinator: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation?,
                 withError error: Error) {
        print("didFailProvisionalNavigation:", error)
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation?,
                 withError error: Error) {
        print("didFail navigation:", error)
    }

    func webView(_ webView: WKWebView,
                 didFinish navigation: WKNavigation?) {
        print("didFinish navigation")
    }
}

struct CleanerWebView: UIViewRepresentable {
    let url: URL
    let cleanupScript: String

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WebEnvironment.shared.makeConfig()
        let contentController = WKUserContentController()

        if !cleanupScript.isEmpty {
            let script = WKUserScript(
                source: cleanupScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            contentController.addUserScript(script)
        }
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - InstagramView

private let instagramJS = """
function isLoginPage() {
  return window.location.pathname.startsWith("/accounts/login")
      || document.querySelector('form[action*="/accounts/login/"]');
}

function isFeedPage() {
  const path = window.location.pathname;
  const isRoot = path === "/" || path === "";
  return isRoot && !isLoginPage();
}

function cleanInstagram() {
  if (!isFeedPage() || isLoginPage()) return;

  const selectors = [
    'section[aria-label="Reels"]',
    'section[aria-label="Suggested for you"]'
  ];
  selectors.forEach(sel => {
    document.querySelectorAll(sel).forEach(el => {
      el.style.display = "none";
    });
  });
}

cleanInstagram();
setInterval(cleanInstagram, 3000);
"""

struct InstagramCleanerView: View {
    var body: some View {
        CleanerWebView(
            url: URL(string: "https://www.instagram.com/")!,
            cleanupScript: instagramJS
        )
        //.ignoresSafeArea()
        .navigationTitle("Instagram")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - XView

private let xJS = """
function isLoginPage() {
  return window.location.pathname.startsWith("/login")
      || document.querySelector('form[action="/sessions"]');
}

function isHomeTimeline() {
  const path = window.location.pathname;
  return (path === "/" || path.startsWith("/home")) && !isLoginPage();
}

function cleanX() {
  if (!isHomeTimeline()) return;

  const selectors = [
    'aside[role="complementary"]',
    'div[aria-label="Who to follow"]'
  ];
  selectors.forEach(sel => {
    document.querySelectorAll(sel).forEach(el => {
      el.style.display = "none";
    });
  });
}

cleanX();
setInterval(cleanX, 3000);
"""

struct XCleanerView: View {
    var body: some View {
        CleanerWebView(
            url: URL(string: "https://x.com/")!,
            cleanupScript: ""//xJS
        )
        //.ignoresSafeArea()
        .navigationTitle("X")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - RedditView

private let redditJS = """
function isLoginPage() {
  return window.location.pathname.startsWith("/login");
}

function isFrontPage() {
  const path = window.location.pathname;
  return (path === "/" || path.startsWith("/r/popular")) && !isLoginPage();
}

function cleanReddit() {
  if (!isFrontPage()) return;

  const selectors = [
    'div[data-testid="frontpage-sidebar"]',
    'div[id^="TrendingPosts"]'
  ];
  selectors.forEach(sel => {
    document.querySelectorAll(sel).forEach(el => {
      el.style.display = "none";
    });
  });
}

cleanReddit();
setInterval(cleanReddit, 3000);
"""

struct RedditCleanerView: View {
    var body: some View {
        CleanerWebView(
            url: URL(string: "https://www.reddit.com/")!,
            cleanupScript: redditJS
        )
        //.ignoresSafeArea()
        .navigationTitle("Reddit")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - LinkedInView

private let linkedinJS = """
function isLoginPage() {
  const path = window.location.pathname;
  return path.startsWith("/login") || path.startsWith("/checkpoint/");
}

function isFeedPage() {
  const path = window.location.pathname;
  return path.startsWith("/feed") && !isLoginPage();
}

function cleanLinkedIn() {
  if (!isFeedPage() || isLoginPage()) return;

  const selectors = [
    'aside[aria-label="LinkedIn News"]',
    'aside[aria-label="Add to your feed"]',
    'section[aria-label="Sponsored"]'
  ];
  selectors.forEach(sel => {
    document.querySelectorAll(sel).forEach(el => {
      el.style.display = "none";
    });
  });
}

cleanLinkedIn();
setInterval(cleanLinkedIn, 3000);
"""

struct LinkedInCleanerView: View {
    var body: some View {
        CleanerWebView(
            url: URL(string: "https://www.linkedin.com/feed/")!,
            cleanupScript: linkedinJS
        )
        //.ignoresSafeArea()
        .navigationTitle("LinkedIn")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - TikTokView

private let tiktokJS = """
function isLoginPage() {
  const path = window.location.pathname;
  return path.startsWith("/login");
}

function isHomeFeed() {
  const path = window.location.pathname;
  // main home feed is "/" or localized variants; adjust as needed
  const isRoot = path === "/" || path === "";
  return isRoot && !isLoginPage();
}

function cleanTikTok() {
  if (!isHomeFeed() || isLoginPage()) return;

  const selectors = [
    'div[data-e2e="recommend-side-panel"]',   // right sidebar
    'div[data-e2e="trending-hashtag-panel"]', // trending panel
    'div[data-e2e="footer"]'                  // footer clutter
  ];
  selectors.forEach(sel => {
    document.querySelectorAll(sel).forEach(el => {
      el.style.display = "none";
    });
  });
}

cleanTikTok();
setInterval(cleanTikTok, 3000);
"""

struct TikTokCleanerView: View {
    var body: some View {
        CleanerWebView(
            url: URL(string: "https://www.tiktok.com/")!,
            cleanupScript: tiktokJS
        )
        .ignoresSafeArea()
        .navigationTitle("TikTok")
        .navigationBarTitleDisplayMode(.inline)
    }
}
