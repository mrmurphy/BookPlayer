//
//  LiveTranscriptController.swift
//  BookPlayer
//
//  Drives live transcript for playback: buffer ~10s ahead of playhead, expose current text.
//

import Combine
import Foundation
@preconcurrency import BookPlayerKit

private let bufferLength: TimeInterval = 10
private let chunkDuration: TimeInterval = 10
private let runsWindowHalf: TimeInterval = 15

/// Provides playback state for the live transcript. PlayerManager conforms.
public protocol LiveTranscriptPlaybackProvider: AnyObject {
  var currentItem: PlayableItem? { get }
  func currentItemPublisher() -> AnyPublisher<PlayableItem?, Never>
  func isPlayingPublisher() -> AnyPublisher<Bool, Never>
  /// Emits when the playhead has been updated (same source as progress UI). Subscribe to drive transcript tick.
  func playbackPositionDidUpdatePublisher() -> AnyPublisher<Void, Never>
}

extension LiveTranscriptPlaybackProvider {
  public func playbackPositionDidUpdatePublisher() -> AnyPublisher<Void, Never> {
    Empty(completeImmediately: false).eraseToAnyPublisher()
  }
}

extension PlayerManager: LiveTranscriptPlaybackProvider {}

/// Owns buffer-fill and current-segment text for the now-playing transcript.
public final class LiveTranscriptController: ObservableObject {
  @Published public private(set) var liveTranscriptText: String = ""

  /// Runs overlapping a window around the playhead, for karaoke-style highlighting.
  @Published public private(set) var transcriptRuns: [TranscriptSegmentLookup] = []
  @Published public private(set) var currentRunIndex: Int?

  private let provider: LiveTranscriptPlaybackProvider
  private let store: PlaybackTranscriptStoreProtocol
  private let engineFactory: () -> TranscriptEngineProtocol
  private var cancellables = Set<AnyCancellable>()
  private var positionUpdateCancellable: AnyCancellable?
  private var fillBufferTask: Task<Void, Never>?
  private var fillBufferTaskId: UInt64 = 0
  private let inFlightLock = NSLock()
  private var lastBufferPosition: (path: String, chapter: Int16, start: TimeInterval)?

  public init(
    provider: LiveTranscriptPlaybackProvider,
    store: PlaybackTranscriptStoreProtocol,
    engineFactory: @escaping () -> TranscriptEngineProtocol
  ) {
    self.provider = provider
    self.store = store
    self.engineFactory = engineFactory
    bindPlayback()
  }

  private func bindPlayback() {
    Publishers.CombineLatest(
      provider.currentItemPublisher(),
      provider.isPlayingPublisher()
    )
    .receive(on: DispatchQueue.main)
    .sink { [weak self] item, isPlaying in
      self?.handlePlaybackState(item: item, isPlaying: isPlaying)
    }
    .store(in: &cancellables)
  }

  private func handlePlaybackState(item: PlayableItem?, isPlaying: Bool) {
    positionUpdateCancellable?.cancel()
    positionUpdateCancellable = nil
    guard let item else {
      liveTranscriptText = ""
      transcriptRuns = []
      currentRunIndex = nil
      lastBufferPosition = nil
      return
    }
    // Run tick once for the current position, then subscribe to the same playhead-update stream the progress UI uses.
    tick()
    positionUpdateCancellable = provider.playbackPositionDidUpdatePublisher()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.tick()
      }
  }

  private func tick() {
    guard let item = provider.currentItem else {
      liveTranscriptText = ""
      transcriptRuns = []
      currentRunIndex = nil
      return
    }
    let globalTime = item.currentTime
    guard let chapter = item.getChapter(at: globalTime) else {
      liveTranscriptText = ""
      transcriptRuns = []
      currentRunIndex = nil
      return
    }
    let timeInChapter = item.getChapterTime(in: chapter, for: globalTime)
    let relPath = item.relativePath
    let chIndex = chapter.index

    let pos = (path: relPath, chapter: chIndex, start: timeInChapter)
    if lastBufferPosition.map({ $0.path != pos.path || $0.chapter != pos.chapter || abs($0.start - pos.start) > 2 }) ?? true {
      lastBufferPosition = pos
      fillBuffer(relativePath: relPath, chapter: chapter, item: item, fromTimeInChapter: timeInChapter)
    }

    let rangeStart = max(0, timeInChapter - runsWindowHalf)
    let rangeEnd = min(chapter.duration, timeInChapter + runsWindowHalf)
    let runs = (try? store.segments(
      relativePath: relPath,
      chapterIndex: chIndex,
      overlappingRangeStart: rangeStart,
      rangeEnd: rangeEnd
    )) ?? []
    transcriptRuns = runs
    currentRunIndex = runs.firstIndex { timeInChapter >= $0.startInChapter && timeInChapter < $0.startInChapter + $0.duration }

    let text = (try? store.textForPosition(
      relativePath: relPath,
      chapterIndex: chIndex,
      timeInChapter: timeInChapter
    )) ?? ""
    liveTranscriptText = text
  }

  private func fillBuffer(
    relativePath: String,
    chapter: PlayableChapter,
    item: PlayableItem,
    fromTimeInChapter start: TimeInterval
  ) {
    let rangeEnd = min(start + bufferLength, chapter.duration)
    guard rangeEnd > start else { return }

    fillBufferTask?.cancel()
    fillBufferTaskId &+= 1
    let myId = fillBufferTaskId
    var task: Task<Void, Never>!
    task = Task.detached(priority: .utility) { [weak self] in
      defer {
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          if self.fillBufferTaskId == myId {
            self.fillBufferTask = nil
          }
        }
      }
      guard let self else { return }

      typealias Chunk = (start: TimeInterval, duration: TimeInterval)
      var uncovered: [Chunk] = []
      var chunkStart = start
      while chunkStart < rangeEnd {
        let chunkDurationActual = min(chunkDuration, rangeEnd - chunkStart)
        let chunkEnd = chunkStart + chunkDurationActual
        let overlaps = (try? self.store.segments(
          relativePath: relativePath,
          chapterIndex: chapter.index,
          overlappingRangeStart: chunkStart,
          rangeEnd: chunkEnd
        )) ?? []
        if !Self.chunkIsCovered(by: overlaps, chunkStart: chunkStart, chunkEnd: chunkEnd) {
          uncovered.append((chunkStart, chunkDurationActual))
        }
        chunkStart += chunkDurationActual
      }
      // Prioritize chunk under or nearest the playhead.
      uncovered.sort { a, b in
        Self.distanceFromPlayheadToChunk(playhead: start, chunkStart: a.start, chunkDuration: a.duration)
          < Self.distanceFromPlayheadToChunk(playhead: start, chunkStart: b.start, chunkDuration: b.duration)
      }

      for (chunkStart, chunkDurationActual) in uncovered {
        if Task.isCancelled { break }
        await self.transcribeChunk(
          item: item,
          chapter: chapter,
          startInChapter: chunkStart,
          duration: chunkDurationActual
        )
      }
    }
    fillBufferTask = task
  }

  /// Distance used to order uncovered chunks: 0 when the playhead lies inside the chunk; otherwise minimum edge distance.
  internal static func distanceFromPlayheadToChunk(playhead: TimeInterval, chunkStart: TimeInterval, chunkDuration: TimeInterval) -> TimeInterval {
    let chunkEnd = chunkStart + chunkDuration
    if chunkStart <= playhead && playhead < chunkEnd { return 0 }
    return min(abs(chunkStart - playhead), abs(chunkEnd - playhead))
  }

  private static func chunkIsCovered(by overlaps: [TranscriptSegmentLookup], chunkStart: TimeInterval, chunkEnd: TimeInterval) -> Bool {
    guard chunkEnd > chunkStart else { return true }
    var t = chunkStart
    for seg in overlaps.sorted(by: { $0.startInChapter < $1.startInChapter }) {
      if seg.startInChapter > t { break }
      t = max(t, seg.startInChapter + seg.duration)
    }
    return t >= chunkEnd
  }

  private func transcribeChunk(
    item: PlayableItem,
    chapter: PlayableChapter,
    startInChapter: TimeInterval,
    duration: TimeInterval
  ) async {
    guard FileManager.default.fileExists(atPath: chapter.fileURL.path) else { return }

    let spec = TranscriptSegmentSpec(
      fileURL: chapter.fileURL,
      startTime: startInChapter,
      duration: duration
    )
    let engine = engineFactory()

    if let withRuns = try? await engine.transcribeWithRuns(segment: spec), !withRuns.runs.isEmpty {
      for run in withRuns.runs {
        let start = startInChapter + run.startInSegment
        guard !run.text.isEmpty else { continue }
        try? store.store(
          relativePath: item.relativePath,
          chapterIndex: chapter.index,
          startInChapter: start,
          duration: run.duration,
          text: run.text
        )
      }
      return
    }

    var text: String?
    do {
      text = try await engine.transcribe(segment: spec)
    } catch {
      if TranscriptEngineChoice.current == .parakeet {
        text = try? await AppleSpeechTranscriptEngine().transcribe(segment: spec)
      }
    }
    guard let text, !text.isEmpty else { return }
    try? store.store(
      relativePath: item.relativePath,
      chapterIndex: chapter.index,
      startInChapter: startInChapter,
      duration: duration,
      text: text
    )
  }
}
