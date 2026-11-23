import AppKit

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

NSColor(srgbRed: 0.075, green: 0.078, blue: 0.095, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvas, height: canvas)).fill()

if let glow = NSGradient(colors: [
    NSColor(srgbRed: 0.33, green: 0.42, blue: 0.98, alpha: 0.22),
    NSColor(srgbRed: 0.33, green: 0.42, blue: 0.98, alpha: 0),
]) {
    glow.draw(in: NSRect(x: 220, y: 260, width: 640, height: 640), relativeCenterPosition: .zero)
}

func card(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
}

card(
    NSRect(x: 168, y: 430, width: 500, height: 340),
    radius: 48,
    fill: NSColor(srgbRed: 0.20, green: 0.22, blue: 0.27, alpha: 1)
)

card(
    NSRect(x: 292, y: 236, width: 572, height: 412),
    radius: 58,
    fill: NSColor(srgbRed: 0.43, green: 0.49, blue: 0.98, alpha: 1)
)

let front = NSRect(x: 314, y: 258, width: 528, height: 368)
card(front, radius: 46, fill: NSColor(srgbRed: 0.97, green: 0.97, blue: 0.96, alpha: 1))

let bar = NSColor(srgbRed: 0.86, green: 0.87, blue: 0.89, alpha: 1)
card(NSRect(x: front.minX + 48, y: front.minY + 168, width: 250, height: 26), radius: 8, fill: bar)
card(NSRect(x: front.minX + 48, y: front.minY + 122, width: 168, height: 26), radius: 8, fill: bar)

image.unlockFocus()

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let iconset = root.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("could not encode icon\n", stderr)
    exit(1)
}

let master = root.appendingPathComponent("icon-1024.png")
try png.write(to: master)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func run(_ path: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 { exit(process.terminationStatus) }
}

for (name, pixels) in sizes {
    let dest = iconset.appendingPathComponent(name)
    try run("/usr/bin/sips", ["-z", "\(pixels)", "\(pixels)", master.path, "--out", dest.path])
}
try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("AppIcon.icns").path])
