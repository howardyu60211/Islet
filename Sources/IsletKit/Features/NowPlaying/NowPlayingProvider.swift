import Foundation

enum MediaCommand {
    case play
    case pause
    case togglePlayPause
    case nextTrack
    case previousTrack
}

/// 「正在播放」資料來源：全系統（mediaremote-adapter）或退回模式（Music／Spotify）。
protocol NowPlayingProvider: AnyObject {
    /// 有新資料時呼叫；nil 代表沒有在播放。
    var onUpdate: (NowPlayingInfo?) -> Void { get set }
    func start()
    func stop()
    func send(_ command: MediaCommand)
    func seek(to seconds: TimeInterval)
    func setShuffle(mode: Int)
    func setRepeat(mode: Int)
}

extension NowPlayingProvider {
    // 預設不支援；只有回報了隨機／重複狀態的播放器才會出現按鈕
    func setShuffle(mode: Int) {}
    func setRepeat(mode: Int) {}
}
