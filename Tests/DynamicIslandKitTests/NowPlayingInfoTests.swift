import Foundation
import Testing
@testable import DynamicIslandKit

struct NowPlayingInfoTests {
    /// 實際從 `mediaremote-adapter get --micros` 拿到的格式。
    private let fullLine = """
    {"type":"data","diff":false,"payload":{"playbackRate":1,"timestampEpochMicros":1792395619827632,"album":"","elapsedTimeMicros":1403485544,"playing":true,"bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari.WebApp.37DE8CE8","processIdentifier":16317,"title":"Best of Chill Mix","uniqueIdentifier":14017213,"artist":"NoCopyrightSounds","durationMicros":2440061000,"artworkData":"aGVsbG8=","artworkMimeType":"image/png"}}
    """

    @Test func parsesAFullPayload() throws {
        var state = AdapterStreamState()
        let applied = state.apply(line: fullLine)
        #expect(applied)
        let info = try #require(state.info)
        #expect(info.title == "Best of Chill Mix")
        #expect(info.artist == "NoCopyrightSounds")
        #expect(info.isPlaying)
        #expect(info.duration == 2440.061)
        #expect(info.elapsed == 1403.485544)
        #expect(info.timestamp == Date(timeIntervalSince1970: 1_792_395_619.827632))
        #expect(info.playbackRate == 1)
        // 瀏覽器分頁要顯示瀏覽器（網頁 App）本身，而不是 WebKit 的 GPU 程序
        #expect(info.bundleIdentifier == "com.apple.Safari.WebApp.37DE8CE8")
        #expect(info.artworkData == Data("hello".utf8))
    }

    @Test func diffsAreMergedAndNullRemovesKeys() throws {
        var state = AdapterStreamState()
        _ = state.apply(line: fullLine)
        let merged = state.apply(line: #"{"type":"data","diff":true,"payload":{"playing":false,"playbackRate":0,"artworkData":null}}"#)
        #expect(merged)
        let info = try #require(state.info)
        #expect(!info.isPlaying)
        #expect(info.playbackRate == 0)
        #expect(info.artworkData == nil)
        #expect(info.title == "Best of Chill Mix")
    }

    @Test func emptyPayloadMeansNothingIsPlaying() {
        var state = AdapterStreamState()
        _ = state.apply(line: fullLine)
        let cleared = state.apply(line: #"{"type":"data","diff":false,"payload":{}}"#)
        #expect(cleared)
        #expect(state.info == nil)
    }

    @Test func ignoresLinesThatAreNotDataMessages() {
        var state = AdapterStreamState()
        let notJSON = state.apply(line: "not json")
        let noPayload = state.apply(line: #"{"type":"data"}"#)
        #expect(!notJSON)
        #expect(!noPayload)
    }

    @Test func elapsedTimeAdvancesOnlyWhilePlaying() {
        let start = Date(timeIntervalSince1970: 1000)
        var info = NowPlayingInfo(
            title: "t", artist: "", album: "", isPlaying: true,
            duration: 100, elapsed: 10, timestamp: start, playbackRate: 1,
            bundleIdentifier: nil, artworkData: nil
        )
        #expect(info.elapsed(at: start.addingTimeInterval(5)) == 15)
        // 不會超過歌曲長度
        #expect(info.elapsed(at: start.addingTimeInterval(500)) == 100)

        info.isPlaying = false
        #expect(info.elapsed(at: start.addingTimeInterval(5)) == 10)
    }

    @Test func formatsTimes() {
        #expect(formatTime(0) == "0:00")
        #expect(formatTime(75.9) == "1:15")
        #expect(formatTime(3725) == "1:02:05")
    }

    @Test func parsesMusicAndSpotifyNotifications() {
        let music = PlayerUpdate(player: .music, userInfo: [
            "Name": "Song", "Artist": "Artist", "Album": "Album",
            "Total Time": 215_000, "Player State": "Playing",
        ])
        #expect(music.state == "playing")
        #expect(music.duration == 215)
        #expect(music.position == nil)

        let spotify = PlayerUpdate(player: .spotify, userInfo: [
            "Name": "Song", "Artist": "Artist", "Album": "Album",
            "Duration": 180_000, "Player State": "Paused", "Playback Position": 42.5,
        ])
        #expect(spotify.state == "paused")
        #expect(spotify.duration == 180)
        #expect(spotify.position == 42.5)
    }

    @Test func shuffleAndRepeatOnlyAppearWhenThePlayerReportsThem() throws {
        var state = AdapterStreamState()
        _ = state.apply(line: fullLine)
        // YouTube（瀏覽器）沒有這兩個欄位
        #expect(state.info?.shuffleMode == nil)
        #expect(state.info?.repeatMode == nil)

        _ = state.apply(line: #"{"type":"data","diff":true,"payload":{"shuffleMode":3,"repeatMode":0}}"#)
        let info = try #require(state.info)
        #expect(info.shuffleMode == 3)
        // 0 代表不支援
        #expect(info.repeatMode == nil)
    }
}
