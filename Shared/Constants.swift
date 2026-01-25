//
//  Constants.swift
//  BookPlayer

import Foundation

public enum Constants {
  public enum UserDefaults {
    // Application information
    public static let completedFirstLaunch = "userSettingsCompletedFirstLaunch"
    public static let appIcon = "userSettingsAppIcon"
    public static let donationMade = "userSettingsDonationMade"
    public static let showPlayer = "userSettingsShowPlayer"
    /// Deprecated
    public static let syncTasksQueue = "userSyncTasksQueue"
    public static let lastSyncTimestamp = "lastSyncTimestamp"
    public static let hasScheduledLibraryContents = "hasScheduledLibraryContents"

    // User preferences
    public static let themeBrightnessEnabled = "userSettingsBrightnessEnabled"
    public static let themeBrightnessThreshold = "userSettingsBrightnessThreshold"
    public static let themeDarkVariantEnabled = "userSettingsThemeDarkVariant"
    public static let systemThemeVariantEnabled = "userSettingsSystemThemeVariant"
    public static let chapterContextEnabled = "userSettingsChapterContext"
    public static let remainingTimeEnabled = "userSettingsRemainingTime"
    public static let smartRewindEnabled = "userSettingsSmartRewind"
    public static let smartRewindMaxInterval = "userSettingsSmartRewindMaxInterval"
    public static let boostVolumeEnabled = "userSettingsBoostVolume"
    public static let globalSpeedEnabled = "userSettingsGlobalSpeed"
    public static let seekProgressBarEnabled = "userSettingsSeekProgressBar"
    public static let autoplayEnabled = "userSettingsAutoplay"
    public static let autoplayRestartEnabled = "userSettingsAutoplayRestart"
    public static let allowCellularData = "userSettingsAllowCellularData"
    public static let iCloudBackupsEnabled = "userSettingsiCloudBackupsEnabled"
    public static let crashReportsDisabled = "userSettingsCrashReportsDisabled"
    public static let skanAttributionDisabled = "userSettingsSKANAttributionDisabled"
    public static let orientationLock = "userSettingsOrientationLock"
    public static let autolockDisabled = "userSettingsDisableAutolock"
    public static let autolockDisabledOnlyWhenPowered = "userSettingsAutolockOnlyWhenPowered"
    public static let playerListPrefersBookmarks = "userSettingsPlayerListPrefersBookmarks"
    public static let storageFilesSortOrder = "userSettingsStorageFilesSortOrder"
    public static let customSleepTimerDuration = "userSettingsCustomSleepTimerDuration"
    public static let autoTimerEnabled = "userSettingsAutoTimerEnabled"
    public static let lastEnabledTimer = "userSettingsLastEnabledTimer"
    public static let repeatEnabledSuffix = "_repeatEnabled"
    public static let isAutomaticBookmarksSectionCollapsed = "userSettingsIsAutomaticBookmarksSectionCollapsed"

    public static let rewindInterval = "userSettingsRewindInterval"
    public static let forwardInterval = "userSettingsForwardInterval"

    public static let updateProgress = "userSettingsUpdateProgress"

    /// Key to store an array of identifiers that need their progress recalculated
    public static let staleProgressIdentifiers = "staleProgressIdentifiers"

    // One-time migrations
    public static let fileProtectionMigration = "userFileProtectionMigration"

    /// Shared widget currently playing relative path
    public static let sharedWidgetNowPlayingPath = "sharedWidgetNowPlayingPath"

    /// Key to store the last played items
    public static let sharedWidgetLastPlayedItems = "sharedWidgetLastPlayedItems"

    /// Key to store the playback records
    public static let sharedWidgetPlaybackRecords = "sharedWidgetPlaybackRecords"

    /// Key to store the current theme
    public static let sharedWidgetTheme = "sharedWidgetTheme"

    /// Jellyfin
    public static let jellyfinLibraryLayout = "jellyfinLibraryLayout"
    public static let jellyfinLibraryLayoutSortBy = "jellyfinLibraryLayoutSortBy"

    /// AudiobookShelf
    public static let audiobookshelfLibraryLayout = "audiobookshelfLibraryLayout"
    public static let audiobookshelfLibraryLayoutSortBy = "audiobookshelfLibraryLayoutSortBy"

    /// Hardcover
    public static let hardcoverAutoMatch = "hardcoverAutoMatch"
    public static let hardcoverAutoAddWantToRead = "hardcoverAutoAddWantToRead"
    public static let hardcoverReadingThreshold = "hardcoverReadingThreshold"

    /// Speed controls
    public static let quickSpeedFirstPreference = "quickSpeedFirstPreference"
    public static let quickSpeedSecondPreference = "quickSpeedSecondPreference"
    public static let quickSpeedThirdPreference = "quickSpeedThirdPreference"

    /// Transcript engine: "apple" (default) or "parakeet". Parakeet requires iOS 17+.
    public static let transcriptEngine = "userSettingsTranscriptEngine"
    /// Parakeet model version: "v2" or "v3". Used when transcript engine is Parakeet.
    public static let parakeetModelVersion = "userSettingsParakeetModelVersion"
    /// Set to true when Parakeet ASR model V2 has been successfully downloaded and loaded at least once.
    public static let parakeetModelDownloadedV2 = "userSettingsParakeetModelDownloadedV2"
    /// Set to true when Parakeet ASR model V3 has been successfully downloaded and loaded at least once.
    public static let parakeetModelDownloadedV3 = "userSettingsParakeetModelDownloadedV3"
    /// Deprecated: use parakeetModelDownloadedV2 / parakeetModelDownloadedV3.
    public static let parakeetModelDownloaded = "userSettingsParakeetModelDownloaded"
  }

  public enum SmartRewind {
    public static let threshold: TimeInterval = 60 * 60 // 60 minutes
    public static let minRewind: TimeInterval = 2
  }

  public enum BookmarkTranscript {
    public static let defaultStartOffset: TimeInterval = 3
    public static let defaultEndOffset: TimeInterval = 10
    public static let adjustmentStep: TimeInterval = 2
    public static let minOffset: TimeInterval = 0
    public static let maxOffset: TimeInterval = 30
    /// Apple's Speech framework allows up to one minute of audio per request. Segments longer than this are clamped.
    public static let maxSegmentDuration: TimeInterval = 60
  }

  public enum Volume {
    public static let normal: Float = 1.0
    public static let boosted: Float = 2.0
  }

  public static let UserActivityPlayback = Bundle.main.bundleIdentifier! + ".activity.playback"
  public static let ApplicationGroupIdentifier = "group.\(Bundle.main.configurationString(for: .bundleIdentifier)).files"

  public enum Widgets: String {
    case sharedNowPlayingWidget = "com.bookplayer.shared.widget"
    case sharedIconWidget = "com.bookplayer.shared.icon.widget"
    case lastPlayedWidget = "com.bookplayer.widget.small.lastPlayed"
    case timeListenedWidget = "com.bookplayer.widget.small.timeListened"
  }
}
