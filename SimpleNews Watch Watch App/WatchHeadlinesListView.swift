//
//  WatchHeadlinesListView.swift
//  SimpleNewsWatch
//
//  A scrollable list of top headlines for Apple Watch.
//

import SwiftUI

private let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()

struct WatchHeadlinesListView: View {
    var viewModel: WatchHeadlinesViewModel

    /// Deep link article ID from complication tap
    @Binding var deepLinkArticleID: String?
    /// Whether to show AI summary from complication deep link
    @Binding var showSummaryFromDeepLink: Bool

    /// Navigation state for deep-linked article
    @State private var selectedHeadline: WatchHeadline?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.headlines.isEmpty {
                    ProgressView("Loading...")
                } else if let error = viewModel.errorMessage, viewModel.headlines.isEmpty {
                    VStack(spacing: 8) {
                        Text(error)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await viewModel.loadHeadlines() }
                        }
                        .font(.footnote)
                    }
                } else {
                    List {
                        // AI Summary card (if enabled and available)
                        if viewModel.enableAISummary, let summary = viewModel.aiSummary, !summary.isEmpty {
                            NavigationLink {
                                WatchAISummaryDetailView(summary: summary)
                            } label: {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(.purple)
                                        .font(.caption)
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Today's Summary")
                                            .font(.headline)
                                            .foregroundStyle(.purple)

                                        Text("AI-powered news briefing")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.purple.opacity(0.15))
                            )
                        }

                        // Regular headlines
                        ForEach(viewModel.headlines) { headline in
                            NavigationLink {
                                WatchHeadlineDetailView(
                                    headline: headline,
                                    viewModel: viewModel
                                )
                            } label: {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: headline.isSaved ? "bookmark.fill" : "bookmark")
                                        .foregroundStyle(.blue)
                                        .font(.caption)
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(headline.title)
                                            .font(.headline)
                                            .lineLimit(3)
                                            .minimumScaleFactor(0.75)
                                            .multilineTextAlignment(.leading)

                                        HStack(spacing: 4) {
                                            if let source = headline.source {
                                                Text(source)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            if let date = headline.publishedAt {
                                                if headline.source != nil {
                                                    Text("·")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Text(relativeFormatter.localizedString(for: date, relativeTo: Date()))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("SimpleNews")
            .refreshable {
                await viewModel.loadHeadlines()
            }
            .task {
                if viewModel.headlines.isEmpty {
                    await viewModel.loadHeadlines()
                }
            }
            // Handle deep link to specific article
            .onChange(of: deepLinkArticleID) {
                if let id = deepLinkArticleID {
                    selectedHeadline = viewModel.headlines.first(where: { $0.id == id })
                    deepLinkArticleID = nil
                }
            }
            .sheet(item: $selectedHeadline) { headline in
                WatchHeadlineDetailView(headline: headline, viewModel: viewModel)
            }
            // Handle deep link to AI summary
            .sheet(isPresented: $showSummaryFromDeepLink) {
                if let summary = viewModel.aiSummary, !summary.isEmpty {
                    WatchAISummaryDetailView(summary: summary)
                } else {
                    Text("No summary available yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - AI Summary Detail View for Watch

struct WatchAISummaryDetailView: View {
    let summary: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                        .font(.subheadline)
                    Text("AI Summary")
                        .font(.headline)
                        .foregroundStyle(.purple)
                }

                Text(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()

                Text(summary)
                    .font(.footnote)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
            }
            .padding()
        }
        .navigationTitle("AI Summary")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("Watch Headlines List") {
    let vm = WatchHeadlinesViewModel()
    vm.aiSummary = "Markets rally as tech giants report strong earnings. The World Baseball Classic kicks off with the US facing Japan. European leaders meet to discuss climate policy."
    vm.enableAISummary = true
    vm.headlines = [
        WatchHeadline(
            id: "1",
            title: "World Baseball Classic 2026: Everything to know about the tournament",
            source: "cbssports.com",
            publishedAt: Date().addingTimeInterval(-60 * 9),
            urlString: nil,
            description: "Key storylines, teams, and schedule for the 2026 WBC.",
            isSaved: true
        ),
        WatchHeadline(
            id: "2",
            title: "Cole Payton is not the next Taysom Hill, he's here to prove he's an NFL QB",
            source: "cbssports.com",
            publishedAt: Date().addingTimeInterval(-60 * 47),
            urlString: nil,
            description: "Why Cole Payton wants to be evaluated as a true pocket passer.",
            isSaved: false
        )
    ]
    return WatchHeadlinesListView(
        viewModel: vm,
        deepLinkArticleID: .constant(nil),
        showSummaryFromDeepLink: .constant(false)
    )
}
#endif

