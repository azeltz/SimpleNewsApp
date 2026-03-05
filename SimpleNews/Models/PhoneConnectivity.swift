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
    var onToggleSavedFromWatch: ((_ id: String, _ title: String, _ source: String, _ urlString: String, _ shouldSave: Bool) -> Void)?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Push the current set of saved article IDs to the watch.
    /// Call this whenever the saved list changes on iOS.
    func sendSavedIDsToWatch(_ ids: [String]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        do {
            try session.updateApplicationContext(["savedIDs": ids])
        } catch {
            print("Phone: failed to update applicationContext: \(error.localizedDescription)")
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("Phone WCSession activation error: \(error.localizedDescription)")
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

    /// Receive toggle-saved command from watch via sendMessage.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncomingMessage(message)
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
        let shouldSave = message["isSaved"] as? Bool ?? true

        DispatchQueue.main.async { [weak self] in
            self?.onToggleSavedFromWatch?(id, title, source, urlString, shouldSave)
        }
    }
}
