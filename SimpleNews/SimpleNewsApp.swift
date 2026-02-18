//
//  SimpleNewsApp.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/1/25.
//

import SwiftUI
import SwiftData

@main
struct SimpleNewsApp: App {
    @StateObject private var newsViewModel = NewsViewModel()

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack {
                    HomeView(viewModel: newsViewModel)
                }
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

                NavigationStack {
                    SavedView(viewModel: newsViewModel)
                }
                .tabItem {
                    Label("Saved", systemImage: "bookmark.fill")
                }

                NavigationStack {
                    SettingsView(viewModel: newsViewModel)
                }
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
            }
            // Make selected tab clearly blue, not gray
            .tint(Color.blue)
        }
    }
}
