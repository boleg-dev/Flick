import AppKit

protocol SwitchingPresentation: AnyObject {
    func show(items: [WindowItem], selection: Int, onAction: @escaping (SwitchingSession.Action) -> Void) -> Bool
    func select(_ index: Int, animated: Bool)
    func dismiss()
}

final class SwitchingSession {
    struct Input {
        let key: CGKeyCode?
        let flags: CGEventFlags
    }

    enum Action {
        case cycle(Int), hover(Int), choose(Int), cancel
        case titles([CGWindowID: String])
    }

    private final class Run {
        let generation: Int
        var items: [WindowItem] = []
        var selection = 0
        var lastMove = Date.distantPast

        init(generation: Int) { self.generation = generation }
    }

    private let presentation: SwitchingPresentation
    private let windows: () -> [WindowItem]
    private let frontmostPID: () -> pid_t?
    private let focus: (WindowItem) -> Void
    private let enqueue: (@escaping () -> Void) -> Void
    // Input ownership changes inside the event tap; presentation changes run later.
    private var accepting: Run?
    private var presented: Run?
    private var generation = 0
    private var optionDown = false

    init(
        presentation: SwitchingPresentation,
        windows: @escaping () -> [WindowItem] = WindowLister.onScreen,
        frontmostPID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
        focus: @escaping (WindowItem) -> Void = WindowFocus.focus,
        enqueue: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }
    ) {
        self.presentation = presentation
        self.windows = windows
        self.frontmostPID = frontmostPID
        self.focus = focus
        self.enqueue = enqueue
    }

    func openFromMenu() {
        guard accepting == nil, presented == nil else { return }
        begin(scope: .all, direction: 0)
    }

    func handle(_ input: Input) -> Bool {
        let option = input.flags.contains(.maskAlternate)
        let interrupted = input.flags.contains(.maskCommand) || input.flags.contains(.maskControl)
        guard let key = input.key else {
            if let run = accepting {
                if interrupted { finish(run, confirm: false) }
                else if optionDown && !option { finish(run, confirm: true) }
            }
            optionDown = option
            return false
        }
        if let run = accepting {
            if interrupted {
                finish(run, confirm: false)
                return false
            }
            let direction = input.flags.contains(.maskShift) ? -1 : 1
            switch key {
            case Key.left: send(.cycle(-1), to: run)
            case Key.right: send(.cycle(1), to: run)
            case Key.tab, Key.grave: send(.cycle(direction), to: run)
            case Key.escape: finish(run, confirm: false)
            case Key.return, Key.keypadEnter: finish(run, confirm: true)
            default: break
            }
            return true
        }
        guard option, !interrupted, key == Key.tab || key == Key.grave else { return false }
        optionDown = true
        begin(scope: key == Key.tab ? .all : .currentApp, direction: input.flags.contains(.maskShift) ? -1 : 1)
        return true
    }

    private func begin(scope: SwitchScope, direction: Int) {
        generation += 1
        let run = Run(generation: generation)
        accepting = run
        enqueue { [weak self, run] in
            guard let self else { return }
            let all = self.windows()
            let front = self.frontmostPID()
            let same = all.filter { $0.pid == front }
            run.items = scope == .currentApp && !same.isEmpty ? same : all
            if run.items.count > 1, direction != 0, run.items.first?.pid == front {
                run.selection = direction > 0 ? 1 : run.items.count - 1
            }
            self.presented = run
            let shown = self.presentation.show(items: run.items, selection: run.selection) { [weak self, weak run] action in
                guard let self, let run else { return }
                self.apply(action, to: run)
            }
            if !shown {
                self.presented = nil
                if self.accepting === run { self.accepting = nil }
            }
        }
    }

    private func send(_ action: Action, to run: Run) {
        enqueue { [weak self] in self?.apply(action, to: run) }
    }

    private func apply(_ action: Action, to run: Run) {
        guard presented === run else { return }
        switch action {
        case .cycle(let direction):
            guard run.items.count > 1 else { return }
            run.selection = (run.selection + direction % run.items.count + run.items.count) % run.items.count
            let animated = Date().timeIntervalSince(run.lastMove) > 0.07
            run.lastMove = Date()
            presentation.select(run.selection, animated: animated)
        case .hover(let index), .choose(let index):
            guard run.items.indices.contains(index) else { return }
            if case .hover = action, run.selection == index { return }
            run.selection = index
            run.lastMove = Date()
            if case .choose = action {
                presentation.select(index, animated: false)
                finish(run, confirm: true)
            } else {
                presentation.select(index, animated: true)
            }
        case .cancel:
            finish(run, confirm: false)
        case .titles(let titles):
            for index in run.items.indices {
                if let title = titles[run.items[index].id] { run.items[index].title = title }
            }
        }
    }

    private func finish(_ run: Run, confirm: Bool) {
        if accepting === run { accepting = nil }
        enqueue { [weak self] in
            guard let self, self.presented === run else { return }
            self.presentation.dismiss()
            self.presented = nil
            guard confirm, run.items.indices.contains(run.selection) else { return }
            let chosen = run.items[run.selection]
            self.enqueue { [weak self] in
                guard let self, self.generation == run.generation, self.accepting == nil, self.presented == nil else { return }
                self.focus(chosen)
            }
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
