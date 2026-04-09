//
//  BookmarkTranscriptionService.swift
//  BookPlayer
//
//  Created by BookPlayer.
//

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

final class BookmarkTranscriptionService: BPLogger, BookmarkTranscriptionServiceProtocol, @unchecked Sendable {
  private struct TranscriptSegment {
    let fileURL: URL
    let startTime: TimeInterval
    let duration: TimeInterval
  }

  /// Result of segment range computation: segment for engine + identity for store.
  private struct SegmentInfo {
    let segment: TranscriptSegment
    let relativePath: String
    let chapterIndex: Int16
    let startInChapter: TimeInterval
    let duration: TimeInterval
  }

  private enum TranscriptUpdate {
    case unchanged
    case clear
    case set(String)
  }

  private let dataManager: DataManager
  private let store: PlaybackTranscriptStoreProtocol
  private let engineFactory: () -> TranscriptEngineProtocol
  private var activeTasks: [String: Task<Void, Never>] = [:]
  private let taskLock = NSLock()
  private let updatesSubject = PassthroughSubject<String, Never>()

  var bookmarkUpdatesPublisher: AnyPublisher<String, Never> {
    updatesSubject.eraseToAnyPublisher()
  }

  init(
    dataManager: DataManager,
    store: PlaybackTranscriptStoreProtocol,
    engineFactory: @escaping () -> TranscriptEngineProtocol
  ) {
    self.dataManager = dataManager
    self.store = store
    self.engineFactory = engineFactory
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

        guard let info = self.makeSegmentInfo(
          for: bookmark,
          in: item,
          startOffset: clampedStart,
          endOffset: clampedEnd
        ) else {
          throw BookPlayerError.runtimeError("Could not build transcript segment.")
        }

        let rangeStart = info.startInChapter
        let rangeEnd = info.startInChapter + info.duration

        if let cached = self.cachedTranscript(
          relativePath: info.relativePath,
          chapterIndex: info.chapterIndex,
          rangeStart: rangeStart,
          rangeEnd: rangeEnd
        ) {
          guard !Task.isCancelled else { return }
          await self.updateBookmark(
            bookmark,
            startOffset: nil,
            endOffset: nil,
            transcriptUpdate: .set(cached),
            state: .ready
          )
          self.publishUpdate(for: bookmark.relativePath)
          return
        }

        let authStatus = await self.ensureSpeechAuthorization()
        guard authStatus == .authorized else {
          throw BookPlayerError.runtimeError("Speech recognition not authorized.")
        }

        let spec = TranscriptSegmentSpec(
          fileURL: info.segment.fileURL,
          startTime: info.segment.startTime,
          duration: info.segment.duration
        )
        let transcript: String
        do {
          let engine = self.engineFactory()
          transcript = try await engine.transcribe(segment: spec)
        } catch {
          if TranscriptEngineChoice.current == .parakeet {
            do {
              transcript = try await AppleSpeechTranscriptEngine().transcribe(segment: spec)
            } catch let fallbackErr {
              Self.logger.error("Bookmark transcription (Parakeet fallback) failed: \(fallbackErr.localizedDescription)")
              await self.updateBookmark(
                bookmark,
                startOffset: nil,
                endOffset: nil,
                transcriptUpdate: .clear,
                state: .failed
              )
              self.publishUpdate(for: bookmark.relativePath)
              return
            }
          } else {
            throw error
          }
        }
        guard !Task.isCancelled else { return }

        try? self.store.store(
          relativePath: info.relativePath,
          chapterIndex: info.chapterIndex,
          startInChapter: info.startInChapter,
          duration: info.duration,
          text: transcript
        )

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

  /// Returns merged transcript if the store has segments that fully cover [rangeStart, rangeEnd].
  private func cachedTranscript(
    relativePath: String,
    chapterIndex: Int16,
    rangeStart: TimeInterval,
    rangeEnd: TimeInterval
  ) -> String? {
    guard let lookups = try? store.segments(
      relativePath: relativePath,
      chapterIndex: chapterIndex,
      overlappingRangeStart: rangeStart,
      rangeEnd: rangeEnd
    ), !lookups.isEmpty else { return nil }

    let sorted = lookups.sorted { $0.startInChapter < $1.startInChapter }
    let first = sorted.first!
    let last = sorted.last!
    if first.startInChapter > rangeStart || (last.startInChapter + last.duration) < rangeEnd {
      return nil
    }
    return sorted.map(\.text).joined(separator: " ")
  }

  private func makeSegmentInfo(
    for bookmark: SimpleBookmark,
    in item: PlayableItem,
    startOffset: TimeInterval,
    endOffset: TimeInterval
  ) -> SegmentInfo? {
    guard let chapter = item.getChapter(at: bookmark.time) else { return nil }

    let startGlobal = max(bookmark.time - startOffset, chapter.start)
    let endGlobal = min(bookmark.time + endOffset, chapter.end)
    let startTime = max(item.getChapterTime(in: chapter, for: startGlobal), 0)
    var endTime = max(item.getChapterTime(in: chapter, for: endGlobal), 0)
    var duration = max(endTime - startTime, 0)

    if duration > Constants.BookmarkTranscript.maxSegmentDuration {
      duration = Constants.BookmarkTranscript.maxSegmentDuration
      endTime = startTime + duration
    }

    guard duration > 0 else { return nil }
    guard FileManager.default.fileExists(atPath: chapter.fileURL.path) else { return nil }

    return SegmentInfo(
      segment: TranscriptSegment(
        fileURL: chapter.fileURL,
        startTime: startTime,
        duration: duration
      ),
      relativePath: item.relativePath,
      chapterIndex: chapter.index,
      startInChapter: startTime,
      duration: duration
    )
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
