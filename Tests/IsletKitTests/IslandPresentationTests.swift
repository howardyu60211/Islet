import Foundation
import CoreGraphics
import Testing
@testable import IsletKit

struct IslandPresentationTests {
    private let charging = IslandEvent(kind: .charging(level: 80))
    private let timerDone = IslandEvent(kind: .timerFinished(title: "時間到", subtitle: ""))

    @Test func expandedWinsOverEverything() {
        let presentation = IslandPresentation.resolve(isExpanded: true, event: timerDone, timerActive: true, musicActive: true)
        #expect(presentation == .expanded)
    }

    @Test func eventsBeatPersistentActivities() {
        #expect(IslandPresentation.resolve(isExpanded: false, event: timerDone, timerActive: true, musicActive: true) == .banner(timerDone))
    }

    @Test func chargingIsShownCompactInsteadOfAsABanner() {
        #expect(IslandPresentation.resolve(isExpanded: false, event: charging, timerActive: false, musicActive: true) == .compact(.charging(level: 80)))
    }

    @Test func volumeFocusAndSensorsAreShownCompact() {
        let volume = IslandEvent(kind: .volume(level: 40, muted: false))
        #expect(IslandPresentation.resolve(isExpanded: false, event: volume, timerActive: true, musicActive: true) == .compact(.volume(level: 40, muted: false)))
        let focus = IslandEvent(kind: .focus(.debugSample, active: true))
        #expect(IslandPresentation.resolve(isExpanded: false, event: focus, timerActive: false, musicActive: false) == .compact(.focus(.debugSample, active: true)))
        let microphone = IslandEvent(kind: .sensor(.microphone, app: nil, active: true))
        #expect(IslandPresentation.resolve(isExpanded: false, event: microphone, timerActive: false, musicActive: false) == .compact(.sensor(.microphone, app: nil, active: true)))
    }

    @Test func volumeKeepsTheSameContentKeyWhileAdjusting() {
        #expect(IslandPresentation.compact(.volume(level: 10, muted: false)).contentKey == IslandPresentation.compact(.volume(level: 90, muted: true)).contentKey)
        #expect(IslandEvent(kind: .volume(level: 10, muted: false)).isTransient)
        #expect(!IslandEvent(kind: .sensor(.screenRecording, app: nil, active: true)).isTransient)
    }

    @Test func clipboardIsATransientCompactAnimation() {
        let summary = ClipboardSummary(id: UUID(), kind: .text, excerpt: "hi", image: nil)
        let event = IslandEvent(kind: .clipboard(summary))
        #expect(event.isTransient)
        #expect(IslandPresentation.resolve(isExpanded: false, event: event, timerActive: true, musicActive: true) == .compact(.clipboard(summary)))
        // 連續拷貝時每次都重新播進場動畫
        let next = ClipboardSummary(id: UUID(), kind: .text, excerpt: "hi", image: nil)
        #expect(CompactActivity.clipboard(summary).key != CompactActivity.clipboard(next).key)
    }

    @Test func runningTimerBeatsMusicWhenNotPaired() {
        #expect(IslandPresentation.resolve(isExpanded: false, event: nil, timerActive: true, musicActive: true, pairsActivities: false) == .compact(.timer))
        #expect(IslandPresentation.resolve(isExpanded: false, event: nil, timerActive: false, musicActive: true) == .compact(.nowPlaying))
    }

    @Test func twoActivitiesArePairedWithMusicOnTheLeft() {
        #expect(IslandPresentation.resolve(isExpanded: false, event: nil, timerActive: true, musicActive: true) == .compact(.pair(.nowPlaying, .timer)))
        #expect(IslandPresentation.resolve(isExpanded: false, event: nil, timerActive: false, musicActive: true, activeSensors: [.microphone]) == .compact(.pair(.nowPlaying, .sensors([.microphone]))))
        #expect(IslandPresentation.resolve(isExpanded: false, event: nil, timerActive: true, musicActive: false, activeSensors: [.screenRecording]) == .compact(.pair(.timer, .sensors([.screenRecording]))))
        // 三個都有時，麥克風讓位給音樂和計時器
        #expect(IslandPresentation.resolve(isExpanded: false, event: nil, timerActive: true, musicActive: true, activeSensors: [.microphone]) == .compact(.pair(.nowPlaying, .timer)))
    }

    @Test func sensorsAloneDoNotOccupyTheIsland() {
        #expect(IslandPresentation.resolve(isExpanded: false, event: nil, timerActive: false, musicActive: false, activeSensors: [.microphone]) == .idle)
    }

    @Test func eventsStillTakeOverAPair() {
        let volume = IslandEvent(kind: .volume(level: 40, muted: false))
        #expect(IslandPresentation.resolve(isExpanded: false, event: volume, timerActive: true, musicActive: true) == .compact(.volume(level: 40, muted: false)))
    }

    @Test func pairIsSymmetricAroundTheNotch() {
        let notch = CGSize(width: 190, height: 32)
        let pair = IslandMetrics.make(for: .compact(.pair(.nowPlaying, .timer)), notch: notch)
        #expect(pair.bodySize.width == notch.width + LiveActivity.timer.sideWidth * 2)
        #expect(CompactActivity.pair(.nowPlaying, .timer).includesNowPlaying)
        #expect(!CompactActivity.pair(.timer, .sensors([.microphone])).includesNowPlaying)
    }

    @Test func nothingGoingOnIsIdle() {
        #expect(IslandPresentation.resolve(isExpanded: false, event: nil, timerActive: false, musicActive: false) == .idle)
    }

    @Test func idleHidesBehindTheNotchAndCompactGrowsSideways() {
        let notch = CGSize(width: 190, height: 32)
        let idle = IslandMetrics.make(for: .idle, notch: notch)
        #expect(idle.bodySize.width < notch.width)
        #expect(idle.bodySize.height < notch.height)
        #expect(idle.frameSize.width <= notch.width + idle.topRadius * 2)

        let compact = IslandMetrics.make(for: .compact(.nowPlaying), notch: notch)
        #expect(compact.bodySize.height == notch.height)
        #expect(compact.bodySize.width == notch.width + CompactActivity.nowPlaying.sideWidth * 2)
    }

    @Test func expandedIslandFitsInsideThePanel() {
        let notch = CGSize(width: 220, height: 40)
        let expanded = IslandMetrics.make(for: .expanded, notch: notch)
        #expect(expanded.frameSize.width < NotchWindowController.panelSize.width)
        #expect(expanded.frameSize.height + 30 < NotchWindowController.panelSize.height)
    }

    @Test func eventsOfTheSameKindShareACategory() {
        #expect(charging.category == IslandEvent(kind: .lowBattery(level: 10)).category)
        #expect(charging.category != timerDone.category)
        #expect(timerDone.relatedTab == .timer)
    }

    @Test func fileDragsTriggerWellBelowTheNotch() {
        // AppKit 座標：y 往上，島貼著螢幕頂端（956）
        let island = CGRect(x: 643, y: 925, width: 183, height: 31)
        let zone = IslandViewModel.fileDragTriggerRect(around: island)
        #expect(zone.contains(CGPoint(x: 735, y: 850)))   // 瀏海下方 ~100pt
        #expect(zone.contains(CGPoint(x: 540, y: 900)))   // 瀏海左邊
        #expect(!zone.contains(CGPoint(x: 735, y: 800)))  // 太下面
        #expect(!zone.contains(CGPoint(x: 300, y: 940)))  // 太旁邊
    }
}
