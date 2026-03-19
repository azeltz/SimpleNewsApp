//
//  SettingsView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/13/26.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var usageTracker: UsageTracker
    @ObservedObject var viewModel: NewsViewModel
    @State private var draftSettings: AppSettings = AppSettings.load()
    @State private var newTagText: String = ""
    @State private var newBlockedTagText: String = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("User ID")
                    Spacer()
                    Text(UserIdManager.current)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }

            displaySection
            readingAndExportSection
            backgroundRefreshSection
            notificationsSection
            sourcesSection
            if draftSettings.enableTags {
                tagsSection
            }
            mutedTopicsSection
            if draftSettings.sortByInterests {
                interestsSection
            }
            usageSection
        }
        .navigationTitle("Settings")
        .onAppear {
            draftSettings = settingsStore.settings
        }
        .onChange(of: draftSettings) {
            applyChanges()
        }
    }

    private func applyChanges() {
        settingsStore.settings = draftSettings
        settingsStore.save()
    }

    // MARK: - Display

    private var displaySection: some View {
        Section("Display") {
            Toggle("Show images in list", isOn: $draftSettings.showImages)
            Toggle("Show descriptions in list", isOn: $draftSettings.showDescriptions)

            Toggle("Show tags for each article", isOn: $draftSettings.enableTags)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Sort articles based on interests", isOn: $draftSettings.sortByInterests)
                if draftSettings.sortByInterests {
                    Text("Prioritizes articles matching your interests but does not hide others.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Toggle("Show inline article view", isOn: $draftSettings.enableInLineView)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Rich link previews", isOn: $draftSettings.enableRichLinkPreviews)
                Text("Shows embedded previews (YouTube, Twitter, etc.) inside article details instead of loading the full page.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Toggle("Track read/unread articles", isOn: $draftSettings.enableReadTracking)

            Toggle("Ask before removing saved articles", isOn: $draftSettings.confirmUnsaveInSavedTab)

            Toggle("Show AI summary on Home", isOn: $draftSettings.enableAISummary)

            Toggle("Show Social tab", isOn: $draftSettings.showSocialTab)

            Button("Clear cached web content") {
                viewModel.clearCaches()
            }
            .foregroundColor(.red)
        }
    }

    // MARK: - Reading & Export

    private var readingAndExportSection: some View {
        Section("Reading & Export") {
            Toggle("Include main image in exports", isOn: $draftSettings.includeImageInExport)

            Toggle("Hide images in article body", isOn: $draftSettings.hideArticleBodyImages)
        }
    }

    // MARK: - Notifications

    @StateObject private var notificationManager = NotificationManager.shared

    private var backgroundRefreshSection: some View {
        Section("Background Refresh") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Background refresh", isOn: $draftSettings.enableBackgroundRefresh)
                    .onChange(of: draftSettings.enableBackgroundRefresh) {
                        if !draftSettings.enableBackgroundRefresh {
                            draftSettings.enableBreakingAlerts = false
                        }
                    }
                Text("Allow SimpleNews to update articles in the background so digests and alerts stay current. If this is off, notifications may be delayed or out of date.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            if !notificationManager.isAuthorized {
                VStack(alignment: .leading, spacing: 8) {
                    Button("Enable Notifications") {
                        Task {
                            let granted = await notificationManager.requestPermission()
                            if granted {
                                draftSettings.enableDailyDigest = true
                                notificationManager.syncWithSettings(draftSettings)
                            }
                        }
                    }
                    Text("Allow notifications to receive a daily digest and breaking news alerts.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } else {
                Toggle("Daily digest", isOn: $draftSettings.enableDailyDigest)
                    .onChange(of: draftSettings.enableDailyDigest) {
                        notificationManager.syncWithSettings(draftSettings)
                    }

                if draftSettings.enableDailyDigest {
                    DatePicker(
                        "Digest time",
                        selection: Binding(
                            get: {
                                var comps = DateComponents()
                                comps.hour = draftSettings.dailyDigestHour
                                comps.minute = draftSettings.dailyDigestMinute
                                return Calendar.current.date(from: comps) ?? Date()
                            },
                            set: { newDate in
                                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                                draftSettings.dailyDigestHour = comps.hour ?? 8
                                draftSettings.dailyDigestMinute = comps.minute ?? 0
                                notificationManager.syncWithSettings(draftSettings)
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }

                // Breaking news: only available when background refresh is on
                if draftSettings.enableBackgroundRefresh {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Breaking news alerts", isOn: $draftSettings.enableBreakingAlerts)
                        if draftSettings.enableBreakingAlerts {
                            Text("Get notifications when important breaking stories are detected.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Breaking news alerts", isOn: .constant(false))
                            .disabled(true)
                        Text("Turn on Background refresh to enable breaking news alerts.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Button("Send test notification") {
                Task {
                    if !NotificationManager.shared.isAuthorized {
                        _ = await NotificationManager.shared.requestPermission()
                    }
                    NotificationManager.shared.scheduleTestNotification()
                }
            }
            .font(.caption)
        }
        .task {
            await notificationManager.refreshAuthorizationStatus()
        }
    }

    // MARK: - Sources entry

    private var sourcesSection: some View {
        Section(header: Text("Sources")) {
            NavigationLink("Manage news sources") {
                NewsSourcesSettingsView(viewModel: viewModel)
            }

            NavigationLink("Subscriptions") {
                SubscriptionsView()
            }

            if draftSettings.showSocialTab {
                NavigationLink("Manage social sources") {
                    SocialSourcesSettingsView()
                }
            }
        }
    }

    // MARK: - Tags
    
    private var tagsSection: some View {
        Section("Tags") {
            NavigationLink("Edit keyword tags") {
                KeywordRulesEditorView()
            }
        }
    }
    
    // MARK: - Muted Topics

    private var mutedTopicsSection: some View {
        Section("Muted topics") {
            if viewModel.settings.blockedTags.isEmpty {
                Text("No muted topics. Articles with muted tags are hidden from Home.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.settings.blockedTags, id: \.self) { tag in
                    Text(tag)
                }
                .onDelete(perform: deleteBlockedTags)
            }

            HStack {
                TextField("Add muted topic", text: $newBlockedTagText)
                    .textInputAutocapitalization(.never)
                Button("Block") {
                    let trimmed = newBlockedTagText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    viewModel.addBlockedTag(trimmed)
                    newBlockedTagText = ""
                }
            }

            NavigationLink("Hidden articles") {
                HiddenArticlesView(viewModel: viewModel)
            }
        }
    }

    private func deleteBlockedTags(at offsets: IndexSet) {
        let tags = viewModel.settings.blockedTags
        for index in offsets {
            viewModel.removeBlockedTag(tags[index])
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
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(tag)
                                .font(.body)
                            Spacer()
                            Text(weightLabel(weight))
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundColor(weightColor(weight))
                                .frame(width: 30, alignment: .trailing)
                        }
                        Slider(
                            value: Binding(
                                get: { weight },
                                set: { newValue in
                                    viewModel.setWeight(newValue.rounded(), for: tag)
                                }
                            ),
                            in: -10...10,
                            step: 1
                        )
                        .tint(weightColor(weight))
                    }
                    .padding(.vertical, 2)
                }
                .onDelete(perform: deleteTags)
            }

            addTagRow

            VStack(alignment: .leading, spacing: 4) {
                Text("Positive values (+1 to +10) mean you want more of this topic.")
                Text("Negative values (-1 to -10) mean you want less of this topic.")
                Text("Zero means neutral \u{2013} this topic doesn\u{2019}t affect article order.")
            }
            .font(.footnote)
            .foregroundColor(.secondary)
        }
    }

    /// Format the weight value with explicit sign for display.
    private func weightLabel(_ weight: Double) -> String {
        let intVal = Int(weight.rounded())
        if intVal > 0 { return "+\(intVal)" }
        return "\(intVal)"
    }

    /// Color the weight indicator: green for positive, red for negative, gray for zero.
    private func weightColor(_ weight: Double) -> Color {
        let intVal = Int(weight.rounded())
        if intVal > 0 { return .green }
        if intVal < 0 { return .red }
        return .secondary
    }

    // MARK: - Helpers

    private var addTagRow: some View {
        HStack {
            TextField("Add topic (e.g. technology)", text: $newTagText)
                .textInputAutocapitalization(.never)
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

    // MARK: - Usage

    /// Screens that should appear in "Usage Today" based on current settings.
    private var enabledUsageScreens: [UsageTracker.Screen] {
        var screens: [UsageTracker.Screen] = [.news]
        if draftSettings.showInstagram { screens.append(.instagram) }
        if draftSettings.showReddit { screens.append(.reddit) }
        if draftSettings.showLinkedIn { screens.append(.linkedin) }
        //if draftSettings.showX { screens.append(.x) }
        //if draftSettings.showTikTok { screens.append(.tiktok) }
        return screens
    }

    private var anySocialSourceEnabled: Bool {
        draftSettings.showInstagram || draftSettings.showReddit ||
        draftSettings.showLinkedIn || /* draftSettings.showX || */ draftSettings.showTikTok
    }

    private var usageSection: some View {
        Section {
            let today = usageTracker.todaySummary()

            ForEach(enabledUsageScreens, id: \.rawValue) { screen in
                let seconds = today[screen] ?? 0
                let minutes = Int(seconds) / 60
                let secs = Int(seconds) % 60
                HStack {
                    Text(screen.rawValue)
                    Spacer()
                    Text("\(minutes)m \(secs)s")
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }

            Stepper("News daily limit: \(usageTracker.newsLimitMinutes)m",
                    value: Binding(
                        get: { usageTracker.newsLimitMinutes },
                        set: { usageTracker.newsLimitMinutes = $0 }
                    ), in: 0...120, step: 5)
                .font(.subheadline)

            if anySocialSourceEnabled {
                Stepper("Social daily limit: \(usageTracker.socialLimitMinutes)m",
                        value: Binding(
                            get: { usageTracker.socialLimitMinutes },
                            set: { usageTracker.socialLimitMinutes = $0 }
                        ), in: 0...120, step: 5)
                    .font(.subheadline)
            }
        } header: {
            Text("Usage Today")
        } footer: {
            Text("Set to 0 to disable the limit. You'll see a gentle reminder when you exceed the limit.")
        }
    }
}

#if DEBUG
#Preview("Settings") {
    PreviewWrapper {
        NavigationStack {
            SettingsView(viewModel: NewsViewModel())
        }
    }
}
#endif
