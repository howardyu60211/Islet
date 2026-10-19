import AppKit
import os

/// 支援 AppleScript 的播放器。
nonisolated enum ScriptablePlayer: String, CaseIterable, Sendable {
    case music = "com.apple.Music"
    case spotify = "com.spotify.client"

    var scriptName: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }

    /// 播放狀態改變時播放器會發出的分散式通知（不需要任何權限就能監聽）。
    var notificationName: Notification.Name {
        switch self {
        case .music: Notification.Name("com.apple.Music.playerInfo")
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        }
    }
}

/// 播放器通知或 AppleScript 查詢的結果。
nonisolated struct PlayerUpdate: Sendable {
    let player: ScriptablePlayer
    /// 小寫：playing / paused / stopped。
    let state: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval?
    let position: TimeInterval?

    init(player: ScriptablePlayer, state: String, title: String, artist: String, album: String, duration: TimeInterval?, position: TimeInterval?) {
        self.player = player
        self.state = state.lowercased()
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.position = position
    }

    /// 解析分散式通知的 userInfo（Music 的長度是 "Total Time"，Spotify 是 "Duration"，都是毫秒）。
    init(player: ScriptablePlayer, userInfo: [AnyHashable: Any]?) {
        let info = userInfo ?? [:]
        let milliseconds = (info["Total Time"] as? NSNumber) ?? (info["Duration"] as? NSNumber)
        self.init(
            player: player,
            state: info["Player State"] as? String ?? "stopped",
            title: info["Name"] as? String ?? "",
            artist: info["Artist"] as? String ?? "",
            album: info["Album"] as? String ?? "",
            duration: milliseconds.map { $0.doubleValue / 1000 },
            position: (info["Playback Position"] as? NSNumber)?.doubleValue
        )
    }
}

/// 退回模式：Music 與 Spotify 的分散式通知＋AppleScript。
/// 第一次讀封面或控制播放時，macOS 會詢問「自動化」權限。
final class AppleScriptNowPlayingProvider: NowPlayingProvider {
    var onUpdate: (NowPlayingInfo?) -> Void = { _ in }

    private var observers: [NSObjectProtocol] = []
    private var player: ScriptablePlayer?
    private var info: NowPlayingInfo?
    private let logger = Logger(subsystem: "com.howardyu.DynamicIsland", category: "AppleScript")

    func start() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        for player in ScriptablePlayer.allCases {
            let token = center.addObserver(forName: player.notificationName, object: nil, queue: .main) { [weak self] notification in
                let update = PlayerUpdate(player: player, userInfo: notification.userInfo)
                MainActor.assumeIsolated { self?.handle(update) }
            }
            observers.append(token)
        }
        // App 啟動前就已經在播放的話，主動問一次
        for player in ScriptablePlayer.allCases where isRunning(player) {
            if let update = queryState(of: player), update.state == "playing" {
                handle(update)
                break
            }
        }
    }

    func stop() {
        let center = DistributedNotificationCenter.default()
        observers.forEach(center.removeObserver)
        observers.removeAll()
        player = nil
        info = nil
    }

    func send(_ command: MediaCommand) {
        guard let player = player ?? ScriptablePlayer.allCases.first(where: isRunning) else { return }
        let verb = switch command {
        case .play: "play"
        case .pause: "pause"
        case .togglePlayPause: "playpause"
        case .nextTrack: "next track"
        case .previousTrack: "previous track"
        }
        runScript("tell application \"\(player.scriptName)\" to \(verb)")
    }

    func seek(to seconds: TimeInterval) {
        guard let player, isRunning(player), var info else { return }
        runScript("tell application \"\(player.scriptName)\" to set player position to \(max(0, seconds))")
        // Music 跳轉後不會發通知，自己更新進度
        info.elapsed = seconds
        info.timestamp = Date()
        publish(info)
    }

    // MARK: - 狀態

    private func handle(_ update: PlayerUpdate) {
        let isPlaying = update.state == "playing"
        // 另一個播放器正在播的時候，忽略這個暫停的
        if let current = player, current != update.player, info?.isPlaying == true, !isPlaying {
            return
        }
        guard update.state != "stopped", !update.title.isEmpty else {
            if player == update.player || player == nil {
                player = nil
                publish(nil)
            }
            return
        }

        let isSameTrack = player == update.player
            && info?.title == update.title
            && info?.artist == update.artist
            && info?.album == update.album
        let newInfo = NowPlayingInfo(
            title: update.title,
            artist: update.artist,
            album: update.album,
            isPlaying: isPlaying,
            duration: update.duration ?? (isSameTrack ? info?.duration : nil),
            elapsed: update.position ?? queryPosition(of: update.player),
            timestamp: Date(),
            playbackRate: isPlaying ? 1 : 0,
            bundleIdentifier: update.player.rawValue,
            artworkData: isSameTrack ? info?.artworkData : nil
        )
        player = update.player
        publish(newInfo)
        if !isSameTrack {
            loadArtwork(of: update.player, trackKey: newInfo.trackKey)
        }
    }

    private func publish(_ newInfo: NowPlayingInfo?) {
        info = newInfo
        onUpdate(newInfo)
    }

    private func loadArtwork(of player: ScriptablePlayer, trackKey: String) {
        switch player {
        case .music:
            let data = runScript("tell application \"Music\" to get raw data of artwork 1 of current track")?.data
            setArtwork(data, trackKey: trackKey)
        case .spotify:
            guard let string = runScript("tell application \"Spotify\" to get artwork url of current track")?.stringValue,
                  let url = URL(string: string)
            else { return }
            Task { [weak self] in
                let data = try? await URLSession.shared.data(from: url).0
                self?.setArtwork(data, trackKey: trackKey)
            }
        }
    }

    private func setArtwork(_ data: Data?, trackKey: String) {
        guard let data, !data.isEmpty, var info, info.trackKey == trackKey else { return }
        info.artworkData = data
        publish(info)
    }

    // MARK: - AppleScript

    private func isRunning(_ player: ScriptablePlayer) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.rawValue).isEmpty
    }

    private func queryPosition(of player: ScriptablePlayer) -> TimeInterval? {
        guard isRunning(player) else { return nil }
        return runScript("tell application \"\(player.scriptName)\" to get player position")?.doubleValue
    }

    private func queryState(of player: ScriptablePlayer) -> PlayerUpdate? {
        // Music 的 duration 是秒，Spotify 是毫秒
        let durationExpression = player == .music ? "(duration of t) * 1000" : "duration of t"
        let source = """
        tell application "\(player.scriptName)"
            if player state is stopped then return {"stopped"}
            set t to current track
            return {player state as text, name of t, artist of t, album of t, \(durationExpression), player position}
        end tell
        """
        guard let result = runScript(source), result.numberOfItems >= 6 else { return nil }
        return PlayerUpdate(
            player: player,
            state: result.atIndex(1)?.stringValue ?? "stopped",
            title: result.atIndex(2)?.stringValue ?? "",
            artist: result.atIndex(3)?.stringValue ?? "",
            album: result.atIndex(4)?.stringValue ?? "",
            duration: result.atIndex(5).map { $0.doubleValue / 1000 },
            position: result.atIndex(6)?.doubleValue
        )
    }

    @discardableResult
    private func runScript(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            logger.error("AppleScript 失敗：\(error.description, privacy: .public)")
            return nil
        }
        return result
    }
}
