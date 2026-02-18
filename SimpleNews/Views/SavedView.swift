//
//  SavedView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/13/26.
//

import SwiftUI

struct SavedView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @ObservedObject var viewModel: NewsViewModel

    @State private var expandedArticleIDs: Set<String> = []
    @State private var selectedSaved: SavedArticle? = nil
    @State private var safariItem: SafariItem? = nil
    @State private var pendingUnsave: SavedArticle? = nil
    @State private var showUnsaveAlert: Bool = false

    // Search state (local to Saved tab)
    @State private var searchText: String = ""
    @State private var searchInTitle: Bool = true
    @State private var searchInDescription: Bool = true
    @State private var searchInTags: Bool = true

    private var filteredSaved: [SavedArticle] {
        guard !searchText.isEmpty else { return viewModel.savedArticles }
        let q = searchText.lowercased()

        return viewModel.savedArticles.filter { saved in
            let article = articleFromSaved(saved)

            var matches = false

            if searchInTitle {
                matches = matches || article.title.lowercased().contains(q)
            }
            if searchInDescription, let desc = article.description?.lowercased() {
                matches = matches || desc.contains(q)
            }
            if searchInTags {
                let tagsText = article.tags.joined(separator: " ").lowercased()
                matches = matches || tagsText.contains(q)
            }

            return matches
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.savedArticles.isEmpty {
                    Text("No saved articles yet.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    List(filteredSaved) { saved in
                        let article = articleFromSaved(saved)
                        ArticleRow(
                            article: article,
                            showImages: settingsStore.settings.showImages,
                            showDescription: settingsStore.settings.showDescriptions,
                            isExpanded: expandedArticleIDs.contains(article.id),
                            showTags: settingsStore.settings.enableTags,
                            onToggleSaved: {
                                if settingsStore.settings.confirmUnsaveInSavedTab {
                                    pendingUnsave = saved
                                    showUnsaveAlert = true
                                } else {
                                    viewModel.toggleSaved(article)
                                }
                            },
                            onOpenDetail: {
                                selectedSaved = saved
                            },
                            onOpenLink: {
                                if let url = saved.url {
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
                    }
                }
            }
            .navigationTitle("Saved")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic)
            )
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Section("Search in") {
                            Toggle("Titles", isOn: $searchInTitle)
                            Toggle("Descriptions", isOn: $searchInDescription)
                            Toggle("Tags", isOn: $searchInTags)
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .menuActionDismissBehavior(.disabled)
                }
            }
            .sheet(item: $selectedSaved) { saved in
                let article = articleFromSaved(saved)
                NavigationStack {
                    ArticleDetailView(
                        article: article,
                        showImages: settingsStore.settings.showImages,
                        enableInLineView: settingsStore.settings.enableInLineView,
                        onToggleSaved: {
                            viewModel.toggleSaved(article)
                        }
                    )
                }
            }
            .fullScreenCover(item: $safariItem) { item in
                SafariView(url: item.url)
                    .ignoresSafeArea()
            }
            .alert(
                "Remove from Saved?",
                isPresented: $showUnsaveAlert,
                presenting: pendingUnsave
            ) { item in
                Button("Remove", role: .destructive) {
                    let article = articleFromSaved(item)
                    viewModel.toggleSaved(article)
                    pendingUnsave = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingUnsave = nil
                }
            } message: { _ in
                Text("Are you sure you want to remove this article from your saved list?")
            }
        }
    }

    // Build a lightweight Article from SavedArticle for reuse with ArticleRow / ArticleDetailView
    private func articleFromSaved(_ saved: SavedArticle) -> Article {
        Article(
            id: saved.id,
            title: saved.title,
            description: saved.description,
            content: nil,
            imageURL: saved.imageURL,
            source: saved.source,
            category: nil,
            publishedAt: saved.publishedAt,
            url: saved.url,
            isSaved: true,
            liked: nil,
            aiTags: []
        )
    }
}
