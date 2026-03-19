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
//                    settingsStore.settings.showX ||
                    settingsStore.settings.showReddit ||
                    settingsStore.settings.showTikTok ||
                    settingsStore.settings.showLinkedIn

                if hasAnySource {
                    if settingsStore.settings.showInstagram {
                        NavigationLink {
                            SocialSiteView(config: .instagram)
                        } label: {
                            Label("Instagram", systemImage: "camera")
                                .foregroundStyle(Color(red: 0.91, green: 0.19, blue: 0.42))
                                .bold()
                        }
                    }

                    if settingsStore.settings.showReddit {
                        NavigationLink {
                            SocialSiteView(config: .reddit)
                        } label: {
                            Label("Reddit", systemImage: "bubble.left.and.bubble.right")
                                .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.0))
                                .bold()
                        }
                    }

                    if settingsStore.settings.showLinkedIn {
                        NavigationLink {
                            SocialSiteView(config: .linkedin)
                        } label: {
                            Label("LinkedIn", systemImage: "briefcase")
                                .foregroundStyle(Color(red: 0.04, green: 0.40, blue: 0.76))
                                .bold()
                        }
                    }

//                    if settingsStore.settings.showX {
//                        NavigationLink {
//                            TwitterFeedView()
//                        } label: {
//                            Label("X (Twitter)", systemImage: "bird")
//                                .foregroundStyle(.primary)
//                                .bold()
//                        }
//                    }

//                    if settingsStore.settings.showTikTok {
//                        NavigationLink {
//                            SocialSiteView(config: .tiktok)
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

// MARK: - Bridge from SwiftUI to UIKit

final class SocialWebBridge: ObservableObject {
    weak var controller: SocialWebViewController?

    @Published var isMinimized: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    func goBack() {
        controller?.goBack()
        refreshCapabilities()
    }

    func goForward() {
        controller?.goForward()
        refreshCapabilities()
    }

    func reload() {
        controller?.reload()
        refreshCapabilities()
    }

    func toggleMinimized() {
        isMinimized.toggle()
        controller?.setMinimized(isMinimized)
    }

    func refreshCapabilities() {
        guard let webView = controller?.webView else { return }
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}

// MARK: - SocialWebViewController

/// A UIKit view controller that owns a WKWebView.
final class SocialWebViewController: UIViewController, WKNavigationDelegate {
    let url: URL
    let cleanupScript: String
    let bridge: SocialWebBridge
    var webView: WKWebView!

    init(url: URL, cleanupScript: String, bridge: SocialWebBridge) {
        self.url = url
        self.cleanupScript = cleanupScript
        self.bridge = bridge
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        if !cleanupScript.isEmpty {
            let script = WKUserScript(
                source: cleanupScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            config.userContentController.addUserScript(script)
        }

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        webView.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        bridge.refreshCapabilities()
    }

    // MARK: - API used by the bridge

    func goBack() {
        if webView.canGoBack {
            webView.goBack()
        } else {
            webView.evaluateJavaScript("history.back()", completionHandler: nil)
        }
    }

    func goForward() {
        if webView.canGoForward {
            webView.goForward()
        } else {
            webView.evaluateJavaScript("history.forward()", completionHandler: nil)
        }
    }

    func reload() {
        webView.reload()
    }

    func setMinimized(_ minimized: Bool) {
        // Hook up layout changes here if you want minimized to affect the web view
    }
}

// MARK: - SwiftUI wrapper for SocialWebViewController

private struct SocialCleanerView: UIViewControllerRepresentable {
    let url: URL
    let cleanupScript: String
    @ObservedObject var bridge: SocialWebBridge

    func makeUIViewController(context: Context) -> SocialWebViewController {
        let vc = SocialWebViewController(url: url, cleanupScript: cleanupScript, bridge: bridge)
        bridge.controller = vc
        return vc
    }

    func updateUIViewController(_ uiViewController: SocialWebViewController, context: Context) {}
}

// MARK: - Site configuration

struct SocialSiteConfig {
    let title: String
    let url: URL
    let cleanupScript: String

    // Helper for loading JS from the app bundle
    static func script(named name: String) -> String {
        guard
            let url = Bundle.main.url(forResource: name, withExtension: "js"),
            let data = try? Data(contentsOf: url),
            let string = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return string
    }

    static let instagram = SocialSiteConfig(
        title: "Instagram",
        url: URL(string: "https://www.instagram.com/")!,
        cleanupScript: script(named: "instagram")
    )

    static let reddit = SocialSiteConfig(
        title: "Reddit",
        url: URL(string: "https://www.reddit.com/")!,
        cleanupScript: script(named: "reddit")
    )

    static let linkedin = SocialSiteConfig(
        title: "LinkedIn",
        url: URL(string: "https://www.linkedin.com/feed/")!,
        cleanupScript: script(named: "linkedin")
    )

    static let x = SocialSiteConfig(
        title: "X",
        url: URL(string: "https://x.com/home")!,
        cleanupScript: script(named: "x")
    )

    static let tiktok = SocialSiteConfig(
        title: "TikTok",
        url: URL(string: "https://www.tiktok.com/")!,
        cleanupScript: script(named: "tiktok")
    )
}

// MARK: - Generic SocialSiteView

struct SocialSiteView: View {
    let config: SocialSiteConfig
    @StateObject private var bridge = SocialWebBridge()
    @EnvironmentObject var usageTracker: UsageTracker
    @State private var showLimitAlert = false

    private var trackingScreen: UsageTracker.Screen? {
        switch config.title {
        case "Instagram": return .instagram
        case "Reddit": return .reddit
        case "LinkedIn": return .linkedin
        //case "X": return .x
        //case "TikTok": return .tiktok
        default: return nil
        }
    }

    var body: some View {
        SocialCleanerView(
            url: config.url,
            cleanupScript: config.cleanupScript,
            bridge: bridge
        )
        .navigationTitle(config.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let s = trackingScreen {
                usageTracker.enter(s)
                if usageTracker.isOverSocialLimit(for: s) {
                    showLimitAlert = true
                }
            }
        }
        .onDisappear { if let s = trackingScreen { usageTracker.leave(s) } }
        .alert("Time Check", isPresented: $showLimitAlert) {
            Button("Keep Going") { }
        } message: {
            Text("You've reached your daily social time goal. Want to keep going?")
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !bridge.isMinimized {
                    HStack(spacing: 12) {
                        Button(action: { bridge.goBack() }) {
                            Image(systemName: "chevron.left")
                        }
                        Button(action: { bridge.goForward() }) {
                            Image(systemName: "chevron.right")
                        }
                        Button(action: { bridge.reload() }) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        bridge.toggleMinimized()
                    }
                }) {
                    Image(systemName: bridge.isMinimized
                          ? "arrow.down.backward.and.arrow.up.forward"
                          : "arrow.up.forward.and.arrow.down.backward")
                }
            }
        }
    }
}
#if DEBUG
#Preview("Social View") {
    PreviewWrapper {
        SocialView()
    }
}
#endif

