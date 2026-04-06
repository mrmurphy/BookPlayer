//
//  BookmarkQuoteDefaultsSettingsView.swift
//  BookPlayer
//

import BookPlayerKit
import SwiftUI

struct BookmarkQuoteDefaultsSettingsView: View {
  @EnvironmentObject var theme: ThemeViewModel

  @AppStorage(Constants.UserDefaults.bookmarkQuoteSecondsBeforeDefault) private var secondsBefore = 20
  @AppStorage(Constants.UserDefaults.bookmarkQuoteSecondsAfterDefault) private var secondsAfter = 30

  private let range = 5...180

  var body: some View {
    Form {
      ThemedSection {
        Stepper(value: $secondsBefore, in: range, step: 5) {
          Text(
            String(
              format: "settings_bookmark_quote_seconds_before_format".localized,
              secondsBefore
            )
          )
          .foregroundStyle(theme.primaryColor)
        }

        Stepper(value: $secondsAfter, in: range, step: 5) {
          Text(
            String(
              format: "settings_bookmark_quote_seconds_after_format".localized,
              secondsAfter
            )
          )
          .foregroundStyle(theme.primaryColor)
        }
      } footer: {
        Text("settings_bookmark_quote_footer".localized)
          .foregroundStyle(theme.secondaryColor)
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.systemBackgroundColor)
    .navigationTitle("settings_bookmark_quote_title".localized)
    .navigationBarTitleDisplayMode(.inline)
  }
}
