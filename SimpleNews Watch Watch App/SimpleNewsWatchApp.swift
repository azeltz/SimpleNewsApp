//
//  SimpleNewsWatchApp.swift
//  SimpleNewsWatch
//
//  watchOS companion app entry point.
//

import SwiftUI

@main
struct SimpleNewsWatchApp: App {
    @State private var headlinesViewModel = WatchHeadlinesViewModel()

    /// Deep link article ID from complication tap (simplenews://article/<id>)
    @State private var deepLinkArticleID: String?
    /// Whether to show AI summary (simplenews://summary)
    @State private var showSummaryFromDeepLink: Bool = false

    init() {
        // Activate WatchConnectivity early
        WatchSessionManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchHeadlinesListView(
                viewModel: headlinesViewModel,
                deepLinkArticleID: $deepLinkArticleID,
                showSummaryFromDeepLink: $showSummaryFromDeepLink
            )
            .onAppear {
                // Attach the view model and replay any context that arrived
                // between session activation (in init) and first render.
                WatchSessionManager.shared.attach(viewModel: headlinesViewModel)
                WatchSessionManager.shared.replayPendingContext()
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "simplenews" else { return }
        switch url.host {
        case "home":
            // Just open main list (default behavior)
            deepLinkArticleID = nil
            showSummaryFromDeepLink = false
        case "summary":
            showSummaryFromDeepLink = true
        case "article":
            let id = url.pathComponents.dropFirst().first ?? ""
            if !id.isEmpty {
                deepLinkArticleID = id
            }
        default:
            break
        }
    }
}

#if DEBUG
#Preview("Watch App Root") {
    let vm = WatchHeadlinesViewModel()
    vm.headlines = [
        WatchHeadline(
            id: "1",
            title: "Sample headline for watch preview",
            source: "Preview Source",
            publishedAt: Date().addingTimeInterval(-600),
            urlString: nil,
            description: "Sample description for watch preview",
            isSaved: false
        )
    ]
    return WatchHeadlinesListView(
        viewModel: vm,
        deepLinkArticleID: .constant(nil),
        showSummaryFromDeepLink: .constant(false)
    )
}
#endif
