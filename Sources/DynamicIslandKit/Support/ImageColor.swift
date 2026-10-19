import AppKit
import CoreImage

extension NSImage {
    /// 轉成固定大小的點陣圖。NSWorkspace 給的 App 圖示是延遲繪製的 IconServices 圖，
    /// 直接放進 SwiftUI 會有繪製問題，也比較耗資源。
    func bitmapCopy(pointSize: CGFloat, scale: CGFloat = 2) -> NSImage? {
        let pixels = Int(pointSize * scale)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = NSSize(width: pointSize, height: pointSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(in: NSRect(origin: .zero, size: bitmap.size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }

    /// 圖片的平均色，再調亮、調飽和一點，讓它在黑色的島上看得清楚。
    func vibrantAverageColor() -> NSColor? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent)]
        ), let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        let average = NSColor(
            srgbRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: min(saturation * 1.3, 1), brightness: max(brightness, 0.82), alpha: 1)
    }
}
