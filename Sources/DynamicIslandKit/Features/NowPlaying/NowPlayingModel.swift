import AppKit
import Observation
import SwiftUI
import os

/// 「正在播放」的狀態與控制，島的畫面從這裡讀資料。
@Observable
final class NowPlayingModel {
    enum Backend: Equatable {
        case off
        case starting
        /// mediaremote-adapter：任何 App 都支援。
        case systemWide
        /// 退回模式：只支援 Music 與 Spotify。
        case musicAndSpotify

        var title: String {
            switch self {
            case .off: "已關閉"
            case .starting: "偵測中…"
            case .systemWide: "全系統（任何 App）"
            case .musicAndSpotify: "Music／Spotify"
            }
        }
    }

    private(set) var backend: Backend = .off
    /// 聲音輸出裝置（播放器裡的切換按鈕）。
    let outputs = AudioOutputModel()
    private(set) var info: NowPlayingInfo?
    private(set) var artwork: NSImage?
    private(set) var accentColor: Color = .white
    private(set) var sourceAppIcon: NSImage?
    /// 正在播放，或暫停不到幾秒：收合時要不要顯示音樂。
    private(set) var isRecentlyActive = false

    @ObservationIgnored private var provider: (any NowPlayingProvider)?
    @ObservationIgnored private var lingerTask: Task<Void, Never>?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "com.howardyu.DynamicIsland", category: "NowPlaying")

    // MARK: - 啟動

    func start() {
        guard backend == .off else { return }
        backend = .starting
        outputs.start()
        startTask = Task { [weak self] in
            await self?.chooseBackend()
        }
    }

    func stop() {
        startTask?.cancel()
        provider?.stop()
        provider = nil
        backend = .off
        apply(nil)
    }

    private func chooseBackend() async {
        guard let resources = MediaRemoteAdapterProvider.Resources.bundled else {
            logger.info("App 裡沒有 mediaremote-adapter")
            useFallback()
            return
        }
        // 保險：檢查一直沒有回應就改用退回模式
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.backend == .starting else { return }
            self.logger.error("adapter 檢查沒有回應，改用 Music／Spotify 模式")
            self.useFallback()
        }
        defer { watchdog.cancel() }
        // 上次 App 被強制結束時留下的 adapter 程序
        await MediaRemoteAdapterProvider.terminateOrphans(resources)
        let startDate = Date()
        let isFunctional = await MediaRemoteAdapterProvider.isFunctional(resources)
        logger.info("adapter test: \(isFunctional, privacy: .public) (\(Date().timeIntervalSince(startDate), format: .fixed(precision: 2), privacy: .public)s)")
        guard backend == .starting else { return }
        if isFunctional {
            let adapter = MediaRemoteAdapterProvider(resources: resources)
            adapter.onFailure = { [weak self] in
                self?.useFallback()
            }
            use(adapter, backend: .systemWide)
        } else {
            useFallback()
        }
    }

    private func useFallback() {
        provider?.stop()
        use(AppleScriptNowPlayingProvider(), backend: .musicAndSpotify)
    }

    private func use(_ provider: any NowPlayingProvider, backend: Backend) {
        logger.info("now playing backend: \(backend.title, privacy: .public)")
        self.provider = provider
        self.backend = backend
        provider.onUpdate = { [weak self] info in
            self?.apply(info)
        }
        provider.start()
    }

    // MARK: - 資料

    func apply(_ newInfo: NowPlayingInfo?) {
        if newInfo?.artworkData != info?.artworkData {
            updateArtwork(newInfo?.artworkData)
        }
        if newInfo?.bundleIdentifier != info?.bundleIdentifier {
            updateSourceIcon(newInfo?.bundleIdentifier)
        }
        if newInfo != info {
            if newInfo?.trackKey != info?.trackKey || newInfo?.isPlaying != info?.isPlaying {
                logger.info("now playing: playing=\(newInfo?.isPlaying ?? false, privacy: .public) source=\(newInfo?.bundleIdentifier ?? "-", privacy: .public) artwork=\(newInfo?.artworkData != nil, privacy: .public)")
            }
            info = newInfo
        }
        updateActivity()
    }

    private func updateArtwork(_ data: Data?) {
        guard let data, let image = NSImage(data: data) else {
            artwork = nil
            accentColor = .white
            return
        }
        artwork = image
        accentColor = image.vibrantAverageColor().map { Color(nsColor: $0) } ?? .white
    }

    private func updateSourceIcon(_ bundleIdentifier: String?) {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else {
            sourceAppIcon = nil
            return
        }
        sourceAppIcon = NSWorkspace.shared.icon(forFile: url.path).bitmapCopy(pointSize: 32)
    }

    /// 播放中就顯示；暫停後再留 5 秒才收回。
    private func updateActivity() {
        lingerTask?.cancel()
        if info?.isPlaying == true {
            if !isRecentlyActive { isRecentlyActive = true }
            return
        }
        guard isRecentlyActive else { return }
        guard info != nil else {
            isRecentlyActive = false
            return
        }
        lingerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.isRecentlyActive = false
        }
    }

    // MARK: - 控制

    var isPlaying: Bool { info?.isPlaying == true }

    func togglePlayPause() {
        setPlaying(!isPlaying, command: .togglePlayPause)
    }

    func play() {
        setPlaying(true, command: .play)
    }

    func pause() {
        setPlaying(false, command: .pause)
    }

    private func setPlaying(_ playing: Bool, command: MediaCommand) {
        // 先在畫面上切換，stream 隨後會確認
        if var current = info, current.isPlaying != playing {
            current.elapsed = current.elapsed(at: Date())
            current.timestamp = Date()
            current.isPlaying = playing
            current.playbackRate = playing ? 1 : 0
            apply(current)
        }
        provider?.send(command)
    }

    func nextTrack() {
        provider?.send(.nextTrack)
    }

    func previousTrack() {
        provider?.send(.previousTrack)
    }

    func seek(to seconds: TimeInterval) {
        if var current = info {
            current.elapsed = seconds
            current.timestamp = Date()
            apply(current)
        }
        provider?.seek(to: seconds)
    }

    /// 快轉／倒轉（秒數可正可負），用跳轉做，所以瀏覽器裡的 YouTube 也能用。
    func skip(by seconds: TimeInterval) {
        guard let info, let duration = info.duration, let elapsed = info.elapsed(at: Date()) else { return }
        seek(to: min(max(elapsed + seconds, 0), max(duration - 1, 0)))
    }

    /// 隨機播放：開（歌曲）↔ 關。
    func toggleShuffle() {
        guard var current = info, let mode = current.shuffleMode else { return }
        let next = mode == 1 ? 3 : 1
        current.shuffleMode = next
        apply(current)
        provider?.setShuffle(mode: next)
    }

    /// 重複播放：關 → 全部 → 單曲 → 關。
    func cycleRepeat() {
        guard var current = info, let mode = current.repeatMode else { return }
        let next = switch mode {
        case 1: 3
        case 3: 2
        default: 1
        }
        current.repeatMode = next
        apply(current)
        provider?.setRepeat(mode: next)
    }

    func openSourceApp() {
        guard let bundleIdentifier = info?.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
