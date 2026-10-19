import AppKit

/// 計時結束的提示音：先暫停正在播的音樂，提示音以最大音量響三次，再繼續播放。
/// （macOS 沒有公開的 API 能只把「其他 App」的聲音調小，所以用暫停／繼續來讓提示音清楚。）
final class TimerAlert {
    static let repeatCount = 3

    /// /System/Library/Sounds 裡可用的音效名稱。
    static var availableSounds: [String] {
        let folder = URL(fileURLWithPath: "/System/Library/Sounds")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    private let nowPlaying: NowPlayingModel
    private var task: Task<Void, Never>?

    init(nowPlaying: NowPlayingModel) {
        self.nowPlaying = nowPlaying
    }

    func play(sound name: String, pausingMusic: Bool) {
        task?.cancel()
        let shouldResume = pausingMusic && nowPlaying.isPlaying
        if shouldResume {
            nowPlaying.pause()
        }
        task = Task { [weak self] in
            if shouldResume {
                // 等音樂真的停下來
                try? await Task.sleep(for: .milliseconds(350))
            }
            for _ in 0..<Self.repeatCount {
                guard !Task.isCancelled, let sound = Self.sound(named: name) else { break }
                sound.play()
                try? await Task.sleep(for: .seconds(max(sound.duration, 0.5) + 0.25))
            }
            if shouldResume {
                self?.nowPlaying.play()
            }
        }
    }

    /// 設定裡試聽用，只響一次。
    static func preview(_ name: String) {
        sound(named: name)?.play()
    }

    private static func sound(named name: String) -> NSSound? {
        // NSSound(named:) 回傳共用物件，複製一份才能重複播放
        guard let sound = (NSSound(named: NSSound.Name(name)) ?? NSSound(named: "Glass"))?.copy() as? NSSound else {
            return nil
        }
        sound.volume = 1
        return sound
    }
}
