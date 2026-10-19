import Foundation

/// 「正在播放」的一份快照。
struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    /// 秒；直播等沒有長度的內容為 nil。
    var duration: TimeInterval?
    /// `timestamp` 那一刻的播放位置（秒）。
    var elapsed: TimeInterval?
    var timestamp: Date?
    var playbackRate: Double
    /// 來源 App（瀏覽器分頁會是瀏覽器或網頁 App 的 bundle id）。
    var bundleIdentifier: String?
    var artworkData: Data?
    /// 隨機播放：1 關、2 專輯、3 歌曲；播放器不支援時為 nil（例如瀏覽器裡的 YouTube）。
    var shuffleMode: Int? = nil
    /// 重複播放：1 關、2 單曲、3 全部；播放器不支援時為 nil。
    var repeatMode: Int? = nil

    /// 用來判斷是不是換歌了。
    var trackKey: String {
        [bundleIdentifier ?? "", title, artist, album].joined(separator: "|")
    }

    /// 依快照時間與播放速度推算某個時間點的播放位置。
    func elapsed(at date: Date) -> TimeInterval? {
        guard var position = elapsed else { return nil }
        if isPlaying, let timestamp {
            position += date.timeIntervalSince(timestamp) * playbackRate
        }
        if let duration {
            position = min(position, duration)
        }
        return max(0, position)
    }
}

extension NowPlayingInfo {
    /// 解析 mediaremote-adapter（`--micros`）的完整 payload；沒有在播放時回傳 nil。
    init?(adapterPayload payload: [String: Any]) {
        guard let title = payload["title"] as? String, !title.isEmpty else { return nil }
        func seconds(_ key: String) -> TimeInterval? {
            (payload[key] as? NSNumber).map { $0.doubleValue / 1_000_000 }
        }
        let isPlaying = (payload["playing"] as? NSNumber)?.boolValue ?? false
        /// 0 或沒有這個欄位代表播放器不支援。
        func mode(_ key: String) -> Int? {
            (payload[key] as? NSNumber).map(\.intValue).flatMap { (1...3).contains($0) ? $0 : nil }
        }
        self.init(
            title: title,
            artist: payload["artist"] as? String ?? "",
            album: payload["album"] as? String ?? "",
            isPlaying: isPlaying,
            duration: seconds("durationMicros").flatMap { $0 > 0 ? $0 : nil },
            elapsed: seconds("elapsedTimeMicros"),
            timestamp: seconds("timestampEpochMicros").map { Date(timeIntervalSince1970: $0) },
            playbackRate: (payload["playbackRate"] as? NSNumber)?.doubleValue ?? (isPlaying ? 1 : 0),
            bundleIdentifier: payload["parentApplicationBundleIdentifier"] as? String
                ?? payload["bundleIdentifier"] as? String,
            artworkData: (payload["artworkData"] as? String).flatMap { Data(base64Encoded: $0) },
            shuffleMode: mode("shuffleMode"),
            repeatMode: mode("repeatMode")
        )
    }
}

/// mediaremote-adapter `stream` 輸出的狀態：每一行是一個 JSON，
/// `diff: true` 時只帶有變動的欄位（值為 null 代表該欄位被移除），否則是完整 payload。
struct AdapterStreamState {
    private(set) var payload: [String: Any] = [:]

    /// 套用一行輸出；不是資料訊息時回傳 false。
    mutating func apply(line: String) -> Bool {
        guard let data = line.data(using: .utf8),
              let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let incoming = message["payload"] as? [String: Any]
        else { return false }

        if (message["diff"] as? NSNumber)?.boolValue == true {
            for (key, value) in incoming {
                if value is NSNull {
                    payload.removeValue(forKey: key)
                } else {
                    payload[key] = value
                }
            }
        } else {
            payload = incoming
        }
        return true
    }

    var info: NowPlayingInfo? {
        NowPlayingInfo(adapterPayload: payload)
    }
}
