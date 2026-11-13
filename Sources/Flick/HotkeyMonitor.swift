import Carbon
import CoreGraphics
import Foundation

/// Option-Tab session. State changes happen inside the event tap so a key repeat
/// cannot slip through before the panel exists.
final class HotkeyMonitor {
    var open: ((_ scope: SwitchScope, _ direction: Int) -> Void)?
    var cycle: ((Int) -> Void)?
    var confirm: (() -> Void)?
    var cancel: (() -> Void)?

    private(set) var isInstalled = false
    private var engaged = false
    private var optionDown = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func start() {
        guard tap == nil else {
            isInstalled = true
            return
        }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isInstalled = false
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        optionDown = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
        isInstalled = true
    }

    func endSession() {
        engaged = false
    }

    func openFromMenu() {
        engaged = true
        open?(.all, 0)
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

        let flags = event.flags
        let option = flags.contains(.maskAlternate)
        let command = flags.contains(.maskCommand)
        let control = flags.contains(.maskControl)

        if type == .flagsChanged {
            if engaged && (command || control) {
                engaged = false
                optionDown = option
                ui { self.cancel?() }
                return Unmanaged.passUnretained(event)
            }
            if engaged && optionDown && !option {
                engaged = false
                optionDown = option
                ui { self.confirm?() }
                return Unmanaged.passUnretained(event)
            }
            optionDown = option
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let key = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let shift = flags.contains(.maskShift)

        if engaged && (command || control) {
            engaged = false
            ui { self.cancel?() }
            return Unmanaged.passUnretained(event)
        }

        if engaged {
            if let direction = cycleDirection(key: key, shift: shift) {
                ui { self.cycle?(direction) }
                return nil
            }
            if key == Key.escape {
                engaged = false
                ui { self.cancel?() }
                return nil
            }
            if key == Key.return || key == Key.keypadEnter {
                engaged = false
                ui { self.confirm?() }
                return nil
            }
            return nil
        }

        guard option, !command, !control else { return Unmanaged.passUnretained(event) }

        let direction = shift ? -1 : 1
        if key == Key.tab {
            engaged = true
            optionDown = true
            ui { self.open?(.all, direction) }
            return nil
        }
        if key == Key.grave {
            engaged = true
            optionDown = true
            ui { self.open?(.currentApp, direction) }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func ui(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }

    private func cycleDirection(key: CGKeyCode, shift: Bool) -> Int? {
        switch key {
        case Key.left:
            return -1
        case Key.right:
            return 1
        case Key.tab, Key.grave:
            return shift ? -1 : 1
        default:
            return nil
        }
    }
}

private enum Key {
    static let tab: CGKeyCode = 48
    static let grave: CGKeyCode = 50
    static let escape: CGKeyCode = 53
    static let `return`: CGKeyCode = 36
    static let keypadEnter: CGKeyCode = 76
    static let left: CGKeyCode = 123
    static let right: CGKeyCode = 124
}
