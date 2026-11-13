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

final class SwitcherOverlay: SwitchingPresentation {
    private var items: [WindowItem] = []
    private var panels: [OverlayPanel] = []
    private var stage: StageView?
    private let previews = WindowPreviews()
    private var onAction: ((SwitchingSession.Action) -> Void)?
    private var scrollBucket: CGFloat = 0
    private var mouseAtShow = NSPoint.zero

    func show(items: [WindowItem], selection: Int, onAction: @escaping (SwitchingSession.Action) -> Void) -> Bool {
        let screens = NSScreen.screens
        guard let active = NSScreen.main ?? screens.first else { return false }
        let screenFrames: [CGRect]? = PreviewSettings.showWindowPlacement ? screens.compactMap {
            guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return CGDisplayBounds(id.uint32Value)
        } : nil
        self.items = items
        self.onAction = onAction
        mouseAtShow = NSEvent.mouseLocation
        scrollBucket = 0

        for screen in screens {
            let panel = OverlayPanel(frame: screen.frame)
            if screen.frame == active.frame {
                let stage = StageView()
                stage.onBackground = { onAction(.cancel) }
                stage.onHover = { [weak self] index in self?.hover(index) }
                stage.onClick = { onAction(.choose($0)) }
                stage.onScroll = { [weak self] event in self?.scroll(event) }
                stage.rebuild(items: items, selection: selection, screenFrames: screenFrames, labels: labels(for:))
                panel.contentView = stage
                self.stage = stage
            } else {
                let dim = DimView()
                dim.onMouseDown = { onAction(.cancel) }
                panel.contentView = dim
            }
            panels.append(panel)
        }
        previews.start(items: items, selection: selection) { [weak self] in self?.apply($0) }
        panels.forEach { $0.orderFrontRegardless() }
        stage?.window?.makeKey()
        stage?.needsLayout = true
        stage?.layoutSubtreeIfNeeded()
        return true
    }

    func select(_ index: Int, animated: Bool) {
        stage?.setSelection(index, animated: animated)
    }

    func dismiss() {
        previews.cancel()
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        stage = nil
        onAction = nil
        items = []
    }

    private func hover(_ index: Int) {
        let mouse = NSEvent.mouseLocation
        guard hypot(mouse.x - mouseAtShow.x, mouse.y - mouseAtShow.y) > 4 else { return }
        onAction?(.hover(index))
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
            onAction?(.cycle(1))
        }
        while scrollBucket >= threshold {
            scrollBucket -= threshold
            onAction?(.cycle(-1))
        }
    }

    private func apply(_ update: WindowPreviews.Update) {
        switch update {
        case .titles(let titles):
            var changed = false
            for index in items.indices {
                if let title = titles[items[index].id], title != items[index].title {
                    items[index].title = title
                    changed = true
                }
            }
            guard changed else { return }
            onAction?(.titles(titles))
            for item in items {
                let (title, subtitle) = labels(for: item)
                stage?.setLabels(title: title, subtitle: subtitle, for: item.id)
            }
        case .image(let id, let image):
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

    func rebuild(items: [WindowItem], selection: Int, screenFrames: [CGRect]?, labels: (WindowItem) -> (String, String?)) {
        self.selection = selection
        cards.forEach { $0.removeFromSuperview() }
        cards = items.enumerated().map { index, item in
            let (title, subtitle) = labels(item)
            let card = CardView()
            card.bind(item: item, placement: screenFrames.flatMap { WindowPlacement(window: item.bounds, screens: $0) })
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
    private let imageView = WindowPreviewView()
    private let placeholder = NSImageView()
    private let badge = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")

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

    func bind(item: WindowItem, placement: WindowPlacement?) {
        windowID = item.id
        imageView.placement = placement
        setImage(nil)
    }

    func setIcon(_ image: NSImage) {
        placeholder.image = image
        imageView.fallbackIcon = image
        badge.image = image
    }

    func setImage(_ image: NSImage?) {
        imageView.image = image
        let hasImage = image != nil
        imageView.isHidden = !hasImage && imageView.placement == nil
        placeholder.isHidden = hasImage || imageView.placement != nil
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

final class WindowPreviewView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var placement: WindowPlacement? { didSet { needsDisplay = true } }
    var fallbackIcon: NSImage? { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        if let placement {
            drawPlacement(placement)
        } else if let image, image.size.width > 0, image.size.height > 0 {
            let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                                 width: size.width, height: size.height))
        }
    }

    private func drawPlacement(_ placement: WindowPlacement) {
        guard bounds.width > 12, bounds.height > 12 else { return }
        let frames = placement.frames(in: bounds.insetBy(dx: 6, dy: 6))
        let screenPath = NSBezierPath(roundedRect: frames.screen, xRadius: 3, yRadius: 3)
        NSColor.black.withAlphaComponent(0.35).setFill()
        screenPath.fill()
        NSGraphicsContext.saveGraphicsState()
        screenPath.addClip()
        NSColor.white.withAlphaComponent(0.12).setFill()
        frames.window.fill()
        if let image {
            image.draw(in: frames.window)
        } else if let icon = fallbackIcon {
            let side = min(32, min(frames.window.width, frames.window.height) * 0.65)
            icon.draw(in: NSRect(x: frames.window.midX - side / 2, y: frames.window.midY - side / 2,
                                width: side, height: side))
        }
        NSColor.white.withAlphaComponent(0.35).setStroke()
        let windowPath = NSBezierPath(rect: frames.window.insetBy(dx: 0.5, dy: 0.5))
        windowPath.lineWidth = 1
        windowPath.stroke()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        screenPath.lineWidth = 1
        screenPath.stroke()
    }
}
