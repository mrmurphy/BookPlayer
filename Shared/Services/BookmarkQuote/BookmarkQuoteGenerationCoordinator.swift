//
//  BookmarkQuoteGenerationCoordinator.swift
//  BookPlayerKit
//

import Foundation

public struct BookmarkQuoteGenerationResult: Sendable {
  public let snapshot: BookmarkQuoteSnapshot
  public let cleanupPath: QuoteCleanupPath

  public init(snapshot: BookmarkQuoteSnapshot, cleanupPath: QuoteCleanupPath) {
    self.snapshot = snapshot
    self.cleanupPath = cleanupPath
  }
}

public actor BookmarkQuoteGenerationCoordinator {
  public init() {}

  public func generate(
    bookmark: SimpleBookmark,
    playable: PlayableItem,
    secondsBefore: Double,
    secondsAfter: Double,
    library: LibraryServiceProtocol
  ) async throws -> BookmarkQuoteGenerationResult {
    let start = max(0, bookmark.time - secondsBefore)
    let end = min(playable.duration, bookmark.time + secondsAfter)

    let extractor = BookmarkAudioSegmentExtractor()
    let segmentURL = try await extractor.exportSegment(
      sourceURL: playable.fileURL,
      start: start,
      end: end
    )
    defer { try? FileManager.default.removeItem(at: segmentURL) }

    let raw = try await BookmarkSpeechTranscriber().transcribe(fileURL: segmentURL)
    let cleaned = await BookmarkQuoteCleanerFacade.clean(raw: raw)

    try library.saveQuote(
      for: bookmark,
      raw: raw,
      cleaned: cleaned.text,
      secondsBefore: secondsBefore,
      secondsAfter: secondsAfter
    )
    let snapshot = try library.loadQuoteSnapshot(for: bookmark)
    return BookmarkQuoteGenerationResult(snapshot: snapshot, cleanupPath: cleaned.path)
  }
}
