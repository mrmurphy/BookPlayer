//
//  PlayerViewModelTests.swift
//  BookPlayerTests
//
//  Created by gianni.carlo on 14/7/23.
//  Copyright © 2023 BookPlayer LLC. All rights reserved.
//

import Combine
import XCTest

@testable import BookPlayer
@testable import BookPlayerKit

final class PlayerViewModelTests: XCTestCase {

  private final class BookmarkTranscriptionServiceMock: BookmarkTranscriptionServiceProtocol {
    var bookmarkUpdatesPublisher: AnyPublisher<String, Never> {
      Empty().eraseToAnyPublisher()
    }

    func startTranscription(for bookmark: SimpleBookmark, in item: PlayableItem) {}

    func updateTranscriptRange(
      for bookmark: SimpleBookmark,
      in item: PlayableItem,
      startOffset: TimeInterval,
      endOffset: TimeInterval
    ) {}

    func cancelTranscription(for bookmark: SimpleBookmark) {}
  }

  private final class MockLiveTranscriptPlaybackProvider: LiveTranscriptPlaybackProvider {
    var currentItem: PlayableItem? { nil }
    func currentItemPublisher() -> AnyPublisher<PlayableItem?, Never> { Just(nil).eraseToAnyPublisher() }
    func isPlayingPublisher() -> AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
    func playbackPositionDidUpdatePublisher() -> AnyPublisher<Void, Never> {
      Empty(completeImmediately: false).eraseToAnyPublisher()
    }
  }

  var sut: PlayerViewModel!

  override func setUpWithError() throws {
    let liveController = LiveTranscriptController(
      provider: MockLiveTranscriptPlaybackProvider(),
      store: PlaybackTranscriptStore(),
      engineFactory: { AppleSpeechTranscriptEngine() }
    )
    sut = PlayerViewModel(
      playerManager: PlayerManagerProtocolMock(),
      libraryService: LibraryServiceProtocolMock(),
      syncService: SyncServiceProtocolMock(),
      bookmarkTranscriptionService: BookmarkTranscriptionServiceMock(),
      liveTranscriptController: liveController
    )
  }

  override func tearDownWithError() throws {
    sut = nil
    UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.customSleepTimerDuration)
  }

  func testSettingLastCustomSleepTimerDuration() {
    let initialValue = UserDefaults.standard.double(forKey: Constants.UserDefaults.customSleepTimerDuration)

    XCTAssert(initialValue == 0)

    sut.handleCustomSleepTimerOption(seconds: 20)

    let newValue = UserDefaults.standard.double(forKey: Constants.UserDefaults.customSleepTimerDuration)

    XCTAssert(newValue == 20)
  }

  func testFetchingLastCustomSleepTimerDuration() {
    let initialValue = sut.getLastCustomSleepTimerDuration()

    XCTAssertNil(initialValue)

    UserDefaults.standard.set(30, forKey: Constants.UserDefaults.customSleepTimerDuration)

    let storedValue = sut.getLastCustomSleepTimerDuration()

    XCTAssert(storedValue == 30)
  }
}
