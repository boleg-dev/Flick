import AppKit

enum Metrics {
    static let thumbW: CGFloat = 176
    static let thumbH: CGFloat = 110
    static let textH: CGFloat = 34
    static let textGap: CGFloat = 8
    static let cardGap: CGFloat = 10
    static let padX: CGFloat = 18
    static let padY: CGFloat = 16
    static let hintH: CGFloat = 15
    static let hintGap: CGFloat = 16
    static let corner: CGFloat = 20
    static var cardW: CGFloat { thumbW }
    static var cardH: CGFloat { thumbH + textGap + textH }
}

final class SwitcherController {
    var sessionEnded: (() -> Void)?

    private(set) var isVisible = false
    private var items: [WindowItem] = []
    private var selection = 0
    private var panels: [OverlayPanel] = []
    private var stage: StageView?
    private var thumbnailTask: Task<Void, Never>?
    private var cache: [CGWindowID: NSImage] = [:]
    private var scrollBucket: CGFloat = 0
    private var mouseAtShow = NSPoint.zero
    private var lastMove = Date.distantPast
    private var focusGeneration = 0

    func present(scope: SwitchScope, direction: Int) {
        guard !isVisible else { return }
        focusGeneration += 1

        let all = WindowLister.onScreen()
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        switch scope {
        case .all:
            items = all
        case .currentApp:
            let same = all.filter { $0.pid == frontPID }
            items = same.isEmpty ? all : same
        }

        let focusedIsFirst = items.first?.pid == frontPID
        selection = WindowLister.initialIndex(
            count: items.count,
            direction: direction,
            focusedIsFirst: focusedIsFirst
        )
        mouseAtShow = NSEvent.mouseLocation
        scrollBucket = 0
        lastMove = .distantPast
        seedFlickPreviews()
        show()
        loadThumbnails()
    }

    func cycle(_ direction: Int) {
        guard isVisible, items.count > 1, direction != 0 else { return }
        selection = (selection + direction) % items.count
        if selection < 0 { selection += items.count }
        let animated = Date().timeIntervalSince(lastMove) > 0.07
        lastMove = Date()
        stage?.setSelection(selection, animated: animated)
    }

    func confirm() {
        guard isVisible else { return }
        let chosen = items.indices.contains(selection) ? items[selection] : nil
        focusGeneration += 1
        let generation = focusGeneration
        dismiss()
        guard let chosen else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.focusGeneration == generation, !self.isVisible else { return }
            WindowFocus.focus(chosen)
        }
    }

    func cancel() {
        guard isVisible else { return }
        focusGeneration += 1
        dismiss()
    }

    private func dismiss() {
        isVisible = false
        thumbnailTask?.cancel()
        thumbnailTask = nil
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        stage = nil
        sessionEnded?()
    }

    private func show() {
        let screens = NSScreen.screens
        guard let active = NSScreen.main ?? screens.first else {
            sessionEnded?()
            return
        }

        for screen in screens {
            let panel = OverlayPanel(frame: screen.frame)
            if screen.frame == active.frame {
                let stage = StageView()
                stage.onBackground = { [weak self] in self?.cancel() }
                stage.onHover = { [weak self] index in self?.hover(index) }
                stage.onClick = { [weak self] index in self?.click(index) }
                stage.onScroll = { [weak self] event in self?.scroll(event) }
                stage.rebuild(items: items, selection: selection, labels: labels(for:))
                for item in items {
                    if let image = cache[item.id] {
                        stage.setImage(image, for: item.id)
                    }
                }
                panel.contentView = stage
                self.stage = stage
            } else {
                let dim = DimView()
                dim.onMouseDown = { [weak self] in self?.cancel() }
                panel.contentView = dim
            }
            panel.orderFrontRegardless()
            panels.append(panel)
        }

        isVisible = true
        stage?.window?.makeKey()
        stage?.needsLayout = true
        stage?.layoutSubtreeIfNeeded()
    }

    private func hover(_ index: Int) {
        let mouse = NSEvent.mouseLocation
        guard hypot(mouse.x - mouseAtShow.x, mouse.y - mouseAtShow.y) > 4 else { return }
        guard index != selection else { return }
        selection = index
        lastMove = Date()
        stage?.setSelection(index, animated: true)
    }

    private func click(_ index: Int) {
        selection = index
        stage?.setSelection(index, animated: false)
        confirm()
    }

    private func scroll(_ event: NSEvent) {
        let delta: CGFloat
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            delta = event.scrollingDeltaX
        } else {
            delta = -event.scrollingDeltaY
        }
        guard delta != 0 else { return }
        scrollBucket += delta
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 32 : 2
        while scrollBucket <= -threshold {
            scrollBucket += threshold
            cycle(1)
        }
        while scrollBucket >= threshold {
            scrollBucket -= threshold
            cycle(-1)
        }
    }

    private func seedFlickPreviews() {
        let own = ProcessInfo.processInfo.processIdentifier
        for item in items where item.pid == own {
            if let image = WindowPreview.image(windowID: item.id) {
                cache[item.id] = image
            }
        }
    }

    private func loadThumbnails() {
        thumbnailTask?.cancel()
        guard !items.isEmpty else { return }
        var ordered = items
        if items.indices.contains(selection) {
            ordered = Array(items[selection...]) + Array(items[..<selection])
        }
        let own = ProcessInfo.processInfo.processIdentifier
        let ids = ordered.filter { $0.pid != own }.map(\.id)
        thumbnailTask = Task { [weak self] in
            for await shot in ThumbnailService.capture(ids: ids) {
                if Task.isCancelled { return }
                await MainActor.run { [weak self] in
                    guard let self, self.isVisible else { return }
                    self.apply(shot)
                }
            }
        }
    }

    private func apply(_ shot: ThumbnailService.Shot) {
        if !shot.titles.isEmpty {
            var changed = false
            for (id, title) in shot.titles {
                guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
                if items[index].title != title {
                    items[index].title = title
                    changed = true
                }
            }
            if changed {
                for item in items {
                    let (title, subtitle) = labels(for: item)
                    stage?.setLabels(title: title, subtitle: subtitle, for: item.id)
                }
            }
        }
        if let (id, cgImage) = shot.image {
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            if cache.count > 48 { cache.removeAll() }
            cache[id] = image
            stage?.setImage(image, for: id)
        }
    }

    private func labels(for item: WindowItem) -> (String, String?) {
        let trimmed = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed.compare(item.appName, options: .caseInsensitive) != .orderedSame {
            return (trimmed, item.appName)
        }
        let peers = items.filter { $0.pid == item.pid }
        if peers.count > 1, let index = peers.firstIndex(where: { $0.id == item.id }) {
            return (item.appName, "Window \(index + 1)")
        }
        return (item.appName, nil)
    }
}

final class OverlayPanel: NSPanel {
    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isFloatingPanel = true
        worksWhenModal = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        appearance = NSAppearance(named: .darkAqua)
        isMovable = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class DimView: NSView {
    var onMouseDown: (() -> Void)?

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.22).setFill()
        bounds.fill()
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }
}

final class StageView: NSView {
    var onBackground: (() -> Void)?
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?
    var onScroll: ((NSEvent) -> Void)?

    private let shell = NSView()
    private let effect = NSVisualEffectView()
    private let stripClip = NSView()
    private let strip = NSView()
    private let hint = NSTextField(labelWithString: "")
    private let fade = CAGradientLayer()
    private var cards: [CardView] = []
    private var selection = 0
    private var laidOutWidth: CGFloat = -1

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.22).setFill()
        bounds.fill()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if shell.frame.contains(point) { return }
        onBackground?()
    }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event)
    }

    init() {
        super.init(frame: .zero)
        shell.wantsLayer = true
        shell.layer?.shadowColor = NSColor.black.cgColor
        shell.layer?.shadowOpacity = 0.42
        shell.layer?.shadowRadius = 30
        shell.layer?.shadowOffset = CGSize(width: 0, height: -8)

        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.isEmphasized = true
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Metrics.corner
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

        stripClip.wantsLayer = true
        stripClip.layer?.masksToBounds = true

        hint.font = .systemFont(ofSize: 11, weight: .medium)
        hint.textColor = NSColor.white.withAlphaComponent(0.45)
        hint.alignment = .center
        hint.lineBreakMode = .byTruncatingTail

        addSubview(shell)
        shell.addSubview(effect)
        effect.addSubview(stripClip)
        stripClip.addSubview(strip)
        effect.addSubview(hint)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func rebuild(items: [WindowItem], selection: Int, labels: (WindowItem) -> (String, String?)) {
        self.selection = selection
        cards.forEach { $0.removeFromSuperview() }
        cards = items.enumerated().map { index, item in
            let (title, subtitle) = labels(item)
            let card = CardView()
            card.bind(id: item.id)
            card.toolTip = subtitle.map { "\(title)\n\($0)" } ?? title
            card.setLabels(title: title, subtitle: subtitle)
            card.setIcon(item.icon)
            card.onHover = { [weak self] in self?.onHover?(index) }
            card.onClick = { [weak self] in self?.onClick?(index) }
            card.onScroll = { [weak self] event in self?.onScroll?(event) }
            strip.addSubview(card)
            return card
        }
        hint.stringValue = items.isEmpty ? "No windows" : "Release ⌥ to switch    ·    esc cancels"
        laidOutWidth = -1
        setSelection(selection, animated: false)
        needsLayout = true
    }

    func setSelection(_ index: Int, animated: Bool) {
        selection = index
        for (cardIndex, card) in cards.enumerated() {
            card.setSelected(cardIndex == index, animated: animated)
        }
        layoutStrip(animated: animated && laidOutWidth > 0)
    }

    func setImage(_ image: NSImage, for id: CGWindowID) {
        cards.first { $0.windowID == id }?.setImage(image)
    }

    func setLabels(title: String, subtitle: String?, for id: CGWindowID) {
        guard let card = cards.first(where: { $0.windowID == id }) else { return }
        card.setLabels(title: title, subtitle: subtitle)
        card.toolTip = subtitle.map { "\(title)\n\($0)" } ?? title
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let screen = window?.screen else { return }
        let local = screen.visibleFrame.offsetBy(dx: -screen.frame.origin.x, dy: -screen.frame.origin.y)
        let size = panelSize(maxWidth: max(280, local.width - 40))
        var frame = NSRect(
            x: local.midX - size.width / 2,
            y: local.midY - size.height / 2 + local.height * 0.04,
            width: size.width,
            height: size.height
        )
        frame.origin.x = min(max(frame.minX, local.minX + 12), max(local.minX + 12, local.maxX - size.width - 12))
        frame.origin.y = min(max(frame.minY, local.minY + 12), max(local.minY + 12, local.maxY - size.height - 12))
        shell.frame = frame
        effect.frame = shell.bounds
        shell.layer?.shadowPath = CGPath(
            roundedRect: shell.bounds,
            cornerWidth: Metrics.corner,
            cornerHeight: Metrics.corner,
            transform: nil
        )

        if cards.isEmpty {
            stripClip.isHidden = true
            hint.frame = NSRect(x: 16, y: (shell.bounds.height - Metrics.hintH) / 2, width: shell.bounds.width - 32, height: Metrics.hintH)
            return
        }

        stripClip.isHidden = false
        let viewport = shell.bounds.width - Metrics.padX * 2
        stripClip.frame = NSRect(
            x: Metrics.padX,
            y: Metrics.padY + Metrics.hintH + Metrics.hintGap,
            width: viewport,
            height: Metrics.cardH
        )
        hint.frame = NSRect(x: Metrics.padX, y: Metrics.padY, width: viewport, height: Metrics.hintH)

        if abs(viewport - laidOutWidth) > 0.5 {
            laidOutWidth = viewport
            placeCards()
            layoutStrip(animated: false)
        }
    }

    private func panelSize(maxWidth: CGFloat) -> NSSize {
        if cards.isEmpty { return NSSize(width: 280, height: 78) }
        let content = contentWidth
        let viewport = min(content, maxWidth - Metrics.padX * 2)
        let width = viewport + Metrics.padX * 2
        let height = Metrics.padY + Metrics.cardH + Metrics.hintGap + Metrics.hintH + Metrics.padY
        return NSSize(width: width, height: height)
    }

    private var contentWidth: CGFloat {
        guard !cards.isEmpty else { return 0 }
        return CGFloat(cards.count) * Metrics.cardW + CGFloat(cards.count - 1) * Metrics.cardGap
    }

    private func placeCards() {
        for (index, card) in cards.enumerated() {
            let x = CGFloat(index) * (Metrics.cardW + Metrics.cardGap)
            card.frame = NSRect(x: x, y: 0, width: Metrics.cardW, height: Metrics.cardH)
        }
        strip.frame.size = NSSize(width: max(contentWidth, stripClip.bounds.width), height: Metrics.cardH)
    }

    private func layoutStrip(animated: Bool) {
        let viewport = stripClip.bounds.width
        guard viewport > 0 else { return }
        let content = contentWidth
        let x: CGFloat
        if content <= viewport {
            x = (viewport - content) / 2
        } else {
            let stride = Metrics.cardW + Metrics.cardGap
            let mid = CGFloat(selection) * stride + Metrics.cardW / 2
            x = min(0, max(viewport - content, viewport / 2 - mid))
        }
        let frame = NSRect(x: x, y: 0, width: max(content, viewport), height: Metrics.cardH)
        updateFade(viewport: viewport, content: content, originX: x)
        if animated {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0.14
            NSAnimationContext.current.timingFunction = CAMediaTimingFunction(name: .easeOut)
            strip.animator().frame = frame
            NSAnimationContext.endGrouping()
        } else {
            strip.frame = frame
        }
    }

    private func updateFade(viewport: CGFloat, content: CGFloat, originX: CGFloat) {
        let showLeft = originX < -1
        let showRight = originX + content > viewport + 1
        guard viewport > 1, showLeft || showRight else {
            stripClip.layer?.mask = nil
            return
        }
        fade.frame = stripClip.bounds
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        let clear = NSColor.clear.cgColor
        let solid = NSColor.black.cgColor
        let portion = min(0.22, 42 / viewport)
        if showLeft && showRight {
            fade.colors = [clear, solid, solid, clear]
            fade.locations = [0, NSNumber(value: portion), NSNumber(value: 1 - portion), 1]
        } else if showRight {
            fade.colors = [solid, solid, clear]
            fade.locations = [0, NSNumber(value: 1 - portion), 1]
        } else {
            fade.colors = [clear, solid, solid]
            fade.locations = [0, NSNumber(value: portion), 1]
        }
        stripClip.layer?.mask = fade
    }
}

final class CardView: NSView {
    var onHover: (() -> Void)?
    var onClick: (() -> Void)?
    var onScroll: ((NSEvent) -> Void)?
    private(set) var windowID: CGWindowID = 0

    private let imageWell = NSView()
    private let imageView = FillImageView()
    private let placeholder = NSImageView()
    private let badge = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private var icon = NSImage()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageWell.wantsLayer = true
        imageWell.layer?.cornerRadius = 11
        imageWell.layer?.masksToBounds = true
        imageWell.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        imageWell.layer?.borderWidth = 1
        imageWell.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor

        placeholder.imageScaling = .scaleProportionallyUpOrDown
        badge.imageScaling = .scaleProportionallyUpOrDown
        badge.wantsLayer = true
        badge.layer?.shadowOpacity = 0.55
        badge.layer?.shadowRadius = 2
        badge.layer?.shadowOffset = CGSize(width: 0, height: 0)
        badge.layer?.shadowColor = NSColor.black.cgColor
        badge.isHidden = true

        configure(titleField, size: 12, weight: .semibold)
        configure(subtitleField, size: 11, weight: .regular)

        addSubview(imageWell)
        imageWell.addSubview(imageView)
        imageWell.addSubview(placeholder)
        imageWell.addSubview(badge)
        addSubview(titleField)
        addSubview(subtitleField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func bind(id: CGWindowID) { windowID = id }

    func setIcon(_ image: NSImage) {
        icon = image
        placeholder.image = image
        badge.image = image
    }

    func setImage(_ image: NSImage?) {
        imageView.image = image
        let hasImage = image != nil
        imageView.isHidden = !hasImage
        placeholder.isHidden = hasImage
        badge.isHidden = !hasImage
    }

    func setLabels(title: String, subtitle: String?) {
        titleField.stringValue = title
        subtitleField.stringValue = subtitle ?? ""
        subtitleField.isHidden = subtitle == nil
        needsLayout = true
    }

    func setSelected(_ selected: Bool, animated: Bool) {
        let apply = {
            self.imageWell.layer?.borderWidth = selected ? 2.5 : 1
            self.imageWell.layer?.borderColor = self.borderColor(selected: selected)
            self.imageView.alphaValue = selected ? 1 : 0.55
            self.placeholder.alphaValue = selected ? 1 : 0.45
            self.badge.alphaValue = selected ? 1 : 0.7
            self.titleField.textColor = NSColor.white.withAlphaComponent(selected ? 0.96 : 0.46)
            self.subtitleField.textColor = NSColor.white.withAlphaComponent(selected ? 0.55 : 0.28)
        }
        if animated {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0.12
            NSAnimationContext.current.allowsImplicitAnimation = true
            apply()
            NSAnimationContext.endGrouping()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            apply()
            CATransaction.commit()
        }
    }

    override func layout() {
        super.layout()
        let thumbY = Metrics.textH + Metrics.textGap
        imageWell.frame = NSRect(x: 0, y: thumbY, width: bounds.width, height: Metrics.thumbH)
        imageView.frame = imageWell.bounds
        let iconSide: CGFloat = 46
        placeholder.frame = NSRect(
            x: (imageWell.bounds.width - iconSide) / 2,
            y: (imageWell.bounds.height - iconSide) / 2,
            width: iconSide,
            height: iconSide
        )
        badge.frame = NSRect(x: 7, y: 7, width: 18, height: 18)

        if subtitleField.isHidden {
            titleField.frame = NSRect(x: 0, y: (Metrics.textH - 16) / 2, width: bounds.width, height: 16)
        } else {
            titleField.frame = NSRect(x: 0, y: 16, width: bounds.width, height: 16)
            subtitleField.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 14)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func scrollWheel(with event: NSEvent) { onScroll?(event) }

    private func configure(_ field: NSTextField, size: CGFloat, weight: NSFont.Weight) {
        field.font = .systemFont(ofSize: size, weight: weight)
        field.alignment = .center
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.usesSingleLineMode = true
        field.cell?.truncatesLastVisibleLine = true
        field.textColor = .white
    }

    private func borderColor(selected: Bool) -> CGColor {
        let color: NSColor = selected ? .controlAccentColor : NSColor.white.withAlphaComponent(0.16)
        return (color.usingColorSpace(.sRGB) ?? color).cgColor
    }
}

final class FillImageView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let width = image.size.width * scale
        let height = image.size.height * scale
        let dest = NSRect(
            x: (bounds.width - width) / 2,
            y: (bounds.height - height) / 2,
            width: width,
            height: height
        )
        image.draw(in: dest, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1)
    }
}
