//
//  SavedView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/13/26.
//

import SwiftUI

enum SavedSegment: String, CaseIterable, Identifiable {
    case saved = "Saved"
    case imported = "Imported"
    var id: String { rawValue }
}

struct SavedView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var importedStore: ImportedArticlesStore
    @ObservedObject var viewModel: NewsViewModel

    @State private var selectedSegment: SavedSegment = .saved
    @State private var expandedArticleIDs: Set<String> = []
    @State private var selectedSaved: SavedArticle? = nil
    @State private var safariItem: SafariItem? = nil
    @State private var pendingUnsave: SavedArticle? = nil
    @State private var showUnsaveAlert: Bool = false

    @State private var searchText: String = ""
    @State private var searchInTitle: Bool = true
    @State private var searchInDescription: Bool = true
    @State private var searchInTags: Bool = true

    @State private var showImportSheet: Bool = false   // NEW

    private var hasImported: Bool {
        !importedStore.articles.isEmpty
    }

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
                if selectedSegment == .saved || !hasImported {
                    savedContent
                } else {
                    importedContent
                }
            }
            .navigationTitle(
                (selectedSegment == .saved || !hasImported) ? "Saved" : "Imported"
            )
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic)
            )
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .toolbar {
                // Center area: segmented control when imported exists
                ToolbarItem(placement: .principal) {
                    if hasImported {
                        Picker("", selection: $selectedSegment) {
                            Text("Saved").tag(SavedSegment.saved)
                            Text("Imported").tag(SavedSegment.imported)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 240)
                    } else {
                        Text("")
                            .font(.headline)
                    }
                }

                // Trailing: + button (same behavior as Home) + filter menu
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
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .menuActionDismissBehavior(.disabled)
                }
            }
            .sheet(item: $selectedSaved) { saved in
                SavedArticleDetailWrapper(
                    saved: saved,
                    viewModel: viewModel
                )
                .environmentObject(settingsStore)
            }
            .fullScreenCover(item: $safariItem) { item in
                SafariView(url: item.url)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showImportSheet) {         // NEW
                ImportURLView()
                    .environmentObject(importedStore)
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
            .onChange(of: hasImported) {
                if !hasImported {
                    selectedSegment = .saved
                }
            }
        }
    }

    // MARK: - Saved segment content

    @ViewBuilder
    private var savedContent: some View {
        if viewModel.savedArticles.isEmpty {
            List {
                Text("No saved articles yet.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
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

    // MARK: - Imported segment content

    @ViewBuilder
    private var importedContent: some View {
        if importedStore.articles.isEmpty {
            List {
                Text("No imported articles.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        } else {
            List {
                ForEach($importedStore.articles) { $article in
                    NavigationLink {
                        ArticleDetailView(
                            article: $article,
                            showImages: settingsStore.settings.showImages,
                            enableInLineView: settingsStore.settings.enableInLineView,
                            hideArticleBodyImages: settingsStore.settings.hideArticleBodyImages,
                            includeImageInExport: settingsStore.settings.includeImageInExport,
                            enableRichLinkPreviews: settingsStore.settings.enableRichLinkPreviews,
                            onToggleSaved: {
                                viewModel.toggleSaved(article)
                            }
                        )
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            if settingsStore.settings.showImages,
                               let url = article.imageURL ?? article.readerImageURL {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().scaledToFill()
                                    default:
                                        Color.gray.opacity(0.1)
                                    }
                                }
                                .frame(width: 72, height: 72)
                                .clipped()
                                .cornerRadius(8)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(article.title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .lineLimit(3)

                                if let source = article.source {
                                    Text(source)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                if let publishedAt = article.publishedAt {
                                    Text(publishedAt, style: .date)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()
                        }
                    }
                }
                .onDelete { offsets in
                    importedStore.remove(at: offsets)
                }
            }
        }
    }

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
            aiTags: [],
            readerImageURL: saved.readerImageURL
        )
    }
}

#if DEBUG
#Preview("Saved View") {
    PreviewWrapper {
        SavedView(viewModel: NewsViewModel())
    }
}
#endif

// Wrapper that lets ArticleDetailView edit an Article and then
// pushes readerImageURL changes back into the SavedArticle list.
private struct SavedArticleDetailWrapper: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @ObservedObject var viewModel: NewsViewModel

    let saved: SavedArticle
    @State private var article: Article

    init(
        saved: SavedArticle,
        viewModel: NewsViewModel
    ) {
        self.saved = saved
        self.viewModel = viewModel
        self._article = State(initialValue: Article(
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
            aiTags: [],
            readerImageURL: saved.readerImageURL
        ))
    }

    var body: some View {
        NavigationStack {
            ArticleDetailView(
                article: $article,
                showImages: settingsStore.settings.showImages,
                enableInLineView: settingsStore.settings.enableInLineView,
                hideArticleBodyImages: settingsStore.settings.hideArticleBodyImages,
                includeImageInExport: settingsStore.settings.includeImageInExport,
                enableRichLinkPreviews: settingsStore.settings.enableRichLinkPreviews,
                onToggleSaved: {
                    viewModel.toggleSaved(article)
                }
            )
        }
        .onChange(of: article.readerImageURL) { _, newValue in
            viewModel.updateSavedReaderImageURL(
                url: saved.url,
                readerImageURL: newValue
            )
        }
    }
}
