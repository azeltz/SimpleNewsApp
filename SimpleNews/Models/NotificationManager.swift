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

    func scheduleDailyDigest(hour: Int, minute: Int) {
        // Remove any existing daily digest notification
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyDigestIdentifier])

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = "Your Daily News Digest"
        content.body = "Tap to see today's top stories and AI summary."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.dailyDigestIdentifier,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("Failed to schedule daily digest: \(error.localizedDescription)")
            }
        }
    }

    func cancelDailyDigest() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyDigestIdentifier])
    }

    // MARK: - Breaking News Alerts

    /// Posts a local notification for a breaking article from a tracked source.
    func postBreakingAlert(title: String, source: String) {
        let content = UNMutableNotificationContent()
        content.title = "Breaking: \(source)"
        content.body = title
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "breaking-\(UUID().uuidString)",
            content: content,
            trigger: nil // deliver immediately
        )

        center.add(request) { error in
            if let error {
                print("Failed to post breaking alert: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Sync settings

    /// Call this when notification settings change to update scheduled notifications.
    func syncWithSettings(_ settings: AppSettings) {
        if settings.enableDailyDigest && isAuthorized {
            scheduleDailyDigest(hour: settings.dailyDigestHour, minute: settings.dailyDigestMinute)
        } else {
            cancelDailyDigest()
        }
    }
}
