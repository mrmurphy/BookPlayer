//
//  ChapterPreviewTranscriptionService.swift
//  BookPlayer
//
//  Transcribes the first N seconds of each chapter for the chapters list preview.
//  Uses the shared PlaybackTranscriptStore so previews are reused by live playback.
//

import Foundation
@preconcurrency import BookPlayerKit

public protocol ChapterPreviewTranscriptionServiceProtocol: Sendable {
  /// Returns cached or newly transcribed text for the start of the chapter; nil on failure or empty.
  func ensureChapterPreview(
    item: PlayableItem,
    chapter: PlayableChapter,
    duration: TimeInterval
  ) async -> String?
}

public final class ChapterPreviewTranscriptionService: ChapterPreviewTranscriptionServiceProtocol, @unchecked Sendable {
  private let store: PlaybackTranscriptStoreProtocol
  private let engineFactory: () -> TranscriptEngineProtocol

  public init(
    store: PlaybackTranscriptStoreProtocol,
    engineFactory: @escaping () -> TranscriptEngineProtocol
  ) {
    self.store = store
    self.engineFactory = engineFactory
  }

  public func ensureChapterPreview(
    item: PlayableItem,
    chapter: PlayableChapter,
    duration: TimeInterval = Constants.ChapterPreview.defaultDuration
  ) async -> String? {
    let rangeEnd = min(duration, chapter.duration)
    guard rangeEnd > 0 else { return nil }
    guard FileManager.default.fileExists(atPath: chapter.fileURL.path) else { return nil }

    if let cached = cachedPreview(
      relativePath: item.relativePath,
      chapterIndex: chapter.index,
      rangeStart: 0,
      rangeEnd: rangeEnd
    ) {
      return cached
    }

    // For single-file books all chapters share one file; chapter.start is the offset in that file.
    // Transcribe from that offset so each chapter gets its own start, not the book’s start.
    let spec = TranscriptSegmentSpec(
      fileURL: chapter.fileURL,
      startTime: chapter.start,
      duration: rangeEnd
    )
    var text: String?
    do {
      let engine = engineFactory()
      text = try await engine.transcribe(segment: spec)
    } catch {
      if TranscriptEngineChoice.current == .parakeet {
        text = try? await AppleSpeechTranscriptEngine().transcribe(segment: spec)
      }
    }
    guard let text, !text.isEmpty else { return nil }

    try? store.store(
      relativePath: item.relativePath,
      chapterIndex: chapter.index,
      startInChapter: 0,
      duration: rangeEnd,
      text: text
    )
    return text
  }

  private func cachedPreview(
    relativePath: String,
    chapterIndex: Int16,
    rangeStart: TimeInterval,
    rangeEnd: TimeInterval
  ) -> String? {
    guard let lookups = try? store.segments(
      relativePath: relativePath,
      chapterIndex: chapterIndex,
      overlappingRangeStart: rangeStart,
      rangeEnd: rangeEnd
    ), !lookups.isEmpty else { return nil }

    let sorted = lookups.sorted { $0.startInChapter < $1.startInChapter }
    let first = sorted.first!
    let last = sorted.last!
    if first.startInChapter > rangeStart || (last.startInChapter + last.duration) < rangeEnd {
      return nil
    }
    return sorted.map(\.text).joined(separator: " ")
  }
}
