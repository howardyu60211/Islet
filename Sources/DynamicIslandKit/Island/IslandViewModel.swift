import AppKit
import Observation
import SwiftUI
import os

/// 島的狀態機：決定現在要顯示什麼、什麼時候展開／收合、事件怎麼排隊。
@Observable
final class IslandViewModel {
    let preferences: Preferences
    let battery: BatteryMonitor
    let nowPlaying: NowPlayingModel
    let timer: TimerModel
    let shelf: ShelfModel
    let clipboard: ClipboardModel
    let microphone: MicrophoneMonitor
    let screenRecording: ScreenRecordingMonitor
    let backgroundApps: BackgroundAppsModel
    @ObservationIgnored private let logger = Logger(subsystem: "com.howardyu.DynamicIsland", category: "Island")

    /// 內建螢幕的瀏海；沒有內建螢幕時為 nil（面板隱藏）。
    var geometry: NotchGeometry?
    private(set) var isExpanded = false
    var selectedTab: IslandTab = .media
    private(set) var activeEvent: IslandEvent?
    /// 正拖著檔案經過島（顯示暫存架投放區）。
    private(set) var isFileDragHovering = false
    /// 滑動切歌時播放器內容的水平位移（只套用在頂部條以下的內容）。
    private(set) var swipeOffset: CGFloat = 0
    /// 剪貼簿分頁左邊的滾輪。
    private(set) var clipboardWheel = WheelTracker()

    /// 由 AppServices 注入。
    @ObservationIgnored var openSettings: () -> Void = {}

    @ObservationIgnored private var pendingEvents: [IslandEvent] = []
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var expandTask: Task<Void, Never>?
    @ObservationIgnored private var collapseTask: Task<Void, Never>?
    @ObservationIgnored private var pointerInside = false
    @ObservationIgnored private var isPointerDown = false
    @ObservationIgnored private var dragChangeCountAtMouseDown = 0
    @ObservationIgnored private var isMenuTracking = false
    /// 正從暫存架把檔案拖出去（這時不要顯示投放區）。
    @ObservationIgnored private var isDraggingOutOfShelf = false
    @ObservationIgnored private var menuObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var swipeTracker = SwipeTracker()
    @ObservationIgnored private var isSwipeTransitioning = false
    /// 滾輪選到的那筆（照 ID 記：拷貝後項目移到最前面，選的還是同一筆）。
    @ObservationIgnored private var clipboardSelectedID: UUID?
    @ObservationIgnored private var wheelSnapTask: Task<Void, Never>?

    init(
        preferences: Preferences,
        battery: BatteryMonitor,
        nowPlaying: NowPlayingModel,
        timer: TimerModel,
        shelf: ShelfModel,
        clipboard: ClipboardModel,
        microphone: MicrophoneMonitor = MicrophoneMonitor(),
        screenRecording: ScreenRecordingMonitor = ScreenRecordingMonitor(),
        backgroundApps: BackgroundAppsModel = BackgroundAppsModel()
    ) {
        self.preferences = preferences
        self.battery = battery
        self.nowPlaying = nowPlaying
        self.timer = timer
        self.shelf = shelf
        self.clipboard = clipboard
        self.microphone = microphone
        self.screenRecording = screenRecording
        self.backgroundApps = backgroundApps
        observeMenuTracking()
    }

    // MARK: - 目前的樣子

    var notchSize: CGSize { geometry?.notchSize ?? NotchGeometry.fallbackSize }

    /// 頂部條上要顯示的「使用中」指示燈。
    var activeSensors: [Sensor] {
        var sensors: [Sensor] = []
        if preferences.microphoneIndicatorEnabled, microphone.isActive { sensors.append(.microphone) }
        if preferences.screenRecordingIndicatorEnabled, screenRecording.isActive { sensors.append(.screenRecording) }
        return sensors
    }

    var presentation: IslandPresentation {
        IslandPresentation.resolve(
            isExpanded: isExpanded,
            event: activeEvent,
            timerActive: preferences.timerEnabled && timer.isActive,
            musicActive: preferences.musicEnabled && preferences.musicCompactEnabled && nowPlaying.isRecentlyActive,
            activeSensors: activeSensors,
            pairsActivities: preferences.pairActivities
        )
    }

    var metrics: IslandMetrics {
        IslandMetrics.make(for: presentation, notch: notchSize)
    }

    var availableTabs: [IslandTab] {
        IslandTab.allCases.filter { tab in
            switch tab {
            case .media: preferences.musicEnabled
            case .shelf: preferences.shelfEnabled
            case .clipboard: preferences.clipboardEnabled
            case .timer: preferences.timerEnabled
            }
        }
    }

    // MARK: - 展開／收合

    func expand(tab: IslandTab? = nil) {
        expandTask?.cancel()
        collapseTask?.cancel()
        let tabs = availableTabs
        if let tab = tab ?? activeEvent?.relatedTab, tabs.contains(tab) {
            selectedTab = tab
        } else if !tabs.contains(selectedTab), let first = tabs.first {
            selectedTab = first
        }
        guard !isExpanded else { return }
        if preferences.shelfEnabled {
            shelf.pruneMissing()
        }
        resetClipboardWheel()
        // 展開時就算看過目前的事件了
        eventTask?.cancel()
        activeEvent = nil
        isExpanded = true
        logger.debug("expand tab=\(self.selectedTab.rawValue, privacy: .public)")
        if preferences.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    func collapse() {
        expandTask?.cancel()
        collapseTask?.cancel()
        isFileDragHovering = false
        guard isExpanded else { return }
        isExpanded = false
        logger.debug("collapse")
        scheduleNextEvent()
    }

    /// 點一下島：事件顯示中就關掉事件，否則展開。
    func handleTap() {
        if activeEvent != nil {
            dismissActiveEvent()
        } else if !isExpanded {
            expand()
        }
    }

    // MARK: - 事件

    func post(_ event: IslandEvent) {
        guard geometry != nil else { return }
        if event.isTransient {
            // 音量這種只在當下有意義：島在顯示別的東西就不排隊，直接略過
            guard !isExpanded, activeEvent == nil || activeEvent?.category == event.category else { return }
            present(event)
            return
        }
        pendingEvents.removeAll { $0.category == event.category }
        if let active = activeEvent, active.category == event.category {
            present(event)
        } else {
            pendingEvents.append(event)
            showNextEventIfPossible()
        }
    }

    func dismissActiveEvent() {
        eventTask?.cancel()
        guard activeEvent != nil else { return }
        activeEvent = nil
        scheduleNextEvent()
    }

    private func showNextEventIfPossible() {
        guard activeEvent == nil, !isExpanded, !pendingEvents.isEmpty else { return }
        present(pendingEvents.removeFirst())
    }

    private func present(_ event: IslandEvent) {
        activeEvent = event
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(event.duration))
            guard !Task.isCancelled, let self, self.activeEvent?.id == event.id else { return }
            self.activeEvent = nil
            self.scheduleNextEvent()
        }
    }

    /// 等收合動畫跑完再顯示下一個事件。
    private func scheduleNextEvent() {
        guard !pendingEvents.isEmpty else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            self?.showNextEventIfPossible()
        }
    }

    // MARK: - 游標

    /// 游標在島的 frame 內時，面板才接收滑鼠事件。
    func acceptsMouse(at point: CGPoint) -> Bool {
        guard let geometry else { return false }
        return geometry.islandRect(size: metrics.frameSize).contains(point)
    }

    func handlePointer(_ kind: MouseTracker.Kind, at point: CGPoint) {
        guard let geometry else { return }
        let inside = hoverRect(in: geometry).contains(point)
        switch kind {
        case .down:
            isPointerDown = true
            dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
        case .dragged:
            if preferences.shelfEnabled, !isDraggingOutOfShelf, isFileDragInProgress() {
                // 拖檔案時靠近瀏海就展開，不用碰到螢幕最頂端（那裡會觸發系統的指揮中心）
                let target = isExpanded ? inside : Self.fileDragTriggerRect(around: geometry.islandRect(size: metrics.frameSize)).contains(point)
                if target {
                    beginFileDragHover()
                } else {
                    endFileDragHover()
                }
            }
        case .up:
            isPointerDown = false
            isDraggingOutOfShelf = false
            endFileDragHover()
            // 放開滑鼠時游標已經在島上（例如拖曳經過），補一次停留展開
            if inside, pointerInside {
                scheduleExpand()
            }
        case .moved:
            break
        }
        updatePointer(inside: inside)
    }

    /// 拖著檔案時，收合的島周圍多大的範圍就要展開：左右各 120pt、往下 90pt。
    static func fileDragTriggerRect(around islandRect: CGRect) -> CGRect {
        let extended = islandRect.insetBy(dx: -120, dy: 0)
        return CGRect(x: extended.minX, y: extended.minY - 90, width: extended.width, height: extended.height + 90)
    }

    /// 觸發展開的範圍：比島本身大一點，展開後再多留一些邊距，避免邊緣抖動。
    private func hoverRect(in geometry: NotchGeometry) -> CGRect {
        let rect = geometry.islandRect(size: metrics.frameSize)
        return isExpanded ? rect.insetBy(dx: -12, dy: -14) : rect.insetBy(dx: -10, dy: -6)
    }

    private func updatePointer(inside: Bool) {
        guard inside != pointerInside else { return }
        pointerInside = inside
        if inside {
            collapseTask?.cancel()
            scheduleExpand()
        } else {
            expandTask?.cancel()
            scheduleCollapse()
        }
    }

    private func scheduleExpand() {
        // 拖曳視窗或選取文字經過瀏海時不要展開
        guard !isExpanded, !isPointerDown, preferences.expandMode == .hover else { return }
        let delay = preferences.hoverDelay
        expandTask?.cancel()
        expandTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.pointerInside else { return }
            self.expand()
        }
    }

    private func scheduleCollapse() {
        guard isExpanded else { return }
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            guard !self.pointerInside, !self.isMenuTracking, !self.isFileDragHovering else { return }
            self.collapse()
        }
    }

    // MARK: - 滑動切歌

    /// 切歌時內容滑出去的距離（不滑出畫面，避免整塊變黑）。
    static let swipeExitDistance: CGFloat = 110

    /// 播放器內容的不透明度：滑得越遠越淡，但最淡也保留 35%。
    var swipeOpacity: Double {
        1 - min(abs(swipeOffset) / Self.swipeExitDistance, 1) * 0.65
    }

    /// 觸控板在島上左右滑：收合的音樂膠囊，或展開後的音樂分頁。
    /// 剪貼簿分頁則是上下滑動轉滾輪。
    func handleScroll(_ sample: ScrollSample, at point: CGPoint) {
        if isExpanded, selectedTab == .clipboard {
            if acceptsMouse(at: point) { scrollClipboardWheel(sample) }
            return
        }
        guard preferences.musicEnabled, nowPlaying.info != nil, acceptsMouse(at: point) else {
            cancelSwipeTracking()
            return
        }
        switch presentation {
        case .idle:
            break
        case .compact(let activity) where activity.includesNowPlaying:
            break
        case .expanded where selectedTab == .media:
            break
        default:
            cancelSwipeTracking()
            return
        }
        guard !isSwipeTransitioning, let update = swipeTracker.feed(sample) else { return }
        switch update {
        case .tracking(let offset):
            // 跟著手指走（不加動畫，才會跟手）
            swipeOffset = SwipeTracker.rubberBand(offset)
        case .commit(let direction):
            commitSwipe(direction)
        case .cancel:
            // 沒滑到門檻：彈回原位，表示沒有切歌
            withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
                swipeOffset = 0
            }
        }
    }

    private func cancelSwipeTracking() {
        swipeTracker.reset()
        guard swipeOffset != 0, !isSwipeTransitioning else { return }
        withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
            swipeOffset = 0
        }
    }

    /// 往滑動方向滑出一段 → 切歌 → 馬上從另一側滑回來（約半秒，不等新歌資訊；
    /// 新歌的歌名與封面到了會在原地淡入淡出換上）。
    private func commitSwipe(_ direction: SwipeTracker.Direction) {
        isSwipeTransitioning = true
        let exit = direction == .next ? -Self.swipeExitDistance : Self.swipeExitDistance
        withAnimation(.easeIn(duration: 0.14)) {
            swipeOffset = exit
        }
        switch direction {
        case .next: nowPlaying.nextTrack()
        case .previous: nowPlaying.previousTrack()
        }
        if preferences.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self else { return }
            // 瞬間移到另一側，再滑進來
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.swipeOffset = -exit
            }
            withAnimation(.spring(duration: 0.38, bounce: 0.15)) {
                self.swipeOffset = 0
            }
            try? await Task.sleep(for: .milliseconds(300))
            self.isSwipeTransitioning = false
        }
    }

    // MARK: - 剪貼簿滾輪

    var selectedClipboardItem: ClipboardModel.Item? {
        let items = clipboard.items
        return items.isEmpty ? nil : items[clipboardWheel.index(count: items.count)]
    }

    private func scrollClipboardWheel(_ sample: ScrollSample) {
        let count = clipboard.items.count
        let before = clipboardWheel.index(count: count)
        wheelSnapTask?.cancel()
        if clipboardWheel.feed(sample, count: count, speed: preferences.clipboardWheelSpeed) {
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) { clipboardWheel.snap(count: count) }
        } else if sample.isMomentum || sample.phase == .ended || sample.phase == .none {
            // 手指放開（或慣性捲動停了）一下子就對齊；手指還放著時不對齊
            wheelSnapTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, let self else { return }
                withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
                    self.clipboardWheel.snap(count: self.clipboard.items.count)
                }
            }
        }
        if clipboardWheel.index(count: count) != before {
            clipboardSelectedID = selectedClipboardItem?.id
            // 每跳一列輕震一下，像轉盤的刻度
            if preferences.hapticFeedback {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
    }

    func selectClipboardItem(at index: Int) {
        let count = clipboard.items.count
        withAnimation(.spring(duration: 0.4, bounce: 0.2)) { clipboardWheel.select(index, count: count) }
        clipboardSelectedID = selectedClipboardItem?.id
    }

    /// 展開剪貼簿分頁時接收鍵盤（↑ ↓ 選擇、Return 複製、Esc 收合）。
    var wantsKeyboard: Bool {
        isExpanded && selectedTab == .clipboard && !clipboard.items.isEmpty
    }

    /// 按鍵處理完就回傳 true（不要再傳給別人）。
    func handleKey(_ key: IslandKey) -> Bool {
        guard wantsKeyboard else { return false }
        let index = clipboardWheel.index(count: clipboard.items.count)
        switch key {
        case .up: selectClipboardItem(at: index - 1)
        case .down: selectClipboardItem(at: index + 1)
        case .return:
            if let item = selectedClipboardItem { clipboard.copy(item) }
        case .escape: collapse()
        }
        return true
    }

    /// 紀錄變了（新的拷貝、從紀錄拷貝後移到最前面、移除）：滾輪轉到原本選的那筆。
    func clipboardItemsChanged() {
        let items = clipboard.items
        if let id = clipboardSelectedID, let index = items.firstIndex(where: { $0.id == id }) {
            selectClipboardItem(at: index)
        } else {
            selectClipboardItem(at: clipboardWheel.index(count: items.count))
        }
    }

    /// 每次展開都從最新的一筆開始（切換分頁不重設）。
    func resetClipboardWheel() {
        wheelSnapTask?.cancel()
        clipboardWheel.select(0, count: clipboard.items.count)
        clipboardSelectedID = clipboard.items.first?.id
    }

    // MARK: - 拖曳檔案

    func beginShelfDragOut() {
        isDraggingOutOfShelf = true
    }

    /// 這次按下滑鼠之後有新的拖曳內容，而且裡面有檔案。
    private func isFileDragInProgress() -> Bool {
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragChangeCountAtMouseDown else { return false }
        return pasteboard.types?.contains(.fileURL) ?? false
    }

    private func beginFileDragHover() {
        guard !isFileDragHovering else { return }
        isFileDragHovering = true
        expand(tab: .shelf)
    }

    private func endFileDragHover() {
        guard isFileDragHovering else { return }
        isFileDragHovering = false
        if !pointerInside {
            scheduleCollapse()
        }
    }

    #if DEBUG
    /// 快照用：直接顯示拖曳檔案時的投放區。
    func debugShowDropZones() {
        isFileDragHovering = true
        expand(tab: .shelf)
    }
    #endif

    // MARK: - 右鍵選單開著時不要收合

    private func observeMenuTracking() {
        let center = NotificationCenter.default
        menuObservers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isMenuTracking = true }
        })
        menuObservers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isMenuTracking = false
                if !self.pointerInside {
                    self.scheduleCollapse()
                }
            }
        })
    }
}
