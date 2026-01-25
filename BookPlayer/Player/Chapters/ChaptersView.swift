//
//  ChaptersView.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 7/9/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import SwiftUI

struct ChaptersView: View {
  @StateObject private var model: Self.Model
  @StateObject private var theme = ThemeViewModel()
  @Environment(\.dismiss) private var dismiss

  init(initModel: @escaping () -> Self.Model) {
    self._model = .init(wrappedValue: initModel())
  }

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        List {
          ForEach(Array(model.chapters.enumerated()), id: \.element.id) { index, chapter in
            rowView(chapter, index: index)
          }
        }
        .onAppear {
          if let currentChapter = model.currentChapter {
            proxy.scrollTo(currentChapter.id, anchor: .center)
          }
          model.loadPreviewsIfNeeded()
        }
        .listStyle(.plain)
        .applyListStyle(with: theme, background: theme.systemBackgroundColor)
        .navigationTitle("chapters_title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("done_title") {
              dismiss()
            }
            .foregroundStyle(theme.linkColor)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func rowView(_ chapter: PlayableChapter, index: Int) -> some View {
    let title =
      chapter.title == ""
      ? String.localizedStringWithFormat("chapter_number_title".localized, index + 1)
      : chapter.title
    let subtitle = String.localizedStringWithFormat(
      "chapters_item_description".localized,
      TimeParser.formatTime(chapter.start),
      TimeParser.formatTime(chapter.duration)
    )
    let previewText = model.previewTexts[chapter.index].flatMap { $0.isEmpty ? nil : $0 }
    let isTranscribing = model.transcribingChapterIndex == chapter.index
    Button {
      model.handleChapterSelected(chapter)
      dismiss()
    } label: {
      HStack {
        VStack(alignment: .leading, spacing: Spacing.S4) {
          Text(title)
            .bpFont(Fonts.titleRegular)
            .foregroundStyle(theme.primaryColor)
          Text(subtitle)
            .bpFont(Fonts.caption)
            .foregroundStyle(theme.secondaryColor)
          if isTranscribing {
            HStack(spacing: Spacing.S4) {
              ProgressView()
                .scaleEffect(0.85)
              Text(NSLocalizedString("chapters_preview_transcribing", comment: ""))
                .bpFont(Fonts.caption)
                .foregroundStyle(theme.secondaryColor)
            }
          } else if let previewText {
            Text(previewText)
              .bpFont(Fonts.caption)
              .foregroundStyle(theme.secondaryColor)
              .lineLimit(2)
          }
        }
        Spacer()
        if chapter == model.currentChapter {
          Image(systemName: "checkmark")
            .foregroundStyle(theme.linkColor)
        }
      }
    }
    .listRowBackground(theme.systemBackgroundColor)
  }
}

extension ChaptersView {
  class Model: ObservableObject {
    @Published var chapters: [PlayableChapter]
    @Published var currentChapter: PlayableChapter?
    /// Chapter index -> preview transcription (first ~15s). Updated when loadPreviewsIfNeeded runs.
    @Published var previewTexts: [Int16: String] = [:]
    /// Index of the chapter currently being transcribed (one at a time). Nil when idle.
    @Published var transcribingChapterIndex: Int16?

    init(chapters: [PlayableChapter], currentChapter: PlayableChapter?) {
      self.chapters = chapters
      self.currentChapter = currentChapter
    }

    func handleChapterSelected(_ chapter: PlayableChapter) {}

    /// Override to load chapter preview transcriptions when the chapters view appears.
    func loadPreviewsIfNeeded() {}
  }
}

#Preview {
  @Previewable var chapter1 = PlayableChapter(
    title: "Chapter 1",
    author: "Author 1",
    start: .zero,
    duration: 300,
    relativePath: "book1.m4b",
    remoteURL: nil,
    index: 0
  )

  ChaptersView {
    .init(
      chapters: [
        chapter1,
        .init(
          title: "Chapter 2",
          author: "Author 1",
          start: 300,
          duration: 300,
          relativePath: "book1.m4b",
          remoteURL: nil,
          index: 1
        ),
      ],
      currentChapter: chapter1
    )
  }
}
