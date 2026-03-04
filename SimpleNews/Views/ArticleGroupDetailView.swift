//
//  ArticleGroupDetailView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/3/26.
//

import SwiftUI

struct ArticleGroupDetailView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    let group: ArticleGroup
    @Binding var articles: [Article]
    let onToggleSaved: (Article) -> Void

    @State private var selectedIndex: Int = 0

    private var currentArticle: Article {
        group.allArticles[selectedIndex]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if group.allArticles.count > 1 {
                    Picker("Source", selection: $selectedIndex) {
                        ForEach(0..<group.allArticles.count, id: \.self) { i in
                            Text(group.allArticles[i].source ?? "Source \(i + 1)")
                                .tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                // Find the binding into the articles array
                if let idx = articles.firstIndex(where: { $0.id == currentArticle.id }) {
                    ArticleDetailView(
                        article: $articles[idx],
                        showImages: settingsStore.settings.showImages,
                        enableInLineView: settingsStore.settings.enableInLineView,
                        onToggleSaved: {
                            onToggleSaved(articles[idx])
                        }
                    )
                } else {
                    // Fallback: show as read-only
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(currentArticle.title)
                                .font(.title2).bold()
                            if let desc = currentArticle.description {
                                Text(desc)
                                    .font(.body)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
    }
}
