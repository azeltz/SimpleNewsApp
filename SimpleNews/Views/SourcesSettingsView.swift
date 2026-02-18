//
//  SourcesSettingsView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/18/26.
//

import SwiftUI
import UIKit

struct NewsSourcesSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @ObservedObject var viewModel: NewsViewModel

    @State private var draftSettings: AppSettings = AppSettings.load()

    // Preferred domains (Newsdata + quality mode)
    @State private var newSourceDomain: String = ""

    // Backend feeds state (RSS worker)
    @State private var feedId: String = ""
    @State private var feedURL: String = ""
    @State private var feedSource: String = ""
    @State private var selectedKind: String = "periodic"
    @State private var isCustomKind: Bool = false
    @State private var customKindName: String = ""
    @State private var customHour: Int = 12
    @State private var customMinute: Int = 0
    @State private var backendSourceStatus: String?
    @State private var backendFeeds: [BackendFeed] = []
    @State private var isLoadingBackendFeeds = false

    private let predefinedKinds = [
        "breaking",
        "critical",
        "top",
        "important",
        "consistent",
        "periodic",
        "social",
        "morning_daily"
    ]

    var body: some View {
        Form {
            rssSection
            newsdataSection
        }
        .navigationTitle("News Sources")
        .onAppear {
            draftSettings = settingsStore.settings
            Task { await loadBackendFeeds() }
        }
        .onDisappear {
            applyChanges()
        }
    }

    // MARK: - RSS section

    private var rssSection: some View {
        Section("RSS") {
            // RSS toggle
            Toggle("Include RSS articles", isOn: $draftSettings.enableRSS)

            if draftSettings.enableRSS {
                // Existing backend sources
                if isLoadingBackendFeeds {
                    Text("Loading current backend sources...")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else if backendFeeds.isEmpty {
                    Text("No backend sources configured yet.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    DisclosureGroup("Show existing backend sources") {
                        ForEach(backendFeeds) { feed in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feed.id)
                                    .font(.subheadline)
                                Text(feed.url)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                Text("\(feed.source) • kind: \(feed.kind)\(scheduleLabel(feed.schedule))")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Feed ID
                VStack(alignment: .leading, spacing: 4) {
                    Text("Feed ID")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        TextField("e.g. user_custom_1", text: $feedId)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)

                        HStack(spacing: 6) {
                            PasteButton(payloadType: String.self) { strings in
                                if let first = strings.first {
                                    feedId = first.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                            }
                            .labelStyle(.iconOnly)
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            Button {
                                feedId = ""
                            } label: {
                                Image(systemName: "xmark")
                                    .frame(width: 32, height: 32)
                                    .background(Color(.systemGray5))
                                    .foregroundColor(.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }

                // Feed URL
                VStack(alignment: .leading, spacing: 4) {
                    Text("Feed URL")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        TextField("https://example.com/rss", text: $feedURL)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.URL)
                            .autocapitalization(.none)

                        HStack(spacing: 6) {
                            PasteButton(payloadType: String.self) { strings in
                                if let first = strings.first {
                                    feedURL = first.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                            }
                            .labelStyle(.iconOnly)
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            Button {
                                feedURL = ""
                            } label: {
                                Image(systemName: "xmark")
                                    .frame(width: 32, height: 32)
                                    .background(Color(.systemGray5))
                                    .foregroundColor(.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }

                // Source domain
                VStack(alignment: .leading, spacing: 4) {
                    Text("Source domain")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        TextField("example.com", text: $feedSource)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)

                        HStack(spacing: 6) {
                            PasteButton(payloadType: String.self) { strings in
                                if let first = strings.first {
                                    feedSource = first
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                        .lowercased()
                                }
                            }
                            .labelStyle(.iconOnly)
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            Button {
                                feedSource = ""
                            } label: {
                                Image(systemName: "xmark")
                                    .frame(width: 32, height: 32)
                                    .background(Color(.systemGray5))
                                    .foregroundColor(.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }

                .padding(.vertical, 4)

                Toggle("Use custom schedule", isOn: $isCustomKind)

                if isCustomKind {
                    TextField("Custom kind name (e.g. morning_7am)", text: $customKindName)
                        .autocapitalization(.none)

                    Stepper("Hour (UTC): \(customHour)", value: $customHour, in: 0...23)
                    Stepper("Minute (UTC): \(customMinute)", value: $customMinute, in: 0...59)
                } else {
                    Picker("Kind", selection: $selectedKind) {
                        ForEach(predefinedKinds, id: \.self) { kind in
                            Text(kind)
                        }
                    }
                }

                Button("Add source to backend") {
                    Task { await addBackendSource() }
                }

                if let status = backendSourceStatus {
                    Text(status)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Newsdata section

    private var newsdataSection: some View {
        Section("Newsdata") {
            // Newsdata toggle
            Toggle("Include Newsdata articles", isOn: $draftSettings.enableNewsdata)

            if draftSettings.enableNewsdata {
                // Quality + preferred domains
                Toggle("Quality mode (use only preferred / top sources)", isOn: $draftSettings.qualityMode)

                Text("When on, results are limited to your preferred domains if set, or a small set of top outlets, with less variety but higher consistency.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if draftSettings.preferredSources.isEmpty {
                    Text("Preferred domains (optional): add sources like nytimes.com, apnews.com, haaretz.com. In quality mode, only these will be used if set.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(draftSettings.preferredSources, id: \.self) { domain in
                        Text(domain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    draftSettings.preferredSources.removeAll { $0 == domain }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }

                HStack {
                    TextField("Add domain (e.g. reuters.com)", text: $newSourceDomain)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Button("Add") {
                        let trimmed = newSourceDomain
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased()
                        guard !trimmed.isEmpty else { return }
                        if !draftSettings.preferredSources.contains(trimmed) {
                            draftSettings.preferredSources.append(trimmed)
                        }
                        newSourceDomain = ""
                    }
                }
            }
        }
    }


    // MARK: - Helpers

    private func scheduleLabel(_ schedule: BackendFeed.Schedule?) -> String {
        guard let schedule = schedule else { return "" }
        if let timeUTC = schedule.timeUTC {
            return " • timeUTC: \(timeUTC)"
        }
        if let minutes = schedule.minutes {
            return " • every \(minutes)m"
        }
        return ""
    }

    private func applyChanges() {
        settingsStore.settings = draftSettings
        settingsStore.settings.save()
        Task { await viewModel.refreshIfAllowed(ignoreCooldown: true) }
    }

    private func loadBackendFeeds() async {
        let url = URL(string: "https://rss-aggregator.simplenews.workers.dev/feeds")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        await MainActor.run { isLoadingBackendFeeds = true }
        defer { Task { @MainActor in isLoadingBackendFeeds = false } }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }

            struct FeedsResponse: Codable { let feeds: [BackendFeed] }
            let decoded = try JSONDecoder().decode(FeedsResponse.self, from: data)
            await MainActor.run { backendFeeds = decoded.feeds }
        } catch {
            // optional: set status
        }
    }

    private func addBackendSource() async {
        guard
            !feedId.isEmpty,
            let url = URL(string: feedURL),
            !feedSource.isEmpty
        else {
            await MainActor.run {
                backendSourceStatus = "Please fill all fields with valid values."
            }
            return
        }

        let kindToSend: String
        var schedule: [String: Any]? = nil

        if isCustomKind, !customKindName.isEmpty {
            kindToSend = customKindName
            let timeUTC = String(format: "%02d:%02d", customHour, customMinute)
            schedule = ["timeUTC": timeUTC]
        } else {
            kindToSend = selectedKind
        }

        let workerURL = URL(string: "https://rss-aggregator.simplenews.workers.dev/feeds")!
        var request = URLRequest(url: workerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var feedDict: [String: Any] = [
            "id": feedId,
            "url": url.absoluteString,
            "source": feedSource,
            "kind": kindToSend,
        ]
        if let schedule = schedule {
            feedDict["schedule"] = schedule
        }

        let payload: [String: Any] = ["feeds": [feedDict]]

        do {
            let body = try JSONSerialization.data(withJSONObject: payload, options: [])
            request.httpBody = body

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                await MainActor.run { backendSourceStatus = "Bad response from server." }
                return
            }
            guard (200...299).contains(http.statusCode) else {
                await MainActor.run { backendSourceStatus = "Server error \(http.statusCode)" }
                return
            }

            if
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let ok = json["ok"] as? Bool,
                ok == true
            {
                await MainActor.run {
                    backendSourceStatus = "Source added successfully."
                    feedId = ""
                    feedURL = ""
                    feedSource = ""
                    customKindName = ""
                    isCustomKind = false
                }
                await loadBackendFeeds()
            } else {
                await MainActor.run {
                    backendSourceStatus = "Unexpected response from server."
                }
            }
        } catch {
            await MainActor.run {
                backendSourceStatus = "Network error: \(error.localizedDescription)"
            }
        }
    }
}

struct SocialSourcesSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var draftSettings: AppSettings = AppSettings.load()

    var body: some View {
        Form {
            Section("Social sources") {
                Toggle("Show Instagram", isOn: $draftSettings.showInstagram)
                    .onChange(of: draftSettings.showInstagram) {
                        applyChanges()
                    }

                Toggle("Show X (Twitter)", isOn: $draftSettings.showX)
                    .onChange(of: draftSettings.showX) {
                        applyChanges()
                    }

                Toggle("Show Reddit", isOn: $draftSettings.showReddit)
                    .onChange(of: draftSettings.showReddit) {
                        applyChanges()
                    }

                Toggle("Show TikTok", isOn: $draftSettings.showTikTok)
                    .onChange(of: draftSettings.showTikTok) {
                        applyChanges()
                    }

                Toggle("Show LinkedIn", isOn: $draftSettings.showLinkedIn)
                    .onChange(of: draftSettings.showLinkedIn) {
                        applyChanges()
                    }

                Text("These control which social apps appear under the Social tab. Hiding a source does not affect your accounts or logins.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("Social sources")
        .onAppear {
            draftSettings = settingsStore.settings
        }
        .onDisappear {
            applyChanges()
        }
    }

    private func applyChanges() {
        settingsStore.settings = draftSettings
        settingsStore.settings.save()
    }
}
