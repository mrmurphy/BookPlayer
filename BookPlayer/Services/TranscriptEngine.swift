//
//  TranscriptEngine.swift
//  BookPlayer
//
//  Abstraction for transcription backends (Apple Speech vs Parakeet/FluidAudio).
//

import Foundation
@preconcurrency import BookPlayerKit

/// Segment specification for transcription: file location and time range (chapter-relative).
public struct TranscriptSegmentSpec: Sendable {
  public let fileURL: URL
  public let startTime: TimeInterval
  public let duration: TimeInterval

  public init(fileURL: URL, startTime: TimeInterval, duration: TimeInterval) {
    self.fileURL = fileURL
    self.startTime = startTime
    self.duration = duration
  }
}

/// A single timestamped run of text. Times are relative to the start of the transcribed segment.
public struct TranscriptRun: Sendable {
  public let startInSegment: TimeInterval
  public let duration: TimeInterval
  public let text: String

  public init(startInSegment: TimeInterval, duration: TimeInterval, text: String) {
    self.startInSegment = startInSegment
    self.duration = duration
    self.text = text
  }
}

/// Transcription result that includes per-run timings for karaoke-style sync.
public struct TranscriptionWithRuns: Sendable {
  public let fullText: String
  public let runs: [TranscriptRun]

  public init(fullText: String, runs: [TranscriptRun]) {
    self.fullText = fullText
    self.runs = runs
  }
}

public protocol TranscriptEngineProtocol: Sendable {
  func transcribe(segment: TranscriptSegmentSpec) async throws -> String

  /// When implemented, returns runs with timings relative to the segment. Caller adds segment.startTime for chapter time.
  /// Default returns nil; callers fall back to transcribe(segment:) and treat the whole segment as one run.
  func transcribeWithRuns(segment: TranscriptSegmentSpec) async throws -> TranscriptionWithRuns?
}

public extension TranscriptEngineProtocol {
  func transcribeWithRuns(segment: TranscriptSegmentSpec) async throws -> TranscriptionWithRuns? {
    nil
  }
}

/// User-facing transcript engine choice. Raw value is stored in UserDefaults.
public enum TranscriptEngineChoice: String, CaseIterable, Sendable {
  case apple = "apple"
  case parakeet = "parakeet"

  public static var defaultValue: TranscriptEngineChoice { .apple }

  public static var current: TranscriptEngineChoice {
    let raw = UserDefaults.standard.string(forKey: Constants.UserDefaults.transcriptEngine)
    return TranscriptEngineChoice(rawValue: raw ?? "") ?? .defaultValue
  }

  public static func set(_ choice: TranscriptEngineChoice) {
    UserDefaults.standard.set(choice.rawValue, forKey: Constants.UserDefaults.transcriptEngine)
  }

  /// Parakeet requires iOS 17+.
  public var isAvailable: Bool {
    switch self {
    case .apple: return true
    case .parakeet:
      if #available(iOS 17.0, *) { return true }
      return false
    }
  }
}

/// Parakeet ASR model version. Stored in UserDefaults when Parakeet is selected.
public enum ParakeetModelVersion: String, CaseIterable, Sendable {
  case v2 = "v2"
  case v3 = "v3"

  public static var defaultValue: ParakeetModelVersion { .v3 }

  public static var current: ParakeetModelVersion {
    let raw = UserDefaults.standard.string(forKey: Constants.UserDefaults.parakeetModelVersion)
    return ParakeetModelVersion(rawValue: raw ?? "") ?? .defaultValue
  }
}
