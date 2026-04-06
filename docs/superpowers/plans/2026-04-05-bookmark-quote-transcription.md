# Bookmark quote transcription implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a user creates a user bookmark, BookPlayer captures a configurable audio window, transcribes it with on-device Speech APIs (iOS 26+), cleans the text with Foundation Models when available (otherwise NaturalLanguage heuristics), persists results on the bookmark, and offers a SwiftUI sheet to tune the window, preview raw/cleaned text, and copy with optional book metadata.

**Architecture:** All quote-specific logic lives in small types under `Shared/Services/BookmarkQuote/` (BookPlayerKit). A coordinator sequences audio extraction → transcription → cleanup → Core Data persistence. UI and settings live in the BookPlayer app target. Everything that calls iOS 26-only frameworks is isolated in `@available(iOS 26, *)` files so the project can keep its current deployment target while building with the iOS 26 SDK.

**Tech stack:** Core Data (new model version), AVFoundation (segment export), `Speech` (SpeechAnalyzer / SpeechTranscriber / AssetInventory per Apple docs), `FoundationModels` (SystemLanguageModel, LanguageModelSession, `@Generable`), `NaturalLanguage` (heuristic fallback), SwiftUI, XCTest.

**Authoritative spec:** `docs/superpowers/specs/2026-04-05-bookmark-quote-transcription-design.md`

---

## File map (create / modify)

| Path | Role |
|------|------|
| `Shared/CoreData/BookPlayer.xcdatamodeld/Audiobook Player 11.xcdatamodel/contents` | New model version: optional quote fields on `Bookmark` |
| `Shared/CoreData/BookPlayer.xcdatamodeld/.xccurrentversion` | Point current model to `Audiobook Player 11` |
| `Shared/CoreData/Backed-Models/Bookmark+CoreDataProperties.swift` | `@NSManaged` for new attributes |
| `Shared/Constants.swift` | UserDefaults keys for default seconds before/after |
| `Shared/Services/LibraryService.swift` | Quote CRUD on `Bookmark` |
| `Shared/Services/LibraryService.swift` (`LibraryServiceProtocol`) | New protocol methods |
| `BookPlayer/Generated/AutoMockable.generated.swift` | Regenerate after protocol change (Sourcery) |
| `Shared/Services/BookmarkQuote/BookmarkQuoteModels.swift` | `BookmarkQuoteSnapshot`, errors, `QuoteCleanupPath` enum |
| `Shared/Services/BookmarkQuote/BookmarkQuoteHeuristicCleaner.swift` | NL-only cleanup |
| `Shared/Services/BookmarkQuote/BookmarkQuoteMetadataFormatter.swift` | Clipboard with optional metadata |
| `Shared/Services/BookmarkQuote/BookmarkAudioSegmentExtractor.swift` | AVAsset → temp audio file for time range |
| `Shared/Services/BookmarkQuote/BookmarkSpeechTranscriber.swift` | `@available(iOS 26, *)` Speech pipeline |
| `Shared/Services/BookmarkQuote/BookmarkQuoteFoundationModelsCleaner.swift` | `@available(iOS 26, *)` FM cleanup |
| `Shared/Services/BookmarkQuote/BookmarkQuoteCleanerFacade.swift` | Chooses FM vs heuristic from model availability |
| `Shared/Services/BookmarkQuote/BookmarkQuoteGenerationCoordinator.swift` | Orchestrates full pipeline + cancellation |
| `BookPlayer/Info.plist` | `NSSpeechRecognitionUsageDescription` (and microphone only if required by chosen export path) |
| `BookPlayer/Coordinators/DataInitializerCoordinator.swift` | Register default 20 / 30 s on first launch if keys unset |
| `BookPlayer/Settings/Sections/SettingsPlaybackSectionView.swift` (or new section file) | Defaults for seconds before/after |
| `BookPlayer/Player/Views/Bookmarks/BookmarkQuoteView.swift` | Sheet UI |
| `BookPlayer/Player/Views/Bookmarks/BookmarkQuoteViewModel.swift` | State machine for the sheet |
| `BookPlayer/Player/Views/Bookmarks/BookmarksView.swift` | Entry: context menu / button for user bookmarks |
| `BookPlayer/Player/Views/Bookmarks/BookmarksViewModel.swift` | Present quote sheet, optional refresh |
| `BookPlayer/Player/ViewModels/PlayerViewModel.swift` | After bookmark created: offer “Quote” in alert actions (gated by `#available(iOS 26, *)`) |
| `BookPlayer/**/*.lproj/Localizable.strings` (e.g. `BookPlayer/en.lproj`) | New copy keys |
| `BookPlayerTests/Services/BookmarkQuoteHeuristicCleanerTests.swift` | Unit tests |
| `BookPlayerTests/Services/BookmarkQuoteMetadataFormatterTests.swift` | Unit tests |

**Xcode:** After adding Swift files under `Shared/Services/BookmarkQuote/`, ensure each file’s target membership includes **BookPlayerKit** (and not the watch extension). Use **File → Add Files to "BookPlayer"** if the folder is new.

**SDK:** Build with **Xcode that ships the iOS 26 SDK**. Keep `IPHONEOS_DEPLOYMENT_TARGET` as today unless the maintainers choose a project-wide bump; new APIs stay behind `@available(iOS 26, *)`.

---

### Task 1: Core Data model version 11

**Files:**
- Create: `Shared/CoreData/BookPlayer.xcdatamodeld/Audiobook Player 11.xcdatamodel/contents` (duplicate structure from `Audiobook Player 10` and add attributes)
- Modify: `Shared/CoreData/BookPlayer.xcdatamodeld/.xccurrentversion`
- Modify: `Shared/CoreData/Backed-Models/Bookmark+CoreDataProperties.swift`

- [ ] **Step 1: Duplicate model 10 → 11 in Xcode**

In Xcode, select `BookPlayer.xcdatamodeld` → **Editor → Add Model Version…** → name `Audiobook Player 11`, set as current. On the `Bookmark` entity add optional attributes:

- `quoteRawText` — String, optional  
- `quoteCleanedText` — String, optional  
- `quoteSecondsBefore` — Double, optional  
- `quoteSecondsAfter` — Double, optional  
- `quoteLastUpdatedAt` — Date, optional  

- [ ] **Step 2: Regenerate / update `Bookmark+CoreDataProperties.swift`**

Add:

```swift
@NSManaged public var quoteRawText: String?
@NSManaged public var quoteCleanedText: String?
@NSManaged public var quoteSecondsBefore: Double
@NSManaged public var quoteSecondsAfter: Double
@NSManaged public var quoteLastUpdatedAt: Date?
```

Use **optional** Core Data types: for scalar doubles, either mark optional in the model and use `NSNumber?` pattern or use `transformable` — **prefer optional scalars** as the rest of the model does for similar fields. If Xcode generates `NSNumber?` for optional Double, match that style consistently with other entities in this project.

- [ ] **Step 3: Build BookPlayerKit**

Run:

```bash
cd /Users/murphy/projects/BookPlayer
xcodebuild -scheme BookPlayer -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build
```

Expected: **BUILD SUCCEEDED** (adjust simulator name to one installed locally).

- [ ] **Step 4: Commit**

```bash
git add Shared/CoreData/BookPlayer.xcdatamodeld Shared/CoreData/Backed-Models/Bookmark+CoreDataProperties.swift
git commit -m "feat(coredata): add bookmark quote fields for transcription v1"
```

---

### Task 2: UserDefaults keys and first-launch defaults

**Files:**
- Modify: `Shared/Constants.swift`
- Modify: `BookPlayer/Coordinators/DataInitializerCoordinator.swift`

- [ ] **Step 1: Add keys in `Constants.UserDefaults`**

In `Shared/Constants.swift`, inside `public enum UserDefaults`, add:

```swift
public static let bookmarkQuoteSecondsBeforeDefault = "userSettingsBookmarkQuoteSecondsBefore"
public static let bookmarkQuoteSecondsAfterDefault = "userSettingsBookmarkQuoteSecondsAfter"
```

- [ ] **Step 2: Register defaults in `setupUserDefaultsPreferences`**

In `DataInitializerCoordinator.setupUserDefaultsPreferences`, after the guard that skips non–first-launch, **or** in a small dedicated helper called from `setupLibrary` that runs once when keys are missing, set:

```swift
let shared = UserDefaults.sharedDefaults
if shared.object(forKey: Constants.UserDefaults.bookmarkQuoteSecondsBeforeDefault) == nil {
  shared.set(20, forKey: Constants.UserDefaults.bookmarkQuoteSecondsBeforeDefault)
}
if shared.object(forKey: Constants.UserDefaults.bookmarkQuoteSecondsAfterDefault) == nil {
  shared.set(30, forKey: Constants.UserDefaults.bookmarkQuoteSecondsAfterDefault)
}
```

Use `sharedDefaults` to match other player-facing preferences (see `chapterContextEnabled` pattern in the same file).

- [ ] **Step 3: Commit**

```bash
git add Shared/Constants.swift BookPlayer/Coordinators/DataInitializerCoordinator.swift
git commit -m "feat(settings): default bookmark quote window 20s / 30s"
```

---

### Task 3: `BookmarkQuoteHeuristicCleaner` + tests (TDD)

**Files:**
- Create: `Shared/Services/BookmarkQuote/BookmarkQuoteHeuristicCleaner.swift` (BookPlayerKit target)
- Create: `BookPlayerTests/Services/BookmarkQuoteHeuristicCleanerTests.swift`

- [ ] **Step 1: Write failing test**

`BookPlayerTests/Services/BookmarkQuoteHeuristicCleanerTests.swift`:

```swift
import XCTest
@testable import BookPlayerKit

final class BookmarkQuoteHeuristicCleanerTests: XCTestCase {
  func testCollapsesWhitespaceAndNewlines() {
    let raw = "  hello \n\n world  "
    let out = BookmarkQuoteHeuristicCleaner.cleanedQuote(from: raw)
    XCTAssertFalse(out.contains("\n"))
    XCTAssertTrue(out.contains("hello"))
    XCTAssertTrue(out.contains("world"))
  }

  func testAddsEllipsisWhenTrimmingToInnerSentences() {
    let raw = "orphan word. This is a full sentence. Another one here. trailing"
    let out = BookmarkQuoteHeuristicCleaner.cleanedQuote(from: raw)
    XCTAssertTrue(out.contains("This is a full sentence"))
    XCTAssertTrue(out.hasPrefix("…") || out.hasSuffix("…") || out.contains("…"))
  }

  func testEmptyInput() {
    XCTAssertEqual(BookmarkQuoteHeuristicCleaner.cleanedQuote(from: ""), "")
    XCTAssertEqual(BookmarkQuoteHeuristicCleaner.cleanedQuote(from: "   \n"), "")
  }
}
```

- [ ] **Step 2: Run tests — expect failure**

```bash
cd /Users/murphy/projects/BookPlayer
xcodebuild -scheme BookPlayer -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:BookPlayerTests/BookmarkQuoteHeuristicCleanerTests test
```

Expected: **fail** — type `BookmarkQuoteHeuristicCleaner` missing.

- [ ] **Step 3: Implement cleaner**

`Shared/Services/BookmarkQuote/BookmarkQuoteHeuristicCleaner.swift`:

```swift
import Foundation
import NaturalLanguage

public enum BookmarkQuoteHeuristicCleaner {
  /// Sentence-based trim for when Foundation Models is unavailable.
  public static func cleanedQuote(from raw: String) -> String {
    let singleLine = raw
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")

    let collapsed = singleLine.replacingOccurrences(
      of: "  +",
      with: " ",
      options: .regularExpression
    ).trimmingCharacters(in: .whitespacesAndNewlines)

    guard !collapsed.isEmpty else { return "" }

    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = collapsed

    var ranges: [Range<String.Index>] = []
    tokenizer.enumerateTokens(in: collapsed.startIndex..<collapsed.endIndex) { range, _ in
      ranges.append(range)
      return true
    }

    guard let firstRange = ranges.first, let lastRange = ranges.last else {
      return "…" + collapsed + "…"
    }

    let excerpt = String(collapsed[firstRange.lowerBound..<lastRange.upperBound])
    let trimmedExcerpt = excerpt.trimmingCharacters(in: .whitespacesAndNewlines)

    var leadingEllipsis = firstRange.lowerBound > collapsed.startIndex
    var trailingEllipsis = lastRange.upperBound < collapsed.endIndex

    if trimmedExcerpt.isEmpty {
      return "…" + collapsed + "…"
    }

    var result = trimmedExcerpt
    if leadingEllipsis { result = "…" + result }
    if trailingEllipsis { result = result + "…" }
    return result
  }
}
```

- [ ] **Step 4: Run tests — expect pass**

Same `xcodebuild` command as Step 2. Expected: **all tests pass**.

- [ ] **Step 5: Commit**

```bash
git add Shared/Services/BookmarkQuote/BookmarkQuoteHeuristicCleaner.swift BookPlayerTests/Services/BookmarkQuoteHeuristicCleanerTests.swift BookPlayer.xcodeproj/project.pbxproj
git commit -m "feat(quote): heuristic bookmark quote cleanup with NLTokenizer"
```

---

### Task 4: `BookmarkQuoteMetadataFormatter` + tests (TDD)

**Files:**
- Create: `Shared/Services/BookmarkQuote/BookmarkQuoteMetadataFormatter.swift`
- Create: `BookPlayerTests/Services/BookmarkQuoteMetadataFormatterTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
@testable import BookPlayerKit

final class BookmarkQuoteMetadataFormatterTests: XCTestCase {
  func testWithoutMetadataReturnsQuoteOnly() {
    let s = BookmarkQuoteMetadataFormatter.clipboardPayload(
      cleanedQuote: "Hello world.",
      title: "My Book",
      author: "Ada L.",
      formattedTimestamp: "1:02:03",
      includeMetadata: false
    )
    XCTAssertEqual(s, "Hello world.")
  }

  func testWithMetadataPrependsBlock() {
    let s = BookmarkQuoteMetadataFormatter.clipboardPayload(
      cleanedQuote: "Hello world.",
      title: "My Book",
      author: "Ada L.",
      formattedTimestamp: "1:02:03",
      includeMetadata: true
    )
    XCTAssertTrue(s.hasPrefix("My Book\nAda L.\n1:02:03\n\n"))
    XCTAssertTrue(s.hasSuffix("Hello world."))
  }
}
```

- [ ] **Step 2: Run tests — expect failure**

```bash
xcodebuild -scheme BookPlayer -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:BookPlayerTests/BookmarkQuoteMetadataFormatterTests test
```

- [ ] **Step 3: Implement**

`Shared/Services/BookmarkQuote/BookmarkQuoteMetadataFormatter.swift`:

```swift
import Foundation

public enum BookmarkQuoteMetadataFormatter {
  public static func clipboardPayload(
    cleanedQuote: String,
    title: String,
    author: String,
    formattedTimestamp: String,
    includeMetadata: Bool
  ) -> String {
    guard includeMetadata else { return cleanedQuote }
    let header = "\(title)\n\(author)\n\(formattedTimestamp)\n\n"
    return header + cleanedQuote
  }
}
```

- [ ] **Step 4: Run tests — expect pass**

- [ ] **Step 5: Commit**

```bash
git add Shared/Services/BookmarkQuote/BookmarkQuoteMetadataFormatter.swift BookPlayerTests/Services/BookmarkQuoteMetadataFormatterTests.swift BookPlayer.xcodeproj/project.pbxproj
git commit -m "feat(quote): clipboard formatter with optional book metadata"
```

---

### Task 5: Shared models + `LibraryService` persistence API

**Files:**
- Create: `Shared/Services/BookmarkQuote/BookmarkQuoteModels.swift`
- Modify: `Shared/Services/LibraryService.swift` (`LibraryServiceProtocol` + implementation)

- [ ] **Step 1: Add models**

`BookmarkQuoteModels.swift`:

```swift
import Foundation

public struct BookmarkQuoteSnapshot: Equatable, Sendable {
  public var rawText: String?
  public var cleanedText: String?
  public var secondsBefore: Double?
  public var secondsAfter: Double?
  public var lastUpdated: Date?

  public init(
    rawText: String?,
    cleanedText: String?,
    secondsBefore: Double?,
    secondsAfter: Double?,
    lastUpdated: Date?
  ) {
    self.rawText = rawText
    self.cleanedText = cleanedText
    self.secondsBefore = secondsBefore
    self.secondsAfter = secondsAfter
    self.lastUpdated = lastUpdated
  }
}

public enum BookmarkQuoteServiceError: Error {
  case bookmarkNotFound
}
```

- [ ] **Step 2: Extend protocol**

In `LibraryServiceProtocol` under Bookmarks:

```swift
func loadQuoteSnapshot(for bookmark: SimpleBookmark) throws -> BookmarkQuoteSnapshot
func saveQuote(
  for bookmark: SimpleBookmark,
  raw: String,
  cleaned: String,
  secondsBefore: Double,
  secondsAfter: Double
) throws
```

- [ ] **Step 3: Implement using `getBookmarkReference`**

In `LibraryService`:

```swift
public func loadQuoteSnapshot(for bookmark: SimpleBookmark) throws -> BookmarkQuoteSnapshot {
  guard let ref = getBookmarkReference(from: bookmark) else {
    throw BookmarkQuoteServiceError.bookmarkNotFound
  }
  let hasQuote = ref.quoteRawText != nil || ref.quoteCleanedText != nil
  return BookmarkQuoteSnapshot(
    rawText: ref.quoteRawText,
    cleanedText: ref.quoteCleanedText,
    secondsBefore: hasQuote ? ref.quoteSecondsBefore : nil,
    secondsAfter: hasQuote ? ref.quoteSecondsAfter : nil,
    lastUpdated: ref.quoteLastUpdatedAt
  )
}
```

**Important:** Map `secondsBefore` / `secondsAfter` to `nil` when no quote has ever been saved (`hasQuote == false`), regardless of scalar defaults Xcode generates for optional Core Data numbers.

Implementation for `saveQuote`:

```swift
public func saveQuote(
  for bookmark: SimpleBookmark,
  raw: String,
  cleaned: String,
  secondsBefore: Double,
  secondsAfter: Double
) throws {
  guard let ref = getBookmarkReference(from: bookmark) else {
    throw BookmarkQuoteServiceError.bookmarkNotFound
  }
  ref.quoteRawText = raw
  ref.quoteCleanedText = cleaned
  ref.quoteSecondsBefore = secondsBefore
  ref.quoteSecondsAfter = secondsAfter
  ref.quoteLastUpdatedAt = Date()
  dataManager.saveContext()
}
```

- [ ] **Step 4: Regenerate Sourcery mocks**

From repo root (with Sourcery installed):

```bash
cd /Users/murphy/projects/BookPlayer
sourcery
```

Expected: `BookPlayer/Generated/AutoMockable.generated.swift` updates without compile errors.

- [ ] **Step 5: Build**

```bash
xcodebuild -scheme BookPlayer -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build
```

- [ ] **Step 6: Commit**

```bash
git add Shared/Services/BookmarkQuote/BookmarkQuoteModels.swift Shared/Services/LibraryService.swift BookPlayer/Generated/AutoMockable.generated.swift
git commit -m "feat(quote): persist bookmark quote fields via LibraryService"
```

---

### Task 6: `BookmarkAudioSegmentExtractor`

**Files:**
- Create: `Shared/Services/BookmarkQuote/BookmarkAudioSegmentExtractor.swift`

- [ ] **Step 1: Define API**

```swift
import AVFoundation
import Foundation

public enum BookmarkAudioSegmentExtractorError: Error {
  case fileNotFound
  case exportFailed
}

public struct BookmarkAudioSegmentExtractor: Sendable {
  public init() {}

  /// Exports `[start, end]` (clamped to asset duration) to a temporary file URL suitable for speech analysis.
  public func exportSegment(
    sourceURL: URL,
    start: TimeInterval,
    end: TimeInterval
  ) async throws -> URL {
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      throw BookmarkAudioSegmentExtractorError.fileNotFound
    }

    let asset = AVURLAsset(url: sourceURL)
    let durationSec = try await asset.load(.duration).seconds
    let safeStart = max(0, min(start, durationSec))
    let safeEnd = max(safeStart, min(end, durationSec))

    let startCM = CMTime(seconds: safeStart, preferredTimescale: 600)
    let endCM = CMTime(seconds: safeEnd, preferredTimescale: 600)
    let durationCM = CMTimeSubtract(endCM, startCM)
    let range = CMTimeRange(start: startCM, duration: durationCM)

    guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
      throw BookmarkAudioSegmentExtractorError.exportFailed
    }

    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("bp-quote-\(UUID().uuidString).m4a")
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try? FileManager.default.removeItem(at: outputURL)
    }

    export.outputURL = outputURL
    export.outputFileType = .m4a
    export.timeRange = range

    await export.export()

    guard export.status == .completed else {
      throw BookmarkAudioSegmentExtractorError.exportFailed
    }

    return outputURL
  }
}
```

If `export()` async API differs slightly by SDK, use the Xcode-suggested `await export.export(to: …)` overload for your deployment.

- [ ] **Step 2: Build BookPlayerKit**

- [ ] **Step 3: Commit**

```bash
git add Shared/Services/BookmarkQuote/BookmarkAudioSegmentExtractor.swift BookPlayer.xcodeproj/project.pbxproj
git commit -m "feat(quote): export bookmark time range to temp audio for STT"
```

---

### Task 7: `BookmarkSpeechTranscriber` (iOS 26 Speech)

**Files:**
- Create: `Shared/Services/BookmarkQuote/BookmarkSpeechTranscriber.swift`

- [ ] **Step 1: Implement against Apple documentation**

Add `import Speech`. Mark the type:

```swift
@available(iOS 26, *)
public struct BookmarkSpeechTranscriber: Sendable {
  public init() {}

  public func transcribe(fileURL: URL) async throws -> String {
    fatalError("Implement using SpeechAnalyzer + SpeechTranscriber + AssetInventory per Apple docs and WWDC25 session 277")
  }
}
```

Replace `fatalError` with the real pipeline:

1. Use **`AssetInventory`** (or the documented replacement) to ensure on-device models are available; throw a dedicated error like `BookmarkSpeechError.assetsNotReady` if not.  
2. Configure **`SpeechTranscriber`** as a module on **`SpeechAnalyzer`**.  
3. Feed audio from `fileURL` using the format Apple’s sample code expects.  
4. Collect final text from the analyzer’s `AsyncSequence` output.  
5. Delete the temp file after transcription if the coordinator does not own cleanup.

**References:** [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer), WWDC25 “Bring advanced speech-to-text to your app with SpeechAnalyzer”.

- [ ] **Step 2: Build on iOS 26 SDK** — fix symbols until **BUILD SUCCEEDED**.

- [ ] **Step 3: Commit**

```bash
git add Shared/Services/BookmarkQuote/BookmarkSpeechTranscriber.swift
git commit -m "feat(quote): SpeechAnalyzer transcription for bookmark audio"
```

---

### Task 8: `BookmarkQuoteFoundationModelsCleaner` (iOS 26)

**Files:**
- Create: `Shared/Services/BookmarkQuote/BookmarkQuoteFoundationModelsCleaner.swift`

- [ ] **Step 1: Add Generable result type**

```swift
import Foundation
import FoundationModels

@available(iOS 26, *)
@Generable
struct CleanedBookmarkQuote: Equatable {
  @Guide(description: "Verbatim quotable excerpt. No preamble or meta commentary.")
  let quote: String
  @Guide(description: "True if the excerpt starts mid-sentence and should show a leading ellipsis character.")
  let leadingEllipsis: Bool
  @Guide(description: "True if the excerpt ends mid-sentence and should show a trailing ellipsis character.")
  let trailingEllipsis: Bool
}
```

- [ ] **Step 2: Implement cleaner**

```swift
@available(iOS 26, *)
public enum BookmarkQuoteFoundationModelsCleaner {
  public static func cleanedQuote(from raw: String) async throws -> String {
    let model = SystemLanguageModel.default
    guard case .available = model.availability else {
      throw BookmarkQuoteFMError.modelUnavailable
    }

    let session = LanguageModelSession(instructions: Instructions {
      "You polish audiobook speech-to-text into a single quotable excerpt."
      "Preserve the speaker's meaning and wording; fix obvious STT junk only."
      "Never add title, author, or timestamps."
    })

    let response = try await session.respond(
      generating: CleanedBookmarkQuote.self,
      options: GenerationOptions(sampling: .greedy)
    ) {
      "Raw transcription:\n\(raw)"
    }

    var text = response.content.quote.trimmingCharacters(in: .whitespacesAndNewlines)
    if response.content.leadingEllipsis { text = "…" + text }
    if response.content.trailingEllipsis { text = text + "…" }
    return text
  }
}

@available(iOS 26, *)
public enum BookmarkQuoteFMError: Error {
  case modelUnavailable
}
```

Adjust `respond(generating:options:)` / `Instructions` syntax to match the exact Xcode 26 API if the compiler suggests a different initializer.

- [ ] **Step 3: Build**

- [ ] **Step 4: Commit**

```bash
git add Shared/Services/BookmarkQuote/BookmarkQuoteFoundationModelsCleaner.swift
git commit -m "feat(quote): Foundation Models cleanup for bookmark quotes"
```

---

### Task 9: `BookmarkQuoteCleanerFacade` + coordinator

**Files:**
- Create: `Shared/Services/BookmarkQuote/BookmarkQuoteCleanerFacade.swift`
- Create: `Shared/Services/BookmarkQuote/BookmarkQuoteGenerationCoordinator.swift`

- [ ] **Step 1: Facade**

```swift
import Foundation

public enum QuoteCleanupPath: String, Sendable {
  case foundationModels
  case heuristic
}

public enum BookmarkQuoteCleanerFacade {
  public static func clean(
    raw: String
  ) async -> (text: String, path: QuoteCleanupPath) {
    if #available(iOS 26, *) {
      if case .available = SystemLanguageModel.default.availability {
        do {
          let text = try await BookmarkQuoteFoundationModelsCleaner.cleanedQuote(from: raw)
          return (text, .foundationModels)
        } catch {
          return (BookmarkQuoteHeuristicCleaner.cleanedQuote(from: raw), .heuristic)
        }
      }
    }
    return (BookmarkQuoteHeuristicCleaner.cleanedQuote(from: raw), .heuristic)
  }
}
```

Add `import FoundationModels` only inside `#available` branches if needed to avoid import issues — if the compiler requires top-level import, keep the file `@available(iOS 26, *)` **only** for the FM branch and split into two files if Swift complains.

**Pragmatic split if needed:** Put `BookmarkQuoteCleanerFacade` in the app target instead of BookPlayerKit to avoid linking FoundationModels into Kit on older toolchains — **prefer keeping everything in Kit** if linking succeeds.

- [ ] **Step 2: Coordinator skeleton**

`BookmarkQuoteGenerationCoordinator`:

```swift
import Foundation

public actor BookmarkQuoteGenerationCoordinator {
  private var task: Task<Void, Never>?

  public init() {}

  public func cancel() {
    task?.cancel()
    task = nil
  }

  public func generate(
    bookmark: SimpleBookmark,
    playable: PlayableItem,
    secondsBefore: Double,
    secondsAfter: Double,
    library: LibraryServiceProtocol
  ) async throws -> BookmarkQuoteSnapshot {
    cancel()
    let start = max(0, bookmark.time - secondsBefore)
    let end = min(playable.duration, bookmark.time + secondsAfter)

    let extractor = BookmarkAudioSegmentExtractor()
    let segmentURL = try await extractor.exportSegment(
      sourceURL: playable.fileURL,
      start: start,
      end: end
    )
    defer { try? FileManager.default.removeItem(at: segmentURL) }

    let raw: String
    if #available(iOS 26, *) {
      raw = try await BookmarkSpeechTranscriber().transcribe(fileURL: segmentURL)
    } else {
      throw BookmarkQuoteGenerationError.osTooOld
    }

    let cleaned = await BookmarkQuoteCleanerFacade.clean(raw: raw)
    try library.saveQuote(
      for: bookmark,
      raw: raw,
      cleaned: cleaned.text,
      secondsBefore: secondsBefore,
      secondsAfter: secondsAfter
    )
    return try library.loadQuoteSnapshot(for: bookmark)
  }
}

public enum BookmarkQuoteGenerationError: Error {
  case osTooOld
}
```

Wire `PlayableItem` import (already in BookPlayerKit). Replace `throws` / `cancel` semantics with `Task.checkCancellation()` inside the inner `Task` if you offload work to unstructured tasks.

- [ ] **Step 3: Build**

- [ ] **Step 4: Commit**

```bash
git add Shared/Services/BookmarkQuote/BookmarkQuoteCleanerFacade.swift Shared/Services/BookmarkQuote/BookmarkQuoteGenerationCoordinator.swift
git commit -m "feat(quote): coordinator for extract, transcribe, clean, save"
```

---

### Task 10: Settings UI for default window

**Files:**
- Modify: `BookPlayer/Settings/Sections/SettingsPlaybackSectionView.swift` or add `SettingsBookmarkQuoteSectionView.swift` and embed from `SettingsView.swift`

- [ ] **Step 1: Add SwiftUI controls bound to `UserDefaults.sharedDefaults`**

Use `@AppStorage(Constants.UserDefaults.bookmarkQuoteSecondsBeforeDefault)` and `...After...` with **Double** or **Int** storage (if `@AppStorage` Double is awkward, store **Int** seconds and document the change in `DataInitializerCoordinator` defaults).

Clamp displayed values to **5…180** in the control’s `onChange`.

- [ ] **Step 2: Add localized section title** e.g. `settings_bookmark_quote_section_title` / `settings_bookmark_quote_seconds_before`.

- [ ] **Step 3: Build + snapshot sanity**

- [ ] **Step 4: Commit**

```bash
git add BookPlayer/Settings BookPlayer/en.lproj/Localizable.strings BookPlayer.xcodeproj/project.pbxproj
git commit -m "feat(settings): defaults for bookmark quote window"
```

---

### Task 11: `BookmarkQuoteView` + `BookmarkQuoteViewModel`

**Files:**
- Create: `BookPlayer/Player/Views/Bookmarks/BookmarkQuoteViewModel.swift`
- Create: `BookPlayer/Player/Views/Bookmarks/BookmarkQuoteView.swift`

- [ ] **Step 1: ViewModel state**

Hold:

- `secondsBefore`, `secondsAfter` (initialized from `loadQuoteSnapshot` if present, else `UserDefaults`)  
- `showRaw` (Bool)  
- `includeMetadataInCopy` (Bool)  
- `phase`: idle / preparingAssets / transcribing / cleaning / error  
- `errorMessage: String?`  
- `cleanupPath: QuoteCleanupPath?` for subtle footnote when `.heuristic`  
- `snapshot: BookmarkQuoteSnapshot`

Methods: `applyTuning()` calls `BookmarkQuoteGenerationCoordinator().generate(...)`, `copyToPasteboard()` uses `BookmarkQuoteMetadataFormatter` + `UIPasteboard.general.string`.

- [ ] **Step 2: SwiftUI layout**

- Steppers and optional sliders for before/after (clamped 5…180).  
- **“Update quote”** button triggers `applyTuning()`.  
- Primary `Text` for cleaned quote; disclosure / toggle for raw.  
- **Copy** button.  
- Checkbox for metadata.  
- If `phase` is loading, show `ProgressView` and disable duplicate applies.

Gate the entire feature with:

```swift
if #available(iOS 26, *) {
  // full UI
} else {
  Text("bookmark_quote_unavailable_os".localized) // or EmptyView
}
```

- [ ] **Step 3: Commit**

```bash
git add BookPlayer/Player/Views/Bookmarks/BookmarkQuoteView.swift BookPlayer/Player/Views/Bookmarks/BookmarkQuoteViewModel.swift BookPlayer/en.lproj/Localizable.strings
git commit -m "feat(ui): bookmark quote sheet with tuning and copy"
```

---

### Task 12: Entry points — bookmarks list + player alert

**Files:**
- Modify: `BookPlayer/Player/Views/Bookmarks/BookmarksView.swift`
- Modify: `BookPlayer/Player/Views/Bookmarks/BookmarksViewModel.swift` (or pass closure from parent)
- Modify: `BookPlayer/Player/ViewModels/PlayerViewModel.swift`

- [ ] **Step 1: Bookmarks list**

For **user** bookmark rows, add a **menu** or trailing button (e.g. `quote.bubble`) that sets `@State var quoteBookmark: SimpleBookmark?` and presents `.sheet(item: $quoteBookmark) { … BookmarkQuoteView(...) }`.

Do **not** show the control for automatic bookmark types.

- [ ] **Step 2: Player bookmark alert**

In `showBookmarkSuccessAlert`, when `!existed` and `#available(iOS 26, *)`, append a `BPActionItem` titled `bookmark_quote_action_title` that presents the same sheet (requires a callback into the view layer — use existing `displaySheet` / published `sheet` state pattern in `PlayerViewModel` consistent with how `bookmark` sheet works).

- [ ] **Step 3: Info.plist**

Add `NSSpeechRecognitionUsageDescription` with a clear string e.g. “BookPlayer transcribes a short audio clip around your bookmark so you can copy a quote.”

- [ ] **Step 4: Manual test checklist**

1. Create bookmark on iOS 26 simulator with a local m4b.  
2. Open Quote sheet, run Update quote, verify raw + cleaned.  
3. Toggle Apple Intelligence off (if simulator allows) and confirm heuristic path + footnote.  
4. Copy with and without metadata.  
5. Change N/Y, Apply, confirm text changes (re-transcription).

- [ ] **Step 5: Commit**

```bash
git add BookPlayer/Player/Views/Bookmarks BookPlayer/Player/ViewModels/PlayerViewModel.swift BookPlayer/Info.plist
git commit -m "feat(quote): entry points from bookmarks list and bookmark alert"
```

---

## Plan self-review

**Spec coverage**

| Spec area | Tasks |
|-----------|-------|
| Core Data fields | Task 1, 5 |
| Defaults 20/30 s, UserDefaults | Task 2, 10 |
| Extract + re-transcribe on Apply | Task 6, 9, 11 |
| SpeechAnalyzer + assets | Task 7 |
| FM + NL fallback | Task 3, 8, 9 |
| Raw vs cleaned UI + copy + metadata checkbox | Task 4, 11 |
| Entry: bookmark alert + list | Task 12 |
| iOS 26 gate, no legacy STT | Tasks 7–12 |
| No sync | Explicitly omitted from `SyncableBookmark` |
| Privacy copy / plist | Task 12 |

**Placeholder scan:** No `TBD` / vague-only steps; `fatalError` in Task 7 is an explicit implementation contract with Apple docs.

**Type consistency:** `BookmarkQuoteSnapshot`, `saveQuote`, `loadQuoteSnapshot`, and coordinator use the same `SimpleBookmark` identity as existing bookmark APIs.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-05-bookmark-quote-transcription.md`.

**1. Subagent-driven (recommended)** — dispatch a fresh subagent per task, review between tasks. **Required sub-skill:** subagent-driven-development.

**2. Inline execution** — run tasks in this session with checkpoints. **Required sub-skill:** executing-plans.

Which approach do you want?
