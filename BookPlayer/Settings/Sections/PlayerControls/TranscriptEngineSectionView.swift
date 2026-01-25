//
//  TranscriptEngineSectionView.swift
//  BookPlayer
//
//  Setting to choose transcript/voice-to-text engine: Apple Speech (default) or Parakeet.
//

import BookPlayerKit
import SwiftUI

struct TranscriptEngineSectionView: View {
  @AppStorage(Constants.UserDefaults.transcriptEngine) private var transcriptEngineRaw: String = TranscriptEngineChoice.defaultValue.rawValue
  @AppStorage(Constants.UserDefaults.parakeetModelVersion) private var parakeetModelVersionRaw: String = ParakeetModelVersion.defaultValue.rawValue
  @AppStorage(Constants.UserDefaults.parakeetModelDownloadedV2) private var parakeetModelDownloadedV2: Bool = false
  @AppStorage(Constants.UserDefaults.parakeetModelDownloadedV3) private var parakeetModelDownloadedV3: Bool = false
  @AppStorage(Constants.UserDefaults.parakeetModelDownloaded) private var parakeetModelDownloadedLegacy: Bool = false
  @EnvironmentObject var theme: ThemeViewModel
  @State private var downloadingVersion: ParakeetModelVersion?

  private var selectedChoice: TranscriptEngineChoice {
    TranscriptEngineChoice(rawValue: transcriptEngineRaw) ?? .defaultValue
  }

  private var selectedParakeetVersion: ParakeetModelVersion {
    ParakeetModelVersion(rawValue: parakeetModelVersionRaw) ?? .defaultValue
  }

  private func selectionBinding(_ storage: Binding<String>) -> Binding<TranscriptEngineChoice> {
    Binding(
      get: { TranscriptEngineChoice(rawValue: storage.wrappedValue) ?? .defaultValue },
      set: { storage.wrappedValue = $0.rawValue }
    )
  }

  private func parakeetVersionBinding(_ storage: Binding<String>) -> Binding<ParakeetModelVersion> {
    Binding(
      get: { ParakeetModelVersion(rawValue: storage.wrappedValue) ?? .defaultValue },
      set: { storage.wrappedValue = $0.rawValue }
    )
  }

  private func isDownloaded(_ version: ParakeetModelVersion) -> Bool {
    switch version {
    case .v2: return parakeetModelDownloadedV2
    case .v3: return parakeetModelDownloadedV3 || parakeetModelDownloadedLegacy
    }
  }

  private func sizeString(for version: ParakeetModelVersion) -> String {
    switch version {
    case .v2: return NSLocalizedString("settings_transcript_parakeet_size_v2", comment: "")
    case .v3: return NSLocalizedString("settings_transcript_parakeet_size_v3", comment: "")
    }
  }

  private func versionLabel(for version: ParakeetModelVersion) -> String {
    switch version {
    case .v2: return NSLocalizedString("settings_transcript_parakeet_version_v2", comment: "")
    case .v3: return NSLocalizedString("settings_transcript_parakeet_version_v3", comment: "")
    }
  }

  var body: some View {
    Section {
      Picker(NSLocalizedString("settings_transcript_engine_title", comment: ""), selection: selectionBinding($transcriptEngineRaw)) {
        Text(NSLocalizedString("settings_transcript_engine_apple", comment: "")).tag(TranscriptEngineChoice.apple)
        if TranscriptEngineChoice.parakeet.isAvailable {
          Text(NSLocalizedString("settings_transcript_engine_parakeet", comment: "")).tag(TranscriptEngineChoice.parakeet)
        }
      }
      .pickerStyle(.menu)

      if TranscriptEngineChoice.parakeet.isAvailable, selectedChoice == .parakeet {
        Picker(NSLocalizedString("settings_transcript_parakeet_version_label", comment: ""), selection: parakeetVersionBinding($parakeetModelVersionRaw)) {
          ForEach(ParakeetModelVersion.allCases, id: \.rawValue) { v in
            Text("\(versionLabel(for: v)) (\(sizeString(for: v)))")
              .tag(v)
          }
        }
        .pickerStyle(.menu)

        ForEach(ParakeetModelVersion.allCases, id: \.rawValue) { version in
          HStack {
            Text(versionLabel(for: version))
            Text(sizeString(for: version))
              .foregroundStyle(theme.secondaryColor)
            Spacer()
            if downloadingVersion == version {
              ProgressView()
                .scaleEffect(0.9)
              Text(NSLocalizedString("settings_transcript_parakeet_model_downloading", comment: ""))
                .foregroundStyle(theme.secondaryColor)
            } else if isDownloaded(version) {
              Text(NSLocalizedString("settings_transcript_parakeet_model_ready", comment: ""))
                .foregroundStyle(theme.secondaryColor)
            } else {
              Text(NSLocalizedString("settings_transcript_parakeet_model_not_downloaded", comment: ""))
                .foregroundStyle(theme.secondaryColor)
              Button(NSLocalizedString("settings_transcript_parakeet_download_button", comment: "")) {
                downloadParakeetModel(version: version)
              }
            }
          }
        }
      }
    } footer: {
      Text(NSLocalizedString("settings_transcript_engine_footer", comment: ""))
        .foregroundStyle(theme.secondaryColor)
    }
  }

  private func downloadParakeetModel(version: ParakeetModelVersion) {
    guard downloadingVersion == nil else { return }
    downloadingVersion = version
    Task {
      if #available(iOS 17.0, *) {
        await ParakeetTranscriptEngine.ensureModelDownloaded(version: version)
      }
      await MainActor.run {
        downloadingVersion = nil
      }
    }
  }
}

#Preview {
  Form {
    TranscriptEngineSectionView()
  }
  .environmentObject(ThemeViewModel())
}
