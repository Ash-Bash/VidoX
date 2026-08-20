import SwiftUI

struct OnboardingPage: Identifiable, Hashable {
    var id: String { title }
    let systemImage: String
    let accent: Color
    let title: String
    let message: String
    var usesAppIcon = false
}

/// First-launch welcome, styled like Apple’s built-in app introductions.
struct OnboardingView: View {
    let onFinished: () -> Void

    @State private var pageIndex = 0
    @State private var goingForward = true

    private var pages: [OnboardingPage] {
        var items: [OnboardingPage] = [
            OnboardingPage(
                systemImage: "play.rectangle.fill",
                accent: Color(red: 0.0, green: 0.48, blue: 1.0),
                title: "Welcome to VidoX",
                message: "Your videos, in one place. Download a link, keep it in your private library, and play it here.",
                usesAppIcon: true
            ),
            OnboardingPage(
                systemImage: "arrow.down.circle.fill",
                accent: Color(red: 0.20, green: 0.78, blue: 0.35),
                title: "Paste a link",
                message: "Drop in YouTube, Instagram, TikTok, and other supported links. VidoX fetches the video into this app — not your Photos library."
            ),
            OnboardingPage(
                systemImage: "film.stack.fill",
                accent: Color(red: 0.0, green: 0.48, blue: 1.0),
                title: "Browse your library",
                message: "Search, switch grid or list, and sort by newest, title, size, or site."
            ),
            OnboardingPage(
                systemImage: "pin.fill",
                accent: Color.orange,
                title: "Pin favourites",
                message: "Pin videos you want close. They appear in Pins, and in the sidebar on iPad, Mac, and larger screens."
            ),
            OnboardingPage(
                systemImage: "square.and.arrow.up",
                accent: Color(red: 0.35, green: 0.34, blue: 0.84),
                title: "Keep or share a copy",
                message: "Downloads stay in VidoX. Save to Photos, share, or export to Files only when you want a copy elsewhere."
            )
        ]
        #if os(iOS) || os(macOS) || os(visionOS)
        items.append(
            OnboardingPage(
                systemImage: "antenna.radiowaves.left.and.right",
                accent: Color(red: 0.10, green: 0.68, blue: 0.98),
                title: "Sync nearby Apple devices",
                message: "No iCloud. When this Mac, iPhone, or iPad is nearby with VidoX open, libraries catch up — including downloads made while you were apart."
            )
        )
        #endif
        items.append(
            OnboardingPage(
                systemImage: "checkmark.circle.fill",
                accent: Color(red: 0.20, green: 0.78, blue: 0.35),
                title: "You’re ready",
                message: "Start with Download, or open the library. You can replay this guide anytime from Settings."
            )
        )
        return items
    }

    private var isLast: Bool { pageIndex >= pages.count - 1 }
    private var page: OnboardingPage { pages[pageIndex] }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if pageIndex > 0 {
                    glassCircleButton(systemImage: "chevron.left", accessibilityLabel: "Back", action: goBack)
                } else {
                    Color.clear.frame(width: chromeButtonSize, height: chromeButtonSize)
                }
                Spacer()
                if !isLast {
                    glassCircleButton(systemImage: "xmark", accessibilityLabel: "Skip", action: onFinished)
                } else {
                    Color.clear.frame(width: chromeButtonSize, height: chromeButtonSize)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: chromeBarHeight)

            Spacer(minLength: 4)

            VStack(spacing: 16) {
                if page.usesAppIcon {
                    Image("AppIconDisplay")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: page.systemImage)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(page.accent, in: Circle())
                        .accessibilityHidden(true)
                }

                Text(page.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                Text(page.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .id(page.id)
            .transition(
                .asymmetric(
                    insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)
                )
            )

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == pageIndex ? Color.accentColor : Color.primary.opacity(0.18))
                        .frame(width: index == pageIndex ? 16 : 6, height: 6)
                }
            }
            .accessibilityLabel("Page \(pageIndex + 1) of \(pages.count)")
            .padding(.bottom, 14)

            Button {
                advance()
            } label: {
                Text(isLast ? "Get Started" : "Continue")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .animation(.easeInOut(duration: 0.28), value: pageIndex)
        .interactiveDismissDisabled()
    }

    private func advance() {
        if isLast {
            onFinished()
        } else {
            goingForward = true
            withAnimation(.easeInOut(duration: 0.28)) {
                pageIndex += 1
            }
        }
    }

    private var chromeButtonSize: CGFloat {
        #if os(macOS)
        32
        #else
        44
        #endif
    }

    private var chromeIconSize: CGFloat {
        #if os(macOS)
        13
        #else
        17
        #endif
    }

    private var chromeBarHeight: CGFloat {
        #if os(macOS)
        44
        #else
        56
        #endif
    }

    private func glassCircleButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: chromeIconSize, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: chromeButtonSize, height: chromeButtonSize)
                .contentShape(Circle())
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func goBack() {
        guard pageIndex > 0 else { return }
        goingForward = false
        withAnimation(.easeInOut(duration: 0.28)) {
            pageIndex -= 1
        }
    }
}

#Preview("Onboarding") {
    OnboardingView(onFinished: {})
}
