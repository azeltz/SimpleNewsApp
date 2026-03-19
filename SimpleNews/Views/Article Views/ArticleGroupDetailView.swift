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
    let onToggleSaved: (Article) -> Void
    var onImageDiscovered: ((String, URL) -> Void)? = nil

    @State private var selectedIndex: Int = 0
    @State private var localArticles: [Article]

    init(
        group: ArticleGroup,
        onToggleSaved: @escaping (Article) -> Void,
        onImageDiscovered: ((String, URL) -> Void)? = nil
    ) {
        self.group = group
        self.onToggleSaved = onToggleSaved
        self.onImageDiscovered = onImageDiscovered
        self._localArticles = State(initialValue: group.allArticles)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if localArticles.count > 1 {
                    Picker("Source", selection: $selectedIndex) {
                        ForEach(0..<localArticles.count, id: \.self) { i in
                            Text(localArticles[i].source ?? "Source \(i + 1)")
                                .tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                ArticleDetailView(
                    article: $localArticles[selectedIndex],
                    showImages: settingsStore.settings.showImages,
                    enableInLineView: settingsStore.settings.enableInLineView,
                    hideArticleBodyImages: settingsStore.settings.hideArticleBodyImages,
                    includeImageInExport: settingsStore.settings.includeImageInExport,
                    enableRichLinkPreviews: settingsStore.settings.enableRichLinkPreviews,
                    onToggleSaved: {
                        onToggleSaved(localArticles[selectedIndex])
                    },
                    onImageDiscovered: onImageDiscovered
                )
            }
        }
    }
}

#if DEBUG
#Preview("Article Group Detail") {
    PreviewWrapper {
        ArticleGroupDetailView(
            group: PreviewData.sampleMultiGroup,
            onToggleSaved: { _ in }
        )
    }
}
#endif
