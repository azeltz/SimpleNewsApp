//
//  NewsAPIClient.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/13/26.
//

import Foundation

// MARK: - HTML entities decoding

extension String {
    /// Lightweight HTML entity decoder that works reliably with all scripts
    /// (Hebrew, Arabic, CJK, etc.) without depending on WebKit/NSAttributedString.
    var decodedHTMLEntities: String {
        guard contains("&") else { return self }

        var result = self

        // Named entities (most common in news feeds)
        let namedEntities: [String: String] = [
            "&amp;":   "&",
            "&lt;":    "<",
            "&gt;":    ">",
            "&quot;":  "\"",
            "&apos;":  "'",
            "&#39;":   "'",
            "&nbsp;":  " ",
            "&ndash;": "\u{2013}",
            "&mdash;": "\u{2014}",
            "&lsquo;": "\u{2018}",
            "&rsquo;": "\u{2019}",
            "&ldquo;": "\u{201C}",
            "&rdquo;": "\u{201D}",
            "&hellip;": "\u{2026}",
            "&copy;":  "\u{00A9}",
            "&reg;":   "\u{00AE}",
            "&trade;": "\u{2122}",
        ]

        for (entity, replacement) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Numeric entities: &#123; (decimal) and &#x1A2B; (hex)
        let decimalPattern = /&#(\d+);/
        while let match = result.firstMatch(of: decimalPattern) {
            if let codePoint = UInt32(match.1),
               let scalar = Unicode.Scalar(codePoint) {
                result.replaceSubrange(match.range, with: String(scalar))
            } else {
                break
            }
        }

        let hexPattern = /&#[xX]([0-9a-fA-F]+);/
        while let match = result.firstMatch(of: hexPattern) {
            if let codePoint = UInt32(match.1, radix: 16),
               let scalar = Unicode.Scalar(codePoint) {
                result.replaceSubrange(match.range, with: String(scalar))
            } else {
                break
            }
        }

        return result
    }

    /// Strips HTML tags from a string, leaving only text content.
    var strippedHTMLTags: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
