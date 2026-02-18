//
//  SettingsView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/13/26.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: NewsViewModel
    @State private var draftSettings: AppSettings = AppSettings.load()
    @State private var newTagText: String = ""

    var body: some View {
        Form {
            languageAndCountrySection

            Section(header: Text("Sources")) {
                NavigationLink("Manage sources") {
                    SourcesSettingsView(viewModel: viewModel)
                }
            }

            displaySection
            interestsSection
        }
        .navigationTitle("Settings")
        .onAppear {
            draftSettings = viewModel.settings
        }
        .onDisappear {
            applyChanges()
        }
    }

    // MARK: - Display

    private var displaySection: some View {
        Section("Display") {
            Toggle("Show images in list", isOn: $draftSettings.showImages)
            Toggle("Show descriptions in list", isOn: $draftSettings.showDescriptions)

            // Toggle for inline article view in detail
            Toggle("Show inline article view", isOn: $draftSettings.enableInLineView)

            Toggle("Ask before removing saved articles", isOn: $draftSettings.confirmUnsaveInSavedTab)
        }
    }

    // MARK: - Combined languages + countries

    private var languageAndCountrySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Languages (max 5)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(NewsLanguage.allCases) { lang in
                    let isOn = draftSettings.languages.contains(lang)
                    Toggle(isOn: Binding(
                        get: { isOn },
                        set: { newValue in
                            if newValue {
                                if !draftSettings.languages.contains(lang),
                                   draftSettings.languages.count < 5 {
                                    draftSettings.languages.append(lang)
                                }
                            } else {
                                draftSettings.languages.removeAll { $0 == lang }
                            }
                        })
                    ) {
                        Text(lang.displayName)
                    }
                }

                Divider()

                Text("Countries (max 5)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(NewsCountry.allCases) { country in
                    let isOn = draftSettings.countries.contains(country)
                    Toggle(isOn: Binding(
                        get: { isOn },
                        set: { newValue in
                            if newValue {
                                if !draftSettings.countries.contains(country),
                                   draftSettings.countries.count < 5 {
                                    draftSettings.countries.append(country)
                                }
                            } else {
                                draftSettings.countries.removeAll { $0 == country }
                            }
                        })
                    ) {
                        Text(country.displayName)
                    }
                }
            }
        } header: {
            Text("Regions & languages")
        }
    }

    // MARK: - Interests

    private var interestsSection: some View {
        Section("Your interests") {
            if viewModel.tagWeights.isEmpty {
                Text("No preferences yet. Swipe on articles to like or dislike them.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(
                    viewModel.tagWeights
                        .sorted(by: { $0.value > $1.value }),
                    id: \.key
                ) { tag, weight in
                    HStack {
                        Text(tag)
                        Spacer()
                        Stepper(
                            value: Binding(
                                get: { Int(weight) },
                                set: { newValue in
                                    viewModel.setWeight(Double(newValue), for: tag)
                                }
                            ),
                            in: -10...10
                        ) {
                            Text(String(format: "%.0f", weight))
                                .monospacedDigit()
                        }
                        .frame(width: 120)
                    }
                }
                .onDelete(perform: deleteTags)

                addTagRow

                Text("These include broad categories and AI-generated niche topics. Adjust to personalize your feed.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var addTagRow: some View {
        HStack {
            TextField("Add topic (e.g. technology)", text: $newTagText)
            Button("Add") {
                let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                viewModel.addTag(trimmed)
                newTagText = ""
            }
        }
    }

    private func deleteTags(at offsets: IndexSet) {
        let sortedKeys = viewModel.tagWeights
            .sorted(by: { $0.value > $1.value })
            .map { $0.key }
        for index in offsets {
            let tag = sortedKeys[index]
            viewModel.removeTag(tag)
        }
    }

    private func applyChanges() {
        viewModel.settings = draftSettings
        viewModel.settings.save()
        Task {
            await viewModel.refreshIfAllowed(ignoreCooldown: true)
        }
    }
}
