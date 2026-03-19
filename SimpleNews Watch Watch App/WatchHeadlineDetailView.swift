//
//  WatchHeadlineDetailView.swift
//  SimpleNewsWatch
//
//  Detail view for a single headline on Apple Watch.
//

import SwiftUI

struct WatchHeadlineDetailView: View {
    let headline: WatchHeadline
    @ObservedObject var viewModel: WatchHeadlinesViewModel

    /// Local copy of saved state for responsive UI
    @State private var isSaved: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(.blue)
                        .font(.subheadline)
                    Text(headline.title)
                        .font(.headline)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.leading)
                }

                if let source = headline.source {
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.blue)
                }

                if let date = headline.publishedAt {
                    Text(date, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let description = headline.description, !description.isEmpty {
                    Divider()
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }

                Divider()

                Button {
                    WatchSessionManager.shared.toggleSaved(headline: headline)
                    isSaved.toggle()
                } label: {
                    Label(
                        isSaved ? "Remove from Saved" : "Save Article",
                        systemImage: isSaved ? "bookmark.slash" : "bookmark.fill"
                    )
                    .font(.footnote)
                }
                .buttonStyle(.borderedProminent)
                .tint(isSaved ? .red : .blue)
            }
            .padding()
        }
        .navigationTitle(headline.source ?? "Detail")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isSaved = headline.isSaved }
    }
}

#if DEBUG
#Preview("Watch Headline Detail") {
    let vm = WatchHeadlinesViewModel()
    let sample = WatchHeadline(
        id: "1",
        title: "Cole Payton is not the next Taysom Hill, he's here to prove he's an NFL QB",
        source: "cbssports.com",
        publishedAt: Date().addingTimeInterval(-60 * 16),
        urlString: nil,
        description: "A short summary of the article appears here for quick reading on Apple Watch.",
        isSaved: false
    )
    return WatchHeadlineDetailView(headline: sample, viewModel: vm)
}
#endif
