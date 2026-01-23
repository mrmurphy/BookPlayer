//
//  SimpleBookmark.swift
//  BookPlayer
//
//  Created by gianni.carlo on 23/4/23.
//  Copyright © 2023 BookPlayer LLC. All rights reserved.
//

import Foundation

public struct SimpleBookmark: Decodable, Identifiable {
  public var id: String {
    return UUID().uuidString
  }
  public let time: Double
  public let note: String?
  public let transcriptText: String?
  public let transcriptStartOffset: Double
  public let transcriptEndOffset: Double
  public let transcriptState: BookmarkTranscriptState
  let type: BookmarkType
  public let relativePath: String

  enum CodingKeys: String, CodingKey {
    case time
    case note
    case transcriptText
    case transcriptStartOffset
    case transcriptEndOffset
    case transcriptState
    case type
    case relativePath
  }

  static var fetchRequestProperties = [
    "time",
    "note",
    "transcriptText",
    "transcriptStartOffset",
    "transcriptEndOffset",
    "transcriptState",
    "type",
    "item.relativePath",
  ]

  public func getImageNameForType() -> String? {
    switch type {
    case .play:
      return "play"
    case .skip:
      return "clock.arrow.2.circlepath"
    case .sleep:
      return "moon"
    case .user:
      return nil
    }
  }

  public init(
    time: Double,
    note: String?,
    transcriptText: String? = nil,
    transcriptStartOffset: Double = Constants.BookmarkTranscript.defaultStartOffset,
    transcriptEndOffset: Double = Constants.BookmarkTranscript.defaultEndOffset,
    transcriptState: BookmarkTranscriptState = .none,
    type: BookmarkType,
    relativePath: String
  ) {
    self.time = time
    self.note = note
    self.transcriptText = transcriptText
    self.transcriptStartOffset = transcriptStartOffset
    self.transcriptEndOffset = transcriptEndOffset
    self.transcriptState = transcriptState
    self.type = type
    self.relativePath = relativePath
  }

  public var bookmarkType: BookmarkType {
    return type
  }
}

extension SimpleBookmark {
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.time = try container.decode(Double.self, forKey: .time)
    self.note = try container.decodeIfPresent(String.self, forKey: .note)
    self.transcriptText = try container.decodeIfPresent(String.self, forKey: .transcriptText)
    self.transcriptStartOffset = try container.decodeIfPresent(Double.self, forKey: .transcriptStartOffset)
      ?? Constants.BookmarkTranscript.defaultStartOffset
    self.transcriptEndOffset = try container.decodeIfPresent(Double.self, forKey: .transcriptEndOffset)
      ?? Constants.BookmarkTranscript.defaultEndOffset
    let stateRaw = try container.decodeIfPresent(Int16.self, forKey: .transcriptState)
      ?? BookmarkTranscriptState.none.rawValue
    self.transcriptState = BookmarkTranscriptState(rawValue: stateRaw) ?? .none
    self.type = try container.decode(BookmarkType.self, forKey: .type)
    self.relativePath = try container.decode(String.self, forKey: .relativePath)
  }
}

extension SimpleBookmark: Equatable {
  public static func == (lhs: SimpleBookmark, rhs: SimpleBookmark) -> Bool {
    return lhs.time == rhs.time
      && lhs.relativePath == rhs.relativePath
  }
}

extension SimpleBookmark {
  init(from bookmark: SyncableBookmark) {
    self.relativePath = bookmark.key
    self.time = bookmark.time
    self.note = bookmark.note
    self.transcriptText = nil
    self.transcriptStartOffset = Constants.BookmarkTranscript.defaultStartOffset
    self.transcriptEndOffset = Constants.BookmarkTranscript.defaultEndOffset
    self.transcriptState = .none
    self.type = .user
  }
}
