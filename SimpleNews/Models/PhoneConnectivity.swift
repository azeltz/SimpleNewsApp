//
//  PhoneConnectivity.swift
//  SimpleNews
//
//  Handles iPhone ↔ Watch communication.
//  Receives "toggleSaved" commands from the watch and updates
//  the local saved-articles store. Sends the current set of
//  saved article IDs back to the watch via applicationContext.
//

import Foundation
import WatchConnectivity

final class PhoneSessionManager: NSObject, WCSessionDelegate {
    static let shared = PhoneSessionManager()

    /// Called on the main actor when a toggle-saved command arrives from the watch.
    /// The app entry point should set this to wire into NewsViewModel.toggleSaved.
    var onToggleSavedFromWatch: ((_ id: String, _ title: String, _ source: String, _ urlString: String, _ publishedAt: Date?, _ shouldSave: Bool) -> Void)?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Push the current set of saved article IDs, AI summary, and settings to the watch.
    /// Call this whenever the saved list changes on iOS.
    func sendSavedIDsToWatch(_ ids: [String]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let settings = AppSettings.load()
        var context: [String: Any] = [
            "savedIDs": ids,
            "enableAISummary": settings.enableAISummary,
            "userId": UserIdManager.current
        ]

        // Include cached AI summary if available
        if let summary = PhoneSessionManager.cachedAISummary, !summary.isEmpty {
            context["aiSummary"] = summary
        }

        do {
            try session.updateApplicationContext(context)
        } catch {
            Log.watch.error("Phone: failed to update applicationContext: \(error.localizedDescription)")
        }
    }

    /// Cached AI summary text to send to Watch. Set by the app when a summary is generated.
    static var cachedAISummary: String?

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            Log.watch.error("Phone WCSession activation error: \(error.localizedDescription)")
        }
        // Send current saved IDs to watch on activation
        if activationState == .activated {
            let ids = SavedArticlesStorage.load().map(\.id)
            sendSavedIDsToWatch(ids)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate for watch switching
        session.activate()
    }

    /// Receive toggle-saved command from watch via sendMessage (no reply).
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncomingMessage(message)
    }

    /// Receive toggle-saved command from watch via sendMessage (with reply).
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handleIncomingMessage(message)
        replyHandler(["status": "ok"])
    }

    /// Receive toggle-saved command from watch via transferUserInfo (offline delivery).
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleIncomingMessage(userInfo)
    }

    private func handleIncomingMessage(_ message: [String: Any]) {
        guard let action = message["action"] as? String, action == "toggleSaved" else { return }

        let id = message["id"] as? String ?? ""
        let title = message["title"] as? String ?? ""
        let source = message["source"] as? String ?? ""
        let urlString = message["urlString"] as? String ?? ""
        let descriptionText = message["description"] as? String ?? ""
        let shouldSave = message["isSaved"] as? Bool ?? true
        let publishedAt: Date? = (message["publishedAt"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }

        // Always persist directly to SavedArticlesStorage so saves work
        // even when the main app UI isn't loaded (background wake).
        var saved = SavedArticlesStorage.load()
        if shouldSave {
            if !saved.contains(where: { $0.id == id }) {
                let article = SavedArticle(
                    id: id,
                    title: title,
                    description: descriptionText.isEmpty ? nil : descriptionText,
                    imageURL: nil,
                    source: source.isEmpty ? nil : source,
                    publishedAt: publishedAt,
                    url: urlString.isEmpty ? nil : URL(string: urlString)
                )
                saved.append(article)
                SavedArticlesStorage.save(saved)
            }
        } else {
            if let idx = saved.firstIndex(where: { $0.id == id }) {
                saved.remove(at: idx)
                SavedArticlesStorage.save(saved)
            }
        }

        // Sync updated IDs back to watch immediately
        let ids = saved.map(\.id)
        sendSavedIDsToWatch(ids)

        // Also notify the live UI if the app is in the foreground
        DispatchQueue.main.async { [weak self] in
            self?.onToggleSavedFromWatch?(id, title, source, urlString, publishedAt, shouldSave)
        }
    }
}
