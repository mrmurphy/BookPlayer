//
//  MockPlaybackTranscriptStore.swift
//  BookPlayerTests
//
//  In-memory transcript store for testing run loading and play-position association.
//

import Foundation
@testable import BookPlayer
@testable import BookPlayerKit

/// Mock store that holds predefined runs. Use `preload(runs:relativePath:chapterIndex:)` to set test data.
final class MockPlaybackTranscriptStore: PlaybackTranscriptStoreProtocol, @unchecked Sendable {
  private var segments: [StoredTranscriptSegment] = []
  private let queue = DispatchQueue(label: "test.mock-transcript-store")

  func preload(runs: [(startInChapter: TimeInterval, duration: TimeInterval, text: String)], relativePath: String, chapterIndex: Int16) {
    queue.sync {
      segments.removeAll { $0.relativePath == relativePath && $0.chapterIndex == chapterIndex }
      for run in runs {
        segments.append(StoredTranscriptSegment(
          relativePath: relativePath,
          chapterIndex: chapterIndex,
          startInChapter: run.startInChapter,
          duration: run.duration,
          text: run.text
        ))
      }
      segments.sort { $0.startInChapter < $1.startInChapter }
    }
  }

  func clear() {
    queue.sync { segments.removeAll() }
  }

  func store(
    relativePath: String,
    chapterIndex: Int16,
    startInChapter: TimeInterval,
    duration: TimeInterval,
    text: String
  ) throws {
    queue.sync {
      let segment = StoredTranscriptSegment(
        relativePath: relativePath,
        chapterIndex: chapterIndex,
        startInChapter: startInChapter,
        duration: duration,
        text: text
      )
      segments.removeAll { $0.relativePath == relativePath && $0.chapterIndex == chapterIndex && $0.startInChapter == startInChapter }
      segments.append(segment)
      segments.sort { $0.startInChapter < $1.startInChapter }
    }
  }

  func segments(
    relativePath: String,
    chapterIndex: Int16,
    overlappingRangeStart rangeStart: TimeInterval,
    rangeEnd: TimeInterval
  ) throws -> [TranscriptSegmentLookup] {
    try queue.sync {
      return segments
        .filter { $0.relativePath == relativePath && $0.chapterIndex == chapterIndex && $0.overlaps(rangeStart: rangeStart, rangeEnd: rangeEnd) }
        .sorted { $0.startInChapter < $1.startInChapter }
        .map { TranscriptSegmentLookup(startInChapter: $0.startInChapter, duration: $0.duration, text: $0.text) }
    }
  }

  func textForPosition(
    relativePath: String,
    chapterIndex: Int16,
    timeInChapter: TimeInterval
  ) throws -> String? {
    try queue.sync {
      return segments.first { $0.relativePath == relativePath && $0.chapterIndex == chapterIndex && $0.contains(timeInChapter: timeInChapter) }?.text
    }
  }
}
