//
//  BookmarkTranscriptionService.swift
//  BookPlayer
//
//  Created by BookPlayer.
//

import AVFoundation
@preconcurrency import BookPlayerKit
import Combine
import CoreData
import Foundation
import Speech

protocol BookmarkTranscriptionServiceProtocol: AnyObject {
  var bookmarkUpdatesPublisher: AnyPublisher<String, Never> { get }

  func startTranscription(for bookmark: SimpleBookmark, in item: PlayableItem)
  func updateTranscriptRange(
    for bookmark: SimpleBookmark,
    in item: PlayableItem,
    startOffset: TimeInterval,
    endOffset: TimeInterval
  )
  func cancelTranscription(for bookmark: SimpleBookmark)
}

final class BookmarkTranscriptionService: BPLogger, BookmarkTranscriptionServiceProtocol {
  private struct TranscriptSegment {
    let fileURL: URL
    let startTime: TimeInterval
    let duration: TimeInterval
  }

  private enum TranscriptUpdate {
    case unchanged
    case clear
    case set(String)
  }

  private let dataManager: DataManager
  private var activeTasks: [String: Task<Void, Never>] = [:]
  private let taskLock = NSLock()
  private let updatesSubject = PassthroughSubject<String, Never>()

  var bookmarkUpdatesPublisher: AnyPublisher<String, Never> {
    updatesSubject.eraseToAnyPublisher()
  }

  init(dataManager: DataManager) {
    self.dataManager = dataManager
  }

  func startTranscription(for bookmark: SimpleBookmark, in item: PlayableItem) {
    requestTranscription(
      for: bookmark,
      in: item,
      startOffset: bookmark.transcriptStartOffset,
      endOffset: bookmark.transcriptEndOffset,
      persistOffsets: false
    )
  }

  func updateTranscriptRange(
    for bookmark: SimpleBookmark,
    in item: PlayableItem,
    startOffset: TimeInterval,
    endOffset: TimeInterval
  ) {
    requestTranscription(
      for: bookmark,
      in: item,
      startOffset: startOffset,
      endOffset: endOffset,
      persistOffsets: true
    )
  }

  func cancelTranscription(for bookmark: SimpleBookmark) {
    cancelTask(for: bookmark)
  }

  private func requestTranscription(
    for bookmark: SimpleBookmark,
    in item: PlayableItem,
    startOffset: TimeInterval,
    endOffset: TimeInterval,
    persistOffsets: Bool
  ) {
    guard bookmark.bookmarkType == .user else { return }

    let key = taskKey(for: bookmark)
    cancelTask(with: key)

    let clampedStart = clampOffset(startOffset)
    let clampedEnd = clampOffset(endOffset)

    let task = Task.detached(priority: .utility) { [weak self] in
      guard let self else { return }
      defer { self.setActiveTask(nil, for: key) }

      await self.updateBookmark(
        bookmark,
        startOffset: persistOffsets ? clampedStart : nil,
        endOffset: persistOffsets ? clampedEnd : nil,
        transcriptUpdate: .clear,
        state: .pending
      )
      self.publishUpdate(for: bookmark.relativePath)

      do {
        guard !Task.isCancelled else { return }

        let authStatus = await self.ensureSpeechAuthorization()
        guard authStatus == .authorized else {
          throw BookPlayerError.runtimeError("Speech recognition not authorized.")
        }

        guard let segment = self.makeSegment(
          for: bookmark,
          in: item,
          startOffset: clampedStart,
          endOffset: clampedEnd
        ) else {
          throw BookPlayerError.runtimeError("Could not build transcript segment.")
        }

        let transcript = try await self.transcribe(segment: segment)
        guard !Task.isCancelled else { return }

        await self.updateBookmark(
          bookmark,
          startOffset: nil,
          endOffset: nil,
          transcriptUpdate: .set(transcript),
          state: .ready
        )
        self.publishUpdate(for: bookmark.relativePath)
      } catch {
        guard !Task.isCancelled else { return }
        Self.logger.error("Bookmark transcription failed: \(error.localizedDescription)")
        await self.updateBookmark(
          bookmark,
          startOffset: nil,
          endOffset: nil,
          transcriptUpdate: .clear,
          state: .failed
        )
        self.publishUpdate(for: bookmark.relativePath)
      }
    }

    setActiveTask(task, for: key)
  }

  private func makeSegment(
    for bookmark: SimpleBookmark,
    in item: PlayableItem,
    startOffset: TimeInterval,
    endOffset: TimeInterval
  ) -> TranscriptSegment? {
    guard let chapter = item.getChapter(at: bookmark.time) else { return nil }

    let startGlobal = max(bookmark.time - startOffset, chapter.start)
    let endGlobal = min(bookmark.time + endOffset, chapter.end)
    let startTime = max(item.getChapterTime(in: chapter, for: startGlobal), 0)
    let endTime = max(item.getChapterTime(in: chapter, for: endGlobal), 0)
    let duration = max(endTime - startTime, 0)

    guard duration > 0 else { return nil }
    guard FileManager.default.fileExists(atPath: chapter.fileURL.path) else { return nil }

    return TranscriptSegment(
      fileURL: chapter.fileURL,
      startTime: startTime,
      duration: duration
    )
  }

  private func transcribe(segment: TranscriptSegment) async throws -> String {
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

    let request = SFSpeechURLRecognitionRequest(url: audioURL)
    request.shouldReportPartialResults = false
    if #available(iOS 13.0, *) {
      request.requiresOnDeviceRecognition = true
    }

    return try await withCheckedThrowingContinuation { continuation in
      var resumed = false
      _ = recognizer.recognitionTask(with: request) { result, error in
        if let error, !resumed {
          resumed = true
          continuation.resume(throwing: error)
          return
        }

        if let result, result.isFinal, !resumed {
          resumed = true
          continuation.resume(returning: result.bestTranscription.formattedString)
        }
      }
    }
  }

  private func exportSegment(_ segment: TranscriptSegment) async throws -> URL {
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

  private func updateBookmark(
    _ bookmark: SimpleBookmark,
    startOffset: TimeInterval?,
    endOffset: TimeInterval?,
    transcriptUpdate: TranscriptUpdate,
    state: BookmarkTranscriptState
  ) async {
    let context = dataManager.getBackgroundContext()
    await context.perform { [weak self] in
      guard let self,
        let bookmarkEntity = self.fetchBookmark(bookmark, context: context)
      else { return }

      if let startOffset {
        bookmarkEntity.transcriptStartOffset = startOffset
      }
      if let endOffset {
        bookmarkEntity.transcriptEndOffset = endOffset
      }

      switch transcriptUpdate {
      case .unchanged:
        break
      case .clear:
        bookmarkEntity.transcriptText = nil
      case .set(let text):
        bookmarkEntity.transcriptText = text
      }

      bookmarkEntity.transcriptState = state.rawValue
      self.dataManager.saveSyncContext(context)
    }
  }

  private func fetchBookmark(
    _ bookmark: SimpleBookmark,
    context: NSManagedObjectContext
  ) -> Bookmark? {
    let fetchRequest: NSFetchRequest<Bookmark> = Bookmark.fetchRequest()
    fetchRequest.predicate = NSPredicate(
      format: "%K == %@ && type == %d && time == %f",
      #keyPath(Bookmark.item.relativePath),
      bookmark.relativePath,
      bookmark.bookmarkType.rawValue,
      bookmark.time
    )
    fetchRequest.fetchLimit = 1

    return try? context.fetch(fetchRequest).first
  }

  private func ensureSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
    let currentStatus = SFSpeechRecognizer.authorizationStatus()
    guard currentStatus == .notDetermined else { return currentStatus }

    return await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        SFSpeechRecognizer.requestAuthorization { status in
          continuation.resume(returning: status)
        }
      }
    }
  }

  private func clampOffset(_ value: TimeInterval) -> TimeInterval {
    return min(max(value, Constants.BookmarkTranscript.minOffset), Constants.BookmarkTranscript.maxOffset)
  }

  private func taskKey(for bookmark: SimpleBookmark) -> String {
    return "\(bookmark.relativePath)-\(bookmark.time)-\(bookmark.bookmarkType.rawValue)"
  }

  private func cancelTask(for bookmark: SimpleBookmark) {
    cancelTask(with: taskKey(for: bookmark))
  }

  private func cancelTask(with key: String) {
    let task = getActiveTask(for: key)
    task?.cancel()
    setActiveTask(nil, for: key)
  }

  private func publishUpdate(for relativePath: String) {
    DispatchQueue.main.async { [weak self] in
      self?.updatesSubject.send(relativePath)
    }
  }

  private func getActiveTask(for key: String) -> Task<Void, Never>? {
    taskLock.lock()
    let task = activeTasks[key]
    taskLock.unlock()
    return task
  }

  private func setActiveTask(_ task: Task<Void, Never>?, for key: String) {
    taskLock.lock()
    activeTasks[key] = task
    taskLock.unlock()
  }
}
