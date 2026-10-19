import AppKit
import SwiftUI

/// 裝飾性的音波條（不是真的頻譜），只有播放中才會動。
///
/// 用 Core Animation 的 keyframe 動畫：動畫在系統的 render server 裡跑，App 自己幾乎不吃 CPU。
/// 如果用 SwiftUI 動畫，整個島每一格都要重新排版、重畫（約 10% CPU）。
struct AudioVisualizer: View {
    let isPlaying: Bool
    let color: Color
    var barCount = 4
    var maxHeight: CGFloat = 16

    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 2.5

    var body: some View {
        Group {
            if RenderingContext.isSnapshot {
                // ImageRenderer 畫不出 NSView，快照時畫靜態的條
                HStack(spacing: spacing) {
                    ForEach(0..<barCount, id: \.self) { index in
                        Capsule()
                            .fill(color)
                            .frame(width: barWidth, height: isPlaying ? maxHeight * [0.55, 0.95, 0.7, 0.4][index % 4] : 3)
                    }
                }
            } else {
                VisualizerBars(
                    isPlaying: isPlaying,
                    color: NSColor(color),
                    barCount: barCount,
                    barWidth: barWidth,
                    spacing: spacing
                )
            }
        }
        .frame(width: CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing, height: maxHeight)
        .accessibilityHidden(true)
    }
}

private struct VisualizerBars: NSViewRepresentable {
    let isPlaying: Bool
    let color: NSColor
    let barCount: Int
    let barWidth: CGFloat
    let spacing: CGFloat

    func makeNSView(context: Context) -> VisualizerBarsView {
        VisualizerBarsView(barCount: barCount, barWidth: barWidth, spacing: spacing)
    }

    func updateNSView(_ view: VisualizerBarsView, context: Context) {
        view.update(color: color, isPlaying: isPlaying)
    }
}

final class VisualizerBarsView: NSView {
    private let bars: [CALayer]
    private let barWidth: CGFloat
    private let spacing: CGFloat
    private var isPlaying = false

    /// 停止時的高度比例。
    private static let restingScale: CGFloat = 0.2
    private static let animationKey = "level"

    init(barCount: Int, barWidth: CGFloat, spacing: CGFloat) {
        self.barWidth = barWidth
        self.spacing = spacing
        bars = (0..<barCount).map { _ in CALayer() }
        super.init(frame: .zero)
        wantsLayer = true
        for bar in bars {
            bar.cornerRadius = barWidth / 2
            bar.transform = CATransform3DMakeScale(1, Self.restingScale, 1)
            layer?.addSublayer(bar)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            // transform 會影響 frame，所以用 bounds + position 擺放（以中心縮放）
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(index) * (barWidth + spacing) + barWidth / 2, y: bounds.midY)
        }
        CATransaction.commit()
    }

    func update(color: NSColor, isPlaying: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bars.forEach { $0.backgroundColor = color.cgColor }
        CATransaction.commit()

        guard isPlaying != self.isPlaying else { return }
        self.isPlaying = isPlaying
        isPlaying ? startAnimating() : stopAnimating()
    }

    private func startAnimating() {
        for (index, bar) in bars.enumerated() {
            let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
            // 每根條用不同的高度序列與長度，看起來比較隨機
            animation.values = (0..<6).map { _ in CGFloat.random(in: 0.25...1) } + [Self.restingScale + 0.15]
            animation.duration = 1.1 + Double(index) * 0.23
            animation.calculationMode = .cubic
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timeOffset = Double.random(in: 0...1)
            bar.add(animation, forKey: Self.animationKey)
        }
    }

    private func stopAnimating() {
        for bar in bars {
            bar.removeAnimation(forKey: Self.animationKey)
        }
    }
}
