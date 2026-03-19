//
//  ArticleGroupRow.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/3/26.
//

import SwiftUI

fileprivate let groupRowDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
}()

struct ArticleGroupRow: View {
    let group: ArticleGroup
    let showImages: Bool
    let showDescription: Bool
    let isExpanded: Bool
    let showTags: Bool
    var isRead: Bool = false
    var showReadToggle: Bool = false

    let onToggleSaved: () -> Void
    let onOpenDetail: () -> Void
    let onOpenLink: () -> Void
    let onToggleExpanded: () -> Void
    var onToggleRead: (() -> Void)? = nil

    private var article: Article { group.primaryArticle }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: image | text | action buttons
            HStack(alignment: .top, spacing: 10) {
                if showImages, let url = article.imageURL ?? article.readerImageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Color.gray.opacity(0.1)
                        case .success(let image):
                            image.resizable().scaledToFill()
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
                    Text(group.canonicalTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(3)
                        .foregroundColor(isRead ? .secondary : .primary)
                        .onTapGesture { onOpenDetail() }
                        .accessibilityAddTraits(.isButton)

                    if showDescription, let description = article.description {
                        Text(description)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(isExpanded ? nil : 2)
                            .onTapGesture { onToggleExpanded() }
                            .accessibilityAddTraits(.isButton)
                    }

                    HStack(spacing: 6) {
                        if let source = article.source {
                            Text(source)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if group.allArticles.count > 1 {
                            Text("\(group.allArticles.count)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(
                                    Circle()
                                        .fill(Color.blue)
                                )
                        }
                    }

                    if let publishedAt = article.publishedAt {
                        Text(groupRowDateFormatter.string(from: publishedAt))
                            .font(.caption2)
                            .foregroundColor(.secondary)
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
                            systemName: "doc.text.magnifyingglass",
                            tint: .blue,
                            action: onOpenLink
                        )
                    }
                    if showReadToggle {
                        tappableIcon(
                            systemName: isRead ? "envelope.badge" : "envelope.open",
                            tint: .gray,
                            action: { onToggleRead?() }
                        )
                    }
                }
                .padding(.vertical, 6)
            }

            // Tags row: full width below the image/text row
            if showTags, !article.tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(article.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

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
// MARK: - Flow Layout

/// A simple wrapping layout that places children left-to-right,
/// moving to the next line when a child doesn't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Single Article Group") {
    List {
        ArticleGroupRow(
            group: PreviewData.sampleGroup,
            showImages: true,
            showDescription: true,
            isExpanded: false,
            showTags: true,
            onToggleSaved: {},
            onOpenDetail: {},
            onOpenLink: {},
            onToggleExpanded: {}
        )
    }
}

#Preview("Multi-Source Group") {
    List {
        ArticleGroupRow(
            group: PreviewData.sampleMultiGroup,
            showImages: true,
            showDescription: true,
            isExpanded: false,
            showTags: true,
            onToggleSaved: {},
            onOpenDetail: {},
            onOpenLink: {},
            onToggleExpanded: {}
        )
    }
}
#endif

