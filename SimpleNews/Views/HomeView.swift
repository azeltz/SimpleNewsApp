//
//  HomeView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/13/26.
//

import SwiftUI

struct SafariItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct HomeView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var usageTracker: UsageTracker
    @EnvironmentObject var importedStore: ImportedArticlesStore
    @ObservedObject var viewModel: NewsViewModel
    @ObservedObject var readStore: ReadArticlesStore = .shared

    @State private var expandedArticleIDs: Set<String> = []
    @State private var presentedGroup: ArticleGroup? = nil
    @State private var safariItem: SafariItem? = nil
    @State private var showImportSheet: Bool = false
    @State private var showNewsLimitAlert: Bool = false
    @State private var showDailyDigestSheet: Bool = false
    @State private var oEmbedSheetHTML: String? = nil

    // Deep link from notifications
    @State private var deepLinkedArticleID: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("SimpleNews")   // system large title
                .searchable(
                    text: $viewModel.searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic)
                )
                .searchPresentationToolbarBehavior(.avoidHidingContent)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer(minLength: 0)
                            HStack(spacing: 6) {
                                if viewModel.isLoading {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Updating news…")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else if let status = viewModel.refreshStatusMessage {
                                    Text(status)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else if let snapshot = viewModel.lastSnapshotAt {
                                    Text("Updated \(snapshot, style: .time)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Updated just now")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showImportSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Section("Search in") {
                                Toggle("Titles", isOn: $viewModel.searchInTitle)
                                Toggle("Descriptions", isOn: $viewModel.searchInDescription)
                                Toggle("Tags", isOn: $viewModel.searchInTags)
                            }
                            if settingsStore.settings.enableReadTracking {
                                Divider()
                                Button {
                                    readStore.markAllRead(mergedGroups.map(\.primaryArticle.id))
                                } label: {
                                    Label("Mark all as read", systemImage: "envelope.open")
                                }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                        .menuActionDismissBehavior(.disabled)
                    }
                }
                .task { await viewModel.loadInitial() }
                .refreshable { await viewModel.refreshIfAllowed() }
                .onAppear {
                    usageTracker.enter(.news)
                    if usageTracker.isOverNewsLimit() {
                        showNewsLimitAlert = true
                    }
                }
                .onDisappear { usageTracker.leave(.news) }
                .alert("Time Check", isPresented: $showNewsLimitAlert) {
                    Button("Keep Going") { }
                } message: {
                    Text("You've reached your daily news time goal. Want to keep going?")
                }
                // Deep link handler from notifications
                .onReceive(NotificationCenter.default.publisher(for: .openArticleFromNotification)) { note in
                    if let id = note.userInfo?["articleID"] as? String {
                        deepLinkedArticleID = id
                        openArticleFromNotification(id: id)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .openDailyDigest)) { _ in
                    showDailyDigestSheet = true
                }
                .sheet(isPresented: $showDailyDigestSheet) {
                    DailyDigestSheetView(viewModel: viewModel)
                }
                // Present group detail or single article detail
                .sheet(item: $presentedGroup) { group in
                    ArticleGroupDetailView(
                        group: group,
                        onToggleSaved: { viewModel.toggleSaved($0) },
                        onImageDiscovered: { id, url in
                            viewModel.updateReaderImage(articleID: id, readerImageURL: url)
                        }
                    )
                    .environmentObject(settingsStore)
                }
                .fullScreenCover(item: $safariItem) { item in
                    SafariView(url: item.url)
                        .ignoresSafeArea()
                }
                .sheet(isPresented: Binding(
                    get: { oEmbedSheetHTML != nil },
                    set: { if !$0 { oEmbedSheetHTML = nil } }
                )) {
                    if let html = oEmbedSheetHTML {
                        NavigationStack {
                            OEmbedWebView(embedHTML: html)
                                .navigationTitle("Preview")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .cancellationAction) {
                                        Button("Done") { oEmbedSheetHTML = nil }
                                    }
                                }
                        }
                    }
                }
                .sheet(isPresented: $showImportSheet) {
                    ImportURLView()
                        .environmentObject(importedStore)
                }
        }
    }

    private func retryRefresh() {
        Task { @MainActor in
            await viewModel.refreshIfAllowed(ignoreCooldown: true)
        }
    }

    /// Handle deep-link from notification by selecting a group or single article.
    private func openArticleFromNotification(id: String) {
        if let group = mergedGroups.first(where: { $0.allArticles.contains(where: { $0.id == id }) }) {
            presentedGroup = group
        } else if let article = viewModel.filteredArticles.first(where: { $0.id == id }) {
            presentedGroup = ArticleGroup(
                id: article.id,
                canonicalTitle: article.title,
                primaryArticle: article,
                allArticles: [article]
            )
        }
    }

    /// Merged groups: imported articles + feed articles grouped together.
    private var mergedGroups: [ArticleGroup] {
        let imported = importedStore.articles
        let combined = imported + viewModel.filteredArticles
        let deduped = deduplicateSameSourceSameDay(combined)
        let groups = ArticleGrouper.group(deduped)

        return groups
    }

    private func deduplicateSameSourceSameDay(_ articles: [Article]) -> [Article] {
        var seen: Set<String> = []
        var result: [Article] = []

        for article in articles {
            if seen.contains(article.id) {
                continue
            }
            seen.insert(article.id)
            result.append(article)
        }

        return result
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.articles.isEmpty {
            ProgressView("Loading news...")
        } else if let error = viewModel.errorMessage {
            VStack(spacing: 16) {
                Text(error)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    retryRefresh()
                }
            }
            .padding()
        } else {
            List {
                if settingsStore.settings.enableAISummary {
                    SummaryCardView(viewModel: viewModel)
                }

                ForEach(mergedGroups) { group in
                    ArticleGroupRow(
                        group: group,
                        showImages: settingsStore.settings.showImages,
                        showDescription: settingsStore.settings.showDescriptions,
                        isExpanded: expandedArticleIDs.contains(group.id),
                        showTags: settingsStore.settings.enableTags,
                        isRead: settingsStore.settings.enableReadTracking && readStore.isRead(group.primaryArticle.id),
                        showReadToggle: settingsStore.settings.enableReadTracking,
                        onToggleSaved: { viewModel.toggleSaved(group.primaryArticle) },
                        onOpenDetail: {
                            if settingsStore.settings.enableReadTracking {
                                readStore.markRead(group.primaryArticle.id)
                            }
                            presentedGroup = group
                        },
                        onOpenLink: {
                            if let url = group.primaryArticle.url {
                                if settingsStore.settings.enableRichLinkPreviews,
                                   OEmbedService.provider(for: url) != nil {
                                    Task {
                                        if let html = await OEmbedService.fetchHTML(for: url) {
                                            oEmbedSheetHTML = html
                                        } else {
                                            safariItem = SafariItem(url: url)
                                        }
                                    }
                                } else {
                                    safariItem = SafariItem(url: url)
                                }
                            }
                        },
                        onToggleExpanded: {
                            if expandedArticleIDs.contains(group.id) {
                                expandedArticleIDs.remove(group.id)
                            } else {
                                expandedArticleIDs.insert(group.id)
                            }
                        },
                        onToggleRead: {
                            readStore.toggleRead(group.primaryArticle.id)
                        }
                    )
                    .swipeActions(edge: .trailing) {
                        if settingsStore.settings.sortByInterests {
                            Button(role: .destructive) {
                                viewModel.dislike(group.primaryArticle)
                            } label: {
                                Label("Less like this", systemImage: "hand.thumbsdown")
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if settingsStore.settings.sortByInterests {
                            Button {
                                viewModel.like(group.primaryArticle)
                            } label: {
                                Label("More like this", systemImage: "hand.thumbsup")
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

#if DEBUG
#Preview("Home View") {
    PreviewWrapper {
        HomeView(viewModel: NewsViewModel())
    }
}
#endif
