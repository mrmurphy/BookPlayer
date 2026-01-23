//
//  BookmarksView.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 4/10/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import SwiftUI

struct BookmarksView: View {
  @AppStorage(Constants.UserDefaults.isAutomaticBookmarksSectionCollapsed)
  private var isAutomaticBookmarksSectionCollapsed: Bool = false
  @StateObject private var model: Self.Model
  @StateObject private var theme = ThemeViewModel()

  @State private var showingNoteAlert: SimpleBookmark?
  @State private var bookmarkToDelete: SimpleBookmark?
  @State private var noteText: String = ""
  @State private var selectedBookmarkKey: BookmarkKey?

  @Environment(\.dismiss) private var dismiss

  var deleteAlertTitle: String {
    if let bookmarkToDelete {
      return String(format: "delete_single_item_title".localized, TimeParser.formatTime(bookmarkToDelete.time))
    } else {
      return "delete_single_item_title".localized
    }
  }

  init(initModel: @escaping () -> Self.Model) {
    self._model = .init(wrappedValue: initModel())
  }

  var body: some View {
    NavigationStack {
      List {
        // Automatic bookmarks section
        Section(
          isExpanded: $isAutomaticBookmarksSectionCollapsed,
          content: {
            ForEach(model.automaticBookmarks) { bookmark in
              bookmarkRow(bookmark)
            }
          },
          header: {
            Text("bookmark_type_automatic_title")
              .foregroundStyle(theme.primaryColor)
          }
        )

        // User bookmarks section
        Section {
          ForEach(model.userBookmarks) { bookmark in
            bookmarkRow(bookmark)
              .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                  bookmarkToDelete = bookmark
                } label: {
                  Image(systemName: "trash")
                    .foregroundStyle(Color.red)
                }
                .accessibilityLabel("delete_button")

                Button {
                  noteText = bookmark.note ?? ""
                  showingNoteAlert = bookmark
                } label: {
                  Image(systemName: "pencil")
                }
                .accessibilityLabel("bookmark_note_edit_title")

                Button {
                  selectedBookmarkKey = BookmarkKey(bookmark: bookmark)
                } label: {
                  Image(systemName: "quote.bubble")
                }
                .accessibilityLabel("Transcript")
              }
          }
        } header: {
          Text("bookmark_type_user_title")
            .foregroundStyle(theme.primaryColor)
        }
      }
      .listStyle(.sidebar)
      .applyListStyle(with: theme, background: theme.systemBackgroundColor)
      .navigationTitle("bookmarks_title")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .foregroundStyle(theme.linkColor)
          }
        }

        ToolbarItem(placement: .confirmationAction) {
          if let currentItem = model.currentItem {
            ShareLink(
              item: BookmarksFileTransferable(
                currentItem: currentItem,
                bookmarks: model.userBookmarks
              ),
              preview: SharePreview(
                "bookmarks_title".localized + " \(currentItem.title).txt",
                image: Image(systemName: "bookmark")
              )
            ) {
              Image(systemName: "square.and.arrow.up")
                .foregroundStyle(theme.linkColor)
            }
          }
        }
      }
      .alert(
        "bookmark_note_action_title",
        isPresented: .constant(showingNoteAlert != nil),
        presenting: showingNoteAlert
      ) { bookmark in
        TextField("note_title", text: $noteText)
        Button("cancel_button", role: .cancel) {
          showingNoteAlert = nil
          noteText = ""
        }
        Button("ok_button") {
          model.addNote(noteText, bookmark: bookmark)
          showingNoteAlert = nil
          noteText = ""
        }
      }
      .alert(
        "",
        isPresented: .constant(bookmarkToDelete != nil),
        presenting: bookmarkToDelete
      ) { bookmark in
        Button("cancel_button", role: .cancel) {
          bookmarkToDelete = nil
        }
        Button("delete_button", role: .destructive) {
          model.deleteBookmark(bookmark)
          bookmarkToDelete = nil
        }
      } message: { bookmark in
        Text(String(format: "delete_single_item_title".localized, TimeParser.formatTime(bookmark.time)))
      }
      .sheet(item: $selectedBookmarkKey) { key in
        BookmarkTranscriptSheet(
          bookmarkKey: key,
          model: model
        )
      }
    }
  }

  @ViewBuilder
  private func bookmarkRow(_ bookmark: SimpleBookmark) -> some View {
    Button {
      model.handleBookmarkSelected(bookmark)
      dismiss()
    } label: {
      HStack(spacing: Spacing.S2) {
        Text(TimeParser.formatTime(bookmark.time))
          .frame(minWidth: 61)
          .bpFont(Fonts.caption)
          .foregroundStyle(theme.secondaryColor)

        VStack(alignment: .leading, spacing: Spacing.S1) {
          if let note = bookmark.note {
            Text(note)
              .bpFont(Fonts.body)
              .foregroundStyle(theme.primaryColor)
          }

          if let transcript = bookmark.transcriptText, !transcript.isEmpty {
            Text(transcript)
              .bpFont(Fonts.caption)
              .foregroundStyle(theme.secondaryColor)
              .lineLimit(2)
          } else {
            switch bookmark.transcriptState {
            case .pending:
              ProgressView()
                .tint(theme.secondaryColor)
            case .failed:
              Text("Transcript unavailable")
                .bpFont(Fonts.caption)
                .foregroundStyle(theme.secondaryColor)
            case .none, .ready:
              EmptyView()
            }
          }
        }

        Spacer()

        if let imageName = bookmark.getImageNameForType() {
          Image(systemName: imageName)
            .foregroundStyle(theme.secondaryColor)
        }
      }
    }
    .listRowBackground(theme.secondarySystemBackgroundColor)
  }
}

private struct BookmarkKey: Hashable, Identifiable {
  let relativePath: String
  let time: Double
  let type: BookmarkType

  var id: String {
    "\(relativePath)-\(time)-\(type.rawValue)"
  }

  init(bookmark: SimpleBookmark) {
    self.relativePath = bookmark.relativePath
    self.time = bookmark.time
    self.type = bookmark.bookmarkType
  }
}

private struct BookmarkTranscriptSheet: View {
  let bookmarkKey: BookmarkKey
  @ObservedObject var model: BookmarksView.Model

  @Environment(\.dismiss) private var dismiss

  private var bookmark: SimpleBookmark? {
    model.userBookmarks.first(where: { item in
      item.relativePath == bookmarkKey.relativePath
        && item.time == bookmarkKey.time
        && item.bookmarkType == bookmarkKey.type
    })
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: Spacing.S3) {
        Text("Transcript")
          .bpFont(Fonts.title)

        if let bookmark {
          transcriptContent(for: bookmark)
          rangeControls(for: bookmark)
        } else {
          Text("Transcript unavailable")
            .bpFont(Fonts.body)
        }

        Spacer()
      }
      .padding(Spacing.S4)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("ok_button".localized) {
            dismiss()
          }
        }
      }
      .onAppear {
        if let bookmark {
          model.ensureTranscript(bookmark)
        }
      }
    }
  }

  @ViewBuilder
  private func transcriptContent(for bookmark: SimpleBookmark) -> some View {
    if let transcript = bookmark.transcriptText, !transcript.isEmpty {
      Text(transcript)
        .bpFont(Fonts.body)
        .foregroundStyle(Color.primary)
    } else {
      switch bookmark.transcriptState {
      case .pending:
        ProgressView()
      case .failed:
        Text("Transcript unavailable")
          .bpFont(Fonts.body)
          .foregroundStyle(Color.secondary)
      case .none:
        Text("Transcription ready when you are.")
          .bpFont(Fonts.body)
          .foregroundStyle(Color.secondary)
      case .ready:
        Text("Transcript unavailable")
          .bpFont(Fonts.body)
          .foregroundStyle(Color.secondary)
      }
    }
  }

  @ViewBuilder
  private func rangeControls(for bookmark: SimpleBookmark) -> some View {
    VStack(alignment: .leading, spacing: Spacing.S2) {
      Text("Quote range")
        .bpFont(Fonts.caption)
        .foregroundStyle(Color.secondary)

      RangeAdjuster(
        title: "Start",
        value: bookmark.transcriptStartOffset,
        onDecrease: {
          model.adjustTranscriptStart(bookmark, delta: -Constants.BookmarkTranscript.adjustmentStep)
        },
        onIncrease: {
          model.adjustTranscriptStart(bookmark, delta: Constants.BookmarkTranscript.adjustmentStep)
        }
      )

      RangeAdjuster(
        title: "End",
        value: bookmark.transcriptEndOffset,
        onDecrease: {
          model.adjustTranscriptEnd(bookmark, delta: -Constants.BookmarkTranscript.adjustmentStep)
        },
        onIncrease: {
          model.adjustTranscriptEnd(bookmark, delta: Constants.BookmarkTranscript.adjustmentStep)
        }
      )
    }
  }
}

private struct RangeAdjuster: View {
  let title: String
  let value: TimeInterval
  let onDecrease: () -> Void
  let onIncrease: () -> Void

  var body: some View {
    HStack(spacing: Spacing.S2) {
      Text(title)
        .bpFont(Fonts.body)

      Spacer()

      Button(action: onDecrease) {
        Image(systemName: "minus.circle")
      }
      .disabled(value <= Constants.BookmarkTranscript.minOffset)

      Text("\(Int(value))s")
        .bpFont(Fonts.caption)
        .foregroundStyle(Color.secondary)
        .frame(minWidth: 44)

      Button(action: onIncrease) {
        Image(systemName: "plus.circle")
      }
      .disabled(value >= Constants.BookmarkTranscript.maxOffset)
    }
  }
}

extension BookmarksView {
  class Model: ObservableObject {
    @Published var automaticBookmarks = [SimpleBookmark]()
    @Published var userBookmarks = [SimpleBookmark]()
    @Published var currentItem: PlayableItem?

    init(
      automaticBookmarks: [SimpleBookmark] = [],
      userBookmarks: [SimpleBookmark] = [],
      currentItem: PlayableItem? = nil
    ) {
      self.automaticBookmarks = automaticBookmarks
      self.userBookmarks = userBookmarks
      self.currentItem = currentItem
    }

    func handleBookmarkSelected(_ bookmark: SimpleBookmark) {}
    func deleteBookmark(_ bookmark: SimpleBookmark) {}
    func addNote(_ note: String, bookmark: SimpleBookmark) {}
    func ensureTranscript(_ bookmark: SimpleBookmark) {}
    func adjustTranscriptStart(_ bookmark: SimpleBookmark, delta: TimeInterval) {}
    func adjustTranscriptEnd(_ bookmark: SimpleBookmark, delta: TimeInterval) {}
  }
}

#Preview {
  @Previewable var bookmark1 = SimpleBookmark(
    time: 123.45,
    note: "Important scene",
    type: .user,
    relativePath: "book1.m4b"
  )

  @Previewable var bookmark2 = SimpleBookmark(
    time: 456.78,
    note: nil,
    type: .user,
    relativePath: "book1.m4b"
  )

  @Previewable var automaticBookmark = SimpleBookmark(
    time: 789.12,
    note: "bookmark_automatic_play_title".localized,
    type: .play,
    relativePath: "book1.m4b"
  )

  BookmarksView {
    .init(
      automaticBookmarks: [automaticBookmark],
      userBookmarks: [bookmark1, bookmark2]
    )
  }
}
