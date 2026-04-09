//
//  LiveTranscriptGenerationTests.swift
//  BookPlayerTests
//
//  Tests transcript generation queue: prioritizes chunks under/near the playhead
//  and cancels in-flight work when the user seeks.
//

import Combine
import Foundation
import XCTest

@testable import BookPlayer
@testable import BookPlayerKit

// MARK: - Recording engine

/// Records transcription requests in order. Optional: blocks on first request until resumed.
final class RecordingTranscriptEngine: TranscriptEngineProtocol, @unchecked Sendable {
  struct Request: Sendable {
    let startInChapter: TimeInterval
    let duration: TimeInterval
  }

  private let lock = NSLock()
  private var _recorded: [Request] = []
  private var _blockFirst = false
  private var _firstRequestResume: (() -> Void)?

  var blockFirstRequest: Bool {
    get { lock.lock(); defer { lock.unlock() }; return _blockFirst }
    set { lock.lock(); defer { lock.unlock() }; _blockFirst = newValue }
  }

  func recordedRequests() -> [Request] {
    lock.lock(); defer { lock.unlock() }; return _recorded
  }

  func reset() {
    lock.lock()
    _recorded.removeAll()
    _blockFirst = false
    _firstRequestResume = nil
    lock.unlock()
  }

  /// Call from test after the first request has been recorded to resume the engine.
  func resumeFirstRequest() {
    lock.lock()
    let resume = _firstRequestResume
    _firstRequestResume = nil
    lock.unlock()
    resume?()
  }

  /// Wait until at least N requests have been recorded (busy loop with short sleeps).
  static func waitUntilRequests(
    _ engine: RecordingTranscriptEngine,
    count: Int,
    timeout: TimeInterval = 3
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if engine.recordedRequests().count >= count { return true }
      Thread.sleep(forTimeInterval: 0.02)
    }
    return false
  }

  func transcribe(segment: TranscriptSegmentSpec) async throws -> String {
    record(segment)
    await blockIfFirst()
    return "mock"
  }

  func transcribeWithRuns(segment: TranscriptSegmentSpec) async throws -> TranscriptionWithRuns? {
    record(segment)
    await blockIfFirst()
    return TranscriptionWithRuns(
      fullText: "mock",
      runs: [TranscriptRun(startInSegment: 0, duration: segment.duration, text: "mock")]
    )
  }

  private func record(_ spec: TranscriptSegmentSpec) {
    lock.lock()
    _recorded.append(Request(startInChapter: spec.startTime, duration: spec.duration))
    lock.unlock()
  }

  private func blockIfFirst() async {
    lock.lock()
    let shouldWait = _blockFirst && _recorded.count == 1
    lock.unlock()
    guard shouldWait else { return }
    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
      lock.lock()
      _firstRequestResume = { cont.resume() }
      lock.unlock()
    }
  }
}

// MARK: - Playback provider that can simulate position changes

private final class MockTranscriptPlaybackProvider: LiveTranscriptPlaybackProvider {
  private let itemSubject = CurrentValueSubject<PlayableItem?, Never>(nil)
  private let playingSubject = CurrentValueSubject<Bool, Never>(false)

  var currentItem: PlayableItem? { itemSubject.value }
  func currentItemPublisher() -> AnyPublisher<PlayableItem?, Never> { itemSubject.eraseToAnyPublisher() }
  func isPlayingPublisher() -> AnyPublisher<Bool, Never> { playingSubject.eraseToAnyPublisher() }
  func playbackPositionDidUpdatePublisher() -> AnyPublisher<Void, Never> {
    Empty(completeImmediately: false).eraseToAnyPublisher()
  }

  func setItem(_ item: PlayableItem?) { itemSubject.send(item) }
  func setPlaying(_ isPlaying: Bool) { playingSubject.send(isPlaying) }
}

private func makeItem(
  relativePath: String = "test-book",
  chapterStart: TimeInterval = 0,
  chapterDuration: TimeInterval = 60,
  currentTime: TimeInterval,
  chapterIndex: Int16 = 0
) -> PlayableItem {
  let chapter = PlayableChapter(
    title: "Chapter 1",
    author: "Test",
    start: chapterStart,
    duration: chapterDuration,
    relativePath: relativePath,
    remoteURL: nil,
    index: chapterIndex
  )
  return PlayableItem(
    title: "Test Book",
    author: "Test",
    chapters: [chapter],
    currentTime: currentTime,
    duration: chapterDuration,
    relativePath: relativePath,
    parentFolder: nil,
    percentCompleted: 0,
    lastPlayDate: nil,
    isFinished: false,
    isBoundBook: false
  )
}

private func runUntil(timeout: TimeInterval = 3, interval: TimeInterval = 0.05, condition: () -> Bool) {
  let deadline = Date().addingTimeInterval(timeout)
  while !condition(), Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(interval))
  }
}

// MARK: - Tests

final class LiveTranscriptGenerationTests: XCTestCase {

  private var store: MockPlaybackTranscriptStore!
  private var provider: MockTranscriptPlaybackProvider!
  private var engine: RecordingTranscriptEngine!
  private var controller: LiveTranscriptController!
  private var chapterFileURL: URL!

  override func setUpWithError() throws {
    store = MockPlaybackTranscriptStore()
    provider = MockTranscriptPlaybackProvider()
    engine = RecordingTranscriptEngine()
    engine.reset()
    controller = LiveTranscriptController(
      provider: provider,
      store: store,
      engineFactory: { [weak engine] in engine! }
    )
    let processed = DataManager.getProcessedFolderURL()
    chapterFileURL = processed.appendingPathComponent("test-book")
    try Data(" placeholder ".utf8).write(to: chapterFileURL)
  }

  override func tearDownWithError() throws {
    if let url = chapterFileURL {
      try? FileManager.default.removeItem(at: url)
    }
    store = nil
    provider = nil
    engine = nil
    controller = nil
    chapterFileURL = nil
  }

  // MARK: - Prioritization (ordering helper)

  /// Multiple uncovered 10s chunks: the one containing the playhead is ordered first, then nearer edges.
  func testChunkOrdering_prioritizesChunkContainingPlayheadThenByEdgeDistance() {
    typealias Chunk = (start: TimeInterval, duration: TimeInterval)
    var chunks: [Chunk] = [
      (0, 10),
      (20, 10),
      (10, 10),
    ]
    let playhead: TimeInterval = 12
    chunks.sort { a, b in
      LiveTranscriptController.distanceFromPlayheadToChunk(playhead: playhead, chunkStart: a.start, chunkDuration: a.duration)
        < LiveTranscriptController.distanceFromPlayheadToChunk(playhead: playhead, chunkStart: b.start, chunkDuration: b.duration)
    }
    XCTAssertEqual(chunks[0].start, 10, accuracy: 0.01, "Playhead 12 is inside [10,20)")
    XCTAssertEqual(chunks[1].start, 0, accuracy: 0.01, "Next nearest edge distance is 2 (end of [0,10))")
    XCTAssertEqual(chunks[2].start, 20, accuracy: 0.01)
  }

  func testDistanceFromPlayheadToChunk_insideInterval_isZero() {
    XCTAssertEqual(
      LiveTranscriptController.distanceFromPlayheadToChunk(playhead: 5, chunkStart: 0, chunkDuration: 10),
      0,
      accuracy: 0.001
    )
  }

  // MARK: - Prioritization (integration)

  /// The requested chunk is the one containing the playhead. With bufferLength 10 and chunk 10,
  /// at most one chunk is requested per fill; it must be the playhead chunk.
  func testFillBuffer_requestsChunkContainingPlayhead() {
    let relPath = "test-book"
    let chapterDuration: TimeInterval = 35
    let item = makeItem(relativePath: relPath, chapterDuration: chapterDuration, currentTime: 5)
    provider.setItem(item)
    provider.setPlaying(true)

    runUntil { engine.recordedRequests().count >= 1 }

    let reqs = engine.recordedRequests()
    XCTAssertGreaterThanOrEqual(reqs.count, 1, "Should request the playhead chunk")
    XCTAssertEqual(reqs[0].startInChapter, 5, accuracy: 0.01)
    XCTAssertEqual(reqs[0].duration, 10, accuracy: 0.01)
  }

  func testFillBuffer_playheadAtZero_requestsFromZero() {
    let relPath = "test-book"
    let chapterDuration: TimeInterval = 60
    let item = makeItem(relativePath: relPath, chapterDuration: chapterDuration, currentTime: 0)
    provider.setItem(item)
    provider.setPlaying(true)

    runUntil { engine.recordedRequests().count >= 1 }

    let reqs = engine.recordedRequests()
    XCTAssertGreaterThanOrEqual(reqs.count, 1)
    XCTAssertEqual(reqs[0].startInChapter, 0, accuracy: 0.01)
    XCTAssertEqual(reqs[0].duration, 10, accuracy: 0.01)
  }

  // MARK: - Cancellation on seek

  /// When the user seeks, the in-flight fill is cancelled and a new fill runs for the new position.
  /// We block the engine on the first request, seek, then resume; we must see (0,10) then (30,10)
  /// and must not see (10,20) from the old fill.
  func testFillBuffer_seekCancelsPreviousFill() {
    engine.blockFirstRequest = true
    let relPath = "test-book"
    let chapterDuration: TimeInterval = 60
    provider.setItem(makeItem(relativePath: relPath, chapterDuration: chapterDuration, currentTime: 0))
    provider.setPlaying(true)

    runUntil { engine.recordedRequests().count >= 1 }
    XCTAssertEqual(engine.recordedRequests().count, 1)
    XCTAssertEqual(engine.recordedRequests()[0].startInChapter, 0, accuracy: 0.01)

    provider.setItem(makeItem(relativePath: relPath, chapterDuration: chapterDuration, currentTime: 30))
    runUntil(timeout: 2) { engine.recordedRequests().count >= 2 }
    engine.resumeFirstRequest()

    let reqs = engine.recordedRequests()
    let starts = reqs.map(\.startInChapter)
    XCTAssertTrue(starts.contains(0), "Should have requested chunk at 0")
    XCTAssertTrue(starts.contains(30), "Should have requested chunk at 30 after seek")
    let fromOldFill = reqs.filter { $0.startInChapter >= 10 && $0.startInChapter < 20 }
    XCTAssertTrue(fromOldFill.isEmpty, "Old fill should be cancelled; no request for [10,20)")
  }
}
