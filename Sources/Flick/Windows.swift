import AppKit
import ApplicationServices

struct WindowItem: Identifiable, Equatable {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    var title: String
    let bounds: CGRect
    let bundleURL: URL?

    var icon: NSImage {
        if let bundleURL {
            let image = NSWorkspace.shared.icon(forFile: bundleURL.path)
            image.size = NSSize(width: 128, height: 128)
            return image
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }
}

enum SwitchScope {
    case all
    case currentApp
}

enum WindowLister {
    /// Front to back. Order is the window server's stacking order, which is the
    /// order a switcher should walk: the first Tab lands on the window directly behind.
    static func onScreen() -> [WindowItem] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var items: [WindowItem] = []
        var seen = Set<CGWindowID>()

        for entry in raw {
            guard number(kCGWindowLayer, in: entry) == 0 else { continue }
            guard let pid = pid(in: entry), pid > 0 else { continue }
            guard let running = NSRunningApplication(processIdentifier: pid) else { continue }
            // Menu-bar apps stay out of the list. Flick itself is one, so keep its real windows.
            let isFlick = pid == ownPID
            if !isFlick, running.activationPolicy != .regular { continue }
            guard let bounds = bounds(in: entry),
                  bounds.width >= 100, bounds.height >= 64 else { continue }
            if alpha(in: entry) < 0.05 { continue }

            let id = CGWindowID(number(kCGWindowNumber, in: entry) ?? 0)
            guard id != 0, seen.insert(id).inserted else { continue }

            let appName = string(kCGWindowOwnerName, in: entry)
                ?? running.localizedName
                ?? "App"
            var title = string(kCGWindowName, in: entry) ?? ""
            if isFlick, title.isEmpty { title = "Flick" }
            items.append(WindowItem(
                id: id,
                pid: pid,
                appName: appName,
                title: title,
                bounds: bounds,
                bundleURL: running.bundleURL
            ))
        }
        return items
    }

    /// When the focused app is the first listed window, step off it.
    /// Opening the switcher from a menu leaves Flick in front only when it has no window,
    /// so the first remaining window is already the one to land on.
    static func initialIndex(count: Int, direction: Int, focusedIsFirst: Bool) -> Int {
        guard count > 1, direction != 0, focusedIsFirst else { return 0 }
        return direction > 0 ? 1 : count - 1
    }

    private static func number(_ key: CFString, in entry: [String: Any]) -> Int? {
        let value = entry[key as String]
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    private static func pid(in entry: [String: Any]) -> pid_t? {
        guard let value = number(kCGWindowOwnerPID, in: entry) else { return nil }
        return pid_t(value)
    }

    private static func alpha(in entry: [String: Any]) -> Double {
        let value = entry[kCGWindowAlpha as String]
        if let number = value as? Double { return number }
        if let number = value as? NSNumber { return number.doubleValue }
        return 1
    }

    private static func string(_ key: CFString, in entry: [String: Any]) -> String? {
        guard let value = entry[key as String] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func bounds(in entry: [String: Any]) -> CGRect? {
        guard let dict = entry[kCGWindowBounds as String] as? [String: Any] else { return nil }
        func dim(_ key: String) -> CGFloat? {
            let value = dict[key]
            if let number = value as? CGFloat { return number }
            if let number = value as? NSNumber { return CGFloat(number.doubleValue) }
            return nil
        }
        guard let x = dim("X"), let y = dim("Y"), let width = dim("Width"), let height = dim("Height") else {
            return nil
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

enum WindowPreview {
    /// Grab Flick's own window before the switcher covers it. ScreenCaptureKit often
    /// returns the overlay instead of this window.
    static func image(windowID: CGWindowID) -> NSImage? {
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

enum WindowFocus {
    static func focus(_ window: WindowItem) {
        if window.pid == ProcessInfo.processInfo.processIdentifier {
            focusFlick(window)
            return
        }
        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return }
        if app.isHidden {
            app.unhide()
        }

        let element = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(element, 0.25)
        if let target = match(element, to: window) {
            AXUIElementPerformAction(target, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(element, kAXFocusedWindowAttribute as CFString, target)
        }
        AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate()
    }

    private static func focusFlick(_ window: WindowItem) {
        let number = Int(window.id)
        NSApp.activate(ignoringOtherApps: true)
        guard let match = NSApp.windows.first(where: { $0.windowNumber == number }) else { return }
        match.makeKeyAndOrderFront(nil)
    }

    private static func match(_ app: AXUIElement, to window: WindowItem) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement], !windows.isEmpty else {
            return nil
        }
        if windows.count == 1 {
            return windows[0]
        }

        let wantedTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var best: (AXUIElement, CGFloat)?
        for candidate in windows.prefix(16) {
            let title = axString(candidate, kAXTitleAttribute as CFString)
            if !wantedTitle.isEmpty, title == wantedTitle, let frame = axFrame(candidate) {
                let score = distance(frame, window.bounds) - 50
                if best == nil || score < best!.1 {
                    best = (candidate, score)
                }
                continue
            }
            guard let frame = axFrame(candidate) else { continue }
            let score = distance(frame, window.bounds)
            if best == nil || score < best!.1 {
                best = (candidate, score)
            }
        }
        guard let best, best.1 < 220 else { return nil }
        return best.0
    }

    private static func distance(_ frame: CGRect, _ bounds: CGRect) -> CGFloat {
        let center = hypot(frame.midX - bounds.midX, frame.midY - bounds.midY)
        let size = abs(frame.width - bounds.width) + abs(frame.height - bounds.height)
        return center + size * 0.15
    }

    private static func axString(_ element: AXUIElement, _ attribute: CFString) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return "" }
        return value as? String ?? ""
    }

    private static func axFrame(_ element: AXUIElement) -> CGRect? {
        guard let origin = axPoint(element, kAXPositionAttribute as CFString),
              let size = axSize(element, kAXSizeAttribute as CFString) else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    private static func axPoint(_ element: AXUIElement, _ attribute: CFString) -> CGPoint? {
        guard let value = axRawValue(element, attribute) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private static func axSize(_ element: AXUIElement, _ attribute: CFString) -> CGSize? {
        guard let value = axRawValue(element, attribute) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    private static func axRawValue(_ element: AXUIElement, _ attribute: CFString) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value else {
            return nil
        }
        return (value as! AXValue)
    }
}
