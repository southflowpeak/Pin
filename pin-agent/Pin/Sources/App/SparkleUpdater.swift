import Sparkle

/// Wrapper for Sparkle auto-update functionality
final class SparkleUpdater {

    private let updaterController: SPUStandardUpdaterController

    init() {
        // Initialize updater controller
        // startingUpdater: true = start checking for updates automatically
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Manually check for updates
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Whether the updater can check for updates
    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }
}
