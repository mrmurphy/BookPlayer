//
//  SettingsTranscriptView.swift
//  BookPlayer
//
//  Dedicated transcript settings: engine choice, Parakeet model version, and cache reset.
//

import BookPlayerKit
import SwiftUI

struct SettingsTranscriptView: View {
  @EnvironmentObject var theme: ThemeViewModel
  let transcriptStore: PlaybackTranscriptStore?

  var body: some View {
    Form {
      TranscriptEngineSectionView()
      if transcriptStore != nil {
        Section {
          Button(role: .destructive, action: {
            transcriptStore?.resetCache()
          }) {
            Text(NSLocalizedString("settings_transcript_reset_cache", comment: ""))
          }
        } footer: {
          Text(NSLocalizedString("settings_transcript_reset_cache_footer", comment: ""))
            .foregroundStyle(theme.secondaryColor)
        }
      }
    }
    .environmentObject(theme)
    .defaultFormBackground()
    .background(theme.systemGroupedBackgroundColor)
    .navigationTitle("settings_transcript_title")
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationStack {
    SettingsTranscriptView(transcriptStore: nil)
      .environmentObject(ThemeViewModel())
  }
}
