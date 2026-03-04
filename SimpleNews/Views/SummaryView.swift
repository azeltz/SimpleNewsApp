//
//  SummaryView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/3/26.
//

import SwiftUI

/// An inline, collapsible summary card shown at the top of the home list.
struct SummaryCardView: View {
    @ObservedObject var viewModel: NewsViewModel
    @EnvironmentObject var settingsStore: SettingsStore

    @State private var summaryText: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var isCollapsed: Bool = false

    private var groups: [ArticleGroup] {
        viewModel.groupedArticles
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row – always visible
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isCollapsed.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.blue)
                    Text("Today's Summary")
                        .font(.headline)
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                Divider()
                    .padding(.horizontal, 16)

                // Body
                Group {
                    if isLoading && summaryText.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("Generating summary…")
                            Spacer()
                        }
                        .padding(.vertical, 24)
                    } else if let error = errorMessage {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Could not generate summary")
                                .font(.subheadline).bold()
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    } else if summaryText.isEmpty {
                        Text("Loading summary…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    } else {
                        Text(summaryText)
                            .font(.subheadline)
                            .lineSpacing(4)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                }

                // Refresh button
                if !isLoading {
                    Button {
                        Task { await generateSummary() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
        .task {
            if summaryText.isEmpty && !groups.isEmpty {
                await generateSummary()
            }
        }
        .onChange(of: groups.count) {
            // Re-generate when articles load for the first time
            if summaryText.isEmpty && !groups.isEmpty {
                Task { await generateSummary() }
            }
        }
    }

    private func generateSummary() async {
        isLoading = true
        errorMessage = nil
        do {
            summaryText = try await SummaryService.summarize(groups: groups)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
