//
//  PlaybackTranscriptStore.swift
//  BookPlayer
//
//  Persists transcription segments by (relativePath, chapterIndex, startInChapter, duration)
//  for reuse by live playback transcript and bookmark transcript lookup.
//

import Foundation
@preconcurrency import BookPlayerKit

/// A single stored segment: identity + text.
public struct StoredTranscriptSegment: Codable, Sendable {
  public let relativePath: String
  public let chapterIndex: Int16
  public let startInChapter: TimeInterval
  public let duration: TimeInterval
  public let text: String

  public init(
    relativePath: String,
    chapterIndex: Int16,
    startInChapter: TimeInterval,
    duration: TimeInterval,
    text: String
  ) {
    self.relativePath = relativePath
    self.chapterIndex = chapterIndex
    self.startInChapter = startInChapter
    self.duration = duration
    self.text = text
  }

  public var endInChapter: TimeInterval {
    startInChapter + duration
  }

  public func contains(timeInChapter: TimeInterval) -> Bool {
    timeInChapter >= startInChapter && timeInChapter < endInChapter
  }

  public func overlaps(rangeStart: TimeInterval, rangeEnd: TimeInterval) -> Bool {
    rangeStart < endInChapter && rangeEnd > startInChapter
  }
}

/// Result of looking up segments overlapping a range.
public struct TranscriptSegmentLookup: Sendable {
  public let startInChapter: TimeInterval
  public let duration: TimeInterval
  public let text: String

  public init(startInChapter: TimeInterval, duration: TimeInterval, text: String) {
    self.startInChapter = startInChapter
    self.duration = duration
    self.text = text
  }
}

public protocol PlaybackTranscriptStoreProtocol: Sendable {
  func store(
    relativePath: String,
    chapterIndex: Int16,
    startInChapter: TimeInterval,
    duration: TimeInterval,
    text: String
  ) throws

  /// Returns segments that overlap [rangeStart, rangeEnd] for the given book/chapter, sorted by startInChapter.
  func segments(
    relativePath: String,
    chapterIndex: Int16,
    overlappingRangeStart rangeStart: TimeInterval,
    rangeEnd: TimeInterval
  ) throws -> [TranscriptSegmentLookup]

  /// Returns the text for the segment containing `timeInChapter`, or nil if none.
  func textForPosition(
    relativePath: String,
    chapterIndex: Int16,
    timeInChapter: TimeInterval
  ) throws -> String?
}

/// In-memory + optional JSON persistence. One JSON file per book (keyed by sanitized relativePath).
public final class PlaybackTranscriptStore: PlaybackTranscriptStoreProtocol, @unchecked Sendable {
  private let fileManager = FileManager.default
  private let queue = DispatchQueue(label: "com.bookplayer.playback-transcript-store", qos: .utility)
  private var inMemory: [String: [StoredTranscriptSegment]] = [:]
  private let cacheDirectoryURL: URL
  private let maxSegmentsPerBook: Int

  public init(
    cacheDirectoryURL: URL? = nil,
    maxSegmentsPerBook: Int = 2000
  ) {
    if let url = cacheDirectoryURL {
      self.cacheDirectoryURL = url
    } else {
      let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
      self.cacheDirectoryURL = appSupport.appendingPathComponent("TranscriptCache", isDirectory: true)
    }
    self.maxSegmentsPerBook = maxSegmentsPerBook
    self.ensureDirectoryExists()
    self.loadAllFromDisk()
  }

  private func ensureDirectoryExists() {
    if !fileManager.fileExists(atPath: cacheDirectoryURL.path) {
      try? fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
    }
  }

  private func filename(for relativePath: String) -> String {
    let sanitized = relativePath
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: ":", with: "_")
    return (sanitized.isEmpty ? "default" : sanitized) + ".json"
  }

  private func fileURL(for relativePath: String) -> URL {
    cacheDirectoryURL.appendingPathComponent(filename(for: relativePath))
  }

  private func loadAllFromDisk() {
    queue.sync {
      guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirectoryURL, includingPropertiesForKeys: nil) else { return }
      for url in contents where url.pathExtension == "json" {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([StoredTranscriptSegment].self, from: data),
              !decoded.isEmpty
        else { continue }
        let key = decoded[0].relativePath
        inMemory[key] = decoded
      }
    }
  }

  /// Must only be called from within a block already executing on `queue` (e.g. from store/segments/textForPosition).
  private func loadFromDiskIfNeeded(relativePath: String) {
    guard inMemory[relativePath] == nil else { return }
    let url = fileURL(for: relativePath)
    guard fileManager.fileExists(atPath: url.path),
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode([StoredTranscriptSegment].self, from: data)
    else { return }
    inMemory[relativePath] = decoded
  }

  private func saveToDisk(relativePath: String) {
    let segments = inMemory[relativePath] ?? []
    let url = fileURL(for: relativePath)
    if segments.isEmpty {
      try? fileManager.removeItem(at: url)
      return
    }
    guard let data = try? JSONEncoder().encode(segments) else { return }
    try? data.write(to: url)
  }

  public func store(
    relativePath: String,
    chapterIndex: Int16,
    startInChapter: TimeInterval,
    duration: TimeInterval,
    text: String
  ) throws {
    guard !text.isEmpty else { return }
    let segment = StoredTranscriptSegment(
      relativePath: relativePath,
      chapterIndex: chapterIndex,
      startInChapter: startInChapter,
      duration: duration,
      text: text
    )
    try queue.sync {
      loadFromDiskIfNeeded(relativePath: relativePath)
      var list = inMemory[relativePath] ?? []
      list.removeAll { s in
        s.chapterIndex == chapterIndex && s.startInChapter == startInChapter
      }
      list.append(segment)
      list.sort { $0.startInChapter < $1.startInChapter }
      if list.count > maxSegmentsPerBook {
        list = Array(list.suffix(maxSegmentsPerBook))
      }
      inMemory[relativePath] = list
      saveToDisk(relativePath: relativePath)
    }
  }

  public func segments(
    relativePath: String,
    chapterIndex: Int16,
    overlappingRangeStart rangeStart: TimeInterval,
    rangeEnd: TimeInterval
  ) throws -> [TranscriptSegmentLookup] {
    try queue.sync {
      loadFromDiskIfNeeded(relativePath: relativePath)
      let list = inMemory[relativePath] ?? []
      return list
        .filter { $0.chapterIndex == chapterIndex && $0.overlaps(rangeStart: rangeStart, rangeEnd: rangeEnd) }
        .sorted { $0.startInChapter < $1.startInChapter }
        .map { TranscriptSegmentLookup(startInChapter: $0.startInChapter, duration: $0.duration, text: $0.text) }
    }
  }

  public func textForPosition(
    relativePath: String,
    chapterIndex: Int16,
    timeInChapter: TimeInterval
  ) throws -> String? {
    try queue.sync {
      loadFromDiskIfNeeded(relativePath: relativePath)
      let list = inMemory[relativePath] ?? []
      return list.first { $0.chapterIndex == chapterIndex && $0.contains(timeInChapter: timeInChapter) }?.text
    }
  }

  /// Removes all cached transcriptions from memory and deletes all persisted cache files.
  public func resetCache() {
    queue.sync {
      inMemory.removeAll()
      guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirectoryURL, includingPropertiesForKeys: nil) else { return }
      for url in contents where url.pathExtension == "json" {
        try? fileManager.removeItem(at: url)
      }
    }
  }
}
