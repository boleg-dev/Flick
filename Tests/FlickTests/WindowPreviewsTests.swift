import AppKit
import XCTest
@testable import Flick

final class WindowPreviewsTests: XCTestCase {
    @MainActor
    func testOwnWindowIsCapturedSynchronouslyAndOthersStartAtSelection() async {
        let ownImage = NSImage(size: NSSize(width: 10, height: 10))
        var ownIDs: [CGWindowID] = []
        var externalIDs: [CGWindowID] = []
        var images: [CGWindowID] = []
        let previews = WindowPreviews(ownPID: 10, captureOwn: {
            ownIDs.append($0)
            return ownImage
        }, capture: {
            externalIDs = $0
            return AsyncStream { $0.finish() }
        })
        previews.start(items: [window(1, pid: 20), window(2, pid: 10), window(3, pid: 30)], selection: 2) {
            if case .image(let id, _) = $0 { images.append(id) }
        }
        XCTAssertEqual(ownIDs, [2])
        XCTAssertEqual(images, [2])
        XCTAssertEqual(externalIDs, [3, 1])
        previews.cancel()
    }

    @MainActor
    func testTitlesAreFilteredAndImagesAreReusedOnNextSession() async {
        let delivered = expectation(description: "image delivered")
        var continuation: AsyncStream<WindowPreviews.Update>.Continuation!
        var titles: [CGWindowID: String] = [:]
        let image = NSImage(size: NSSize(width: 10, height: 10))
        let previews = WindowPreviews(ownPID: 99, captureOwn: { _ in nil }, capture: { _ in
            AsyncStream { continuation = $0 }
        })
        previews.start(items: [window(1, pid: 20)], selection: 0) {
            switch $0 {
            case .titles(let result): titles = result
            case .image: delivered.fulfill()
            }
        }
        continuation.yield(.titles([1: "Title", 2: "Unrelated"]))
        continuation.yield(.image(1, image))
        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(titles, [1: "Title"])
        previews.cancel()
        var cached: NSImage?
        previews.start(items: [window(1, pid: 20)], selection: 0) {
            if case .image(_, let result) = $0 { cached = result }
        }
        XCTAssertTrue(cached === image)
        previews.cancel()
    }

    @MainActor
    func testCancelledCaptureCannotDeliverIntoReopenedSession() async {
        let stale = expectation(description: "old session receives no updates")
        stale.isInverted = true
        let current = expectation(description: "new session receives its image")
        var streams: [AsyncStream<WindowPreviews.Update>.Continuation] = []
        let previews = WindowPreviews(ownPID: 99, captureOwn: { _ in nil }, capture: { _ in
            AsyncStream { streams.append($0) }
        })
        let image = NSImage(size: NSSize(width: 10, height: 10))
        previews.start(items: [window(1, pid: 20)], selection: 0) { _ in stale.fulfill() }
        streams[0].yield(.image(1, image))
        previews.start(items: [window(2, pid: 20)], selection: 0) { update in
            if case .image(let id, _) = update {
                XCTAssertEqual(id, 2)
                current.fulfill()
            }
        }
        streams[0].yield(.image(1, image))
        streams[1].yield(.image(2, image))
        await fulfillment(of: [current, stale], timeout: 0.1)
        previews.cancel()
    }

    @MainActor
    func testUnavailableCaptureFinishesWithoutAnUpdate() async {
        let unexpected = expectation(description: "no capture output")
        unexpected.isInverted = true
        let previews = WindowPreviews(ownPID: 99, captureOwn: { _ in nil }, capture: { _ in
            AsyncStream { $0.finish() }
        })
        previews.start(items: [window(1, pid: 20)], selection: 0) { _ in unexpected.fulfill() }
        await fulfillment(of: [unexpected], timeout: 0.05)
        previews.cancel()
    }
}
