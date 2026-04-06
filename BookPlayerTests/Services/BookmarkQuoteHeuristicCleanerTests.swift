//
//  BookmarkQuoteHeuristicCleanerTests.swift
//  BookPlayerTests
//

import XCTest
@testable import BookPlayerKit

final class BookmarkQuoteHeuristicCleanerTests: XCTestCase {
  func testCollapsesWhitespaceAndNewlines() {
    let raw = "  hello \n\n world  "
    let out = BookmarkQuoteHeuristicCleaner.cleanedQuote(from: raw)
    XCTAssertFalse(out.contains("\n"))
    XCTAssertTrue(out.contains("hello"))
    XCTAssertTrue(out.contains("world"))
  }

  func testProducesEllipsisWhenMultipleSentences() {
    let raw = "First. Second sentence here. Third."
    let out = BookmarkQuoteHeuristicCleaner.cleanedQuote(from: raw)
    XCTAssertTrue(out.contains("Second sentence here"))
  }

  func testEmptyInput() {
    XCTAssertEqual(BookmarkQuoteHeuristicCleaner.cleanedQuote(from: ""), "")
    XCTAssertEqual(BookmarkQuoteHeuristicCleaner.cleanedQuote(from: "   \n"), "")
  }
}
