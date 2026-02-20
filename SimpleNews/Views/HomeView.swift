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
    @ObservedObject var viewModel: NewsViewModel

    @State private var expandedArticleIDs: Set<String> = []
    @State private var selectedArticleID: String? = nil
    @State private var safariItem: SafariItem? = nil

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
                                    Text("Updating…")
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
                        Menu {
                            Section("Search in") {
                                Toggle("Titles", isOn: $viewModel.searchInTitle)
                                Toggle("Descriptions", isOn: $viewModel.searchInDescription)
                                Toggle("Tags", isOn: $viewModel.searchInTags)
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                        .menuActionDismissBehavior(.disabled)
                    }
                }
                .task { await viewModel.loadInitial() }
                .refreshable { await viewModel.refreshIfAllowed() }

                // Present ArticleDetailView with a Binding<Article>
                .sheet(
                    item: Binding(
                        get: {
                            // Map selected id -> Article from filtered list
                            selectedArticleID.flatMap { id in
                                viewModel.filteredArticles.first(where: { $0.id == id })
                            }
                        },
                        set: { newValue in
                            selectedArticleID = newValue?.id
                        }
                    )
                ) { article in
                    // Bind into the backing articles array
                    if let index = viewModel.articles.firstIndex(where: { $0.id == article.id }) {
                        NavigationStack {
                            ArticleDetailView(
                                article: $viewModel.articles[index],
                                showImages: settingsStore.settings.showImages,
                                enableInLineView: settingsStore.settings.enableInLineView,
                                onToggleSaved: {
                                    viewModel.toggleSaved(viewModel.articles[index])
                                }
                            )
                        }
                    }
                }

                .fullScreenCover(item: $safariItem) { item in
                    SafariView(url: item.url)
                        .ignoresSafeArea()
                }
        }
    }
    
    private func retryRefresh() {
        Task { @MainActor in
                await viewModel.refreshIfAllowed(ignoreCooldown: true)
        }
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
            List(viewModel.filteredArticles) { article in
                ArticleRow(
                    article: article,
                    showImages: settingsStore.settings.showImages,
                    showDescription: settingsStore.settings.showDescriptions,
                    isExpanded: expandedArticleIDs.contains(article.id),
                    showTags: settingsStore.settings.enableTags,
                    onToggleSaved: { viewModel.toggleSaved(article) },
                    onOpenDetail: {
                        selectedArticleID = article.id
                    },
                    onOpenLink: {
                        if let url = article.url {
                            safariItem = SafariItem(url: url)
                        }
                    },
                    onToggleExpanded: {
                        if expandedArticleIDs.contains(article.id) {
                            expandedArticleIDs.remove(article.id)
                        } else {
                            expandedArticleIDs.insert(article.id)
                        }
                    }
                )
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        viewModel.dislike(article)
                    } label: {
                        Label("Less like this", systemImage: "hand.thumbsdown")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        viewModel.like(article)
                    } label: {
                        Label("More like this", systemImage: "hand.thumbsup")
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}
