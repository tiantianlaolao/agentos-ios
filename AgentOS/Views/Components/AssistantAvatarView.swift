import SwiftUI

enum AvatarState: String {
    case idle, thinking, happy, proactive
}

struct AssistantAvatarView: View {
    enum Size {
        case small   // 32pt - chat bubbles
        case medium  // 40pt - top bar
        case large   // 64pt - welcome screen

        var dimension: CGFloat {
            switch self {
            case .small: return 32
            case .medium: return 40
            case .large: return 64
            }
        }
    }

    let size: Size
    var state: AvatarState = .idle
    var animated: Bool = true

    // Animation state
    @State private var isBreathing = false
    @State private var isFloating = false
    @State private var ripplePhase: CGFloat = 0
    @State private var bounceOffset: CGFloat = 0
    @State private var currentImage: String = "idle"
    @State private var imageOpacity: Double = 1.0

    private var imageName: String {
        state.rawValue
    }

    // Breathing speed depends on state
    private var breathDuration: Double {
        state == .thinking ? 1.2 : 3.5
    }

    var body: some View {
        ZStack {
            // Ripple layers (behind avatar)
            if animated && size != .small {
                rippleCircle(delay: 0)
                rippleCircle(delay: 1.0)
            }

            // Main avatar
            ZStack {
                // Brand gradient background
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.primary, AppTheme.primaryDark],
                            startPoint: UnitPoint(x: 0.15, y: 0.0),
                            endPoint: UnitPoint(x: 0.85, y: 1.0)
                        )
                    )

                // Character image - cropped to face area
                avatarImage(named: currentImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    // Scale up to fill width, image is 2:3 so height overflows
                    .frame(width: size.dimension * 1.3, height: size.dimension * 1.3 * 1.5)
                    // Offset up to center on face (face is in upper ~35% of image)
                    .offset(y: size.dimension * 0.15)
                    .opacity(imageOpacity)
            }
            .frame(width: size.dimension, height: size.dimension)
            .clipShape(Circle())
            // Breathing animation
            .scaleEffect(isBreathing ? 1.05 : 1.0)
            // Floating animation
            .offset(y: isFloating ? -4 : 0)
            // Bounce for proactive
            .offset(y: bounceOffset)
        }
        .frame(width: size.dimension + (size == .small ? 0 : 16),
               height: size.dimension + (size == .small ? 0 : 16))
        .onAppear {
            currentImage = imageName
            guard animated else { return }
            startAnimations()
        }
        .onChange(of: state) { oldState, newState in
            switchImage(to: newState)
        }
    }

    private func startAnimations() {
        // Breathing
        withAnimation(.easeInOut(duration: breathDuration).repeatForever(autoreverses: true)) {
            isBreathing = true
        }
        // Floating (only for medium/large)
        if size != .small {
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                isFloating = true
            }
        }
    }

    private func switchImage(to newState: AvatarState) {
        // Crossfade: fade out → swap → fade in
        withAnimation(.easeOut(duration: 0.15)) {
            imageOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            currentImage = newState.rawValue
            withAnimation(.easeIn(duration: 0.15)) {
                imageOpacity = 1.0
            }
        }

        // Bounce for proactive
        if newState == .proactive {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                bounceOffset = -8
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    bounceOffset = 0
                }
            }
        }

        // Update breathing speed
        isBreathing = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard animated else { return }
            withAnimation(.easeInOut(duration: breathDuration).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }

    private func avatarImage(named name: String) -> Image {
        if let uiImage = UIImage(named: name) {
            return Image(uiImage: uiImage)
        }
        // Fallback: try loading from bundle Resources/Avatar/
        if let path = Bundle.main.path(forResource: name, ofType: "jpg", inDirectory: "Resources/Avatar"),
           let uiImage = UIImage(contentsOfFile: path) {
            return Image(uiImage: uiImage)
        }
        // Try without subdirectory
        if let path = Bundle.main.path(forResource: name, ofType: "jpg"),
           let uiImage = UIImage(contentsOfFile: path) {
            return Image(uiImage: uiImage)
        }
        // Last resort: system placeholder
        return Image(systemName: "person.circle.fill")
    }

    @ViewBuilder
    private func rippleCircle(delay: Double) -> some View {
        Circle()
            .stroke(Color(hex: "#F4A56A").opacity(0.4), lineWidth: 1.5)
            .frame(width: size.dimension + 12, height: size.dimension + 12)
            .scaleEffect(ripplePhase)
            .opacity(Double(2 - ripplePhase) / 2)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.easeOut(duration: 2.8).repeatForever(autoreverses: false)) {
                        ripplePhase = 2.0
                    }
                }
            }
    }
}

#Preview {
    VStack(spacing: 20) {
        AssistantAvatarView(size: .small, state: .idle)
        AssistantAvatarView(size: .medium, state: .thinking)
        AssistantAvatarView(size: .large, state: .happy)
        AssistantAvatarView(size: .large, state: .proactive)
        AssistantAvatarView(size: .medium, animated: false)
    }
    .padding()
    .background(AppTheme.background)
}
