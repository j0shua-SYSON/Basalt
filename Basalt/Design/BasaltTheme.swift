import SwiftUI

enum BasaltTheme {
    static let lichen = Color(red: 0.40, green: 0.52, blue: 0.37)
    static let copper = Color(red: 0.71, green: 0.38, blue: 0.25)
    static let slate = Color(red: 0.31, green: 0.42, blue: 0.48)
    static let mineral = Color(red: 0.54, green: 0.47, blue: 0.63)
    static let cornerRadius: CGFloat = 18
}

struct MineralCanvas: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            LinearGradient(
                colors: colorScheme == .dark
                    ? [BasaltTheme.slate.opacity(0.16), .clear, BasaltTheme.lichen.opacity(0.08)]
                    : [BasaltTheme.slate.opacity(0.08), .clear, BasaltTheme.lichen.opacity(0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct BasaltCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: BasaltTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BasaltTheme.cornerRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(colorScheme == .dark ? 0.10 : 0.07), lineWidth: 0.5)
            }
    }
}

extension View {
    func basaltCard() -> some View {
        modifier(BasaltCardModifier())
    }
}

struct CapabilityLabel: View {
    let capability: ModelCapability

    private var content: (String, String, Color) {
        switch capability {
        case .reasoning: ("Thinking", "brain.head.profile", BasaltTheme.mineral)
        case .vision: ("Vision", "eye", BasaltTheme.slate)
        case .audio: ("Audio", "waveform", BasaltTheme.copper)
        }
    }

    var body: some View {
        Label(content.0, systemImage: content.1)
            .font(.caption.weight(.semibold))
            .foregroundStyle(content.2)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(content.2.opacity(0.12), in: Capsule())
    }
}

