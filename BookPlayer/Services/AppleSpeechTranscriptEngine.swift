//
//  AppleSpeechTranscriptEngine.swift
//  BookPlayer
//
//  Transcript engine using Apple's Speech framework (on-device recognition).
//

import AVFoundation
import Foundation
import Speech
@preconcurrency import BookPlayerKit

public final class AppleSpeechTranscriptEngine: TranscriptEngineProtocol, @unchecked Sendable {
  public init() {}

  public func transcribe(segment: TranscriptSegmentSpec) async throws -> String {
    if let withRuns = try await transcribeWithRuns(segment: segment) {
      return withRuns.fullText
    }
    return ""
  }

  public func transcribeWithRuns(segment: TranscriptSegmentSpec) async throws -> TranscriptionWithRuns? {
    let audioURL = try await exportSegment(segment)
    defer { try? FileManager.default.removeItem(at: audioURL) }

    guard let recognizer = SFSpeechRecognizer(locale: Locale.current) else {
      throw BookPlayerError.runtimeError("Speech recognizer is unavailable.")
    }
    guard recognizer.isAvailable else {
      throw BookPlayerError.runtimeError("Speech recognizer is unavailable.")
    }

    if #available(iOS 13.0, *) {
      guard recognizer.supportsOnDeviceRecognition else {
        throw BookPlayerError.runtimeError("On-device speech recognition not supported.")
      }
    }

    if #available(iOS 17.0, *) {
      recognizer.defaultTaskHint = .dictation
    }

    let request = SFSpeechURLRecognitionRequest(url: audioURL)
    request.shouldReportPartialResults = true
    if #available(iOS 13.0, *) {
      request.requiresOnDeviceRecognition = true
    }

    return try await withCheckedThrowingContinuation { continuation in
      var resumed = false
      var lastWithRuns: TranscriptionWithRuns?
      _ = recognizer.recognitionTask(with: request) { result, error in
        if let result {
          let text = result.bestTranscription.formattedString
          let runs: [TranscriptRun] = result.isFinal ? Self.runs(from: result.bestTranscription) : []
          if !text.isEmpty {
            lastWithRuns = TranscriptionWithRuns(fullText: text, runs: runs)
          }
          if result.isFinal, !resumed {
            resumed = true
            if let withRuns = lastWithRuns {
              continuation.resume(returning: withRuns)
            } else {
              continuation.resume(returning: TranscriptionWithRuns(fullText: "", runs: []))
            }
            return
          }
        }

        if let error, !resumed {
          resumed = true
          if let withRuns = lastWithRuns {
            continuation.resume(returning: withRuns)
          } else {
            continuation.resume(throwing: error)
          }
        }
      }
    }
  }

  private static func runs(from transcription: SFTranscription) -> [TranscriptRun] {
    transcription.segments.compactMap { seg in
      let s = String(seg.substring)
      guard !s.isEmpty else { return nil }
      return TranscriptRun(
        startInSegment: seg.timestamp,
        duration: seg.duration,
        text: s
      )
    }
  }

  private func exportSegment(_ segment: TranscriptSegmentSpec) async throws -> URL {
    let asset = AVURLAsset(url: segment.fileURL)
    guard let exportSession = AVAssetExportSession(
      asset: asset,
      presetName: AVAssetExportPresetAppleM4A
    ) else {
      throw BookPlayerError.runtimeError("Unable to create export session.")
    }

    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("bookmark-transcript-\(UUID().uuidString).m4a")

    if FileManager.default.fileExists(atPath: outputURL.path) {
      try? FileManager.default.removeItem(at: outputURL)
    }

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .m4a
    exportSession.timeRange = CMTimeRange(
      start: CMTime(seconds: segment.startTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
      duration: CMTime(seconds: segment.duration, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    )

    try await withCheckedThrowingContinuation { continuation in
      exportSession.exportAsynchronously {
        switch exportSession.status {
        case .completed:
          continuation.resume()
        case .failed, .cancelled:
          continuation.resume(throwing: exportSession.error ?? BookPlayerError.runtimeError("Export failed."))
        default:
          continuation.resume(throwing: BookPlayerError.runtimeError("Export failed."))
        }
      }
    }

    return outputURL
  }
}
