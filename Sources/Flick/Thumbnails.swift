import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ThumbnailService {
    struct Shot {
        let titles: [CGWindowID: String]
        let image: (CGWindowID, CGImage)?
    }

    static func capture(ids: [CGWindowID]) -> AsyncStream<Shot> {
        AsyncStream { continuation in
            let task = Task {
                guard CGPreflightScreenCaptureAccess(), !ids.isEmpty else {
                    continuation.finish()
                    return
                }
                let content: SCShareableContent
                do {
                    content = try await shareableContent()
                } catch {
                    fputs("Flick previews: \(error)\n", stderr)
                    continuation.finish()
                    return
                }

                var titles: [CGWindowID: String] = [:]
                var windows: [CGWindowID: SCWindow] = [:]
                for window in content.windows {
                    windows[window.windowID] = window
                    if let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                        titles[window.windowID] = title
                    }
                }
                if !titles.isEmpty {
                    continuation.yield(Shot(titles: titles, image: nil))
                }

                for id in ids {
                    if Task.isCancelled { break }
                    guard let window = windows[id] else { continue }
                    if let image = await image(for: window) {
                        continuation.yield(Shot(titles: [:], image: (id, image)))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    }

    private static func image(for window: SCWindow) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = 520
        config.height = 340
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
