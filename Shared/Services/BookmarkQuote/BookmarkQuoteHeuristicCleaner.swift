//
//  BookmarkQuoteHeuristicCleaner.swift
//  BookPlayerKit
//

import Foundation
import NaturalLanguage

public enum BookmarkQuoteHeuristicCleaner {
  /// Sentence-based trim when Foundation Models is unavailable.
  public static func cleanedQuote(from raw: String) -> String {
    let singleLine = raw
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")

    let collapsed = singleLine.replacingOccurrences(
      of: "  +",
      with: " ",
      options: .regularExpression
    ).trimmingCharacters(in: .whitespacesAndNewlines)

    guard !collapsed.isEmpty else { return "" }

    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = collapsed

    var ranges: [Range<String.Index>] = []
    tokenizer.enumerateTokens(in: collapsed.startIndex..<collapsed.endIndex) { range, _ in
      ranges.append(range)
      return true
    }

    guard let firstRange = ranges.first, let lastRange = ranges.last else {
      return "…" + collapsed + "…"
    }

    let excerpt = String(collapsed[firstRange.lowerBound..<lastRange.upperBound])
    let trimmedExcerpt = excerpt.trimmingCharacters(in: .whitespacesAndNewlines)

    let leadingEllipsis = firstRange.lowerBound > collapsed.startIndex
    let trailingEllipsis = lastRange.upperBound < collapsed.endIndex

    if trimmedExcerpt.isEmpty {
      return "…" + collapsed + "…"
    }

    var result = trimmedExcerpt
    if leadingEllipsis { result = "…" + result }
    if trailingEllipsis { result = result + "…" }
    return result
  }
}
