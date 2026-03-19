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
    @State private var isCollapsed: Bool = true

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
                        .foregroundStyle(.purple)
                    Text("Today's Summary")
                        .font(.headline)
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Button {
                            Task { await generateSummary() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if !summaryText.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.subheadline)
                        }
                    }
                    Spacer()
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

// MARK: - Daily Digest Sheet (shown when notification is tapped)

struct DailyDigestSheetView: View {
    @ObservedObject var viewModel: NewsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var summaryText: String = ""
    @State private var isLoading: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle.text.clipboard.fill")
                            .foregroundStyle(.purple)
                        Text("Daily Digest")
                            .font(.title2)
                            .fontWeight(.bold)
                    }

                    Text(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView("Generating summary...")
                            Spacer()
                        }
                        .padding(.vertical, 40)
                    } else if summaryText.isEmpty {
                        Text("No summary available yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(summaryText)
                            .font(.body)
                            .lineSpacing(6)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await generateSummary()
            }
        }
    }

    private func generateSummary() async {
        isLoading = true
        let groups = viewModel.groupedArticles
        do {
            summaryText = try await SummaryService.summarize(groups: groups)
        } catch {
            summaryText = "Could not generate summary: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

#if DEBUG
#Preview("Summary Card") {
    PreviewWrapper {
        List {
            SummaryCardView(viewModel: NewsViewModel())
        }
    }
}

#Preview("Daily Digest Sheet") {
    DailyDigestSheetView(viewModel: NewsViewModel())
}
#endif
