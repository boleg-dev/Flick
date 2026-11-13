import AppKit

enum PreviewSettings {
    static var showWindowPlacement: Bool {
        get { UserDefaults.standard.bool(forKey: "flick.showWindowPlacement") }
        set { UserDefaults.standard.set(newValue, forKey: "flick.showWindowPlacement") }
    }
}

struct WindowPlacement {
    let window: CGRect
    let screen: CGRect

    // Window-server and display bounds both use a top-left origin.
    init?(window: CGRect, screens: [CGRect]) {
        guard window.width > 0, window.height > 0 else { return nil }
        let overlapping = screens.filter { !$0.intersection(window).isEmpty }
        guard let screen = overlapping.max(by: {
            Self.area($0.intersection(window)) < Self.area($1.intersection(window))
        }) else { return nil }
        self.window = window
        self.screen = screen
    }

    func frames(in canvas: CGRect) -> (screen: CGRect, window: CGRect) {
        let scale = min(canvas.width / screen.width, canvas.height / screen.height)
        let screenFrame = CGRect(
            x: canvas.midX - screen.width * scale / 2,
            y: canvas.midY - screen.height * scale / 2,
            width: screen.width * scale,
            height: screen.height * scale
        )
        let windowFrame = CGRect(
            x: screenFrame.minX + (window.minX - screen.minX) * scale,
            y: screenFrame.maxY - (window.maxY - screen.minY) * scale,
            width: window.width * scale,
            height: window.height * scale
        )
        return (screenFrame, windowFrame)
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }
}
