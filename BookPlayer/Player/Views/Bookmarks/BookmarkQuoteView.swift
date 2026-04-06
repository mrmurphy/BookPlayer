//
//  BookmarkQuoteView.swift
//  BookPlayer
//

import BookPlayerKit
import SwiftUI

struct BookmarkQuoteView: View {
  @StateObject private var viewModel: BookmarkQuoteViewModel
  @EnvironmentObject private var theme: ThemeViewModel
  @Environment(\.dismiss) private var dismiss

  init(
    bookmark: SimpleBookmark,
    playable: PlayableItem,
    libraryService: LibraryServiceProtocol
  ) {
    _viewModel = StateObject(
      wrappedValue: BookmarkQuoteViewModel(
        bookmark: bookmark,
        playable: playable,
        libraryService: libraryService
      )
    )
  }

  var body: some View {
    NavigationStack {
      Form {
        if case let .failed(message) = viewModel.phase {
          Section {
            Text(message)
              .foregroundStyle(.red)
              .bpFont(.caption)
          }
        }

        Section {
          Stepper(
            value: $viewModel.secondsBefore,
            in: BookmarkQuoteViewModel.quoteTuningRange,
            step: 5
          ) {
            Text(
              String(
                format: "bookmark_quote_seconds_before_format".localized,
                Int(viewModel.secondsBefore)
              )
            )
            .foregroundStyle(theme.primaryColor)
          }

          Stepper(
            value: $viewModel.secondsAfter,
            in: BookmarkQuoteViewModel.quoteTuningRange,
            step: 5
          ) {
            Text(
              String(
                format: "bookmark_quote_seconds_after_format".localized,
                Int(viewModel.secondsAfter)
              )
            )
            .foregroundStyle(theme.primaryColor)
          }

          Button {
            Task { await viewModel.updateQuote() }
          } label: {
            HStack {
              Text("bookmark_quote_apply_button".localized)
              Spacer()
              if case .working = viewModel.phase {
                ProgressView()
              }
            }
          }
          .disabled(viewModel.phase == .working)
        } header: {
          Text("bookmark_quote_window_section_title".localized)
            .foregroundStyle(theme.secondaryColor)
        }

        Section {
          Toggle(
            isOn: $viewModel.showRaw,
            label: {
              Text("bookmark_quote_show_raw".localized)
                .foregroundStyle(theme.primaryColor)
            }
          )

          if let path = viewModel.lastCleanupPath {
            Text(cleanupPathLabel(path))
              .bpFont(.caption)
              .foregroundStyle(theme.secondaryColor)
          }

          Text(displayedQuoteText)
            .textSelection(.enabled)
            .bpFont(.body)
            .foregroundStyle(theme.primaryColor)
            .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
          Text("bookmark_quote_text_section_title".localized)
            .foregroundStyle(theme.secondaryColor)
        }

        Section {
          Toggle(
            isOn: $viewModel.includeMetadataInCopy,
            label: {
              Text("bookmark_quote_include_metadata".localized)
                .foregroundStyle(theme.primaryColor)
            }
          )

          Button("bookmark_quote_copy_button".localized) {
            viewModel.copyToPasteboard()
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(theme.systemBackgroundColor)
      .navigationTitle("bookmark_quote_title".localized)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .accessibilityLabel("cancel_button".localized)
        }
      }
    }
    .environmentObject(theme)
  }

  private var displayedQuoteText: String {
    if viewModel.showRaw {
      let raw = viewModel.snapshot.rawText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return raw.isEmpty ? "bookmark_quote_empty_placeholder".localized : raw
    }
    let cleaned = viewModel.snapshot.cleanedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !cleaned.isEmpty { return cleaned }
    let raw = viewModel.snapshot.rawText ?? ""
    let fallback = BookmarkQuoteHeuristicCleaner.cleanedQuote(from: raw)
    return fallback.isEmpty ? "bookmark_quote_empty_placeholder".localized : fallback
  }

  private func cleanupPathLabel(_ path: QuoteCleanupPath) -> String {
    switch path {
    case .foundationModels:
      return "bookmark_quote_cleanup_path_foundation_models".localized
    case .heuristic:
      return "bookmark_quote_cleanup_path_heuristic".localized
    }
  }
}
