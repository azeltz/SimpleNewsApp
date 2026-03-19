//
//  SimpleNewsApp.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/1/25.
//

import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks

final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings = AppSettings.load()

    func save() {
        settings.save()
    }
}

@main
struct SimpleNewsApp: App {
    @StateObject private var newsViewModel = NewsViewModel()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var sourcesStore = UserSourcesStore()
    @StateObject private var usageTracker = UsageTracker()
    @StateObject private var importedStore = ImportedArticlesStore()
    @StateObject private var appState = AppState()

    private static let bgRefreshID = "com.simplenews.refresh"

    init() {
        SimpleNewsNotificationDelegate.shared.configure()
        PhoneSessionManager.shared.activate()
        registerBackgroundTask()

        // Cap URLCache disk usage to 20 MB to reduce Documents & Data footprint
        URLCache.shared = URLCache(
            memoryCapacity: 4 * 1024 * 1024,   // 4 MB memory
            diskCapacity: 20 * 1024 * 1024,     // 20 MB disk
            diskPath: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            if settingsStore.settings.hasCompletedOnboarding {
                mainTabView
            } else {
                OnboardingView(sourcesStore: sourcesStore) {
                    settingsStore.settings.hasCompletedOnboarding = true
                    settingsStore.save()
                    Task {
                        await sourcesStore.syncFeedsToServer()
                        await newsViewModel.fetchArticles()
                    }
                }
                .environmentObject(settingsStore)
            }
        }
    }

    private var mainTabView: some View {
        TabView {
            NavigationStack {
                HomeView(viewModel: newsViewModel)
            }
            .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack {
                SavedView(viewModel: newsViewModel)
            }
            .tabItem { Label("Saved", systemImage: "bookmark.fill") }

            if settingsStore.settings.showSocialTab {
                NavigationStack {
                    SocialView()
                }
                .tabItem { Label("Social", systemImage: "person.2.fill") }
                .transition(.opacity)
            }

            NavigationStack {
                SettingsView(viewModel: newsViewModel)
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .environmentObject(settingsStore)
        .environmentObject(sourcesStore)
        .environmentObject(usageTracker)
        .environmentObject(importedStore)
        .environmentObject(appState)
        .tint(.blue)
        .task {
            // Notification + background refresh setup
            await NotificationManager.shared.refreshAuthorizationStatus()
            NotificationManager.shared.syncWithSettings(settingsStore.settings)

            if settingsStore.settings.enableBackgroundRefresh {
                Self.scheduleAppRefresh()
            }

            // WatchConnectivity: handle saves from watch
            setupWatchConnectivity()

            // Send current saved IDs to watch on launch
            SimpleNewsApp.syncSavedIDsToWatch()
        }
        .onChange(of: newsViewModel.articles.count) {
            // When articles load, generate AI summary and cache it for the Watch
            Task {
                let groups = newsViewModel.groupedArticles
                guard !groups.isEmpty else { return }
                if let summary = try? await SummaryService.summarize(groups: groups) {
                    PhoneSessionManager.cachedAISummary = summary
                    SimpleNewsApp.syncSavedIDsToWatch()
                }
            }
        }
    }

    // MARK: - WatchConnectivity integration

    private func setupWatchConnectivity() {
        let vm = newsViewModel
        PhoneSessionManager.shared.onToggleSavedFromWatch = { _, _, _, _, _, _ in
            // PhoneSessionManager already persisted to SavedArticlesStorage
            // and synced IDs back to Watch. Just refresh the live UI.
            vm.reloadSavedArticles()
        }
    }

    static func syncSavedIDsToWatch() {
        let ids = SavedArticlesStorage.load().map(\.id)
        PhoneSessionManager.shared.sendSavedIDsToWatch(ids)
    }

    // MARK: - Background Refresh

    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.bgRefreshID,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Self.handleAppRefresh(task: refreshTask)
        }
    }

    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: bgRefreshID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // 30 minutes
        do {
            try BGTaskScheduler.shared.submit(request)
            Log.bg.debug("Background refresh scheduled successfully")
        } catch let error as BGTaskScheduler.Error where error.code == .unavailable {
            // Expected on Simulator — BGAppRefreshTask only works on device
            Log.bg.info("Background refresh unavailable (Simulator)")
        } catch {
            Log.bg.error("Failed to schedule app refresh: \(error)")
        }
    }

    private static func handleAppRefresh(task: BGAppRefreshTask) {
        let settings = AppSettings.load()

        // Reschedule next refresh if enabled
        if settings.enableBackgroundRefresh {
            scheduleAppRefresh()
        }

        let fetchTask = Task {
            do {
                // Fetch latest articles
                let client = RSSBackendClient()
                let (articles, _) = try await client.fetchArticles()

                // Generate a 25-word summary for the daily digest notification
                let groups = ArticleGrouper.group(articles)
                let shortSummary = Self.generateShortSummary(from: groups)

                await MainActor.run {
                    NotificationManager.shared.cachedShortSummary = shortSummary
                    // Reschedule daily digest with fresh summary
                    NotificationManager.shared.syncWithSettings(settings)
                }

                // Sync saved IDs to watch
                Self.syncSavedIDsToWatch()

                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            fetchTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// Generate a ~25-word summary from the top article groups.
    private static func generateShortSummary(from groups: [ArticleGroup]) -> String {
        let top = groups.prefix(3)
        if top.isEmpty { return "Check SimpleNews for the latest headlines." }

        let titles = top.map { $0.canonicalTitle }
        var summary = "Today: " + titles.joined(separator: ". ") + "."

        // Trim to roughly 25 words
        let words = summary.split(separator: " ")
        if words.count > 25 {
            summary = words.prefix(25).joined(separator: " ") + "..."
        }

        return summary
    }
}
