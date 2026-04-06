//
//  BookmarkQuoteModels.swift
//  BookPlayerKit
//

import Foundation

public struct BookmarkQuoteSnapshot: Equatable, Sendable {
  public var rawText: String?
  public var cleanedText: String?
  public var secondsBefore: Double?
  public var secondsAfter: Double?
  public var lastUpdated: Date?

  public init(
    rawText: String?,
    cleanedText: String?,
    secondsBefore: Double?,
    secondsAfter: Double?,
    lastUpdated: Date?
  ) {
    self.rawText = rawText
    self.cleanedText = cleanedText
    self.secondsBefore = secondsBefore
    self.secondsAfter = secondsAfter
    self.lastUpdated = lastUpdated
  }
}

public enum BookmarkQuoteServiceError: Error {
  case bookmarkNotFound
}

public enum QuoteCleanupPath: String, Sendable {
  case foundationModels
  case heuristic
}
