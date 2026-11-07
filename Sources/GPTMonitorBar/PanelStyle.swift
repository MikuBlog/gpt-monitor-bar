import AppKit
import QuotaCore
import SwiftUI

enum PanelStyle {
    static func accent(for level: BadgeLevel = .healthy, in scheme: ColorScheme) -> Color {
        switch (level, scheme) {
        case (.healthy, .dark): Color(red: 0.38, green: 0.84, blue: 0.73)
        case (.healthy, _): Color(red: 0.03, green: 0.43, blue: 0.35)
        case (.caution, .dark): Color(red: 0.94, green: 0.72, blue: 0.38)
        case (.caution, _): Color(red: 0.58, green: 0.36, blue: 0.08)
        case (.low, .dark): Color(red: 1, green: 0.54, blue: 0.51)
        case (.low, _): Color(red: 0.73, green: 0.23, blue: 0.23)
        case (.unknown, _): .secondary
        }
    }
}

struct BrandMark: View {
    var size: CGFloat

    private static let image: NSImage? = {
        let resource = Bundle.main.url(forResource: "ChatGPTMark", withExtension: "png")
            ?? Bundle.module.url(forResource: "ChatGPTMark", withExtension: "png")
        return resource.flatMap(NSImage.init(contentsOf:))
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "sparkle")
                    .resizable().scaledToFit().padding(size * 0.15)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct PanelBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if scheme == .dark {
            // An opaque graphite base keeps light desktop surfaces from washing out dark mode.
            Color(white: 36.0 / 255)
        } else if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            Rectangle().fill(.regularMaterial)
        }
    }
}

private struct QuotaSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor)
                        .opacity(reduceTransparency ? 1 : scheme == .dark ? 0.52 : 0.72))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.primary.opacity(scheme == .dark ? 0.09 : 0.06), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func quotaSurface() -> some View { modifier(QuotaSurface()) }
}

struct QuietButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 10
    var restingOpacity: Double = 0.035
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.primary.opacity(configuration.isPressed ? 0.10 : isHovered && isEnabled ? 0.065 : restingOpacity))
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isHovered)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
