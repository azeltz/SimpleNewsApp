//
//  NewsTaggerService.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/17/26.
//

import Foundation
import CoreML

/// Wraps the Core ML TF-IDF + logistic regression model that produces semantic tags.
final class NewsTaggerService {
    static let shared = NewsTaggerService()

    private let model: NewsTagger?
    private let tags: [String]
    private let vocabulary: [String: Int]
    private let idf: [Double]
    private let featureCount: Int   // exact TF-IDF dimension used in training

    init() {
        let config = MLModelConfiguration()
        do {
            self.model = try NewsTagger(configuration: config)
        } catch {
            Log.tagging.error("NewsTaggerService: failed to load model: \(error)")
            self.model = nil
            self.tags = []
            self.vocabulary = [:]
            self.idf = []
            self.featureCount = 0
            return
        }

        // Load tag names from model metadata (creatorDefined["tags"])
        if let creatorDefined = model?.model.modelDescription.metadata[.creatorDefinedKey] as? [String: String],
           let tagsString = creatorDefined["tags"] {
            self.tags = tagsString
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            self.tags = []
        }

        // Load TF-IDF metadata from bundled JSON
        guard let vocabURL = Bundle.main.url(forResource: "news_tfidf_vocab", withExtension: "json") else {
            Log.tagging.error("NewsTaggerService: news_tfidf_vocab.json not found in bundle")
            self.vocabulary = [:]
            self.idf = []
            self.featureCount = 0
            return
        }

        do {
            let data = try Data(contentsOf: vocabURL)
            guard let vocabPayload = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                Log.tagging.error("NewsTaggerService: vocab JSON is not a dictionary")
                self.vocabulary = [:]
                self.idf = []
                self.featureCount = 0
                return
            }
            self.vocabulary = vocabPayload["vocabulary"] as? [String: Int] ?? [:]
            self.idf = (vocabPayload["idf"] as? [Double]) ?? []
        } catch {
            Log.tagging.error("NewsTaggerService: failed to load vocab: \(error)")
            self.vocabulary = [:]
            self.idf = []
            self.featureCount = 0
            return
        }

        self.featureCount = idf.count
    }

    /// Public async API: get tags for an article.
    func tags(for article: Article) async -> [String] {
        guard model != nil else { return [] }

        let text = buildInputText(for: article)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        do {
            return try predictFromTFIDF(text: text)
        } catch {
            Log.tagging.error("NewsTaggerService error: \(error)")
            return []
        }
    }

    // MARK: - Input text

    private func buildInputText(for article: Article) -> String {
        var parts: [String] = []
        parts.append(article.title)
        if let description = article.description {
            parts.append(description)
        }
        if let content = article.content {
            parts.append(content)
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - TF-IDF + Core ML prediction

    private func predictFromTFIDF(text: String) throws -> [String] {
        // 1) Tokenize
        let tokens = tokenize(text: text)

        // 2) Build term frequencies
        var tfCounts = [Int: Int]()  // featureIndex -> count
        for token in tokens {
            if let idx = vocabulary[token] {
                tfCounts[idx, default: 0] += 1
            }
        }

        guard !tfCounts.isEmpty else {
            return []
        }

        // 3) Build TF-IDF feature vector
        let featuresArray = try MLMultiArray(shape: [NSNumber(value: featureCount)], dataType: .double)

        for i in 0..<featureCount {
            featuresArray[i] = 0
        }

        let totalTokens = tokens.count
        for (index, count) in tfCounts {
            if index < featureCount && index < idf.count {
                let tf = Double(count) / Double(totalTokens)
                let value = tf * idf[index]
                featuresArray[index] = NSNumber(value: value)
            }
        }

        // Debug: non-zero features
        var nonZeroCount = 0
        for i in 0..<featureCount {
            if featuresArray[i].doubleValue != 0 {
                nonZeroCount += 1
            }
        }


        // 4) Run Core ML model (linear logits)
        guard let model else { return [] }
        let input = NewsTaggerInput(features: featuresArray)
        let output = try model.prediction(input: input)

        guard let logitsArray = output.featureValue(for: "logits")?.multiArrayValue else {
            Log.tagging.error("NewsTaggerService: missing logits output")
            return []
        }

        func sigmoid(_ x: Double) -> Double {
            return 1.0 / (1.0 + exp(-x))
        }

        var tagProbs: [(String, Double)] = []
        for i in 0..<tags.count {
            let tagName = tags[i]
            let logit = logitsArray[i].doubleValue
            let prob = sigmoid(logit)
            tagProbs.append((tagName, prob))
        }

        _ = tagProbs.sorted { $0.1 > $1.1 }

        // 5) Threshold and sort
        let threshold = 0.15
        let maxTags = 6
        let selected = tagProbs
            .sorted { $0.1 > $1.1 }
            .prefix(maxTags)
            .filter { $0.1 >= threshold }
            .map { $0.0 }

        return normalizeTags(selected)
    }

    // Simple tokenizer: lowercased, split on non-letters/digits, drop very short tokens
    private func tokenize(text: String) -> [String] {
        let lower = text.lowercased()
        let separators = CharacterSet.alphanumerics.inverted
        return lower
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 2 }
    }

    // MARK: - Normalization

    private func normalizeTags(_ tags: [String]) -> [String] {
        let trimmed = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Array(Set(trimmed.map { $0.lowercased() }))
    }
}
