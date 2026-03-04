//
//  UsageTracker.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/3/26.
//

import Foundation

/// Tracks time spent in different app sections per calendar day.
@MainActor
final class UsageTracker: ObservableObject {
    enum Screen: String, CaseIterable, Codable {
        case news = "News"
        case instagram = "Instagram"
        case reddit = "Reddit"
        case linkedin = "LinkedIn"
        case x = "X"
        case tiktok = "TikTok"
    }

    struct DaySummary: Codable {
        var date: String // yyyy-MM-dd
        var seconds: [String: TimeInterval] // Screen.rawValue -> seconds
    }

    // MARK: - Published state

    @Published private(set) var history: [DaySummary] = []

    // MARK: - Internal tracking

    private var activeScreens: [Screen: Date] = [:]

    private static let storageKey = "usageTrackerHistory"
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init() {
        loadHistory()
    }

    // MARK: - Enter / Leave

    func enter(_ screen: Screen) {
        guard activeScreens[screen] == nil else { return }
        activeScreens[screen] = Date()
    }

    func leave(_ screen: Screen) {
        guard let start = activeScreens.removeValue(forKey: screen) else { return }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 1 else { return } // ignore sub-second visits
        addSeconds(elapsed, for: screen)
    }

    // MARK: - Queries

    func todaySummary() -> [Screen: TimeInterval] {
        let todayKey = Self.dateFormatter.string(from: Date())
        guard let day = history.first(where: { $0.date == todayKey }) else { return [:] }
        var result: [Screen: TimeInterval] = [:]
        for (key, val) in day.seconds {
            if let screen = Screen(rawValue: key) {
                result[screen] = val
            }
        }
        return result
    }

    func last7Days() -> [DaySummary] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return history.filter { summary in
            if let d = Self.dateFormatter.date(from: summary.date) {
                return cal.dateComponents([.day], from: d, to: today).day ?? 99 < 7
            }
            return false
        }
    }

    // MARK: - Soft limits

    var newsLimitMinutes: Int {
        get { UserDefaults.standard.integer(forKey: "usageLimitNews") }
        set { UserDefaults.standard.set(newValue, forKey: "usageLimitNews"); objectWillChange.send() }
    }

    var socialLimitMinutes: Int {
        get { UserDefaults.standard.integer(forKey: "usageLimitSocial") }
        set { UserDefaults.standard.set(newValue, forKey: "usageLimitSocial"); objectWillChange.send() }
    }

    func isOverNewsLimit() -> Bool {
        guard newsLimitMinutes > 0 else { return false }
        let today = todaySummary()
        let newsSeconds = today[.news] ?? 0
        return newsSeconds / 60 >= Double(newsLimitMinutes)
    }

    func isOverSocialLimit(for screen: Screen) -> Bool {
        guard socialLimitMinutes > 0 else { return false }
        let today = todaySummary()
        let socialScreens: [Screen] = [.instagram, .reddit, .linkedin, .x, .tiktok]
        let totalSocial = socialScreens.reduce(0.0) { $0 + (today[$1] ?? 0) }
        return totalSocial / 60 >= Double(socialLimitMinutes)
    }

    // MARK: - Persistence

    private func addSeconds(_ seconds: TimeInterval, for screen: Screen) {
        let todayKey = Self.dateFormatter.string(from: Date())
        if let idx = history.firstIndex(where: { $0.date == todayKey }) {
            history[idx].seconds[screen.rawValue, default: 0] += seconds
        } else {
            history.append(DaySummary(date: todayKey, seconds: [screen.rawValue: seconds]))
        }
        // Keep only last 30 days
        if history.count > 30 {
            history = Array(history.suffix(30))
        }
        saveHistory()
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([DaySummary].self, from: data) else { return }
        history = decoded
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
