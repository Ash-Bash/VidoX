import SwiftUI

struct PlatformBadge: View {
    let platform: VideoPlatform

    var body: some View {
        Label(platform.displayName, systemImage: platform.iconName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(badgeForeground)
            .background(badgeBackground, in: Capsule())
    }

    private var badgeForeground: Color {
        switch platform {
        case .twitter, .unknown, .web:
            .primary
        default:
            .white
        }
    }

    private var badgeBackground: AnyShapeStyle {
        switch platform {
        case .twitter, .web:
            AnyShapeStyle(Color.primary.opacity(0.12))
        case .unknown:
            AnyShapeStyle(Color.secondary.opacity(0.18))
        default:
            AnyShapeStyle(platform.accentColor.gradient)
        }
    }
}
