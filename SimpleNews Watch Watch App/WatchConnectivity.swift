//
//  WatchConnectivity.swift
//  SimpleNews Watch App
//
//  Handles Watch → iPhone communication for saving articles.
//  The watch sends toggle commands; iOS is the source of truth.
//  iOS sends back the current set of saved IDs via applicationContext.
//

import Foundation
import WatchConnectivity

final class WatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    /// Weak reference to the view model so we can update saved state.
    weak var viewModel: WatchHeadlinesViewModel?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func attach(viewModel: WatchHeadlinesViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Send toggle saved command to iPhone

    func toggleSaved(headline: WatchHeadline) {
        let newSaved = !headline.isSaved

        // Update local state immediately for responsive UI
        Task { @MainActor in
            viewModel?.markSaved(id: headline.id, isSaved: newSaved)
        }

        // Send command to iPhone
        let message: [String: Any] = [
            "action": "toggleSaved",
            "id": headline.id,
            "title": headline.title,
            "source": headline.source ?? "",
            "urlString": headline.urlString ?? "",
            "isSaved": newSaved
        ]

        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("Watch: failed to send toggleSaved: \(error.localizedDescription)")
            }
        } else {
            // Fall back to transferUserInfo for delivery when iPhone becomes reachable
            session.transferUserInfo(message)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("Watch WCSession activation error: \(error.localizedDescription)")
        }
    }

    /// Receive updated saved IDs from iPhone via applicationContext.
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let ids = applicationContext["savedIDs"] as? [String] else { return }
        Task { @MainActor in
            viewModel?.savedIDs = Set(ids)
            viewModel?.refreshSavedFlags()
        }
    }

    /// Also handle applicationContext on activation (for initial sync).
    func sessionReachabilityDidChange(_ session: WCSession) {
        // Check if there's a pending context with saved IDs
        if let ids = session.receivedApplicationContext["savedIDs"] as? [String] {
            Task { @MainActor in
                viewModel?.savedIDs = Set(ids)
                viewModel?.refreshSavedFlags()
            }
        }
    }
}
