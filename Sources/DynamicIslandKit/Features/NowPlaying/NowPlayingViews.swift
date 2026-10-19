import SwiftUI

// MARK: - 展開後的播放器

struct MediaPlayerView: View {
    let model: NowPlayingModel

    var body: some View {
        if let info = model.info {
            HStack(alignment: .center, spacing: 18) {
                Button {
                    model.openSourceApp()
                } label: {
                    ArtworkView(model: model, size: 96, cornerRadius: 16, showsSourceBadge: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打開播放的 App")

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(info.title)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                            Text(subtitle(for: info))
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                        // 換歌時歌名在原地淡入淡出
                        .id(info.trackKey)
                        .transition(.opacity)
                        .animation(.smooth(duration: 0.3), value: info.trackKey)
                        Spacer(minLength: 0)
                        AudioVisualizer(isPlaying: info.isPlaying, color: model.accentColor, maxHeight: 18)
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 8)
                    if info.duration != nil {
                        PlaybackProgressBar(model: model)
                        Spacer(minLength: 4)
                    }
                    PlaybackControls(model: model, info: info)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: 104)
            }
            .foregroundStyle(.white)
        } else {
            EmptyMediaView(backend: model.backend)
        }
    }

    private func subtitle(for info: NowPlayingInfo) -> String {
        [info.artist, info.album].filter { !$0.isEmpty }.joined(separator: " — ")
    }
}

private struct EmptyMediaView: View {
    let backend: NowPlayingModel.Backend

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
            Text("目前沒有播放")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Text("來源：\(backend.title)")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

struct ArtworkView: View {
    let model: NowPlayingModel
    let size: CGFloat
    let cornerRadius: CGFloat
    var showsSourceBadge = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                if let artwork = model.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        // 換封面時淡入淡出
                        .id(ObjectIdentifier(artwork))
                        .transition(.opacity)
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [Color(white: 0.28), Color(white: 0.14)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(.smooth(duration: 0.3), value: model.artwork.map(ObjectIdentifier.init))

            if showsSourceBadge, let icon = model.sourceAppIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: size * 0.32, height: size * 0.32)
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .offset(x: size * 0.08, y: size * 0.08)
            }
        }
    }
}

/// 可以拖曳跳轉的進度條。
private struct PlaybackProgressBar: View {
    let model: NowPlayingModel

    @ViewState private var scrubFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = model.info?.duration ?? 0
            let elapsed = model.info?.elapsed(at: context.date) ?? 0
            let shown = scrubFraction.map { $0 * duration } ?? elapsed
            let fraction = duration > 0 ? min(max(shown / duration, 0), 1) : 0

            VStack(spacing: 5) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule()
                            .fill(.white.opacity(scrubFraction == nil ? 0.85 : 1))
                            .frame(width: max(0, geometry.size.width * fraction))
                    }
                    .frame(height: scrubFraction == nil ? 4 : 7)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                scrubFraction = clamp(value.location.x / geometry.size.width)
                            }
                            .onEnded { value in
                                model.seek(to: clamp(value.location.x / geometry.size.width) * duration)
                                scrubFraction = nil
                            }
                    )
                    .animation(.smooth(duration: 0.15), value: scrubFraction == nil)
                }
                .frame(height: 10)

                HStack {
                    Text(formatTime(shown))
                    Spacer()
                    Text("-" + formatTime(max(0, duration - shown)))
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private func clamp(_ value: CGFloat) -> Double {
        Double(min(max(value, 0), 1))
    }
}

/// 左邊：隨機／重複（播放器支援才顯示）；中間：倒轉 15 秒、上一首、播放、下一首、快轉 15 秒；右邊：輸出裝置。
private struct PlaybackControls: View {
    let model: NowPlayingModel
    let info: NowPlayingInfo

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                if let shuffle = info.shuffleMode {
                    ModeButton(symbol: "shuffle", isOn: shuffle != 1, tint: model.accentColor, label: "隨機播放") {
                        model.toggleShuffle()
                    }
                }
                if let repeatMode = info.repeatMode {
                    ModeButton(
                        symbol: repeatMode == 2 ? "repeat.1" : "repeat",
                        isOn: repeatMode != 1,
                        tint: model.accentColor,
                        label: "重複播放"
                    ) {
                        model.cycleRepeat()
                    }
                }
            }
            .frame(width: 64, alignment: .leading)

            Spacer(minLength: 0)
            HStack(spacing: 14) {
                if info.duration != nil {
                    ControlButton(symbol: "gobackward.15", size: 14, label: "倒轉 15 秒") { model.skip(by: -15) }
                }
                ControlButton(symbol: "backward.fill", size: 15, label: "上一首") { model.previousTrack() }
                ControlButton(symbol: info.isPlaying ? "pause.fill" : "play.fill", size: 22, label: info.isPlaying ? "暫停" : "播放") {
                    model.togglePlayPause()
                }
                ControlButton(symbol: "forward.fill", size: 15, label: "下一首") { model.nextTrack() }
                if info.duration != nil {
                    ControlButton(symbol: "goforward.15", size: 14, label: "快轉 15 秒") { model.skip(by: 15) }
                }
            }
            Spacer(minLength: 0)

            OutputDeviceMenu(outputs: model.outputs)
                .frame(width: 64, alignment: .trailing)
        }
    }
}

/// 隨機／重複這種開關按鈕：開的時候用封面主色。
private struct ModeButton: View {
    let symbol: String
    let isOn: Bool
    let tint: Color
    let label: String
    let action: () -> Void

    @ViewState private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isOn ? tint : .white.opacity(isHovering ? 0.8 : 0.45))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(isHovering ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "開" : "關")
    }
}

/// 聲音輸出裝置選單（MacBook 喇叭、AirPods、外接喇叭…）。
private struct OutputDeviceMenu: View {
    let outputs: AudioOutputModel

    @ViewState private var isHovering = false

    var body: some View {
        let icon = Image(systemName: outputs.current?.symbolName ?? "speaker.wave.2.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(isHovering ? 0.95 : 0.6))
            .frame(width: 30, height: 26)
            .background(Capsule().fill(.white.opacity(isHovering ? 0.1 : 0)))
            .contentShape(Capsule())

        if RenderingContext.isSnapshot {
            icon
        } else {
            Menu {
                Section("輸出裝置") {
                    ForEach(outputs.devices) { device in
                        Button {
                            outputs.select(device)
                        } label: {
                            if device.id == outputs.currentID {
                                Label(device.name, systemImage: "checkmark")
                            } else {
                                Text(device.name)
                            }
                        }
                    }
                }
            } label: {
                icon
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .onHover { isHovering = $0 }
            .accessibilityLabel("輸出裝置：\(outputs.current?.name ?? "未知")")
        }
    }
}

private struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let label: String
    let action: () -> Void

    @ViewState private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size + 18, height: size + 12)
                .background(Circle().fill(.white.opacity(isHovering ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(label)
    }
}

func formatTime(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded(.down))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, secs)
        : String(format: "%d:%02d", minutes, secs)
}

// MARK: - 收合時

struct NowPlayingCompactLeading: View {
    let model: NowPlayingModel

    var body: some View {
        ArtworkView(model: model, size: 22, cornerRadius: 6)
    }
}

struct NowPlayingCompactTrailing: View {
    let model: NowPlayingModel

    var body: some View {
        AudioVisualizer(isPlaying: model.info?.isPlaying ?? false, color: model.accentColor, maxHeight: 16)
    }
}

