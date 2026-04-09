//
//  LiveTranscriptRunTests.swift
//  BookPlayerTests
//
//  Tests loading transcript runs for play positions and chapters, and associating
//  playback position with the correct run (currentRunIndex). Uses mock store and
//  mock playback provider; assertions are based on run timestamps and playhead.
//

import Combine
import XCTest

@testable import BookPlayer
@testable import BookPlayerKit

// MARK: - Mock playback provider

private final class MockTranscriptPlaybackProvider: LiveTranscriptPlaybackProvider {
  private let itemSubject = CurrentValueSubject<PlayableItem?, Never>(nil)
  private let playingSubject = CurrentValueSubject<Bool, Never>(false)

  var currentItem: PlayableItem? { itemSubject.value }
  func currentItemPublisher() -> AnyPublisher<PlayableItem?, Never> { itemSubject.eraseToAnyPublisher() }
  func isPlayingPublisher() -> AnyPublisher<Bool, Never> { playingSubject.eraseToAnyPublisher() }
  func playbackPositionDidUpdatePublisher() -> AnyPublisher<Void, Never> {
    Empty(completeImmediately: false).eraseToAnyPublisher()
  }

  func setItem(_ item: PlayableItem?) {
    itemSubject.send(item)
  }

  func setPlaying(_ isPlaying: Bool) {
    playingSubject.send(isPlaying)
  }
}

// MARK: - Test helpers

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

/// Runs the main run loop until the condition is true or timeout.
private func runUntil(
  timeout: TimeInterval = 2,
  interval: TimeInterval = 0.05,
  condition: () -> Bool
) {
  let deadline = Date().addingTimeInterval(timeout)
  while !condition(), Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(interval))
  }
}

// MARK: - Tests

final class LiveTranscriptRunTests: XCTestCase {

  private var store: MockPlaybackTranscriptStore!
  private var provider: MockTranscriptPlaybackProvider!
  private var controller: LiveTranscriptController!

  override func setUpWithError() throws {
    store = MockPlaybackTranscriptStore()
    provider = MockTranscriptPlaybackProvider()
    controller = LiveTranscriptController(
      provider: provider,
      store: store,
      engineFactory: { fatalError("Transcription should not run in these tests") }
    )
  }

  override func tearDownWithError() throws {
    store = nil
    provider = nil
    controller = nil
  }

  // MARK: - Load runs for play position

  /// With runs at [0,2) "Hello", [2,4) "world", [4,6) "today", playhead at 1.0 → currentRunIndex 0, runs contain all three.
  func testLoadRuns_playheadInsideFirstRun_returnsThatRunAsCurrent() {
    store.preload(
      runs: [
        (0, 2, "Hello"),
        (2, 2, "world"),
        (4, 2, "today"),
      ],
      relativePath: "test-book",
      chapterIndex: 0
    )
    let item = makeItem(currentTime: 1.0)
    provider.setItem(item)
    provider.setPlaying(true)

    runUntil { [weak controller] in
      guard let c = controller else { return true }
      return !c.transcriptRuns.isEmpty
    }

    XCTAssertEqual(controller.currentRunIndex, 0)
    XCTAssertEqual(controller.transcriptRuns.map(\.text), ["Hello", "world", "today"])
    XCTAssertEqual(controller.liveTranscriptText, "Hello")
  }

  /// Playhead at 3.0 (inside [2,4)) → currentRunIndex 1.
  func testLoadRuns_playheadInsideSecondRun_returnsSecondRunAsCurrent() {
    store.preload(
      runs: [
        (0, 2, "Hello"),
        (2, 4, "world"),
        (6, 2, "today"),
      ],
      relativePath: "test-book",
      chapterIndex: 0
    )
    let item = makeItem(currentTime: 3.0)
    provider.setItem(item)
    provider.setPlaying(true)

    runUntil { [weak controller] in controller?.transcriptRuns.count == 3 }

    XCTAssertEqual(controller.currentRunIndex, 1)
    XCTAssertEqual(controller.liveTranscriptText, "world")
  }

  /// Playhead at exactly 2.0 → belongs to [2,4) (start inclusive, end exclusive), so currentRunIndex 1.
  func testLoadRuns_playheadOnRunBoundary_associatesWithFollowingRun() {
    store.preload(
      runs: [
        (0, 2, "Hello"),
        (2, 2, "world"),
      ],
      relativePath: "test-book",
      chapterIndex: 0
    )
    let item = makeItem(currentTime: 2.0)
    provider.setItem(item)
    provider.setPlaying(true)

    runUntil { [weak controller] in controller?.transcriptRuns.count == 2 }

    XCTAssertEqual(controller.currentRunIndex, 1)
    XCTAssertEqual(controller.liveTranscriptText, "world")
  }

  /// Playhead at 0.0 → inside [0,2), currentRunIndex 0.
  func testLoadRuns_playheadAtZero_associatesWithFirstRun() {
    store.preload(
      runs: [(0, 2, "First"), (2, 2, "Second")],
      relativePath: "test-book",
      chapterIndex: 0
    )
    let item = makeItem(currentTime: 0.0)
    provider.setItem(item)
    provider.setPlaying(true)

    runUntil { [weak controller] in controller?.transcriptRuns.count == 2 }

    XCTAssertEqual(controller.currentRunIndex, 0)
    XCTAssertEqual(controller.liveTranscriptText, "First")
  }

  /// Playhead at 10.0 with runs only [0,6) → no run contains 10, currentRunIndex nil; window [0, 25] still returns those 3 runs.
  func testLoadRuns_playheadPastLastRun_returnsNilCurrentIndex() {
    store.preload(
      runs: [
        (0, 2, "Hello"),
        (2, 2, "world"),
        (4, 2, "today"),
      ],
      relativePath: "test-book",
      chapterIndex: 0
    )
    let item = makeItem(currentTime: 10.0)
    provider.setItem(item)
    provider.setPlaying(true)

    runUntil { [weak controller] in (controller?.transcriptRuns.count ?? 0) == 3 }

    XCTAssertNil(controller.currentRunIndex)
    XCTAssertEqual(controller.transcriptRuns.count, 3)
  }

  /// Playhead at 1.0 with runs only at [20,22) → window [0,16] doesn't overlap those runs → empty, currentRunIndex nil.
  func testLoadRuns_playheadBeforeFirstRun_returnsNilCurrentIndex() {
    store.preload(
      runs: [(20, 2, "Late")],
      relativePath: "test-book",
      chapterIndex: 0
    )
    let item = makeItem(currentTime: 1.0)
    provider.setItem(item)
    provider.setPlaying(true)

    runUntil(timeout: 1.5) { [weak controller] in
      controller != nil
    }

    XCTAssertNil(controller.currentRunIndex)
    XCTAssertTrue(controller.transcriptRuns.isEmpty)
  }

  // MARK: - Chapter and path isolation

  /// Runs for chapter 0 only; playhead in chapter 1 → no runs (different chapter).
  func testLoadRuns_respectsChapterIndex() {
    store.preload(
      runs: [(0, 5, "Ch0")],
      relativePath: "test-book",
      chapterIndex: 0
    )
    // Chapter 1: start 60, duration 60 → globalTime 60 → timeInChapter 0 for chapter 1
    let chapter1 = PlayableChapter(title: "Ch1", author: "T", start: 60, duration: 60, relativePath: "test-book", remoteURL: nil, index: 1)
    let item = PlayableItem(
      title: "T", author: "T", chapters: [chapter1],
      currentTime: 60,
      duration: 120,
      relativePath: "test-book",
      parentFolder: nil, percentCompleted: 0, lastPlayDate: nil, isFinished: false, isBoundBook: false
    )
    provider.setItem(item)
    provider.setPlaying(true)

    runUntil(timeout: 1.5) { [weak controller] in controller != nil }

    XCTAssertTrue(controller.transcriptRuns.isEmpty)
    XCTAssertNil(controller.currentRunIndex)
  }

  /// Runs for "book-a"; current item "book-b" → no runs.
  func testLoadRuns_respectsRelativePath() {
    store.preload(
      runs: [(0, 2, "From A")],
      relativePath: "book-a",
      chapterIndex: 0
    )
    let item = makeItem(relativePath: "book-b", currentTime: 1.0)
    provider.setItem(item)
    provider.setPlaying(true)

    runUntil(timeout: 1.5) { [weak controller] in controller != nil }

    XCTAssertTrue(controller.transcriptRuns.isEmpty)
    XCTAssertNil(controller.currentRunIndex)
  }

  // MARK: - Window around playhead

  /// Runs at [0,2), [20,22); playhead at 10 → window [0,25] includes both; currentRunIndex nil.
  func testLoadRuns_windowAroundPlayhead_returnsOnlyOverlappingRuns() {
    store.preload(
      runs: [
        (0, 2, "Early"),
        (20, 2, "Late"),
      ],
      relativePath: "test-book",
      chapterIndex: 0
    )
    let item = makeItem(currentTime: 10.0)
    provider.setItem(item)
    provider.setPlaying(true)

    runUntil { [weak controller] in controller?.transcriptRuns.count == 2 }

    XCTAssertEqual(controller.transcriptRuns.map(\.text), ["Early", "Late"])
    XCTAssertNil(controller.currentRunIndex)
  }

  // MARK: - Timestamp-based association

  /// Multiple runs; playhead moves to exact timestamps; each position maps to the expected run.
  func testPlaybackPosition_associatesWithCorrectTranscript_byTimestamp() {
    store.preload(
      runs: [
        (0, 1, "A"),
        (1, 1, "B"),
        (2, 1, "C"),
        (3, 1, "D"),
      ],
      relativePath: "test-book",
      chapterIndex: 0
    )

    for (globalTime, expectedIndex, expectedText) in [(0.0, 0, "A"), (0.5, 0, "A"), (1.0, 1, "B"), (2.5, 2, "C"), (3.5, 3, "D")] {
      let item = makeItem(currentTime: globalTime)
      provider.setItem(item)
      provider.setPlaying(true)

      runUntil { [weak controller] in
        guard let c = controller else { return true }
        return c.transcriptRuns.count == 4 && c.currentRunIndex == expectedIndex
      }

      XCTAssertEqual(controller.currentRunIndex, expectedIndex, "at globalTime \(globalTime)")
      XCTAssertEqual(controller.liveTranscriptText, expectedText, "at globalTime \(globalTime)")
    }
  }

  /// No item → empty runs, nil current index.
  func testLoadRuns_noCurrentItem_clearsRunsAndCurrentIndex() {
    store.preload(runs: [(0, 2, "X")], relativePath: "test-book", chapterIndex: 0)
    let item = makeItem(currentTime: 1.0)
    provider.setItem(item)
    provider.setPlaying(true)
    runUntil { [weak controller] in controller?.transcriptRuns.count == 1 }
    XCTAssertEqual(controller.currentRunIndex, 0)

    provider.setItem(nil)
    runUntil(timeout: 0.5) { [weak controller] in (controller?.transcriptRuns.isEmpty ?? true) }

    XCTAssertTrue(controller.transcriptRuns.isEmpty)
    XCTAssertNil(controller.currentRunIndex)
  }
}
