import SwiftUI

struct TokenStrataView: View {
    var isActive = false
    var compact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30)) { timeline in
            Canvas { context, size in
                let t = isActive && !reduceMotion
                    ? timeline.date.timeIntervalSinceReferenceDate
                    : 0
                let layers = compact ? 5 : 8
                let layerHeight = size.height / CGFloat(layers + 1)

                for index in 0..<layers {
                    let progress = CGFloat(index) / CGFloat(max(1, layers - 1))
                    let phase = t * (0.55 + Double(progress) * 0.25) + Double(index) * 0.7
                    let lift = CGFloat(sin(phase)) * (isActive ? 4.5 : 1.4)
                    let inset = CGFloat(index % 3) * size.width * 0.025
                    let rect = CGRect(
                        x: inset,
                        y: CGFloat(index + 1) * layerHeight + lift,
                        width: size.width - inset * 2,
                        height: max(3, layerHeight * 0.45)
                    )
                    let color: Color = index.isMultiple(of: 3)
                        ? BasaltTheme.lichen
                        : (index.isMultiple(of: 2) ? BasaltTheme.slate : BasaltTheme.mineral)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: rect.height / 2),
                        with: .color(color.opacity(0.18 + (1 - progress) * 0.22))
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

