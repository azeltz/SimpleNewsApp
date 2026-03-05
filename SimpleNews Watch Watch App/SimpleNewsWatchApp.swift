//
//  SimpleNewsWatchApp.swift
//  SimpleNewsWatch
//
//  watchOS companion app entry point.
//

import SwiftUI

@main
struct SimpleNewsWatchApp: App {
    @StateObject private var headlinesViewModel = WatchHeadlinesViewModel()

    init() {
        // Activate WatchConnectivity early
        WatchSessionManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchHeadlinesListView(viewModel: headlinesViewModel)
                .onAppear {
                    WatchSessionManager.shared.attach(viewModel: headlinesViewModel)
                }
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
    return WatchHeadlinesListView(viewModel: vm)
}
#endif
