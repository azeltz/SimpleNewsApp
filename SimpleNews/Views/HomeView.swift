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
    @ObservedObject var viewModel: NewsViewModel
    @State private var expandedArticleIDs: Set<String> = []
    @State private var selectedArticle: Article? = nil
    @State private var safariItem: SafariItem? = nil

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("SimpleNews")
                .task {
                    await viewModel.loadInitial()
                }
                .refreshable {
                    await viewModel.refreshIfAllowed()
                }
                .sheet(item: $selectedArticle) { article in
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
                    Task { await viewModel.refreshIfAllowed(ignoreCooldown: true) }
                }
            }
        } else {
            List(viewModel.articles) { article in
                ArticleRow(
                    article: article,
                    showImages: viewModel.settings.showImages,
                    showDescription: viewModel.settings.showDescriptions,
                    isExpanded: expandedArticleIDs.contains(article.id),
                    showTags: viewModel.settings.enableTags,
                    onToggleSaved: {
                        viewModel.toggleSaved(article)
                    },
                    onOpenDetail: {
                        selectedArticle = article
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
