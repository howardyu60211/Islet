import Foundation
import os

/// 全系統「正在播放」：透過 vendored mediaremote-adapter，由 Apple 簽章的 /usr/bin/perl 讀取 MediaRemote。
/// 任何 App 都支援（含瀏覽器裡的 YouTube），但這是繞道私有框架的做法，未來 macOS 可能失效。
final class MediaRemoteAdapterProvider: NowPlayingProvider {
    struct Resources {
        let script: URL
        let framework: URL
        let testClient: URL?

        /// App bundle 裡的 adapter；直接用 `swift run` 執行時不存在。
        static var bundled: Resources? {
            let bundle = Bundle.main
            guard let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
                  let frameworks = bundle.privateFrameworksURL
            else { return nil }
            let framework = frameworks.appendingPathComponent("MediaRemoteAdapter.framework")
            guard FileManager.default.fileExists(atPath: framework.path) else { return nil }
            let testClient = bundle.bundleURL.appendingPathComponent("Contents/Helpers/MediaRemoteAdapterTestClient")
            return Resources(
                script: script,
                framework: framework,
                testClient: FileManager.default.isExecutableFile(atPath: testClient.path) ? testClient : nil
            )
        }
    }

    static let perl = URL(fileURLWithPath: "/usr/bin/perl")

    var onUpdate: (NowPlayingInfo?) -> Void = { _ in }
    /// stream 一直中斷時呼叫，讓上層改用退回模式。
    var onFailure: () -> Void = {}

    private let resources: Resources
    private var process: Process?
    private var outputReader: PipeLineReader?
    private var errorReader: PipeLineReader?
    /// 每次啟動 stream 加一，忽略舊 stream 遲到的回呼。
    private var generation = 0
    private var state = AdapterStreamState()
    private var isActive = false
    private var recentFailures: [Date] = []
    private let logger = Logger(subsystem: "com.howardyu.Islet", category: "NowPlaying")

    init(resources: Resources) {
        self.resources = resources
    }

    /// 結束這個 App bundle 之前留下的 adapter 程序（App 當機或被強制結束時，子程序不會跟著結束）。
    static func terminateOrphans(_ resources: Resources) async {
        _ = await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/pkill"),
            arguments: ["-f", resources.script.path],
            timeout: .seconds(3)
        )
    }

    /// 用 adapter 的 `test` 指令確認這版 macOS 還讀得到「正在播放」。
    static func isFunctional(_ resources: Resources) async -> Bool {
        var arguments = [resources.script.path, resources.framework.path]
        if let testClient = resources.testClient {
            arguments.append(testClient.path)
        }
        arguments.append("test")
        return await ProcessRunner.run(perl, arguments: arguments, timeout: .seconds(10)) == 0
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        launchStream()
    }

    func stop() {
        isActive = false
        generation += 1
        outputReader?.stop()
        errorReader?.stop()
        process?.terminate()
        process = nil
    }

    func send(_ command: MediaCommand) {
        let id = switch command {
        case .play: 0
        case .pause: 1
        case .togglePlayPause: 2
        case .nextTrack: 4
        case .previousTrack: 5
        }
        runOnce(["send", String(id)])
    }

    func seek(to seconds: TimeInterval) {
        runOnce(["seek", String(Int64(max(0, seconds) * 1_000_000))])
    }

    func setShuffle(mode: Int) {
        runOnce(["shuffle", String(mode)])
    }

    func setRepeat(mode: Int) {
        runOnce(["repeat", String(mode)])
    }

    private func runOnce(_ arguments: [String]) {
        let fullArguments = [resources.script.path, resources.framework.path] + arguments
        Task {
            _ = await ProcessRunner.run(Self.perl, arguments: fullArguments, timeout: .seconds(5))
        }
    }

    private func launchStream() {
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = [resources.script.path, resources.framework.path, "stream", "--micros"]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            logger.error("無法啟動 adapter：\(error.localizedDescription, privacy: .public)")
            streamEnded()
            return
        }
        self.process = process
        state = AdapterStreamState()
        logger.info("adapter stream 已啟動 pid=\(process.processIdentifier, privacy: .public)")

        generation += 1
        let current = generation
        let outputReader = PipeLineReader(handle: output.fileHandleForReading)
        outputReader.start { [weak self] line in
            guard let self, self.generation == current else { return }
            self.handle(line: line)
        } onEnd: { [weak self] in
            guard let self, self.generation == current else { return }
            self.streamEnded()
        }
        let errorReader = PipeLineReader(handle: errors.fileHandleForReading)
        errorReader.start { [weak self] line in
            self?.logger.info("adapter: \(line, privacy: .public)")
        } onEnd: {}
        self.outputReader = outputReader
        self.errorReader = errorReader
    }

    private func handle(line: String) {
        guard state.apply(line: line) else { return }
        onUpdate(state.info)
    }

    /// stream 結束（不是我們停掉的）：短時間內重試，太常失敗就交給退回模式。
    private func streamEnded() {
        process = nil
        guard isActive else { return }
        onUpdate(nil)
        let now = Date()
        recentFailures = recentFailures.filter { now.timeIntervalSince($0) < 60 } + [now]
        if recentFailures.count >= 4 {
            logger.error("adapter stream 一直中斷，改用 Music／Spotify 模式")
            isActive = false
            onFailure()
            return
        }
        let delay = Double(recentFailures.count)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.isActive, self.process == nil else { return }
            self.launchStream()
        }
    }
}
