import SwiftUI

/// 展開後頂部條右側的電量。
struct BatteryIndicator: View {
    let battery: BatteryMonitor

    var body: some View {
        if let state = battery.state {
            HStack(spacing: 5) {
                Text("\(state.level)%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
                BatteryGlyph(level: state.level, isCharging: state.isCharging, tint: tint(for: state))
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func tint(for state: BatteryState) -> Color {
        if state.isCharging || state.isPluggedIn { return .green }
        if battery.isLowPowerMode { return .yellow }
        if state.level <= 20 { return .red }
        return .white
    }
}
