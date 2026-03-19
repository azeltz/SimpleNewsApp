//
//  HiddenArticlesView.swift
//  SimpleNews
//
//  Shows articles currently hidden from Home due to muted (blocked) tags.
//

import SwiftUI

struct HiddenArticlesView: View {
    @ObservedObject var viewModel: NewsViewModel

    var body: some View {
        List {
            if viewModel.blockedArticles.isEmpty {
                Text("No hidden articles. Articles matching muted topics will appear here.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.blockedArticles) { article in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(article.title)
                            .font(.headline)
                            .lineLimit(3)

                        if let source = article.source {
                            Text(source)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        let matched = viewModel.matchingBlockedTags(for: article)
                        if !matched.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(matched, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        Text(tag)
                                            .font(.caption2)

                                        Button {
                                            viewModel.removeBlockedTag(tag)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red.opacity(0.15))
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Hidden Articles")
    }
}

#if DEBUG
#Preview("Hidden Articles") {
    PreviewWrapper {
        NavigationStack {
            HiddenArticlesView(viewModel: NewsViewModel())
        }
    }
}
#endif
