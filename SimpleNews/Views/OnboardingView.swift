//
//  OnboardingView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/3/26.
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @ObservedObject var sourcesStore: UserSourcesStore
    let onComplete: () -> Void

    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            welcomePage.tag(0)
            sourcesPage.tag(1)
            socialPage.tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "newspaper.fill")
                .font(.system(size: 72))
                .foregroundStyle(.blue)
            Text("Welcome to SimpleNews")
                .font(.largeTitle).bold()
            Text("Your cleaned-up news feed in one place. No clutter, no noise — just the stories that matter to you.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            Button("Next") { withAnimation { page = 1 } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Spacer().frame(height: 40)
        }
    }

    // MARK: - Page 2: Choose sources

    private var sourcesPage: some View {
        VStack(spacing: 16) {
            Text("Choose your news sources")
                .font(.title2).bold()
                .padding(.top, 32)

            Text("Toggle the feeds you want. You can always change these later in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            List {
                ForEach($sourcesStore.defaults) { $feed in
                    Toggle(isOn: $feed.isEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feed.displayName ?? feed.source)
                                .font(.body)
                            Text(feed.source)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)

            Button("Next") { withAnimation { page = 2 } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 24)
        }
    }

    // MARK: - Page 3: Social apps

    private var socialPage: some View {
        VStack(spacing: 16) {
            Text("Social apps")
                .font(.title2).bold()
                .padding(.top, 32)

            Text("SimpleNews includes cleaned-up social browsers. Choose which ones to show in the Social tab.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            List {
                Toggle("Instagram", isOn: Binding(
                    get: { settingsStore.settings.showInstagram },
                    set: { settingsStore.settings.showInstagram = $0 }
                ))
                Toggle("Reddit", isOn: Binding(
                    get: { settingsStore.settings.showReddit },
                    set: { settingsStore.settings.showReddit = $0 }
                ))
                Toggle("LinkedIn", isOn: Binding(
                    get: { settingsStore.settings.showLinkedIn },
                    set: { settingsStore.settings.showLinkedIn = $0 }
                ))
                Toggle("X (Twitter)", isOn: Binding(
                    get: { settingsStore.settings.showX },
                    set: { settingsStore.settings.showX = $0 }
                ))
                Toggle("TikTok", isOn: Binding(
                    get: { settingsStore.settings.showTikTok },
                    set: { settingsStore.settings.showTikTok = $0 }
                ))
            }
            .listStyle(.plain)

            Button("Get Started") {
                settingsStore.save()
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 24)
        }
    }
}
