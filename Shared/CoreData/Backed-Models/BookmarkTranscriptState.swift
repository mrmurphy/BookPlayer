//
//  BookmarkTranscriptState.swift
//  BookPlayer
//
//  Created by BookPlayer.
//

import Foundation

@objc public enum BookmarkTranscriptState: Int16 {
  case none
  case pending
  case ready
  case failed
}
