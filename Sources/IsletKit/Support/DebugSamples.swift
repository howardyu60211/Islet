#if DEBUG
import AppKit

extension NowPlayingInfo {
    /// Debug 選單與快照用的假歌曲。
    static var debugSample: NowPlayingInfo {
        NowPlayingInfo(
            title: "Midnight City Lights (Extended Mix)",
            artist: "Demo Artist",
            album: "Night Drive",
            isPlaying: true,
            duration: 226,
            elapsed: 61,
            timestamp: Date(),
            playbackRate: 1,
            bundleIdentifier: "com.apple.Music",
            artworkData: DebugArtwork.pngData
        )
    }
}

extension FocusMode {
    static var debugSample: FocusMode {
        FocusMode(identifier: "com.apple.donotdisturb.mode.default", configuredName: nil, symbolName: nil, tintName: "systemIndigoColor")
    }
}

extension SensorApp {
    /// 假的錄音 App（沒有在執行，圖示用 bundle ID 找）。
    static var debugSample: SensorApp {
        SensorApp(name: "FaceTime", bundleIdentifier: "com.apple.FaceTime", processIdentifier: -1)
    }
}

enum DebugArtwork {
    /// 程式畫的漸層封面。
    static var pngData: Data? {
        let image = NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            NSGradient(colors: [.systemPink, .systemOrange])?.draw(in: rect, angle: 45)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 110, dy: 110)).fill()
            return true
        }
        return image.pngData()
    }
}
#endif
