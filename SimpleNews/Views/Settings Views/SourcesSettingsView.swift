//
// SourcesSettingsView.swift
// SimpleNews
//
// Created by Amir Zeltzer on 2/18/26.
//

import SwiftUI
import UIKit

struct NewsSourcesSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var sourcesStore: UserSourcesStore
    @ObservedObject var viewModel: NewsViewModel
    @StateObject private var sourcesVM = SourcesViewModel()

    @State private var draftSettings: AppSettings = AppSettings.load()

    // Backend feeds state (RSS worker)
    @State private var backendFeeds: [BackendFeed] = []
    @State private var isLoadingBackendFeeds = false

    // Google News favorites
    @State private var newKeywordText: String = ""
    @State private var isSavingKeywords: Bool = false
    @State private var keywordStatusMessage: String?

    private let rssClient = RSSBackendClient()

    var body: some View {
        Form {
            rssSection
            serverSourcesSection
        }
        .navigationTitle("News Sources")
        .onAppear {
            draftSettings = settingsStore.settings
            Task { await loadBackendFeeds() }
        }
        .task {
            await sourcesVM.loadSources()
        }
        .onChange(of: draftSettings) {
            applyChanges()
        }
        .onDisappear {
            // Refresh the home feed so toggled sources take effect immediately
            Task {
                await viewModel.refreshIfAllowed(ignoreCooldown: true)
            }
        }
    }

    // MARK: - Server-driven sources section

    private var serverSourcesSection: some View {
        Section {
            if sourcesVM.isLoading {
                HStack {
                    ProgressView()
                    Text("Loading sources…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                }
            } else if let error = sourcesVM.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        Task { await sourcesVM.loadSources() }
                    }
                    .font(.footnote)
                }
            } else if sourcesVM.sources.isEmpty {
                Text("No sources available.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                // Select All / Deselect All
                Button(sourcesVM.allEnabled ? "Deselect All" : "Select All") {
                    sourcesVM.setAll(enabled: !sourcesVM.allEnabled)
                }
                .font(.subheadline)

                // Grouped by domain
                ForEach(sourcesVM.groupedSources, id: \.domain) { group in
                    Section(group.domain) {
                        ForEach(group.sources, id: \.self) { index in
                            Toggle(isOn: Binding(
                                get: { sourcesVM.sources[index].enabled },
                                set: { _ in sourcesVM.toggle(at: index) }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sourcesVM.sources[index].description)
                                        .font(.body)
                                    Text(sourcesVM.sources[index].kindLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Sources")
        }
    }

    // MARK: - RSS section

    private var rssSection: some View {
        Section("RSS") {
            // RSS toggle
            Toggle("Include RSS articles", isOn: $draftSettings.enableRSS)

            if draftSettings.enableRSS {
                // 1) Google News favorites editor + default block
                googleNewsFavoritesSection

                // 2) Navigation to advanced "Add source to backend" form
                NavigationLink {
                    BackendSourceEditorView(
                        existingFeeds: backendFeeds,
                        onFeedsUpdated: { feeds in
                            backendFeeds = feeds
                        }
                    )
                } label: {
                    HStack {
                        Image(systemName: "gearshape.2")
                            .foregroundColor(.blue)
                        Text("Advanced: custom backend RSS feed")
                    }
                }
            } else {
                Text("Turn this on to include a Google News feed based on your favorites.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Google News favorites subsection

    private var googleNewsFavoritesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Enable Google News favorites feed", isOn: $draftSettings.enableGoogleNewsFavorites)

            if draftSettings.enableGoogleNewsFavorites {
                if draftSettings.googleNewsUserKeywords.isEmpty {
                    Text("Add keywords to personalize your Google News favorites feed. Fixed favorites like your teams are included automatically if enabled below.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // Pills ABOVE the add field, horizontally scrollable, each with its own remove button
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(draftSettings.googleNewsUserKeywords, id: \.self) { keyword in
                                HStack(spacing: 6) {
                                    Text(keyword)
                                        .font(.body)
                                    Button {
                                        draftSettings.googleNewsUserKeywords.removeAll { $0 == keyword }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color(.systemGray6))
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                // Add field BELOW the existing keywords
                HStack {
                    TextField("Add keyword (e.g. technology)", text: $newKeywordText)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    Button("Add") {
                        let trimmed = newKeywordText
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        if !draftSettings.googleNewsUserKeywords.contains(trimmed) {
                            draftSettings.googleNewsUserKeywords.append(trimmed)
                        }
                        newKeywordText = ""
                    }
                }

                Button {
                    Task { await saveGoogleNewsKeywords() }
                } label: {
                    if isSavingKeywords {
                        ProgressView()
                    } else {
                        Text("Save Google News favorites")
                    }
                }
                .disabled(isSavingKeywords)
                .padding(.top, 4)

                if let status = keywordStatusMessage {
                    Text(status)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                // Default Google News favorites block (fixed keywords)
                let fixedKeywords = viewModel.fixedFavoriteKeywords
                if !fixedKeywords.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Default Google News favorites")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $draftSettings.enableFixedGoogleNewsFavorites)
                                .labelsHidden()
                        }

                        if draftSettings.enableFixedGoogleNewsFavorites {
                            Text(fixedKeywords.joined(separator: ", "))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Turn on to include built‑in team and topic favorites in your Google News feed.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 8)
                }
            } else {
                Text("Turn this on to include a Google News feed based on your favorites.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        // Task { @MainActor in
        //     await viewModel.refreshIfAllowed(ignoreCooldown: true)
        // }
    }

    private func loadBackendFeeds() async {
        let url = simpleNewsBackendBaseURL.appendingPathComponent("feeds")
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
            // Ignore; optional
        }
    }

    private func saveGoogleNewsKeywords() async {
        await MainActor.run {
            isSavingKeywords = true
            keywordStatusMessage = nil
        }
        defer { Task { @MainActor in isSavingKeywords = false } }

        do {
            let combined = viewModel.combinedGoogleNewsKeywords(from: draftSettings)

            if !draftSettings.enableGoogleNewsFavorites {
                // Disable on backend: send empty list only if previously non-empty
                if !draftSettings.lastSyncedGoogleNewsKeywords.isEmpty {
                    try await rssClient.updateKeywords([])
                }
                draftSettings.lastSyncedGoogleNewsKeywords = []
                await MainActor.run {
                    keywordStatusMessage = "Favorites feed disabled."
                }
                return
            }

            // If no change, skip network call
            if Set(combined) == Set(draftSettings.lastSyncedGoogleNewsKeywords) {
                await MainActor.run {
                    keywordStatusMessage = "No changes to save."
                }
                return
            }

            try await rssClient.updateKeywords(combined)
            draftSettings.lastSyncedGoogleNewsKeywords = combined

            await MainActor.run {
                keywordStatusMessage = "Google News favorites updated."
            }
        } catch {
            await MainActor.run {
                keywordStatusMessage = "Failed to update favorites: \(error.localizedDescription)"
            }
        }

        // Persist updated settings
        applyChanges()
    }
}

// MARK: - BackendSourceEditorView (advanced custom backend form)

private struct BackendSourceEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var feedId: String = ""
    @State private var feedURL: String = ""
    @State private var feedSource: String = ""
    @State private var selectedKind: String = "periodic"
    @State private var isCustomKind: Bool = false
    @State private var customKindName: String = ""
    @State private var customHour: Int = 12
    @State private var customMinute: Int = 0
    @State private var backendSourceStatus: String?

    @State private var backendFeeds: [BackendFeed]

    // Subscription auto-prompt state
    @State private var pendingSubscriptionSources: [SubscriptionSource] = []
    @State private var showSubscriptionPrompt = false
    @State private var showSubscriptionLogin = false

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

    let onFeedsUpdated: ([BackendFeed]) -> Void

    init(existingFeeds: [BackendFeed], onFeedsUpdated: @escaping ([BackendFeed]) -> Void) {
        _backendFeeds = State(initialValue: existingFeeds)
        self.onFeedsUpdated = onFeedsUpdated
    }

    var body: some View {
        Form {
            Section("Add source to backend") {
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

                // Kind / schedule
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
        .navigationTitle("Custom backend RSS")
        .alert(
            "\(pendingSubscriptionSources.first?.displayName ?? "This source") requires a login. Sign in now to access full articles?",
            isPresented: $showSubscriptionPrompt
        ) {
            Button("Sign In") {
                showSubscriptionLogin = true
            }
            Button("Later", role: .cancel) {
                pendingSubscriptionSources.removeAll()
            }
        }
        .sheet(isPresented: $showSubscriptionLogin, onDismiss: {
            // Show next prompt if there are more pending sources
            pendingSubscriptionSources.removeFirst()
            if !pendingSubscriptionSources.isEmpty {
                showSubscriptionPrompt = true
            }
        }) {
            if let source = pendingSubscriptionSources.first {
                SubscriptionLoginView(source: source, store: SubscriptionStore.shared)
            }
        }
    }

    // Helpers duplicated (small) for this view
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

        let workerURL = simpleNewsBackendBaseURL.appendingPathComponent("feeds")
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
                // Parse subscriptionMeta for paywalled sources
                var newSubSources: [SubscriptionSource] = []
                if let metaArray = json["subscriptionMeta"] as? [[String: Any]] {
                    for meta in metaArray {
                        guard let domain = meta["domain"] as? String,
                              let requiresLogin = meta["requiresLogin"] as? Bool,
                              requiresLogin,
                              let loginStr = meta["loginURL"] as? String,
                              let loginURL = URL(string: loginStr) else { continue }
                        let source = SubscriptionSource(
                            id: "custom_\(domain)",
                            domain: domain,
                            displayName: domain,
                            loginURL: loginURL,
                            isCustom: true
                        )
                        newSubSources.append(source)
                    }
                }

                await MainActor.run {
                    let subStore = SubscriptionStore.shared
                    for source in newSubSources {
                        if !subStore.hasSource(for: source.domain) {
                            subStore.addCustomSource(source)
                        }
                    }

                    backendSourceStatus = "Source added successfully."
                    feedId = ""
                    feedURL = ""
                    feedSource = ""
                    customKindName = ""
                    isCustomKind = false

                    let actuallyNew = newSubSources.filter { subStore.hasSource(for: $0.domain) }
                    if !actuallyNew.isEmpty {
                        pendingSubscriptionSources = actuallyNew
                        showSubscriptionPrompt = true
                    }
                }

                // Reload feeds and propagate up
                await reloadFeedsFromWorker()
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

    private func reloadFeedsFromWorker() async {
        let url = simpleNewsBackendBaseURL.appendingPathComponent("feeds")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            struct FeedsResponse: Codable { let feeds: [BackendFeed] }
            let decoded = try JSONDecoder().decode(FeedsResponse.self, from: data)
            await MainActor.run {
                backendFeeds = decoded.feeds
                onFeedsUpdated(decoded.feeds)
            }
        } catch {
            // ignore
        }
    }
}

import SwiftUI

struct SocialSourcesForm: View {
    @Binding var draftSettings: AppSettings

    var body: some View {
        Form {
            Section("Social sources") {
                Toggle("Show Instagram", isOn: $draftSettings.showInstagram)
                Toggle("Show Reddit", isOn: $draftSettings.showReddit)
                Toggle("Show LinkedIn", isOn: $draftSettings.showLinkedIn)
                //Toggle("Show X (Twitter)", isOn: $draftSettings.showX)

                Text("These control which social apps appear under the Social tab. Hiding a source does not affect your accounts or logins.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SocialSourcesSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var draftSettings: AppSettings = AppSettings.load()

    var body: some View {
        SocialSourcesForm(draftSettings: $draftSettings)
            .navigationTitle("Social sources")
            .onAppear {
                draftSettings = settingsStore.settings
            }
            .onChange(of: draftSettings) {
                applyChanges()
            }
    }

    private func applyChanges() {
        settingsStore.settings = draftSettings
        settingsStore.settings.save()
    }
}
#if DEBUG
#Preview("News Sources Settings") {
    PreviewWrapper {
        NavigationStack {
            NewsSourcesSettingsView(viewModel: NewsViewModel())
        }
    }
}

#Preview("Social Sources Settings") {
    PreviewWrapper {
        NavigationStack {
            SocialSourcesSettingsView()
        }
    }
}
#endif

