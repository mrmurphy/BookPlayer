//
//  BookmarkQuoteFoundationModelsCleaner.swift
//  BookPlayerKit
//

import Foundation

public enum BookmarkQuoteFoundationModelsCleaner {
  /// Polishes raw STT using Apple Intelligence when available (requires iOS 26+ SDK with FoundationModels).
  public static func cleanedQuote(from raw: String) async throws -> String {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
      return try await performFoundationModelsCleanup(raw)
    }
    #endif
    struct Unavailable: Error {}
    throw Unavailable()
  }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct CleanedBookmarkQuote: Equatable {
  @Guide(description: "Verbatim quotable excerpt. No preamble or meta commentary.")
  let quote: String
  @Guide(description: "True if the excerpt starts mid-sentence and needs a leading ellipsis.")
  let leadingEllipsis: Bool
  @Guide(description: "True if the excerpt ends mid-sentence and needs a trailing ellipsis.")
  let trailingEllipsis: Bool
}

@available(iOS 26.0, macOS 26.0, *)
private func performFoundationModelsCleanup(_ raw: String) async throws -> String {
  guard case .available = SystemLanguageModel.default.availability else {
    struct Unavailable: Error {}
    throw Unavailable()
  }

  let session = LanguageModelSession(instructions: Instructions {
    "You polish audiobook speech-to-text into a single quotable excerpt."
    "Preserve the speaker's meaning and wording; fix obvious STT junk only."
    "Never add title, author, or timestamps."
  })

  let response = try await session.respond(
    generating: CleanedBookmarkQuote.self,
    options: GenerationOptions(sampling: .greedy)
  ) {
    "Raw transcription:\n\(raw)"
  }

  var text = response.content.quote.trimmingCharacters(in: .whitespacesAndNewlines)
  if response.content.leadingEllipsis { text = "…" + text }
  if response.content.trailingEllipsis { text = text + "…" }
  return text
}
#endif
