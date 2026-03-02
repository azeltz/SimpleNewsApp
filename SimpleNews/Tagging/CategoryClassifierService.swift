//
//  CategoryClassifierService.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/23/26.
//

import Foundation
import NaturalLanguage
import CoreML

/// Which backend is actively being used for classification.
enum ClassifierBackend: String {
    case nlModel = "NL"
    case coreML = "ML"
    case keywords = "Keyword"
}

/// Wraps the Apple-native MLTextClassifier model (raw text -> category).
/// Tries NLModel first, falls back to CoreML, then to keyword heuristic.
/// Automatically demotes to keywords after consecutive ML failures.
final class CategoryClassifierService {

    static let shared = CategoryClassifierService()

    private enum LoadedBackend {
        case nlModel(NLModel)
        case coreML(MLModel)
        case keywordsOnly
    }

    private let loadedBackend: LoadedBackend

    /// Tracks which backend is actually producing results right now.
    private(set) var activeBackend: ClassifierBackend

    /// After this many consecutive ML failures, permanently switch to keywords.
    private let failureThreshold = 3
    private var consecutiveFailures = 0
    private var demotedToKeywords = false

    private init() {
        guard let modelURL = Bundle.main.url(forResource: "NewsCategoryClassifier", withExtension: "mlmodelc") else {
            self.loadedBackend = .keywordsOnly
            self.activeBackend = .keywords
            return
        }

        // Try NLModel first
        if let nlModel = try? NLModel(contentsOf: modelURL) {
            let testLabel = nlModel.predictedLabel(for: "test")
            if testLabel != nil {
                self.loadedBackend = .nlModel(nlModel)
                self.activeBackend = .nlModel
                return
            }
        }

        // Fall back to raw CoreML
        if let coreModel = try? MLModel(contentsOf: modelURL) {
            self.loadedBackend = .coreML(coreModel)
            self.activeBackend = .coreML
            return
        }

        self.loadedBackend = .keywordsOnly
        self.activeBackend = .keywords
    }

    /// Predict category for an article. Returns nil only if no method works.
    func predictCategory(for article: Article) -> (String, [String: Double])? {
        let text = buildText(for: article)
        guard !text.isEmpty else { return nil }

        // If ML has failed too many times in a row, skip straight to keywords
        if demotedToKeywords {
            return predictWithKeywords(for: article)
        }

        // Try the loaded ML backend
        let mlResult: (String, [String: Double])?
        switch loadedBackend {
        case .nlModel(let model):
            mlResult = predictWithNLModel(model, text: text)
        case .coreML(let model):
            mlResult = predictWithCoreML(model, text: text)
        case .keywordsOnly:
            mlResult = nil
        }

        if mlResult != nil {
            consecutiveFailures = 0
            return mlResult
        }

        // ML failed — track it
        consecutiveFailures += 1
        if consecutiveFailures >= failureThreshold {
            demotedToKeywords = true
            activeBackend = .keywords
        }

        return predictWithKeywords(for: article)
    }

    // MARK: - NLModel path

    private func predictWithNLModel(_ model: NLModel, text: String) -> (String, [String: Double])? {
        guard let label = model.predictedLabel(for: text) else { return nil }
        let probs = model.predictedLabelHypotheses(for: text, maximumCount: 25)
        return (label, probs)
    }

    // MARK: - CoreML fallback path

    private func predictWithCoreML(_ model: MLModel, text: String) -> (String, [String: Double])? {
        do {
            let input = try MLDictionaryFeatureProvider(dictionary: ["text": text as NSString])
            let output = try model.prediction(from: input)

            guard let label = output.featureValue(for: "label")?.stringValue else { return nil }

            var probs: [String: Double] = [:]
            if let dict = output.featureValue(for: "labelProbability")?.dictionaryValue as? [String: Double] {
                probs = dict
            } else {
                probs[label] = 1.0
            }
            return (label, probs)
        } catch {
            return nil
        }
    }

    // MARK: - Keyword fallback path

    private func predictWithKeywords(for article: Article) -> (String, [String: Double])? {
        let text = buildText(for: article).lowercased()
        guard !text.isEmpty else { return nil }

        let allRules = KeywordTagger.shared.allCategoryRules()
        var scores: [String: Int] = [:]

        for catRules in allRules {
            var hits = 0
            for rule in catRules.tags {
                let matched = rule.keywords.contains { text.contains($0.lowercased()) }
                if matched { hits += 1 }
            }
            if hits > 0 {
                scores[catRules.category] = hits
            }
        }

        guard let best = scores.max(by: { $0.value < $1.value }) else { return nil }

        let total = Double(scores.values.reduce(0, +))
        var probs: [String: Double] = [:]
        for (cat, count) in scores {
            probs[cat] = Double(count) / total
        }

        return (best.key, probs)
    }

    // MARK: - Helpers

    private func buildText(for article: Article) -> String {
        [article.source ?? "", article.title, article.description ?? ""]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
