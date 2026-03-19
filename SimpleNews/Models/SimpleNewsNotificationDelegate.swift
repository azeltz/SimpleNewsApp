//
//  SimpleNewsNotificationDelegate.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/4/26.
//

import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    static let openArticleFromNotification = Notification.Name("openArticleFromNotification")
    static let openDailyDigest = Notification.Name("openDailyDigest")
}

final class SimpleNewsNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    static let shared = SimpleNewsNotificationDelegate()

    private override init() {
        super.init()
    }

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let type = userInfo["type"] as? String

        if type == "dailyDigest" {
            // Open the AI summary modal on the home screen
            NotificationCenter.default.post(name: .openDailyDigest, object: nil)
        } else if let articleID = userInfo["articleID"] as? String {
            // Open specific article (breaking news)
            NotificationCenter.default.post(
                name: .openArticleFromNotification,
                object: nil,
                userInfo: ["articleID": articleID]
            )
        }

        completionHandler()
    }

    /// Show notifications even when app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
