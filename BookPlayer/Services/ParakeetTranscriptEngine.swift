//
//  ParakeetTranscriptEngine.swift
//  BookPlayer
//
//  Transcript engine using FluidAudio (NVIDIA Parakeet TDT CoreML). Requires iOS 17+.
//

import AVFoundation
import FluidAudio
import Foundation
@preconcurrency import BookPlayerKit

@available(iOS 17.0, *)
public final class ParakeetTranscriptEngine: TranscriptEngineProtocol, @unchecked Sendable {
  private var asrManager: AsrManager?
  private var models: AsrModels?
  private var loadedVersion: ParakeetModelVersion?
  private let lock = NSLock()

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

    let manager = try await getOrCreateAsrManager()
    let result = try await manager.transcribe(audioURL, source: .system)
    let runs = Self.runs(from: result)
    return TranscriptionWithRuns(fullText: result.text, runs: runs)
  }

  private static func runs(from result: ASRResult) -> [TranscriptRun] {
    guard let timings = result.tokenTimings, !timings.isEmpty else {
      if result.text.isEmpty { return [] }
      return [TranscriptRun(startInSegment: 0, duration: result.duration, text: result.text)]
    }
    return timings.map { t in
      let text = t.token.replacingOccurrences(of: "▁", with: " ")
      return TranscriptRun(
        startInSegment: t.startTime,
        duration: t.endTime - t.startTime,
        text: text
      )
    }
  }

  private func asrVersion(from version: ParakeetModelVersion) -> AsrModelVersion {
    switch version {
    case .v2: return .v2
    case .v3: return .v3
    }
  }

  private func getOrCreateAsrManager() async throws -> AsrManager {
    let chosen = ParakeetModelVersion.current
    lock.lock()
    if let m = asrManager, let _ = models, loadedVersion == chosen {
      lock.unlock()
      return m
    }
    asrManager = nil
    models = nil
    loadedVersion = nil
    lock.unlock()

    let asrVersion = asrVersion(from: chosen)
    let loadedModels = try await AsrModels.downloadAndLoad(version: asrVersion)
    let manager = AsrManager(config: .default)
    try await manager.initialize(models: loadedModels)

    lock.lock()
    models = loadedModels
    asrManager = manager
    loadedVersion = chosen
    lock.unlock()

    setDownloadedFlag(for: chosen)
    return manager
  }

  private func setDownloadedFlag(for version: ParakeetModelVersion) {
    let key: String = switch version {
    case .v2: Constants.UserDefaults.parakeetModelDownloadedV2
    case .v3: Constants.UserDefaults.parakeetModelDownloadedV3
    }
    UserDefaults.standard.set(true, forKey: key)
  }

  /// Call from settings to download the Parakeet model for the given version. Marks that version as downloaded on success.
  public static func ensureModelDownloaded(version: ParakeetModelVersion) async {
    do {
      let asrVersion: AsrModelVersion = switch version {
      case .v2: .v2
      case .v3: .v3
      }
      _ = try await AsrModels.downloadAndLoad(version: asrVersion)
      let key: String = switch version {
      case .v2: Constants.UserDefaults.parakeetModelDownloadedV2
      case .v3: Constants.UserDefaults.parakeetModelDownloadedV3
      }
      UserDefaults.standard.set(true, forKey: key)
    } catch {
      // Leave flag unset; settings will keep showing "Not downloaded"
    }
  }

  private func exportSegment(_ segment: TranscriptSegmentSpec) async throws -> URL {
    let asset = AVURLAsset(url: segment.fileURL)
    guard let exportSession = AVAssetExportSession(
      asset: asset,
      presetName: AVAssetExportPresetAppleM4A
    ) else {
      throw BookPlayerError.runtimeError("Parakeet: unable to create export session.")
    }

    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("parakeet-transcript-\(UUID().uuidString).m4a")

    if FileManager.default.fileExists(atPath: outputURL.path) {
      try? FileManager.default.removeItem(at: outputURL)
    }

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .m4a
    exportSession.timeRange = CMTimeRange(
      start: CMTime(seconds: segment.startTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
      duration: CMTime(seconds: segment.duration, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    )

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      exportSession.exportAsynchronously {
        switch exportSession.status {
        case .completed:
          continuation.resume()
        case .failed, .cancelled:
          continuation.resume(throwing: exportSession.error ?? BookPlayerError.runtimeError("Parakeet: export failed."))
        default:
          continuation.resume(throwing: BookPlayerError.runtimeError("Parakeet: export failed."))
        }
      }
    }

    return outputURL
  }
}
