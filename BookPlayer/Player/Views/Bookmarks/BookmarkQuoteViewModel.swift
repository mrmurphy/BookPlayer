//
//  BookmarkQuoteViewModel.swift
//  BookPlayer
//

import BookPlayerKit
import Combine
import Foundation
import UIKit

@MainActor
final class BookmarkQuoteViewModel: ObservableObject {
  enum Phase: Equatable {
    case idle
    case working
    case failed(String)
  }

  @Published var secondsBefore: Double
  @Published var secondsAfter: Double
  @Published var showRaw: Bool = false
  @Published var includeMetadataInCopy: Bool = false
  @Published var phase: Phase = .idle
  @Published var snapshot: BookmarkQuoteSnapshot
  @Published var lastCleanupPath: QuoteCleanupPath?

  private let bookmark: SimpleBookmark
  private let playable: PlayableItem
  private let libraryService: LibraryServiceProtocol
  private let coordinator = BookmarkQuoteGenerationCoordinator()

  static let quoteTuningRange: ClosedRange<Double> = 5...180
  private static var minWindow: Double { quoteTuningRange.lowerBound }
  private static var maxWindow: Double { quoteTuningRange.upperBound }

  init(
    bookmark: SimpleBookmark,
    playable: PlayableItem,
    libraryService: LibraryServiceProtocol
  ) {
    self.bookmark = bookmark
    self.playable = playable
    self.libraryService = libraryService
    let shared = UserDefaults.sharedDefaults
    let defBefore = shared.double(forKey: Constants.UserDefaults.bookmarkQuoteSecondsBeforeDefault)
    let defAfter = shared.double(forKey: Constants.UserDefaults.bookmarkQuoteSecondsAfterDefault)
    let loaded = try? libraryService.loadQuoteSnapshot(for: bookmark)
    self.secondsBefore = loaded?.secondsBefore ?? (defBefore > 0 ? defBefore : 20)
    self.secondsAfter = loaded?.secondsAfter ?? (defAfter > 0 ? defAfter : 30)
    self.snapshot = loaded
      ?? BookmarkQuoteSnapshot(
        rawText: nil,
        cleanedText: nil,
        secondsBefore: nil,
        secondsAfter: nil,
        lastUpdated: nil
      )
  }

  func clampWindows() {
    secondsBefore = min(Self.maxWindow, max(Self.minWindow, secondsBefore))
    secondsAfter = min(Self.maxWindow, max(Self.minWindow, secondsAfter))
  }

  func bumpBefore(by delta: Double) {
    secondsBefore = min(Self.maxWindow, max(Self.minWindow, secondsBefore + delta))
  }

  func bumpAfter(by delta: Double) {
    secondsAfter = min(Self.maxWindow, max(Self.minWindow, secondsAfter + delta))
  }

  func updateQuote() async {
    clampWindows()
    phase = .working
    lastCleanupPath = nil
    do {
      let result = try await coordinator.generate(
        bookmark: bookmark,
        playable: playable,
        secondsBefore: secondsBefore,
        secondsAfter: secondsAfter,
        library: libraryService
      )
      snapshot = result.snapshot
      lastCleanupPath = result.cleanupPath
      phase = .idle
    } catch {
      phase = .failed(error.localizedDescription)
    }
  }

  func copyToPasteboard() {
    let quote = snapshot.cleanedText?.isEmpty == false ? snapshot.cleanedText! : BookmarkQuoteHeuristicCleaner.cleanedQuote(from: snapshot.rawText ?? "")
    let ts = TimeParser.formatTime(bookmark.time)
    let payload = BookmarkQuoteMetadataFormatter.clipboardPayload(
      cleanedQuote: quote,
      title: playable.title,
      author: playable.author,
      formattedTimestamp: ts,
      includeMetadata: includeMetadataInCopy
    )
    UIPasteboard.general.string = payload
  }
}
