//
//  ArticleDetailView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/13/26.
//

import SwiftUI

fileprivate let articleDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
}()

struct ArticleDetailView: View {
    let article: Article
    let showImages: Bool
    let enableInLineView: Bool
    let onToggleSaved: () -> Void

    @State private var showSafari: Bool = false
    @State private var isSaved: Bool
    @StateObject private var readerLoader = ReaderLoader()
    @State private var readerHeight: CGFloat = 0

    @Environment(\.openURL) private var openURL

    init(
        article: Article,
        showImages: Bool,
        enableInLineView: Bool,
        onToggleSaved: @escaping () -> Void
    ) {
        self.article = article
        self.showImages = showImages
        self.enableInLineView = enableInLineView
        self.onToggleSaved = onToggleSaved
        _isSaved = State(initialValue: article.isSaved)
    }

    // Helper to decide what text to show if reader is off or fails
    private func bodyText(for article: Article) -> String? {
        if let content = article.content,
           !content.isEmpty,
           content != "ONLY AVAILABLE IN PAID PLANS" {
            return content
        }

        if let description = article.description, !description.isEmpty {
            return description
        }

        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header image
                if showImages, let url = article.imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Color.gray.opacity(0.1)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Color.gray.opacity(0.1)
                        @unknown default:
                            Color.gray.opacity(0.1)
                        }
                    }
                    .frame(height: 220)
                    .clipped()
                    .cornerRadius(12)
                }

                // Title
                Text(article.title)
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.leading)

                // Date
                if let publishedAt = article.publishedAt {
                    Text(articleDateFormatter.string(from: publishedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Source
                if let source = article.source {
                    Text(source)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Tags
                if !article.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(article.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.15))
                                )
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Divider()

                // Show summary if reader is disabled OR reader has not loaded/failed
                if !enableInLineView || readerLoader.readerHTML == nil {
                    if let text = bodyText(for: article) {
                        Text(text)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("No content available.")
                            .foregroundColor(.secondary)
                    }
                }

                // Link actions + optional reader content
                if let url = article.url {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Read full article")
                            .font(.headline)

                        HStack(spacing: 12) {
                            Button {
                                showSafari = true
                            } label: {
                                Label("Open in reader", systemImage: "doc.text.magnifyingglass")
                                    .font(.subheadline)
                            }

                            Button {
                                openURL(url)
                            } label: {
                                Label("Open in browser", systemImage: "arrow.up.right.square")
                                    .font(.subheadline)
                            }
                        }
                        .tint(Color.blue)
                    }

                    // Inline reader – only when enabled in settings
                    if enableInLineView {
                        if let html = readerLoader.readerHTML {
                            ReaderHTMLView(html: html, height: $readerHeight)
                                .frame(height: readerHeight)
                        } else if readerLoader.isLoading {
                            ProgressView("Loading article…")
                        } else if let error = readerLoader.error {
                            Text(error)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(article.source ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    onToggleSaved()
                    isSaved.toggle()
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                }
            }
        }
        .fullScreenCover(isPresented: $showSafari) {
            if let url = article.url {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .task {
            if enableInLineView, let url = article.url {
                await readerLoader.load(from: url)
            }
        }
    }
}
