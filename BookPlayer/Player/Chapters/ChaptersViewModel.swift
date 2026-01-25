//
//  ChaptersViewModel.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 30/8/21.
//  Copyright © 2021 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import Combine
import Foundation

final class ChaptersViewModel: ChaptersView.Model {
  private let playerManager: PlayerManagerProtocol
  private let chapterPreviewService: ChapterPreviewTranscriptionServiceProtocol?

  init(
    playerManager: PlayerManagerProtocol,
    chapterPreviewService: ChapterPreviewTranscriptionServiceProtocol? = nil
  ) {
    self.playerManager = playerManager
    self.chapterPreviewService = chapterPreviewService
    super.init(
      chapters: playerManager.currentItem?.chapters ?? [],
      currentChapter: playerManager.currentItem?.currentChapter
    )
  }

  override func handleChapterSelected(_ chapter: PlayableChapter) {
    self.playerManager.jumpToChapter(chapter)
  }

  override func loadPreviewsIfNeeded() {
    guard let service = chapterPreviewService,
          let item = playerManager.currentItem else { return }
    let chapters = self.chapters
    Task.detached(priority: .utility) { [weak self] in
      guard let self else { return }
      // Process one chapter at a time so the UI shows a single "Transcribing…" for the current job.
      for chapter in chapters {
        await MainActor.run {
          self.transcribingChapterIndex = chapter.index
        }
        let text = await service.ensureChapterPreview(
          item: item,
          chapter: chapter,
          duration: Constants.ChapterPreview.defaultDuration
        )
        await MainActor.run {
          self.previewTexts[chapter.index] = text ?? ""
          if self.transcribingChapterIndex == chapter.index {
            self.transcribingChapterIndex = nil
          }
        }
      }
    }
  }
}
