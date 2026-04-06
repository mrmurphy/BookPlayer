# Design: Bookmark quote transcription (on-device)

**Status:** Approved for implementation planning  
**Date:** 2026-04-05  
**Scope:** User bookmarks only; local storage v1; iOS 26+ / macOS Tahoe+ (and equivalent BookPlayer targets).

## Summary

When the user creates a **user** bookmark, BookPlayer asynchronously captures an audio window around the bookmark time, transcribes it with **SpeechAnalyzer** / **SpeechTranscriber**, then produces a **cleaned, copy-ready quote** using **Foundation Models** when available, or **NaturalLanguage** heuristics when not. The user can tune **seconds before** and **seconds after** the bookmark, **re-run** transcription on the new window, optionally view **raw** vs **cleaned** text, **copy** the result, and optionally **include metadata** (title, author, formatted timestamp) in the copied snippet.

## Goals

- Beautiful, easy **quote** from audio: sensible defaults, minimal friction, trustworthy tuning.
- **Privacy:** processing stays on-device; no user API keys; no new server payloads for quotes in v1.
- **Honest degradation:** transcription when speech assets allow; polish step scales with **Apple Intelligence** / Foundation Models availability.

## Non-goals (v1)

- Syncing quote text or window settings via existing bookmark sync (`SyncableBookmark` remains `key`, `time`, `note` only).
- watchOS parity (unless explicitly added later).
- Legacy OS fallback (`SFSpeechRecognizer`) or pre–iOS 26 / pre–Tahoe support for this feature.

## Platform and availability

- **Minimum OS:** iOS 26, macOS Tahoe (and align any other shipped targets with the same capability gates).
- **Compile-time / runtime:** Gate all UI and services with `#available` (and equivalent checks for Foundation Models and Speech stack). On unsupported OS, the feature is **absent** (no nag screen required beyond standard app deployment minimums).
- **Speech:** **SpeechAnalyzer**, **SpeechTranscriber**, **AssetInventory** — show preparation/download state when assets are not ready; support retry after assets arrive.
- **Cleanup:** **Foundation Models** when the on-device model session is available (user has Apple Intelligence–eligible setup as required by the framework). Otherwise **NaturalLanguage** (`NLTagger` / tokenization) only: trim leading/trailing fragments, normalize whitespace, add leading/trailing `…` where the excerpt is clearly cut.
- **Degraded mode (approved):** If transcription succeeds, **always** persist and show **raw** text. **Cleaned** text always exists: either FM-polished or heuristic. Optional subtle copy when heuristics only (e.g. “Polish limited without Apple Intelligence”) — product decision during implementation.

## Architecture

### High-level pipeline

1. **Trigger:** User bookmark created (`BookmarkType.user`) at time `t` (existing `LibraryService` / `PlayerViewModel` flow).
2. **Resolve audio:** Map `relativePath` (and chapter offset if applicable) to a readable audio source; compute absolute window `[max(0, t − N), t + Y]` clamped to item duration.
3. **Extract segment:** Decode/mux to the format required by **SpeechTranscriber** (per Apple documentation for iOS 26).
4. **Transcribe:** Run analyzer; collect **raw** transcript string (and **timestamps** if the API exposes segment timings in v1 — optional enhancement for future trimming UX).
5. **Clean:**  
   - **Primary:** Foundation Models guided generation (e.g. `@Generable` output: cleaned quote string, boolean or enum for leading/trailing ellipsis intent) with a strict system/user prompt: quotable excerpt only, no commentary, preserve meaning.  
   - **Fallback:** Heuristic cleanup with NaturalLanguage only.
6. **Persist:** Save raw, cleaned, `N`, `Y`, and last-success timestamp on the bookmark record (see Data model).
7. **UI:** Dedicated quote surface (sheet or navigation from bookmark row) with controls in § UX.

### Window changes (approved: re-transcribe)

When the user changes **N** or **Y**, **re-extract** audio and **re-run** transcription, then re-run cleanup. **Do not** rely on text-only cropping as the primary behavior.

**Apply pattern:** Use an explicit **“Update quote”** / **“Apply”** action (or equivalent) after adjusting N/Y so **SpeechTranscriber** is not invoked on every slider tick. Optional debounce for advanced users can be a later enhancement.

### Services (conceptual modules)

- **`BookmarkQuoteCoordinator` (or similar):** Owns the async job queue per bookmark (cancel/replace if user hits Apply twice quickly).
- **`BookmarkAudioSegmentExtractor`:** Given library item + time range → audio buffer/file for Speech API.
- **`BookmarkSpeechTranscriber`:** Asset readiness + SpeechAnalyzer session + raw string out.
- **`BookmarkQuoteCleaner`:** Foundation Models path + NaturalLanguage fallback; single protocol returning cleaned string + metadata about which path ran (for optional UI hint).
- **`BookmarkQuoteMetadataFormatter`:** Builds optional clipboard prefix/suffix (title, author, timestamp).

Keep boundaries testable: heuristics and clipboard formatting are pure Swift and unit-test friendly; speech/FM integration covered by manual / integration checks where automation is impractical.

## Data model (approved: 1a local-only)

Add a **new Core Data model version** (follow existing `Audiobook Player N.xcdatamodel` pattern). Extend **`Bookmark`** with **optional** attributes (names illustrative; align with project naming conventions):

| Attribute | Type | Purpose |
|-----------|------|---------|
| `quoteRawText` | String? | Full raw transcription for current window |
| `quoteCleanedText` | String? | FM- or heuristic-cleaned quote |
| `quoteSecondsBefore` | Double? | Last successfully applied **N** |
| `quoteSecondsAfter` | Double? | Last successfully applied **Y** |
| `quoteLastUpdatedAt` | Date? | Last successful end-to-end generation |

**User** bookmarks only need these populated; other bookmark types ignore them.

**Lightweight model:** Extend **`SimpleBookmark`** (and any fetch property lists) only if the bookmarks UI lists quote state (e.g. “Quote ready” indicator); otherwise load quote fields lazily when opening the quote UI.

**Sync:** Do **not** extend `SyncableBookmark` or server APIs in v1. Other devices will not see quote text until a future sync design.

## Settings

- **Defaults:** Global defaults for **seconds before** and **seconds after** (initial recommendation: **20 s** before, **30 s** after — tune during UX review).
- Persist in existing app settings mechanism (UserDefaults / theme-style storage as appropriate to BookPlayer).
- When opening the quote UI, initialize N/Y from bookmark-stored values if present, else from settings defaults.

## UX (approved: 3a)

- **Entry:** From bookmark success flow and/or bookmarks list — action **“Quote”** / **“Copy quote…”** opening a sheet or detail screen.
- **Controls:**  
  - **Seconds before bookmark** and **seconds after bookmark:** steppers (±1 s), optional sliders, **min 5 s / max 180 s** per side (caps CPU and UI sensibility; adjust only if real content proves insufficient).  
  - Optional **±5 s** chips for quick adjustment.  
  - Primary button **“Update quote”** applying new N/Y and running the pipeline.  
- **Preview:** Large readable **cleaned** text as primary; toggle **“Show raw transcription”** reveals raw (secondary style, scrollable).  
- **States:** Loading (transcribing / cleaning), asset download, error (missing file, unreadable audio, transcription failure), empty.  
- **Copy:** Prominent **Copy** button — copies **cleaned** text by default.  
- **Checkbox:** **“Include book details in copied text”** — when checked, prepend or append a short block: **title**, **author** (from `LibraryItem` / metadata when available), **timestamp** (formatted bookmark time). Use stable, human-readable formatting (plain text).

## Error handling

- **Missing or unreadable file:** Clear message; no crash; allow dismiss.  
- **Speech assets not ready:** Progress or explanatory text; retry when appropriate.  
- **Transcription failure:** Show error; raw/cleaned may remain from previous successful run if any.  
- **Foundation Models unavailable:** Run heuristics only; do not block raw display.

## Testing

- **Unit:** Heuristic cleaner (inputs with partial sentences → expected trimming and ellipses); metadata formatter strings.  
- **UI:** Smoke tests for sheet open, toggle raw, copy button (where test infrastructure allows).  
- **Manual:** Real audiobook samples, FM on vs off, asset download interrupted, very short chapter boundaries.

## Security and privacy

- No quote text leaves the device in v1.  
- Document in release notes / optional in-app copy that speech and on-device models process audio/text locally, subject to Apple’s system behavior.

## Open implementation choices (minor)

- Fine-tuning **default** N/Y (spec suggests 20 / 30 s) after dogfooding.  
- Whether to show a **quote indicator** on bookmark rows when `quoteCleanedText != nil`.  
- Exact **Foundation Models** prompt and `@Generable` schema (must be reviewed against Apple guidelines).

## Approval

Chosen options: **1a** (local-only storage), **2a** (re-transcribe on window change with explicit apply), **3a** (range controls + raw toggle + copy + metadata checkbox), OS **A** (no legacy fallback), degradation **B** (raw + heuristic cleanup when FM unavailable).

**Approved:** design choices confirmed in conversation with Murphy Randle, 2026-04-05.
