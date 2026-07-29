import SwiftUI

@main
struct GameSoundCreatorApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

// MARK: - Launch sequence

/// © → brand logo → title + progress → home.
/// LaunchScreen is a solid color only; © is shown once in SwiftUI to avoid text handoff misalignment.
private struct RootView: View {
    private enum Phase: Equatable {
        case copyright, brandLogo, appTitle, home
    }

    private enum Timing {
        static let copyrightFadeMs = 350
        static let copyrightHoldMs = 2000
        static let crossfadeMs = 400
        static let logoHoldMs = 2000
        static let progressMs = 3200
        static let progressCompleteMs = 180
    }

    @State private var phase: Phase = .copyright
    @State private var copyrightOpacity = 0.0
    @State private var logoOpacity = 0.0
    @State private var titleOpacity = 0.0
    @State private var loadProgress = 0.0
    @State private var showProgress = false

    private let accent = Color(red: 0.91, green: 0.66, blue: 0.22)
    private let background = Color(red: 0.06, green: 0.05, blue: 0.05)
    private let primaryText = Color(red: 0.96, green: 0.93, blue: 0.86)
    private let secondaryText = Color(red: 0.70, green: 0.64, blue: 0.52)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            Text("© ChatNoir Studio")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.72))
                .opacity(copyrightOpacity)
                .accessibilityLabel("ChatNoir Studio")
                .accessibilityHidden(copyrightOpacity < 0.1)

            Image("ChatNoirStudioLogo")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .opacity(logoOpacity)
                .accessibilityLabel("ChatNoir Studio")
                .accessibilityHidden(logoOpacity < 0.1)

            if titleOpacity > 0 {
                titleView.opacity(titleOpacity)
            }

            if phase == .home {
                ContentView()
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .task { await runLaunchSequence() }
    }

    private var titleView: some View {
        ZStack {
            VStack(spacing: 14) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array([10, 18, 12, 22, 14].enumerated()), id: \.offset) { index, height in
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(accent.opacity(0.95 - Double(index) * 0.08))
                            .frame(width: 4, height: CGFloat(height))
                    }
                }
                .frame(height: 24)
                .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("レトロゲーム")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .tracking(6)
                        .foregroundStyle(accent)
                    Text("サウンドクリエイター")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(primaryText)
                }
                .multilineTextAlignment(.center)

                Capsule(style: .continuous)
                    .fill(accent.opacity(0.7))
                    .frame(width: 56, height: 2)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("レトロゲーム サウンドクリエイター")

            if showProgress {
                VStack {
                    Spacer()
                    progressBar
                        .padding(.horizontal, 48)
                        .padding(.bottom, 56)
                }
            }
        }
    }

    private var progressBar: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(accent.opacity(0.18))
                    Capsule(style: .continuous)
                        .fill(accent)
                        .frame(width: max(8, geo.size.width * loadProgress))
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)

            Text("読み込み中…")
                .font(.caption.weight(.medium))
                .foregroundStyle(secondaryText)
        }
    }

    @MainActor
    private func runLaunchSequence() async {
        await Task.yield()
        let warmup = Task { await LaunchWarmup.run() }

        withAnimation(.easeIn(duration: Double(Timing.copyrightFadeMs) / 1000)) {
            copyrightOpacity = 1
        }
        await sleep(Timing.copyrightFadeMs + Timing.copyrightHoldMs)

        phase = .brandLogo
        withAnimation(.easeInOut(duration: Double(Timing.crossfadeMs) / 1000)) {
            copyrightOpacity = 0
            logoOpacity = 1
        }
        await sleep(Timing.crossfadeMs + Timing.logoHoldMs)

        phase = .appTitle
        loadProgress = 0
        showProgress = false
        withAnimation(.easeInOut(duration: Double(Timing.crossfadeMs) / 1000)) {
            logoOpacity = 0
            titleOpacity = 1
        }
        await sleep(Timing.crossfadeMs)

        showProgress = true
        loadProgress = 0
        let progress = Task { await animateProgress(to: 0.92, overMilliseconds: Timing.progressMs) }
        await warmup.value
        await progress.value

        withAnimation(.easeOut(duration: 0.2)) {
            loadProgress = 1
        }
        await sleep(Timing.progressCompleteMs)

        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .home
            titleOpacity = 0
        }
    }

    @MainActor
    private func animateProgress(to target: Double, overMilliseconds totalMs: Int) async {
        let steps = 32
        let stepMs = max(1, totalMs / steps)
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            loadProgress = target * (1 - pow(1 - t, 2))
            await sleep(stepMs)
        }
    }

    @MainActor
    private func sleep(_ milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}
