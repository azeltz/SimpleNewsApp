//
//  SavedView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/13/26.
//

import SwiftUI

struct SavedView: View {
    @ObservedObject var viewModel: NewsViewModel

    @State private var expandedArticleIDs: Set<String> = []
    @State private var selectedSaved: SavedArticle? = nil
    @State private var safariItem: SafariItem? = nil
    @State private var pendingUnsave: SavedArticle? = nil
    @State private var showUnsaveAlert: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.savedArticles.isEmpty {
                    Text("No saved articles yet.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    List(viewModel.savedArticles) { saved in
                        let article = articleFromSaved(saved)
                        ArticleRow(
                            article: article,
                            showImages: viewModel.settings.showImages,
                            showDescription: viewModel.settings.showDescriptions,
                            isExpanded: expandedArticleIDs.contains(article.id),
                            showTags: viewModel.settings.enableTags,      // NEW
                            onToggleSaved: {
                                if viewModel.settings.confirmUnsaveInSavedTab {
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
            .sheet(item: $selectedSaved) { saved in
                let article = articleFromSaved(saved)
                NavigationStack {
                    ArticleDetailView(
                        article: article,
                        showImages: viewModel.settings.showImages,
                        enableInLineView: viewModel.settings.enableInLineView,
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
