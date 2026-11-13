import XCTest
@testable import Flick

final class SwitchingSessionTests: XCTestCase {
    func testQuickReleaseStillPresentsAndConfirmsInOrder() {
        let rig = Rig()
        XCTAssertTrue(rig.key(48))
        XCTAssertFalse(rig.flags([]))
        XCTAssertTrue(rig.display.shown.isEmpty)
        rig.drain()
        XCTAssertEqual(rig.display.shown, [[1, 2, 3]])
        XCTAssertEqual(rig.focused.map(\.id), [2])
        XCTAssertEqual(rig.display.dismissals, 1)
        XCTAssertFalse(rig.key(0, flags: []))
    }

    func testRepeatsBeforePresentationCycleAndWrap() {
        let rig = Rig()
        XCTAssertTrue(rig.key(48))
        XCTAssertTrue(rig.key(48))
        XCTAssertTrue(rig.key(48))
        _ = rig.flags([])
        rig.drain()
        XCTAssertEqual(rig.focused.map(\.id), [1])
    }

    func testReopenSuppressesOldFocusWithoutReleasingNewKeyboardCapture() {
        let rig = Rig()
        _ = rig.key(48)
        _ = rig.flags([])
        _ = rig.key(48)
        rig.drain()
        XCTAssertTrue(rig.focused.isEmpty)
        XCTAssertTrue(rig.key(48))
        _ = rig.flags([])
        rig.drain()
        XCTAssertEqual(rig.focused.map(\.id), [3])
    }

    func testEscapeAndModifierInterruptionCancel() {
        for (key, flags, consumed) in [(UInt16(53), CGEventFlags.maskAlternate, true), (UInt16(0), CGEventFlags.maskCommand, false)] {
            let rig = Rig()
            _ = rig.key(48)
            XCTAssertEqual(rig.key(key, flags: flags), consumed)
            rig.drain()
            XCTAssertTrue(rig.focused.isEmpty)
            XCTAssertEqual(rig.display.dismissals, 1)
            XCTAssertFalse(rig.key(0, flags: []))
        }
        let rig = Rig()
        _ = rig.key(48)
        XCTAssertFalse(rig.flags([.maskAlternate, .maskControl]))
        rig.drain()
        XCTAssertTrue(rig.focused.isEmpty)
    }

    func testPointerDismissalReleasesKeyboardCapture() {
        let rig = Rig()
        _ = rig.key(48)
        rig.drain()
        rig.display.action?(.cancel)
        XCTAssertFalse(rig.key(0, flags: []))
        rig.drain()
        XCTAssertTrue(rig.focused.isEmpty)
    }

    func testMenuOpeningChoosesFirstAndClickUsesEnrichedTitle() {
        let rig = Rig()
        rig.session.openFromMenu()
        rig.drain()
        XCTAssertEqual(rig.display.selections, [0])
        rig.display.action?(.titles([3: "Updated title"]))
        rig.display.action?(.choose(2))
        rig.drain()
        XCTAssertEqual(rig.focused.map(\.id), [3])
        XCTAssertEqual(rig.focused.first?.title, "Updated title")
    }

    func testCurrentAppScopeAndReverseSelection() {
        let rig = Rig()
        _ = rig.key(50, flags: [.maskAlternate, .maskShift])
        _ = rig.flags([])
        rig.drain()
        XCTAssertEqual(rig.display.shown, [[1, 3]])
        XCTAssertEqual(rig.focused.map(\.id), [3])
    }

    func testAbsentCurrentAppFallsBackToAllWindows() {
        let rig = Rig(front: 99)
        _ = rig.key(50)
        _ = rig.flags([])
        rig.drain()
        XCTAssertEqual(rig.display.shown, [[1, 2, 3]])
        XCTAssertEqual(rig.focused.map(\.id), [1])
    }

    func testEmptyListCanBeConfirmedWithoutFocus() {
        let rig = Rig(items: [])
        _ = rig.key(48)
        _ = rig.key(48)
        _ = rig.flags([])
        rig.drain()
        XCTAssertEqual(rig.display.dismissals, 1)
        XCTAssertTrue(rig.focused.isEmpty)
    }

    func testPresentationFailureReleasesCapture() {
        let rig = Rig()
        rig.display.canShow = false
        _ = rig.key(48)
        rig.drain()
        XCTAssertFalse(rig.key(0, flags: []))
        XCTAssertTrue(rig.focused.isEmpty)
    }
}

private final class Display: SwitchingPresentation {
    var canShow = true
    var shown: [[CGWindowID]] = []
    var selections: [Int] = []
    var dismissals = 0
    var action: ((SwitchingSession.Action) -> Void)?

    func show(items: [WindowItem], selection: Int, onAction: @escaping (SwitchingSession.Action) -> Void) -> Bool {
        shown.append(items.map(\.id))
        selections.append(selection)
        action = onAction
        return canShow
    }
    func select(_ index: Int, animated: Bool) { selections.append(index) }
    func dismiss() { dismissals += 1; action = nil }
}

private final class Rig {
    let display = Display()
    var jobs: [() -> Void] = []
    var focused: [WindowItem] = []
    let items: [WindowItem]
    let front: pid_t?
    lazy var session = SwitchingSession(
        presentation: display,
        windows: { [unowned self] in self.items },
        frontmostPID: { [unowned self] in self.front },
        focus: { [unowned self] in self.focused.append($0) },
        enqueue: { [unowned self] in self.jobs.append($0) }
    )

    init(items: [WindowItem] = [window(1, pid: 10), window(2, pid: 20), window(3, pid: 10)], front: pid_t? = 10) {
        self.items = items
        self.front = front
    }
    func key(_ key: UInt16, flags: CGEventFlags = .maskAlternate) -> Bool {
        session.handle(.init(key: key, flags: flags))
    }
    func flags(_ flags: CGEventFlags) -> Bool { session.handle(.init(key: nil, flags: flags)) }
    func drain() {
        var count = 0
        while !jobs.isEmpty {
            count += 1
            precondition(count < 100, "Unexpected scheduling loop")
            jobs.removeFirst()()
        }
    }
}

func window(_ id: CGWindowID, pid: pid_t) -> WindowItem {
    WindowItem(id: id, pid: pid, appName: "App", title: "Window \(id)", bounds: .zero, bundleURL: nil)
}
