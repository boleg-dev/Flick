import AppKit
import CoreGraphics
import ScreenCaptureKit

final class WindowPreviews {
    enum Update {
        case titles([CGWindowID: String])
        case image(CGWindowID, NSImage)
    }

    private let ownPID: pid_t
    private let captureOwn: (CGWindowID) -> NSImage?
    private let capture: ([CGWindowID]) -> AsyncStream<Update>
    private var task: Task<Void, Never>?
    private var generation = 0
    private var cache: [CGWindowID: NSImage] = [:]

    init(
        ownPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        captureOwn: @escaping (CGWindowID) -> NSImage? = WindowPreview.image,
        capture: @escaping ([CGWindowID]) -> AsyncStream<Update> = ThumbnailCapture.capture
    ) {
        self.ownPID = ownPID
        self.captureOwn = captureOwn
        self.capture = capture
    }

    // Call before showing the overlay so Flick's own windows remain unobscured.
    func start(items: [WindowItem], selection: Int, onUpdate: @escaping (Update) -> Void) {
        cancel()
        let generation = self.generation
        let ids = Set(items.map(\.id))
        for item in items {
            if item.pid == ownPID, let image = captureOwn(item.id) { store(image, for: item.id) }
            if let image = cache[item.id] { onUpdate(.image(item.id, image)) }
        }
        let ordered = items.indices.contains(selection)
            ? Array(items[selection...]) + Array(items[..<selection]) : items
        let external = ordered.filter { $0.pid != ownPID }.map(\.id)
        guard !external.isEmpty else { return }
        let stream = capture(external)
        task = Task { @MainActor [weak self] in
            for await update in stream {
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                switch update {
                case .titles(let titles):
                    let relevant = titles.filter { ids.contains($0.key) }
                    if !relevant.isEmpty { onUpdate(.titles(relevant)) }
                case .image(let id, let image):
                    guard ids.contains(id) else { continue }
                    self.store(image, for: id)
                    onUpdate(.image(id, image))
                }
            }
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }

    private func store(_ image: NSImage, for id: CGWindowID) {
        if cache.count >= 48, cache[id] == nil { cache.removeAll() }
        cache[id] = image
    }
}

private enum ThumbnailCapture {
    static func capture(ids: [CGWindowID]) -> AsyncStream<WindowPreviews.Update> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                guard !Task.isCancelled, !ids.isEmpty, CGPreflightScreenCaptureAccess() else {
                    continuation.finish()
                    return
                }
                let content: SCShareableContent
                do {
                    content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                } catch {
                    fputs("Flick previews: \(error)\n", stderr)
                    continuation.finish()
                    return
                }

                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }
                let requested = Set(ids)
                var titles: [CGWindowID: String] = [:]
                var windows: [CGWindowID: SCWindow] = [:]
                for window in content.windows where requested.contains(window.windowID) {
                    windows[window.windowID] = window
                    if let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                        titles[window.windowID] = title
                    }
                }
                if !titles.isEmpty {
                    continuation.yield(.titles(titles))
                }

                for id in ids {
                    if Task.isCancelled { break }
                    guard let window = windows[id] else { continue }
                    if let image = await image(for: window), !Task.isCancelled {
                        continuation.yield(.image(id, NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func image(for window: SCWindow) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = min(520 / max(1, window.frame.width), 340 / max(1, window.frame.height))
        config.width = max(1, Int((window.frame.width * scale).rounded()))
        config.height = max(1, Int((window.frame.height * scale).rounded()))
        config.scalesToFit = true
        config.showsCursor = false
        let windowID = window.windowID
        return await withCheckedContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, error in
                if image == nil, let error {
                    fputs("Flick preview \(windowID): \(error)\n", stderr)
                }
                continuation.resume(returning: image)
            }
        }
    }
}

private enum WindowPreview {
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
