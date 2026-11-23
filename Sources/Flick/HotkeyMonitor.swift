import Carbon
import CoreGraphics
import Foundation

final class HotkeyMonitor {
    private let handleInput: (SwitchingSession.Input) -> Bool
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isInstalled: Bool { tap != nil }

    init(handleInput: @escaping (SwitchingSession.Input) -> Bool) {
        self.handleInput = handleInput
    }

    func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        _ = handleInput(.init(key: nil, flags: CGEventSource.flagsState(.combinedSessionState)))
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        return monitor.handle(type: type, event: event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if IsSecureEventInputEnabled() {
            return Unmanaged.passUnretained(event)
        }

        let key = type == .keyDown ? CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) : nil
        return handleInput(.init(key: key, flags: event.flags)) ? nil : Unmanaged.passUnretained(event)
    }
}
