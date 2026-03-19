//
//  NotificationManager.swift
//  SimpleNews
//
//  Handles notification permissions, daily digest scheduling,
//  and source-based breaking news alerts.
//

import Foundation
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized: Bool = false

    private let center = UNUserNotificationCenter.current()

    private init() {
        Task { await refreshAuthorizationStatus() }
    }

    // MARK: - Authorization

    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            isAuthorized = granted
            return granted
        } catch {
            isAuthorized = false
            return false
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Daily Digest

    private static let dailyDigestIdentifier = "com.simplenews.dailyDigest"

    /// Cached 25-word summary for use in digest notification body when
    /// background refresh is on. Updated by the background task handler.
    @Published var cachedShortSummary: String?

    func scheduleDailyDigest(hour: Int, minute: Int, backgroundRefreshOn: Bool) {
        // Remove any existing daily digest notification
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyDigestIdentifier])

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = "Your SimpleNews Daily Digest"

        if backgroundRefreshOn, let summary = cachedShortSummary, !summary.isEmpty {
            // Use the pre-generated 25-word summary
            content.body = summary
        } else {
            // Generic CTA when background refresh is off or no cached summary
            content.body = "Tap to see today's AI-powered daily digest."
        }

        content.sound = .default
        content.userInfo = ["type": "dailyDigest"]

        let request = UNNotificationRequest(
            identifier: Self.dailyDigestIdentifier,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                Log.notify.error("Failed to schedule daily digest: \(error.localizedDescription)")
            }
        }
    }

    func cancelDailyDigest() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyDigestIdentifier])
    }

    // MARK: - Breaking News Alerts

    /// Posts a local notification for a breaking article from a tracked source.
    /// Pass the Article.id so the app can deep-link into that article when the
    /// user taps the notification.
    func postBreakingAlert(for article: Article) {
        let content = UNMutableNotificationContent()

        let source = article.source ?? "SimpleNews"
        content.title = "Breaking: \(article.title)"

        if let description = article.description, !description.isEmpty {
            content.body = "\(description) - \(source)"
        } else {
            content.body = source
        }

        content.sound = .default

        // Include routing info so the app can deep-link on tap
        content.userInfo = [
            "type": "breaking",
            "articleID": article.id
        ]

        let request = UNNotificationRequest(
            identifier: "breaking-\(article.id)",
            content: content,
            trigger: nil // deliver immediately
        )

        center.add(request) { error in
            if let error {
                Log.notify.error("Failed to post breaking alert: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Sync settings

    /// Call this when notification settings change to update scheduled notifications.
    func syncWithSettings(_ settings: AppSettings) {
        if settings.enableDailyDigest && isAuthorized {
            scheduleDailyDigest(
                hour: settings.dailyDigestHour,
                minute: settings.dailyDigestMinute,
                backgroundRefreshOn: settings.enableBackgroundRefresh
            )
        } else {
            cancelDailyDigest()
        }
    }
    
    // MARK: - Debug / Testing

    func scheduleTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "SimpleNews test"
        content.body = "If you see this, notifications are working."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)

        let request = UNNotificationRequest(
            identifier: "com.simplenews.testNotification",
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                Log.notify.error("Failed to schedule test notification: \(error.localizedDescription)")
            } else {
                Log.notify.debug("Test notification scheduled")
            }
        }
    }
}
