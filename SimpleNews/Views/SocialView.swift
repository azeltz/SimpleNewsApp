//
//  SocialView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/18/26.
//

import SwiftUI
import WebKit
import UIKit

// MARK: - SocialView

struct SocialView: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        NavigationStack {
            List {
                let hasAnySource =
                    settingsStore.settings.showInstagram ||
                    settingsStore.settings.showX ||
                    settingsStore.settings.showReddit ||
                    settingsStore.settings.showTikTok ||
                    settingsStore.settings.showLinkedIn

                if hasAnySource {
                    if settingsStore.settings.showInstagram {
                        NavigationLink {
                            InstagramCleanerView()
                        } label: {
                            Label("Instagram", systemImage: "camera")
                                .foregroundStyle(Color(red: 0.91, green: 0.19, blue: 0.42))
                                .bold()
                        }
                    }

                    if settingsStore.settings.showReddit {
                        NavigationLink {
                            RedditCleanerView()
                        } label: {
                            Label("Reddit", systemImage: "bubble.left.and.bubble.right")
                                .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.0))
                                .bold()
                        }
                    }

                    if settingsStore.settings.showLinkedIn {
                        NavigationLink {
                            LinkedInCleanerView()
                        } label: {
                            Label("LinkedIn", systemImage: "briefcase")
                                .foregroundStyle(Color(red: 0.04, green: 0.40, blue: 0.76))
                                .bold()
                        }
                    }
                    
//                    if settingsStore.settings.showX {
//                        NavigationLink {
//                            XCleanerView()
//                        } label: {
//                            Label("X (Twitter)", systemImage: "bird")
//                                .foregroundStyle(.black)
//                                .bold()
//                        }
//                    }
//                    
//                    if settingsStore.settings.showTikTok {
//                        NavigationLink {
//                            TikTokCleanerView()
//                        } label: {
//                            Label("TikTok", systemImage: "music.note")
//                                .foregroundStyle(Color(red: 0.0, green: 0.95, blue: 0.92))
//                                .bold()
//                        }
//                    }
                    
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No social sources enabled")
                            .font(.headline)

                        Text("Turn on social apps under Social sources settings to see them here.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        NavigationLink {
                            SocialSourcesSettingsView()
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
        print("WKWebView didFailProvisionalNavigation:", error.localizedDescription)
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation?,
                 withError error: Error) {
        print("WKWebView didFail navigation:", error.localizedDescription)
    }

    func webView(_ webView: WKWebView,
                 didFinish navigation: WKNavigation?) {
        print("WKWebView didFinish navigation, url:", webView.url?.absoluteString ?? "nil")
    }
}

struct CleanerWebView: UIViewRepresentable {
    let url: URL
    let cleanupScript: String

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        // Start with a fresh config
        let config = WKWebViewConfiguration()
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

        let request = URLRequest(url: url)
        webView.load(request)

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

//// MARK: - XView
//
//private let xJS = """
//function isLoginPage() {
//  return window.location.pathname.startsWith("/login")
//      || document.querySelector('form[action="/sessions"]');
//}
//
//function isHomeTimeline() {
//  const path = window.location.pathname;
//  return (path === "/" || path.startsWith("/home")) && !isLoginPage();
//}
//
//function cleanX() {
//  if (!isHomeTimeline()) return;
//
//  const selectors = [
//    'aside[role="complementary"]',
//    'div[aria-label="Who to follow"]'
//  ];
//  selectors.forEach(sel => {
//    document.querySelectorAll(sel).forEach(el => {
//      el.style.display = "none";
//    });
//  });
//}
//
//cleanX();
//setInterval(cleanX, 3000);
//"""
//
//struct XCleanerView: View {
//    var body: some View {
//        VStack(spacing: 12) {
//            ProgressView()
//            Text("Opening X in Safari…")
//                .font(.footnote)
//                .foregroundColor(.secondary)
//        }
//        .onAppear {
//            if let url = URL(string: "https://x.com/home") {
//                UIApplication.shared.open(url)
//            }
//        }
//        .navigationTitle("X")
//        .navigationBarTitleDisplayMode(.inline)
//    }
//}

//// MARK: - TikTokView
//
//private let tiktokJS = """
//function isLoginPage() {
//  const path = window.location.pathname;
//  return path.startsWith("/login");
//}
//
//function isHomeFeed() {
//  const path = window.location.pathname;
//  // main home feed is "/" or localized variants; adjust as needed
//  const isRoot = path === "/" || path === "";
//  return isRoot && !isLoginPage();
//}
//
//function cleanTikTok() {
//  if (!isHomeFeed() || isLoginPage()) return;
//
//  const selectors = [
//    'div[data-e2e="recommend-side-panel"]',   // right sidebar
//    'div[data-e2e="trending-hashtag-panel"]', // trending panel
//    'div[data-e2e="footer"]'                  // footer clutter
//  ];
//  selectors.forEach(sel => {
//    document.querySelectorAll(sel).forEach(el => {
//      el.style.display = "none";
//    });
//  });
//}
//
//cleanTikTok();
//setInterval(cleanTikTok, 3000);
//"""
//
//struct TikTokCleanerView: View {
//    var body: some View {
//        VStack(spacing: 12) {
//            ProgressView()
//            Text("Opening TikTok in Safari…")
//                .font(.footnote)
//                .foregroundColor(.secondary)
//        }
//        .onAppear {
//            if let url = URL(string: "https://www.tiktok.com/") {
//                UIApplication.shared.open(url)
//            }
//        }
//        .navigationTitle("TikTok")
//        .navigationBarTitleDisplayMode(.inline)
//    }
//}
