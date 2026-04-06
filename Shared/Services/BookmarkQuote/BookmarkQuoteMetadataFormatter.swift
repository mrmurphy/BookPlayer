//
//  BookmarkQuoteMetadataFormatter.swift
//  BookPlayerKit
//

import Foundation

public enum BookmarkQuoteMetadataFormatter {
  public static func clipboardPayload(
    cleanedQuote: String,
    title: String,
    author: String,
    formattedTimestamp: String,
    includeMetadata: Bool
  ) -> String {
    guard includeMetadata else { return cleanedQuote }
    let header = "\(title)\n\(author)\n\(formattedTimestamp)\n\n"
    return header + cleanedQuote
  }
}
