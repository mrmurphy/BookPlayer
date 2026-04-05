//
//  TranscriptEngineFactory.swift
//  BookPlayer
//
//  Returns the engine for the current TranscriptEngineChoice.
//

import Foundation

enum TranscriptEngineFactory {
  /// Returns the engine selected in settings (Apple or Parakeet when available).
  static func makeEngine() -> TranscriptEngineProtocol {
    let choice = TranscriptEngineChoice.current
    if choice == .parakeet, choice.isAvailable {
      if #available(iOS 17.0, *) {
        return ParakeetTranscriptEngine()
      }
    }
    return AppleSpeechTranscriptEngine()
  }
}
