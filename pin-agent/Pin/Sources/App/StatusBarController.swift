import AppKit

/// Manages the menu bar status item for the Agent application
@MainActor
final class StatusBarController {

    private var statusItem: NSStatusItem?
    private weak var stateMachine: AgentStateMachine?
    private var sparkleUpdater: SparkleUpdater?

    init(stateMachine: AgentStateMachine, sparkleUpdater: SparkleUpdater?) {
        self.stateMachine = stateMachine
        self.sparkleUpdater = sparkleUpdater
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pin")
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateMenu()
    }

    @objc private func statusItemClicked() {
        updateMenu()
    }

    private func updateMenu() {
        let menu = NSMenu()

        // Status section
        let status = stateMachine?.getStatus()
        let isPinned = status?.pinned ?? false

        if isPinned {
            let statusItem = NSMenuItem(title: "📌 Pinned: \(status?.targetAppName ?? "Unknown")", action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)

            if let title = status?.targetWindowTitle {
                let titleItem = NSMenuItem(title: "   \(title)", action: nil, keyEquivalent: "")
                titleItem.isEnabled = false
                menu.addItem(titleItem)
            }

            menu.addItem(NSMenuItem.separator())

            let unpinItem = NSMenuItem(title: "Unpin", action: #selector(unpinWindow), keyEquivalent: "u")
            unpinItem.target = self
            menu.addItem(unpinItem)
        } else {
            // Window selection submenu (ピンされていない場合のみ表示)
            let windowsMenu = NSMenu()
            let windowsItem = NSMenuItem(title: "Pin Window...", action: nil, keyEquivalent: "")
            windowsItem.submenu = windowsMenu

            // Get available windows
            if let windows = getAvailableWindows() {
                for window in windows {
                    let title = "\(window.appName): \(window.windowTitle ?? "Untitled")"
                    let item = NSMenuItem(title: title, action: #selector(pinSelectedWindow(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = window
                    windowsMenu.addItem(item)
                }

                if windows.isEmpty {
                    let noWindowsItem = NSMenuItem(title: "(No windows available)", action: nil, keyEquivalent: "")
                    noWindowsItem.isEnabled = false
                    windowsMenu.addItem(noWindowsItem)
                }
            }

            menu.addItem(windowsItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Check for Updates
        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    // MARK: - Actions

    @objc private func pinSelectedWindow(_ sender: NSMenuItem) {
        guard let windowInfo = sender.representedObject as? TargetWindowInfo else { return }

        Task {
            do {
                try await stateMachine?.pinWindow(windowInfo)
                print("Pinned window: \(windowInfo.appName)")
            } catch {
                print("Failed to pin window: \(error)")
                showAlert(title: "Failed to Pin", message: error.localizedDescription)
            }
        }
    }

    @objc private func unpinWindow() {
        stateMachine?.unpin()
        print("Window unpinned")
    }

    @objc private func checkForUpdates() {
        sparkleUpdater?.checkForUpdates()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Helpers

    private func getAvailableWindows() -> [TargetWindowInfo]? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        var windows: [TargetWindowInfo] = []
        var seenPIDs: Set<pid_t> = []

        for windowInfo in windowList {
            guard let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                  let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] else {
                continue
            }

            // Skip our own app
            if pid == ProcessInfo.processInfo.processIdentifier {
                continue
            }

            // Skip windows without reasonable size
            let width = boundsDict["Width"] ?? 0
            let height = boundsDict["Height"] ?? 0
            guard width > 100 && height > 100 else {
                continue
            }

            // Skip if we already have a window from this app (take the first one)
            if seenPIDs.contains(pid) {
                continue
            }
            seenPIDs.insert(pid)

            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: width,
                height: height
            )

            let windowTitle = windowInfo[kCGWindowName as String] as? String

            let info = TargetWindowInfo(
                pid: pid,
                windowID: windowID,
                appName: ownerName,
                windowTitle: windowTitle,
                bounds: bounds
            )
            windows.append(info)
        }

        return windows
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
