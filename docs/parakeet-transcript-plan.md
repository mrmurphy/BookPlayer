# Plan: Parakeet (FluidAudio) as optional transcript engine

## Goal
Add NVIDIA Parakeet via FluidAudio as a user-selectable alternative to Apple Speech for bookmark transcript generation.

## Framework
- **FluidAudio** (FluidInference): Swift SDK, Apache 2.0, Parakeet TDT CoreML on ANE
- SPM: `https://github.com/FluidInference/FluidAudio.git` from `0.7.9`
- Product: `FluidAudio` only (no TTS → no GPL)
- Requirements: iOS 17+, Apple Silicon recommended; models auto-download from Hugging Face

## Implementation plan

### 1. Add dependency and deployment
- [ ] Add FluidAudio package to the Xcode project (or to BookPlayerKit if transcription stays there).
- [ ] Ensure deployment target is iOS 17+ where Parakeet will be used (or gate the option on OS).
- [ ] Add FluidAudio product to the app target that runs bookmark transcription.

### 2. Transcription engine abstraction
- [ ] Define a protocol, e.g. `BookmarkTranscriptEngine`, with something like:
  - `func transcribe(audioSegmentURL: URL) async throws -> String`
- [ ] Implement **AppleSpeechTranscriptEngine**: wrap current logic (export → `SFSpeechURLRecognitionRequest`, partial-result handling, 60s cap). Keep all existing behavior here.
- [ ] Implement **ParakeetTranscriptEngine** (FluidAudio):
  - Lazy init: `AsrModels.downloadAndLoad(version: .v3)` (or `.v2` for English-only), then `AsrManager(config: .default)`, `asrManager.initialize(models:)`.
  - For each segment: take the already-exported temp file (M4A); if FluidAudio accepts file URL, use it; otherwise load and convert to 16 kHz mono Float32 and call `asrManager.transcribe(samples)`.
- [ ] Reuse existing segment export and `makeSegment` (and 60s cap) so both engines get the same segment.

### 3. Wire engine selection into BookmarkTranscriptionService
- [ ] Inject the chosen engine (or a “router” that picks Apple vs Parakeet) into `BookmarkTranscriptionService` (or equivalent holder of transcript logic).
- [ ] `BookmarkTranscriptionService` calls `engine.transcribe(segmentURL)` (or passes samples if the abstraction uses samples) instead of calling Apple Speech directly.
- [ ] Keep existing behavior when “Apple Speech” is selected.

### 4. Settings and persistence
- [ ] Add a setting: “Transcript engine” (or “Voice-to-text engine”) with options: **Apple Speech** (default), **Parakeet**.
- [ ] Persist choice (e.g. UserDefaults key under `Constants` or existing settings).
- [ ] Where the service is created (e.g. AppDelegate / DI), resolve the chosen engine from this setting and pass it in.

### 5. Audio format for Parakeet
- [ ] Confirm FluidAudio’s ASR input: file URL vs buffer vs 16 kHz mono Float32.
- [ ] If 16 kHz mono required: add a small helper to load M4A (or the exported segment), resample to 16 kHz mono Float32, and pass into `transcribe(samples)`; else use file-based API if available.
- [ ] Ensure temp file lifecycle (create/delete) stays correct for both engines.

### 6. Model download and UX
- [ ] On first use of Parakeet: run `AsrModels.downloadAndLoad(...)` and show a brief “Preparing…” or progress if needed; handle errors (network, disk).
- [ ] Optional: “Download Parakeet models” in Settings (e.g. on Wi‑Fi) so the first transcript doesn’t block on a large download.

### 7. Testing and fallback
- [ ] When Parakeet is selected and init or transcribe fails, fall back to Apple Speech for that run (optional), and/or show “Transcript unavailable” consistent with current behavior.
- [ ] Manual test: both engines produce transcripts for the same bookmark; compare quality and speed.

## Out of scope for this plan
- Watch app or other targets: only add Parakeet to the main iOS app transcript flow unless we explicitly extend later.
- Changing segment length or UX for “Quote range” beyond what’s already done.
- New localization strings are implied by the new setting; exact keys to add when implementing.

## Order of work
1. Dependency + deployment (1)  
2. Engine abstraction and Apple implementation (2, 3 — extract current logic into Apple engine)  
3. Parakeet engine + audio format (2, 5)  
4. Service wiring and setting (3, 4)  
5. Model download UX and fallback (6, 7)
