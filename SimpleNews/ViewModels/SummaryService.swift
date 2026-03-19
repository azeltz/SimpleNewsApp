//
//  SummaryService.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/3/26.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Summarises article groups using Apple's on-device Foundation Models when
/// available, falling back to a simple extractive summary otherwise.
enum SummaryService {

    // MARK: - Public

    static func summarize(groups: [ArticleGroup]) async throws -> String {
        guard !groups.isEmpty else {
            return "No articles to summarize yet. Pull to refresh the news feed."
        }

        // Try the on-device model first
        if let aiSummary = await generateWithFoundationModels(groups: groups) {
            return aiSummary
        }

        // Fallback: extractive summary
        return fallbackSummary(groups: groups)
    }

    // MARK: - Apple Foundation Models (iOS 26+)

    private static func generateWithFoundationModels(groups: [ArticleGroup]) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await _generateWithFoundationModels(groups: groups)
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func _generateWithFoundationModels(groups: [ArticleGroup]) async -> String? {
        do {
            let model = SystemLanguageModel.default
            guard model.isAvailable else { return nil }

            let session = LanguageModelSession(model: model)
            let prompt = buildPrompt(groups: groups)
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            Log.general.error("Foundation Models error: \(error)")
            return nil
        }
    }
    #endif

    // MARK: - Prompt builder

    private static func buildPrompt(groups: [ArticleGroup]) -> String {
        let selected = Array(groups.prefix(15))

        var headlines: [String] = []
        for (i, group) in selected.enumerated() {
            let sourceCount = group.allArticles.count
            let sources = sourceCount > 1 ? " (\(sourceCount) sources)" : ""
            let desc = group.primaryArticle.description ?? ""
            headlines.append("\(i + 1). \(group.canonicalTitle)\(sources)\n   \(desc)")
        }

        let headlineBlock = headlines.joined(separator: "\n")
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)

        return """
        You are a concise news editor. Below are today's top headlines for \(dateStr). \
        Write a roughly 200-word summary in flowing prose that covers the most important \
        and most repeated topics. Combine related stories naturally. Do NOT use bullet points \
        or numbered lists. Write in third person, present tense, like a newspaper briefing. \
        Do not include any headline listing at the end.

        Headlines:
        \(headlineBlock)
        """
    }

    // MARK: - Fallback (extractive)

    private static func fallbackSummary(groups: [ArticleGroup]) -> String {
        let selected = Array(groups.prefix(10))
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)

        // Collect sentences from descriptions to build prose
        var sentences: [String] = []
        for group in selected {
            let title = group.canonicalTitle
            let sourceCount = group.allArticles.count
            let sourceNote = sourceCount > 1 ? ", reported by \(sourceCount) sources" : ""
            let desc = group.primaryArticle.description?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !desc.isEmpty {
                sentences.append("\(title)\(sourceNote). \(desc)")
            } else {
                sentences.append("\(title)\(sourceNote).")
            }
        }

        let body = sentences.joined(separator: " ")
        var result = "Here is your news briefing for \(dateStr). \(body)"

        if selected.count < groups.count {
            result += " There are \(groups.count - selected.count) more stories in your feed."
        }

        return result
    }
}
