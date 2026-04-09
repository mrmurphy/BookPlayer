//
//  BookmarksViewModel.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 5/9/21.
//  Copyright © 2021 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import Combine
import Foundation

final class BookmarksViewModel: BookmarksView.Model {
  let playerManager: PlayerManagerProtocol
  let libraryService: LibraryServiceProtocol
  let syncService: SyncServiceProtocol
  let bookmarkTranscriptionService: BookmarkTranscriptionServiceProtocol

  private var disposeBag = Set<AnyCancellable>()

  init(
    playerManager: PlayerManagerProtocol,
    libraryService: LibraryServiceProtocol,
    syncService: SyncServiceProtocol,
    bookmarkTranscriptionService: BookmarkTranscriptionServiceProtocol
  ) {
    self.playerManager = playerManager
    self.libraryService = libraryService
    self.syncService = syncService
    self.bookmarkTranscriptionService = bookmarkTranscriptionService
    
    super.init()
    
    self.bindCurrentItemObserver()
    self.bindTranscriptUpdates()
  }

  func bindCurrentItemObserver() {
    playerManager.currentItemPublisher()
      .sink { [weak self] currentItem in
        guard let self else { return }

        self.currentItem = currentItem

        if let currentItem {
          self.automaticBookmarks = self.getAutomaticBookmarks(for: currentItem.relativePath)
          self.userBookmarks = self.getUserBookmarks(for: currentItem.relativePath)
          self.syncBookmarks(for: currentItem.relativePath)
        } else {
          self.automaticBookmarks = []
          self.userBookmarks = []
        }
      }
      .store(in: &disposeBag)
  }

  func getAutomaticBookmarks(for relativePath: String) -> [SimpleBookmark] {
    let playBookmarks = self.libraryService.getBookmarks(of: .play, relativePath: relativePath) ?? []
    let skipBookmarks = self.libraryService.getBookmarks(of: .skip, relativePath: relativePath) ?? []
    let sleepBookmarks = self.libraryService.getBookmarks(of: .sleep, relativePath: relativePath) ?? []

    let bookmarks = playBookmarks + skipBookmarks + sleepBookmarks

    return bookmarks.sorted(by: { $0.time < $1.time })
  }

  func getUserBookmarks(for relativePath: String) -> [SimpleBookmark] {
    return self.libraryService.getBookmarks(of: .user, relativePath: relativePath) ?? []
  }

  override func handleBookmarkSelected(_ bookmark: SimpleBookmark) {
    self.playerManager.jumpTo(bookmark.time + 0.01, recordBookmark: false)
  }

  override func addNote(_ note: String, bookmark: SimpleBookmark) {
    libraryService.addNote(note, bookmark: bookmark)
    userBookmarks = getUserBookmarks(for: bookmark.relativePath)
    syncService.scheduleSetBookmark(
      relativePath: bookmark.relativePath,
      time: bookmark.time,
      note: note
    )
  }

  override func deleteBookmark(_ bookmark: SimpleBookmark) {
    bookmarkTranscriptionService.cancelTranscription(for: bookmark)
    libraryService.deleteBookmark(bookmark)
    userBookmarks = getUserBookmarks(for: bookmark.relativePath)
    syncService.scheduleDeleteBookmark(bookmark)
  }

  override func ensureTranscript(_ bookmark: SimpleBookmark) {
    guard let currentItem else { return }

    switch bookmark.transcriptState {
    case .none, .failed:
      bookmarkTranscriptionService.startTranscription(for: bookmark, in: currentItem)
    case .pending, .ready:
      break
    }
  }

  override func adjustTranscriptStart(_ bookmark: SimpleBookmark, delta: TimeInterval) {
    guard let currentItem else { return }

    let newStart = min(
      max(bookmark.transcriptStartOffset + delta, Constants.BookmarkTranscript.minOffset),
      Constants.BookmarkTranscript.maxOffset
    )

    bookmarkTranscriptionService.updateTranscriptRange(
      for: bookmark,
      in: currentItem,
      startOffset: newStart,
      endOffset: bookmark.transcriptEndOffset
    )
  }

  override func adjustTranscriptEnd(_ bookmark: SimpleBookmark, delta: TimeInterval) {
    guard let currentItem else { return }

    let newEnd = min(
      max(bookmark.transcriptEndOffset + delta, Constants.BookmarkTranscript.minOffset),
      Constants.BookmarkTranscript.maxOffset
    )

    bookmarkTranscriptionService.updateTranscriptRange(
      for: bookmark,
      in: currentItem,
      startOffset: bookmark.transcriptStartOffset,
      endOffset: newEnd
    )
  }

  private func bindTranscriptUpdates() {
    bookmarkTranscriptionService.bookmarkUpdatesPublisher
      .receive(on: DispatchQueue.main)
      .sink { [weak self] relativePath in
        guard let self = self else { return }
        guard let currentItem = self.currentItem, currentItem.relativePath == relativePath else { return }
        self.userBookmarks = self.getUserBookmarks(for: relativePath)
      }
      .store(in: &disposeBag)
  }

  func syncBookmarks(for relativePath: String) {
    Task { [weak self] in
      guard
        let self = self,
        let bookmarks = try await self.syncService.syncBookmarksList(relativePath: relativePath)
      else { return }

      self.userBookmarks = bookmarks
    }
  }
}
