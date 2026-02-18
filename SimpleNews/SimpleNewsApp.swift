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

                if newsViewModel.settings.showSocialTab {
                    NavigationStack {
                        SocialView(viewModel: newsViewModel)
                    }
                    .tabItem {
                        Label("Social", systemImage: "person.2.fill")
                    }
                    .transition(.opacity)
                }

                NavigationStack {
                    SettingsView(viewModel: newsViewModel)
                }
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
            }
            .tint(Color.blue)
            .animation(.easeInOut(duration: 0.25), value: newsViewModel.settings.showSocialTab)
        }
    }
}
