//
//  ArticleRow.swift
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

struct ArticleRow: View {
    let article: Article
    let showImages: Bool
    let showDescription: Bool
    let isExpanded: Bool
    let showTags: Bool                      // NEW

    let onToggleSaved: () -> Void
    let onOpenDetail: () -> Void
    let onOpenLink: () -> Void
    let onToggleExpanded: () -> Void // NEW

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
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
                .frame(width: 72, height: 72)
                .clipped()
                .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Title: tap opens detail
                Text(article.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(3)
                    .onTapGesture {
                        onOpenDetail()
                    }

                // Description: tap toggles expanded/collapsed
                if showDescription, let description = article.description {
                    Text(description)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(isExpanded ? nil : 2)
                        .onTapGesture {
                            onToggleExpanded()
                        }
                }

                if let source = article.source {
                    Text(source)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let publishedAt = article.publishedAt {
                    Text(articleDateFormatter.string(from: publishedAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if showTags, !article.tags.isEmpty {   // NEW
                    HStack(spacing: 4) {
                        ForEach(article.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.15))
                                )
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Spacer()

            VStack(spacing: 8) {
                tappableIcon(
                    systemName: article.isSaved ? "bookmark.fill" : "bookmark",
                    tint: article.isSaved ? .blue : .secondary,
                    action: onToggleSaved
                )

                tappableIcon(
                    systemName: "chevron.right",
                    tint: .secondary,
                    action: onOpenDetail
                )

                if article.url != nil {
                    tappableIcon(
                        systemName: "safari",
                        tint: .blue,
                        action: onOpenLink
                    )
                }
            }
            .padding(.vertical, 6)
        }
    }

    // Bigger hit area, same small icon
    private func tappableIcon(
        systemName: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18))
                .foregroundColor(tint)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}
