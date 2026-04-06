//
//  BookmarkSpeechTranscriber.swift
//  BookPlayerKit
//

import Foundation

#if !os(watchOS)
import Speech
#endif

public enum BookmarkSpeechTranscriberError: Error {
  case fileNotFound
  case recognizerUnavailable
  case authorizationDenied
  case recognitionFailed
  #if os(watchOS)
  case unsupportedPlatform
  #endif
}

/// On-device speech-to-text for a short exported audio file (Speech framework).
public struct BookmarkSpeechTranscriber: Sendable {
  public init() {}

  public func transcribe(fileURL: URL) async throws -> String {
#if os(watchOS)
    throw BookmarkSpeechTranscriberError.unsupportedPlatform
#else
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw BookmarkSpeechTranscriberError.fileNotFound
    }

    let authStatus = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
      SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
    }

    guard authStatus == .authorized else {
      throw BookmarkSpeechTranscriberError.authorizationDenied
    }

    guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
      throw BookmarkSpeechTranscriberError.recognizerUnavailable
    }

    let request = SFSpeechURLRecognitionRequest(url: fileURL)
    request.shouldReportPartialResults = false
    request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
      var finished = false
      recognizer.recognitionTask(with: request) { result, error in
        if finished { return }
        if let error {
          finished = true
          cont.resume(throwing: error)
          return
        }
        guard let result else { return }
        if result.isFinal {
          finished = true
          let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
          cont.resume(returning: text)
        }
      }
    }
#endif
  }
}
