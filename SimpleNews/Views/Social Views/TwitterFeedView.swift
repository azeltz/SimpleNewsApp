//
//  TwitterFeedView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/16/26.
//

import SwiftUI

struct TwitterFeedView: View {
    @StateObject private var viewModel = TwitterFeedViewModel()
    @EnvironmentObject var usageTracker: UsageTracker
    @State private var showLimitAlert = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.tweets.isEmpty {
                ProgressView("Loading tweets…")
            } else if let error = viewModel.errorMessage, viewModel.tweets.isEmpty {
                VStack(spacing: 16) {
                    Text(error)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await viewModel.loadTweets() }
                    }
                }
                .padding()
            } else if viewModel.tweets.isEmpty {
                VStack(spacing: 12) {
                    Text("No tweets yet")
                        .font(.headline)
                    if viewModel.hasAccounts {
                        Text("Your followed accounts don't have any tweets available right now. Pull to refresh later.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Follow some accounts in Settings → X Accounts to see tweets here.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.tweets) { tweet in
                            OEmbedWebView(embedHTML: tweet.embedHTML)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
                .refreshable {
                    await viewModel.loadTweets()
                }
            }
        }
        .navigationTitle("X (Twitter)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
//            usageTracker.enter(.x)
//            if usageTracker.isOverSocialLimit(for: .x) {
//                showLimitAlert = true
//            }
        }
//        .onDisappear { usageTracker.leave(.x) }
        .alert("Time Check", isPresented: $showLimitAlert) {
            Button("Keep Going") { }
        } message: {
            Text("You've reached your daily social time goal. Want to keep going?")
        }
        .task {
            await viewModel.loadTweets()
        }
    }
}

#if DEBUG
#Preview("Twitter Feed") {
    PreviewWrapper {
        NavigationStack {
            TwitterFeedView()
        }
    }
}
#endif
