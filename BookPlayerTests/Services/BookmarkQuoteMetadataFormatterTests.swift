//
//  BookmarkQuoteMetadataFormatterTests.swift
//  BookPlayerTests
//

import XCTest
@testable import BookPlayerKit

final class BookmarkQuoteMetadataFormatterTests: XCTestCase {
  func testWithoutMetadataReturnsQuoteOnly() {
    let s = BookmarkQuoteMetadataFormatter.clipboardPayload(
      cleanedQuote: "Hello world.",
      title: "My Book",
      author: "Ada L.",
      formattedTimestamp: "1:02:03",
      includeMetadata: false
    )
    XCTAssertEqual(s, "Hello world.")
  }

  func testWithMetadataPrependsBlock() {
    let s = BookmarkQuoteMetadataFormatter.clipboardPayload(
      cleanedQuote: "Hello world.",
      title: "My Book",
      author: "Ada L.",
      formattedTimestamp: "1:02:03",
      includeMetadata: true
    )
    XCTAssertTrue(s.hasPrefix("My Book\nAda L.\n1:02:03\n\n"))
    XCTAssertTrue(s.hasSuffix("Hello world."))
  }
}
