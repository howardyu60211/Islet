// 產生 App 圖示：swift scripts/make-icon.swift Resources/AppIcon.icns
// 畫一個深色圓角方塊，上方是黑色的小島（左邊封面、右邊音波）。
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawIcon(in size: CGFloat) {
    let unit = size / 1024
    // macOS 圖示格線：824×824 的圓角方塊置中
    let body = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let shape = NSBezierPath(roundedRect: body, xRadius: 186 * unit, yRadius: 186 * unit)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * unit
    shadow.shadowOffset = NSSize(width: 0, height: -10 * unit)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.36, green: 0.30, blue: 0.86, alpha: 1),
        NSColor(calibratedRed: 0.13, green: 0.10, blue: 0.32, alpha: 1),
    ])?.draw(in: body, angle: -90)
    // 柔和的光暈
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])?
        .draw(in: NSBezierPath(ovalIn: body.insetBy(dx: -120 * unit, dy: 260 * unit).offsetBy(dx: 0, dy: 300 * unit)), relativeCenterPosition: .zero)

    // 小島
    let island = NSRect(x: 232 * unit, y: 600 * unit, width: 560 * unit, height: 168 * unit)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: island, xRadius: 84 * unit, yRadius: 84 * unit).fill()

    // 左邊的小封面
    let art = NSRect(x: island.minX + 34 * unit, y: island.midY - 50 * unit, width: 100 * unit, height: 100 * unit)
    NSGradient(colors: [.systemPink, .systemOrange])?
        .draw(in: NSBezierPath(roundedRect: art, xRadius: 26 * unit, yRadius: 26 * unit), angle: 45)

    // 右邊的音波
    NSColor.systemOrange.setFill()
    let heights: [CGFloat] = [56, 96, 70, 110]
    for (index, height) in heights.enumerated() {
        let x = island.maxX - (60 + CGFloat(3 - index) * 30) * unit
        let bar = NSRect(x: x, y: island.midY - height * unit / 2, width: 16 * unit, height: height * unit)
        NSBezierPath(roundedRect: bar, xRadius: 8 * unit, yRadius: 8 * unit).fill()
    }

    // 下方的進度條
    let track = NSRect(x: 232 * unit, y: 420 * unit, width: 560 * unit, height: 22 * unit)
    NSColor.white.withAlphaComponent(0.25).setFill()
    NSBezierPath(roundedRect: track, xRadius: 11 * unit, yRadius: 11 * unit).fill()
    NSColor.white.withAlphaComponent(0.9).setFill()
    NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width * 0.42, height: track.height), xRadius: 11 * unit, yRadius: 11 * unit).fill()
    NSGraphicsContext.restoreGraphicsState()
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { fatalError("無法建立點陣圖") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        drawIcon(in: CGFloat(pixels))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { fatalError("iconutil 失敗") }
print("✓ \(output)")
