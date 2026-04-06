//
//  BookmarkQuoteCleanerFacade.swift
//  BookPlayerKit
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

public enum BookmarkQuoteCleanerFacade {
  public static func clean(raw: String) async -> (text: String, path: QuoteCleanupPath) {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
      if case .available = SystemLanguageModel.default.availability {
        if let text = try? await BookmarkQuoteFoundationModelsCleaner.cleanedQuote(from: raw) {
          return (text, .foundationModels)
        }
      }
    }
    #endif
    let heuristic = BookmarkQuoteHeuristicCleaner.cleanedQuote(from: raw)
    return (heuristic, .heuristic)
  }
}
