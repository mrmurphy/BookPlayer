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
  @State private var quoteBookmark: SimpleBookmark?
  @State private var noteText: String = ""

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
        ThemedSection {
          ForEach(model.userBookmarks) { bookmark in
            userBookmarkRow(bookmark)
              .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                  bookmarkToDelete = bookmark
                } label: {
                  Image(systemName: "trash")
                }
                .tint(.red)
                .accessibilityLabel("delete_button")

                Button {
                  noteText = bookmark.note ?? ""
                  showingNoteAlert = bookmark
                } label: {
                  Image(systemName: "pencil")
                }
                .accessibilityLabel("bookmark_note_edit_title")
              }
          }
        } header: {
          Text("bookmark_type_user_title")
            .foregroundStyle(theme.primaryColor)
        }
      }
      .environmentObject(theme)
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
        isPresented: Binding(
          get: { showingNoteAlert != nil },
          set: { if !$0 { showingNoteAlert = nil; noteText = "" } }
        ),
        presenting: showingNoteAlert
      ) { bookmark in
        TextField("note_title", text: $noteText)
        Button("cancel_button", role: .cancel) {}
        Button("ok_button") {
          model.addNote(noteText, bookmark: bookmark)
        }
      }
      .alert(
        "",
        isPresented: Binding(
          get: { bookmarkToDelete != nil },
          set: { if !$0 { bookmarkToDelete = nil } }
        ),
        presenting: bookmarkToDelete
      ) { bookmark in
        Button("cancel_button", role: .cancel) {}
        Button("delete_button", role: .destructive) {
          model.deleteBookmark(bookmark)
        }
      } message: { bookmark in
        Text(String(format: "delete_single_item_title".localized, TimeParser.formatTime(bookmark.time)))
      }
      .sheet(item: $quoteBookmark) { bookmark in
        if let library = model.libraryServiceForQuotes, let item = model.currentItem {
          BookmarkQuoteView(
            bookmark: bookmark,
            playable: item,
            libraryService: library
          )
          .environmentObject(theme)
        }
      }
    }
  }

  @ViewBuilder
  private func userBookmarkRow(_ bookmark: SimpleBookmark) -> some View {
    Button {
      model.handleBookmarkSelected(bookmark)
      dismiss()
    } label: {
      bookmarkRowLabel(bookmark)
    }
    .contextMenu {
      Button {
        quoteBookmark = bookmark
      } label: {
        Label("bookmark_quote_action_title".localized, systemImage: "quote.bubble")
      }
      .disabled(model.libraryServiceForQuotes == nil || model.currentItem == nil)
    }
    .listRowBackground(theme.secondarySystemBackgroundColor)
  }

  @ViewBuilder
  private func bookmarkRow(_ bookmark: SimpleBookmark) -> some View {
    Button {
      model.handleBookmarkSelected(bookmark)
      dismiss()
    } label: {
      bookmarkRowLabel(bookmark)
    }
    .listRowBackground(theme.secondarySystemBackgroundColor)
  }

  @ViewBuilder
  private func bookmarkRowLabel(_ bookmark: SimpleBookmark) -> some View {
    HStack(spacing: Spacing.S2) {
      Text(TimeParser.formatTime(bookmark.time))
        .frame(minWidth: 61)
        .bpFont(.caption)
        .foregroundStyle(theme.secondaryColor)

      if let note = bookmark.note {
        Text(note)
          .bpFont(.body)
          .foregroundStyle(theme.primaryColor)
      }

      Spacer()

      if let imageName = bookmark.getImageNameForType() {
        Image(systemName: imageName)
          .foregroundStyle(theme.secondaryColor)
      }
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

    var libraryServiceForQuotes: LibraryServiceProtocol? { nil }
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
