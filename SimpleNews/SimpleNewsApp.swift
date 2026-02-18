//
//  SimpleNewsApp.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/1/25.
//

import SwiftUI
import SwiftData

import Combine

final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings = AppSettings.load()

    func save() {
        settings.save()
    }
}

@main
struct SimpleNewsApp: App {
    @StateObject private var newsViewModel = NewsViewModel()
    @StateObject private var settingsStore = SettingsStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack {
                    HomeView(viewModel: newsViewModel)
                }
                .tabItem { Label("Home", systemImage: "house.fill") }

                NavigationStack {
                    SavedView(viewModel: newsViewModel)
                }
                .tabItem { Label("Saved", systemImage: "bookmark.fill") }

                if settingsStore.settings.showSocialTab {
                    NavigationStack {
                        SocialView()
                    }
                    .tabItem { Label("Social", systemImage: "person.2.fill") }
                    .transition(.opacity)
                }

                NavigationStack {
                    SettingsView(viewModel: newsViewModel)
                }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            }
            .environmentObject(settingsStore)
            .tint(.blue)
        }
    }
}
