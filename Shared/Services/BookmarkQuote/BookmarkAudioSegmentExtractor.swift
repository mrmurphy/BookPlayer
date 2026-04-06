//
//  BookmarkAudioSegmentExtractor.swift
//  BookPlayerKit
//

import AVFoundation
import Foundation

public enum BookmarkAudioSegmentExtractorError: Error {
  case fileNotFound
  case exportFailed
}

public struct BookmarkAudioSegmentExtractor: Sendable {
  public init() {}

  /// Exports `[start, end]` (clamped to asset duration) to a temporary `.m4a` file.
  public func exportSegment(
    sourceURL: URL,
    start: TimeInterval,
    end: TimeInterval
  ) async throws -> URL {
    #if os(watchOS)
    _ = sourceURL
    _ = start
    _ = end
    throw BookmarkAudioSegmentExtractorError.exportFailed
    #else
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      throw BookmarkAudioSegmentExtractorError.fileNotFound
    }

    let asset = AVURLAsset(url: sourceURL)
    let durationSeconds = try await asset.load(.duration).seconds
    let safeStart = max(0, min(start, durationSeconds))
    let safeEnd = max(safeStart, min(end, durationSeconds))

    let startCM = CMTime(seconds: safeStart, preferredTimescale: 600)
    let endCM = CMTime(seconds: safeEnd, preferredTimescale: 600)
    let durationCM = CMTimeSubtract(endCM, startCM)
    let range = CMTimeRange(start: startCM, duration: durationCM)

    guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
      throw BookmarkAudioSegmentExtractorError.exportFailed
    }

    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("bp-quote-\(UUID().uuidString).m4a")
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try? FileManager.default.removeItem(at: outputURL)
    }

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .m4a
    exportSession.timeRange = range

    await exportSession.export()

    guard exportSession.status == .completed else {
      throw BookmarkAudioSegmentExtractorError.exportFailed
    }

    return outputURL
    #endif
  }
}
