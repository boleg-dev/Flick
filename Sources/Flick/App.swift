import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

@main
enum FlickMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = AppDelegate.shared
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let shared = AppDelegate()

    private let permissions = PermissionModel()
    private let session = SwitchingSession(presentation: SwitcherOverlay())
    private lazy var hotkeys = HotkeyMonitor { [weak self] in self?.session.handle($0) ?? false }
    private var statusItem: NSStatusItem?
    private var iconHasAccessibility: Bool?
    private var welcome: NSWindow?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "Flick"
        item.isVisible = true
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.title = ""
        }

        refreshPermissions()
        let needsWelcome = !permissions.accessibility || !UserDefaults.standard.bool(forKey: Keys.seenWelcome)
        if needsWelcome {
            showWelcome()
            UserDefaults.standard.set(true, forKey: Keys.seenWelcome)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.refreshPermissions()
            if !self.statusItemIsOnMenuBar() {
                self.showWelcome()
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshPermissions()
        menu.removeAllItems()

        let title = NSMenuItem(title: "Flick", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let shortcut = NSMenuItem(title: "⌥⇥  windows      ⌥`  this app", action: nil, keyEquivalent: "")
        shortcut.isEnabled = false
        menu.addItem(shortcut)

        if permissions.altTabRunning {
            let clash = NSMenuItem(title: "AltTab is also running", action: nil, keyEquivalent: "")
            clash.isEnabled = false
            menu.addItem(clash)
        }

        menu.addItem(.separator())

        let show = NSMenuItem(title: "Show Windows", action: #selector(showWindows), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        let aboutTitle = permissions.accessibility && permissions.screenRecording ? "About Flick" : "Setup…"
        let about = NSMenuItem(title: aboutTitle, action: #selector(showWelcomeAction), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Flick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func showWindows() {
        session.openFromMenu()
    }

    @objc private func showWelcomeAction() {
        showWelcome()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Couldn’t set Open at Login"
            alert.informativeText = "Move Flick into the Applications folder, then try again.\n\n\(error.localizedDescription)"
            alert.runModal()
        }
    }

    private func showWelcome() {
        let root = WelcomeView(
            model: permissions,
            onAccessibility: { SystemSettings.revealAccessibility() },
            onScreenRecording: { SystemSettings.revealScreenRecording() },
            onPreview: { [weak self] in self?.session.openFromMenu() }
        )
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = .preferredContentSize

        let window: NSWindow
        if let welcome {
            window = welcome
            window.contentViewController = hosting
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Flick"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.contentViewController = hosting
            welcome = window
        }

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            let fit = hosting.view.fittingSize
            if fit.height > 120 {
                window.setContentSize(NSSize(width: 440, height: fit.height))
                window.center()
            }
        }
    }

    private func refreshPermissions() {
        permissions.accessibility = AXIsProcessTrusted()
        permissions.screenRecording = CGPreflightScreenCaptureAccess()
        permissions.altTabRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.lwouis.alt-tab-macos"
        }
        if permissions.accessibility {
            hotkeys.start()
        }
        permissions.shortcutReady = hotkeys.isInstalled
        updateStatusIcon()
    }

    private func statusItemIsOnMenuBar() -> Bool {
        guard let window = statusItem?.button?.window else { return false }
        let frame = window.frame
        guard frame.width > 2, frame.height > 2 else { return false }
        return NSScreen.screens.contains { screen in
            let menuHeight = screen.frame.maxY - screen.visibleFrame.maxY
            guard menuHeight > 0 else { return false }
            let menuBar = NSRect(
                x: screen.frame.minX,
                y: screen.visibleFrame.maxY,
                width: screen.frame.width,
                height: menuHeight
            )
            return menuBar.intersects(frame)
        }
    }

    private func updateStatusIcon() {
        guard iconHasAccessibility != permissions.accessibility else { return }
        iconHasAccessibility = permissions.accessibility
        let symbol = permissions.accessibility ? "square.on.square" : "exclamationmark.square"
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: "Flick")
        let image = base?.withSymbolConfiguration(.init(pointSize: 13, weight: .medium)) ?? base
        image?.isTemplate = true
        guard let button = statusItem?.button else { return }
        button.image = image
        button.title = ""
        button.imagePosition = .imageOnly
        button.toolTip = "Hold ⌥ and press Tab"
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Flick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }
}

enum SystemSettings {
    static func revealAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        open([
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ])
    }

    static func revealScreenRecording() {
        CGRequestScreenCaptureAccess()
        open([
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
        ])
    }

    private static func open(_ candidates: [String]) {
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }
}

private enum Keys {
    static let seenWelcome = "flick.seenWelcome"
}
