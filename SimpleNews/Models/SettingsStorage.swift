//
//  SettingsStorage.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/13/26.
//

import SwiftUI

private let settingsKey = "appSettings"

extension AppSettings {
    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey) else {
            return AppSettings()
        }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            Log.data.error("SettingsStorage: decode failed – \(error)")
            return AppSettings()
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }
}
