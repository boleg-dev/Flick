import XCTest
@testable import Flick

final class WindowPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    private let canvas = CGRect(x: 0, y: 0, width: 160, height: 100)

    func testSmallTopLeftWindowKeepsItsSizeAndPosition() throws {
        let placement = try XCTUnwrap(WindowPlacement(window: CGRect(x: 0, y: 0, width: 400, height: 250), screens: [screen]))
        let frames = placement.frames(in: canvas)
        XCTAssertEqual(frames.screen, canvas)
        XCTAssertEqual(frames.window, CGRect(x: 0, y: 75, width: 40, height: 25))
    }

    func testFullScreenWindowFillsMiniatureScreen() throws {
        let placement = try XCTUnwrap(WindowPlacement(window: screen, screens: [screen]))
        XCTAssertEqual(placement.frames(in: canvas).window, canvas)
    }

    func testWindowOnDisplayAbovePrimaryUsesItsOwnCoordinates() throws {
        let above = CGRect(x: -400, y: -1200, width: 1600, height: 1000)
        let placement = try XCTUnwrap(WindowPlacement(window: CGRect(x: -200, y: -1100, width: 800, height: 500), screens: [screen, above]))
        XCTAssertEqual(placement.screen, above)
        XCTAssertEqual(placement.frames(in: canvas).window, CGRect(x: 20, y: 40, width: 80, height: 50))
    }

    func testSpanningWindowUsesLargestIntersectionAndKeepsOverflow() throws {
        let right = CGRect(x: 1600, y: 0, width: 1600, height: 1000)
        let placement = try XCTUnwrap(WindowPlacement(window: CGRect(x: 1400, y: 100, width: 800, height: 500), screens: [screen, right]))
        XCTAssertEqual(placement.screen, right)
        let frames = placement.frames(in: canvas)
        XCTAssertEqual(frames.window, CGRect(x: -20, y: 40, width: 80, height: 50))
        XCTAssertEqual(frames.window.intersection(frames.screen), CGRect(x: 0, y: 40, width: 60, height: 50))
    }

    func testPortraitDisplayIsCenteredWithoutStretching() throws {
        let portrait = CGRect(x: 0, y: 0, width: 1000, height: 1600)
        let placement = try XCTUnwrap(WindowPlacement(window: portrait, screens: [portrait]))
        XCTAssertEqual(placement.frames(in: canvas).screen, CGRect(x: 48.75, y: 0, width: 62.5, height: 100))
    }

    func testUnavailableDisplayFallsBackToRegularPreview() {
        XCTAssertNil(WindowPlacement(window: screen, screens: []))
        XCTAssertNil(WindowPlacement(window: .zero, screens: [screen]))
        XCTAssertNil(WindowPlacement(window: CGRect(x: 2000, y: 0, width: 200, height: 100), screens: [screen]))
    }
}
