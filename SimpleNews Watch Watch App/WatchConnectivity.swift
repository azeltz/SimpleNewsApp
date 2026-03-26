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

    /// Replay the most recent applicationContext that may have arrived
    /// before the view model was attached. Call once after `attach(viewModel:)`.
    func replayPendingContext() {
        guard WCSession.isSupported() else { return }
        let ctx = WCSession.default.receivedApplicationContext
        guard !ctx.isEmpty else { return }
        applyContext(ctx)
    }

    // MARK: - Send toggle saved command to iPhone

    func toggleSaved(headline: WatchHeadline) {
        let newSaved = !headline.isSaved

        // Update local state immediately for responsive UI
        Task { @MainActor in
            viewModel?.markSaved(id: headline.id, isSaved: newSaved)
        }

        // Send command to iPhone
        var message: [String: Any] = [
            "action": "toggleSaved",
            "id": headline.id,
            "title": headline.title,
            "source": headline.source ?? "",
            "urlString": headline.urlString ?? "",
            "description": headline.description ?? "",
            "isSaved": newSaved
        ]
        if let date = headline.publishedAt {
            message["publishedAt"] = date.timeIntervalSince1970
        }

        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(message, replyHandler: { _ in
                // iPhone confirmed receipt
            }) { error in
                // sendMessage failed, falling back to transferUserInfo
                // Fall back to guaranteed delivery
                session.transferUserInfo(message)
            }
        } else {
            // Fall back to transferUserInfo for delivery when iPhone becomes reachable
            session.transferUserInfo(message)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            // WCSession activation error is expected in some environments
        }
    }

    /// Receive updated saved IDs, AI summary, and settings from iPhone via applicationContext.
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyContext(applicationContext)
    }

    /// Also handle applicationContext on activation (for initial sync).
    func sessionReachabilityDidChange(_ session: WCSession) {
        applyContext(session.receivedApplicationContext)
    }

    private func applyContext(_ context: [String: Any]) {
        let ids = context["savedIDs"] as? [String]
        let summary = context["aiSummary"] as? String
        let enableAISummary = context["enableAISummary"] as? Bool ?? true
        let userId = context["userId"] as? String

        Task { @MainActor in
            if let ids {
                viewModel?.savedIDs = Set(ids)
                viewModel?.refreshSavedFlags()
            }
            viewModel?.aiSummary = summary
            viewModel?.enableAISummary = enableAISummary
            if let userId {
                viewModel?.userId = userId
            }
        }
    }
}
