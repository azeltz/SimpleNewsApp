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
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcomePage.tag(0)
                sourcesPage.tag(1)
                socialPage.tag(2)
                finishPage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            //.padding(.bottom, 34) // make room for the button bar

//            // Global bottom bar
//            if page == 3 {
//                VStack {
//                    Button("Get Started") {
//                        sourcesStore.persist()
//                        settingsStore.settings.save()
//                        onComplete()
//                    }
//                    .buttonStyle(.borderedProminent)
//                    .controlSize(.large)
//                    .tint(.blue)
//                    .padding(.horizontal, 24)
//                    .padding(.vertical, 12)
//                }
//                .transition(.move(edge: .bottom).combined(with: .opacity))
//                .animation(.easeInOut(duration: 0.25), value: page)
//                .background(Color(.systemBackground).ignoresSafeArea(edges: .bottom))
//            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }


    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "newspaper.fill")
                .font(.system(size: 72))
                .foregroundStyle(.blue)
            Text("Welcome to\nSimpleNews")
                .font(.largeTitle).bold()
            Text("Your cleaned-up news feed in one place. No clutter, no noise — just the stories that matter to you.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Page 2: Choose sources

    private var sourcesPage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Choose your news sources")
                        .font(.title2).bold()
                        .padding(.top, 32)

                    Text("Toggle the feeds you want. You can always change these later in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    VStack(spacing: 24) {
                        ForEach(FeedSource.SourceGroup.allCases, id: \.self) { group in
                            let indices = sourcesStore.defaults.indices.filter {
                                sourcesStore.defaults[$0].sourceGroup == group
                            }
                            if !indices.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(group.rawValue)
                                        .font(.headline)
                                        .padding(.horizontal, 20)

                                    VStack(spacing: 0) {
                                        ForEach(indices, id: \.self) { i in
                                            Toggle(isOn: $sourcesStore.defaults[i].isEnabled) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(sourcesStore.defaults[i].displayName ?? sourcesStore.defaults[i].source)
                                                        .font(.body)
                                                    Text(sourcesStore.defaults[i].source)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 8)

                                            if i != indices.last {
                                                Divider()
                                                    .padding(.leading, 20)
                                            }
                                        }
                                    }
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.secondarySystemBackground))
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Spacer(minLength: 24)
                }
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
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

            SocialSourcesForm(draftSettings: $settingsStore.settings)
                .scrollContentBackground(.hidden)
                .background(Color(.systemBackground))
        }
    }
    
    // MARK: - Page 4: Finish

    private var finishPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)

            Text("You’re all set")
                .font(.largeTitle).bold()

            Text("Your news sources and social apps are configured. You can adjust them anytime in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Spacer()

            Button("Get Started") {
                sourcesStore.persist()
                settingsStore.settings.save()
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.blue)
            .padding(.horizontal, 32)

            Spacer().frame(height: 40)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }


    // MARK: - Helpers

    private func socialToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.body)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}
#if DEBUG
#Preview("Onboarding") {
    PreviewWrapper {
        OnboardingView(
            sourcesStore: UserSourcesStore(),
            onComplete: {}
        )
    }
}
#endif

