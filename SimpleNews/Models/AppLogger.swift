//
//  AppLogger.swift
//  SimpleNews
//
//  Thin wrapper around os.Logger for structured, filterable logging.
//  Messages are visible in Console.app and Instruments but are NOT
//  written to disk in release builds for privacy and performance.
//

import Foundation
import os

enum Log {
    static let general   = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.simplenews", category: "general")
    static let network   = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.simplenews", category: "network")
    static let data      = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.simplenews", category: "data")
    static let ui        = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.simplenews", category: "ui")
    static let tagging   = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.simplenews", category: "tagging")
    static let export    = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.simplenews", category: "export")
    static let watch     = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.simplenews", category: "watch")
    static let notify    = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.simplenews", category: "notifications")
    static let bg        = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.simplenews", category: "background")
}
