import AudioGenCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @AppStorage("appThemeID") private var themeIDRaw = AppThemeID.lime.rawValue
    /// Concrete theme used while preference is 「ランダム」.
    @AppStorage("appThemeRandomPick") private var themeRandomPick = AppThemeID.lime.rawValue
    @State private var selectedTab = 0
    @State private var didRollRandomThisLaunch = false

    private var theme: AppTheme {
        AppTheme.resolved(
            AppThemeID.resolveStored(themeIDRaw),
            randomPickRaw: themeRandomPick
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
            .tabItem { Label("ホーム", systemImage: "house.fill") }
            .tag(0)

            NavigationStack {
                LibraryView()
            }
            .tabItem { Label("ライブラリ", systemImage: "books.vertical.fill") }
            .tag(1)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("設定", systemImage: "gearshape.fill") }
            .tag(2)
        }
        .environment(\.appTheme, theme)
        .tint(theme.accent)
        .preferredColorScheme(theme.colorScheme)
        .onChange(of: selectedTab) { _, _ in
            stopAllPlayback()
        }
        .onAppear {
            migrateLegacyThemeIDIfNeeded()
            rollRandomThemeIfNeeded()
        }
    }

    private func migrateLegacyThemeIDIfNeeded() {
        let resolved = AppThemeID.resolveStored(themeIDRaw)
        if themeIDRaw != resolved.rawValue {
            themeIDRaw = resolved.rawValue
        }
        let pick = AppThemeID.resolveStored(themeRandomPick)
        if themeRandomPick != pick.rawValue || !AppThemeID.randomPool.contains(pick) {
            themeRandomPick = AppThemeID.lime.rawValue
        }
    }

    private func rollRandomThemeIfNeeded() {
        guard !didRollRandomThisLaunch else { return }
        didRollRandomThisLaunch = true
        guard AppThemeID.resolveStored(themeIDRaw) == .random else { return }
        themeRandomPick = AppTheme.rollRandomPick().rawValue
    }
}

@MainActor
func stopAllPlayback() {
    GenerationService.shared.stop()
}

@MainActor
func hapticLight() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
}

@MainActor
func hapticMedium() {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
}

// MARK: - Shared UI

private struct CreateCard: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let systemImage: String
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(theme.accent)
                .frame(width: 44, height: 44)
                .background(theme.accent.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.primaryText)
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryText.opacity(0.7))
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// Isolated so StudioView (and its menu pickers) are not redrawn on every progress tick.
private struct StudioPlaybackProgress: View {
    @Environment(\.appTheme) private var theme
    @Bindable var monitor: PlaybackMonitor

    var body: some View {
        VStack(spacing: 8) {
            ProgressView(value: monitor.progress)
                .tint(theme.accent)
            HStack {
                Text(monitor.currentTimeText)
                Spacer()
                Text(monitor.durationText)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(theme.secondaryText)
        }
    }
}

/// Idle = outlined (same as Stop). Playing = filled accent.
private struct PlayButtonChrome: ViewModifier {
    @Environment(\.appTheme) private var theme
    let isPlaying: Bool

    func body(content: Content) -> some View {
        if isPlaying {
            content
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
        } else {
            content
                .buttonStyle(.bordered)
                .tint(theme.accent)
        }
    }
}

// MARK: - Home

private struct CreateDestination: Hashable {
    let soundType: SoundType
}

struct HomeView: View {
    @Environment(\.appTheme) private var theme
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    HomeHeroTitle()
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 12, trailing: 16))
                }

                Section {
                    createRow(
                        type: .bgm,
                        title: "BGMスタジオ",
                        systemImage: "music.note.list"
                    )
                    createRow(
                        type: .sfx,
                        title: "効果音スタジオ",
                        systemImage: "waveform"
                    )
                }
                .themedListRowBackground(theme)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .themedListBackground(theme)
            .navigationDestination(for: CreateDestination.self) { dest in
                StudioView(soundType: dest.soundType)
            }
        }
    }

    private func createRow(
        type: SoundType,
        title: String,
        systemImage: String
    ) -> some View {
        NavigationLink(value: CreateDestination(soundType: type)) {
            CreateCard(title: title, systemImage: systemImage, showsChevron: false)
        }
    }
}
/// Home brand lockup — accent-led, lightly animated, theme-aware.
private struct HomeHeroTitle: View {
    @Environment(\.appTheme) private var theme
    @State private var appeared = false

    private let barHeights: [CGFloat] = [10, 18, 12, 22, 14]

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(barHeights.enumerated()), id: \.offset) { index, height in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(theme.accent.opacity(appeared ? 0.95 - Double(index) * 0.08 : 0.25))
                        .frame(width: 4, height: appeared ? height : height * 0.35)
                }
            }
            .frame(height: 24)
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("レトロゲーム")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(theme.accent)

                Text("サウンドクリエイター")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(theme.primaryText)
            }
            .multilineTextAlignment(.center)

            Capsule(style: .continuous)
                .fill(theme.accent.opacity(0.7))
                .frame(width: appeared ? 56 : 16, height: 2)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .opacity(appeared ? 1 : 0.35)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("レトロゲーム サウンドクリエイター")
    }
}

// MARK: - Studio

struct StudioView: View {
    @Environment(\.appTheme) private var theme
    let soundType: SoundType
    private let autoPlay: Bool
    private let initialIntent: SoundIntent?

    @State private var genreId: String
    @State private var sceneGroup = "プレイ中"
    @State private var sceneId = Catalog.BGMScene.battleNormal.rawValue
    @State private var purposeGroup = "バトル"
    @State private var purposeId = Catalog.SFXPurpose.attackLight.rawValue
    /// Default matches SFX studio; BGM overrides via `applyDefaultIfNeeded`.
    @State private var moodId = Catalog.Mood.neutral.rawValue
    @State private var lengthId = Catalog.SFXLength.medium.rawValue
    @State private var instrumentId = Catalog.Instrument.leadSynth.rawValue
    @State private var seed: UInt64 = UInt64.random(in: 1...999_999)

    @State private var mapped: MappedRecipe?
    @State private var catalogDirty = true
    @State private var loopEnabled = true
    @State private var errorText: String?
    @State private var showError = false
    @State private var toast: String?
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var isBusy = false
    @State private var didAppear = false
    @State private var patternFlash = false
    @State private var suppressFineTuneReact = false
    @State private var fineTuneTask: Task<Void, Never>?
    @State private var playTask: Task<Void, Never>?
    @State private var showGeneratingOverlay = false

    @State private var monitor = PlaybackMonitor()
    @State private var library = LibraryStore.shared

    @State private var sfxPitch: Double = 1
    @State private var sfxTimbre: Double = 0.5
    @State private var sfxIntensity: Double = 0.7
    @State private var sfxDurationMs: Double = 280
    @State private var sfxNoteCount: Double = 1
    @State private var bgmTempo: Double = 120
    @State private var bgmPitch: Double = 0
    @State private var bgmRhythm: Double = 0.5
    @State private var bgmMelody = true

    private var service: GenerationService { GenerationService.shared }

    private var titleText: String {
        soundType == .bgm ? "BGMスタジオ" : "効果音スタジオ"
    }

    init(soundType: SoundType, autoPlay: Bool = false) {
        self.soundType = soundType
        self.autoPlay = autoPlay
        self.initialIntent = nil
        _genreId = State(initialValue: Catalog.Genre.cardBattle.rawValue)
        _loopEnabled = State(initialValue: soundType == .bgm)
        if soundType == .bgm {
            let scene = Catalog.BGMScene.battleNormal
            _sceneGroup = State(initialValue: scene.group)
            _sceneId = State(initialValue: scene.rawValue)
            _moodId = State(initialValue: scene.defaultMood.rawValue)
            _lengthId = State(initialValue: scene.defaultLength.rawValue)
            _instrumentId = State(initialValue: Catalog.Instrument.defaultFor(scene: scene).rawValue)
        } else {
            let purpose = Catalog.SFXPurpose.attackLight
            _moodId = State(initialValue: Catalog.Mood.neutral.rawValue)
            _lengthId = State(initialValue: purpose.defaultLength.rawValue)
            _sfxDurationMs = State(initialValue: Double(purpose.category.defaultDurationMs))
            _sfxNoteCount = State(initialValue: 1)
        }
    }

    init(intent: SoundIntent, autoPlay: Bool = false) {
        self.soundType = intent.soundType
        self.autoPlay = autoPlay
        self.initialIntent = intent
        _genreId = State(initialValue: intent.genreId)
        _loopEnabled = State(initialValue: intent.soundType == .bgm)
        let scene = Catalog.BGMScene.resolve(intent.sceneId) ?? .battleNormal
        _sceneGroup = State(initialValue: scene.group)
        _sceneId = State(initialValue: scene.rawValue)
        _purposeId = State(initialValue: intent.purposeId ?? Catalog.SFXPurpose.attackLight.rawValue)
        _moodId = State(initialValue: intent.moodId)
        _lengthId = State(initialValue: intent.lengthId)
        _instrumentId = State(initialValue: Catalog.Instrument.resolve(intent.instrumentId).rawValue)
        _seed = State(initialValue: intent.seed ?? UInt64.random(in: 1...999_999))
        if let purpose = Catalog.SFXPurpose(rawValue: intent.purposeId ?? "") {
            _purposeGroup = State(initialValue: purpose.group)
        }
    }

    var body: some View {
        applyStudioObservers(to: studioShell)
    }

    private var studioShell: some View {
        studioRoot
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(theme.background)
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { studioShareToolbar }
            .safeAreaInset(edge: .bottom) { studioToastBar }
            .alert("エラー", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "不明なエラーです")
            }
            .sheet(isPresented: $showShareSheet) {
                if let exportURL {
                    ShareSheet(items: [exportURL])
                }
            }
            .overlay { generatingOverlay }
            .animation(.easeOut(duration: 0.15), value: showGeneratingOverlay)
    }

    @ViewBuilder
    private var studioRoot: some View {
        if soundType == .sfx {
            sfxStudioBody
        } else {
            bgmStudioBody
        }
    }

    @ToolbarContentBuilder
    private var studioShareToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    saveLibrary()
                } label: {
                    Label("ライブラリに保存", systemImage: "bookmark")
                }
                Button {
                    exportAndShare()
                } label: {
                    Label("WAVを書き出して共有", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(isBusy)
            .accessibilityLabel("共有")
        }
    }

    @ViewBuilder
    private var studioToastBar: some View {
        if let toast {
            Text(toast)
                .font(.footnote)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var generatingOverlay: some View {
        if showGeneratingOverlay {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(theme.accent)
                        .scaleEffect(1.15)
                    Text("BGM生成中…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .background(theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(theme.secondaryText.opacity(0.2), lineWidth: 1)
                }
            }
            .transition(.opacity)
            .zIndex(2)
        }
    }

    private func applyStudioObservers<V: View>(to view: V) -> some View {
        applyFineTuneObservers(to: applyLifecycleObservers(to: view))
    }

    private func applyLifecycleObservers<V: View>(to view: V) -> some View {
        view
            .onAppear(perform: handleStudioAppear)
            .onDisappear(perform: handleStudioDisappear)
    }

    private func applyFineTuneObservers<V: View>(to view: V) -> some View {
        view
            // SFX: sliders only update params; playback is explicit via 再生 / 別パターン.
            .onChange(of: sfxDurationMs) { _, newValue in
                guard soundType == .sfx, !suppressFineTuneReact else { return }
                lengthId = nearestSFXLengthId(ms: Int(newValue.rounded()))
                exportURL = nil
            }
            .onChange(of: sfxPitch) { _, _ in markSFXParamsEdited() }
            .onChange(of: sfxTimbre) { _, _ in markSFXParamsEdited() }
            .onChange(of: sfxIntensity) { _, _ in markSFXParamsEdited() }
            .onChange(of: sfxNoteCount) { _, _ in markSFXParamsEdited() }
            .onChange(of: bgmTempo) { _, _ in scheduleFineTune() }
            .onChange(of: bgmPitch) { _, _ in scheduleFineTune() }
            .onChange(of: bgmRhythm) { _, _ in scheduleFineTune() }
            .onChange(of: bgmMelody) { _, _ in scheduleFineTune() }
    }

    private func handleStudioAppear() {
        guard !didAppear else { return }
        didAppear = true
        stopAllPlayback()
        suppressFineTuneReact = true
        applyDefaultIfNeeded()
        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(200))
            suppressFineTuneReact = false
            if autoPlay {
                playNow(newSeed: false)
            }
        }
    }

    private func handleStudioDisappear() {
        fineTuneTask?.cancel()
        playTask?.cancel()
        service.stop()
        monitor.stopMonitoring()
    }

    /// SFX: all controls on one screen (no modal, no scroll).
    private var sfxStudioBody: some View {
        VStack(spacing: 14) {
            studioMenuRow(title: "カテゴリ") {
                Picker("カテゴリ", selection: sfxPurposeGroupBinding) {
                    ForEach(Catalog.sfxPurposeGroupOrder, id: \.self) { group in
                        Text(group).tag(group)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(theme.accent)
            }

            studioMenuRow(title: "用途") {
                Picker("用途", selection: sfxPurposeIdBinding) {
                    ForEach(Catalog.sfxPurposes(in: purposeGroup), id: \.rawValue) { purpose in
                        Text(purpose.displayName).tag(purpose.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(theme.accent)
            }

            Picker("雰囲気", selection: sfxMoodIdBinding) {
                ForEach(Catalog.moods) { item in
                    Text(item.displayName).tag(item.id)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("雰囲気")

            VStack(spacing: 12) {
                compactSlider("高さ", value: $sfxPitch, range: 0.5...2.0)
                compactSlider("音色", value: $sfxTimbre, range: 0...1)
                compactSlider("強さ", value: $sfxIntensity, range: 0...1)
                compactSlider("長さ", value: $sfxDurationMs, range: 50...1200, step: 10)
                compactSlider("音数", value: $sfxNoteCount, range: 1...8, step: 1)
            }

            Spacer(minLength: 0)

            studioBottomPlaybackControls
        }
    }

    /// Catalog edits update state only; sound plays on 再生 / 別パターン.
    private var sfxPurposeGroupBinding: Binding<String> {
        Binding(
            get: { purposeGroup },
            set: { newValue in
                guard newValue != purposeGroup else { return }
                purposeGroup = newValue
                applyPurposeGroupInline(newValue)
                markSFXCatalogDirty()
            }
        )
    }

    private var sfxPurposeIdBinding: Binding<String> {
        Binding(
            get: { purposeId },
            set: { newValue in
                guard newValue != purposeId else { return }
                purposeId = newValue
                if let purpose = Catalog.SFXPurpose(rawValue: newValue) {
                    suppressFineTuneReact = true
                    sfxDurationMs = Double(purpose.category.defaultDurationMs)
                    lengthId = nearestSFXLengthId(ms: Int(sfxDurationMs.rounded()))
                    Task { @MainActor in suppressFineTuneReact = false }
                }
                markSFXCatalogDirty()
            }
        )
    }

    private var sfxMoodIdBinding: Binding<String> {
        Binding(
            get: { moodId },
            set: { newValue in
                guard newValue != moodId else { return }
                moodId = newValue
                suppressFineTuneReact = true
                syncSFXSlidersFromMood()
                Task { @MainActor in suppressFineTuneReact = false }
                markSFXCatalogDirty()
            }
        )
    }

    private var bgmStudioBody: some View {
        VStack(spacing: 16) {
            // Stops playback when changed.
            VStack(spacing: 10) {
                studioMenuRow(title: "使う場所") {
                    Picker("使う場所", selection: bgmSceneGroupBinding) {
                        ForEach(Catalog.bgmSceneGroupOrder, id: \.self) { group in
                            Text(group).tag(group)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(theme.accent)
                }

                studioMenuRow(title: "用途") {
                    Picker("用途", selection: bgmSceneIdBinding) {
                        ForEach(Catalog.bgmScenes(in: sceneGroup), id: \.rawValue) { scene in
                            Text(scene.displayName).tag(scene.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(theme.accent)
                }

                studioMenuRow(title: "音色イメージ") {
                    Picker("音色イメージ", selection: bgmInstrumentIdBinding) {
                        ForEach(Catalog.instruments) { item in
                            Text(item.displayName).tag(item.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(theme.accent)
                }

                Picker("長さ", selection: bgmLengthIdBinding) {
                    ForEach(Catalog.bgmLengths) { item in
                        Text(item.displayName).tag(item.id)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("長さ")
            }

            studioSectionDivider

            // Keeps playing; regenerates in the background.
            VStack(spacing: 10) {
                Picker("雰囲気", selection: bgmMoodIdBinding) {
                    ForEach(Catalog.moods) { item in
                        Text(item.displayName).tag(item.id)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("雰囲気")

                VStack(spacing: 10) {
                    compactSlider("テンポ", value: $bgmTempo, range: 80...160, step: 1)
                    compactSlider("ピッチ", value: $bgmPitch, range: -6...6, step: 1)
                    compactSlider("リズム", value: $bgmRhythm, range: 0...1)
                }

                studioToggleRow(title: "メロディ", isOn: $bgmMelody)
            }

            Spacer(minLength: 0)

            studioSectionDivider

            studioToggleRow(title: "ループ", isOn: bgmLoopBinding)

            StudioPlaybackProgress(monitor: monitor)

            studioBottomPlaybackControls
        }
    }

    private var studioBottomPlaybackControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                playControlButton
                patternControlButton
            }

            Text("Seed \(seed)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.secondaryText)
        }
    }

    private func studioMenuRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 12)
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var studioSectionDivider: some View {
        Rectangle()
            .fill(theme.secondaryText.opacity(0.45))
            .frame(height: 1)
            .padding(.horizontal, 2)
    }

    private func studioToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: 56, alignment: .leading)
            Spacer(minLength: 0)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    // MARK: Catalog bindings
    // BGM UI order mirrors behavior:
    //   使う場所／用途／音色イメージ／長さ → 停止して再生待ち
    //   雰囲気・テンポ／ピッチ／リズム・メロディ → 再生中は旧音継続のまま再生成し切替
    //   ループ → 再生位置を保ったまま即反映

    private var bgmSceneGroupBinding: Binding<String> {
        Binding(
            get: { sceneGroup },
            set: { newValue in
                guard newValue != sceneGroup else { return }
                sceneGroup = newValue
                applySceneGroupInline(newValue)
                markBGMStructuralDirty()
            }
        )
    }

    private var bgmSceneIdBinding: Binding<String> {
        Binding(
            get: { sceneId },
            set: { newValue in
                guard newValue != sceneId else { return }
                applySceneInline(newValue)
                markBGMStructuralDirty()
            }
        )
    }

    private var bgmInstrumentIdBinding: Binding<String> {
        Binding(
            get: { instrumentId },
            set: { newValue in
                guard newValue != instrumentId else { return }
                instrumentId = newValue
                markBGMStructuralDirty()
            }
        )
    }

    private var bgmMoodIdBinding: Binding<String> {
        Binding(
            get: { moodId },
            set: { newValue in
                guard newValue != moodId else { return }
                moodId = newValue
                scheduleBGMLiveFromIntent()
            }
        )
    }

    private var bgmLengthIdBinding: Binding<String> {
        Binding(
            get: { lengthId },
            set: { newValue in
                guard newValue != lengthId else { return }
                lengthId = newValue
                markBGMStructuralDirty()
            }
        )
    }

    private var bgmLoopBinding: Binding<Bool> {
        Binding(
            get: { loopEnabled },
            set: { newValue in
                guard newValue != loopEnabled else { return }
                loopEnabled = newValue
                applyBGMLoopImmediate()
            }
        )
    }

    // MARK: Compact chrome

    @ViewBuilder
    private var playControlButton: some View {
        let showStop = monitor.isPlaying && !isBusy
        let label = HStack(spacing: 6) {
            if isBusy {
                ProgressView()
                    .tint(theme.accent)
            } else {
                Image(systemName: showStop ? "stop.fill" : "play.fill")
            }
            Text(isBusy ? "生成中" : (showStop ? "停止" : "再生"))
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)

        Button {
            hapticMedium()
            if showStop {
                service.stop()
                monitor.stopMonitoring()
            } else {
                playNow(newSeed: false)
            }
        } label: {
            label
                .foregroundStyle(showStop ? Color.white : theme.accent)
        }
        .disabled(isBusy)
        .modifier(PlayButtonChrome(isPlaying: showStop))
    }

    private var patternControlButton: some View {
        Button {
            flashPatternButton()
            playNow(newSeed: true)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "shuffle")
                Text("別パターン")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(theme.accent)
        .disabled(isBusy)
        .opacity(patternFlash ? 0.7 : 1)
        .animation(.easeOut(duration: 0.12), value: patternFlash)
    }

    private func flashPatternButton() {
        hapticMedium()
        patternFlash = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            patternFlash = false
        }
    }

    private func compactSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: 56, alignment: .leading)
            if let step {
                Slider(value: value, in: range, step: step)
            } else {
                Slider(value: value, in: range)
            }
            Text(step != nil ? String(format: "%.0f", value.wrappedValue) : String(format: "%.2f", value.wrappedValue))
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.secondaryText)
                .frame(width: 44, alignment: .trailing)
        }
    }

    // MARK: Catalog dirty helpers

    private func applySceneGroupInline(_ group: String) {
        let scenes = Catalog.bgmScenes(in: group)
        guard let first = scenes.first else { return }
        if !scenes.contains(where: { $0.rawValue == sceneId }) {
            applySceneInline(first.rawValue)
        }
    }

    private func applySceneInline(_ id: String) {
        sceneId = id
        guard let scene = Catalog.BGMScene.resolve(id) else { return }
        sceneId = scene.rawValue
        sceneGroup = scene.group
        moodId = scene.defaultMood.rawValue
        lengthId = scene.defaultLength.rawValue
        instrumentId = Catalog.Instrument.defaultFor(scene: scene).rawValue
    }

    private func markBGMStructuralDirty() {
        guard soundType == .bgm else { return }
        catalogDirty = true
        exportURL = nil
        fineTuneTask?.cancel()
        playTask?.cancel()
        showGeneratingOverlay = false
        isBusy = false
        service.stop()
        monitor.stopMonitoring()
    }

    /// Mood / fine-tune: keep current audio, regenerate, then switch when ready.
    private func scheduleBGMLiveFromIntent() {
        guard soundType == .bgm, !suppressFineTuneReact else { return }
        exportURL = nil
        fineTuneTask?.cancel()
        if catalogDirty || mapped == nil {
            catalogDirty = true
            return
        }
        guard monitor.isPlaying else {
            catalogDirty = true
            return
        }
        fineTuneTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            guard !catalogDirty, mapped != nil, monitor.isPlaying else { return }
            await reloadBGMFromIntentLive()
        }
    }

    private func applyBGMLoopImmediate() {
        guard soundType == .bgm, monitor.isPlaying, mapped != nil else { return }
        service.setLooping(loopEnabled)
        monitor.setLooping(loopEnabled)
    }

    private func applyCurrentBGMParamsToMapped() {
        guard case .bgm(var recipe) = mapped else { return }
        recipe.params.tempoBpm = Int(bgmTempo.rounded())
        recipe.params.pitchSemitones = Int(bgmPitch.rounded())
        recipe.params.rhythm = Float(bgmRhythm)
        recipe.params.melody = bgmMelody
        recipe.params.instrumentId = Catalog.Instrument.resolve(instrumentId).rawValue
        mapped = .bgm(recipe)
    }

    private func reloadBGMFromIntentLive() async {
        let intent = currentIntent()
        let savedPitch = bgmPitch
        let savedRhythm = bgmRhythm
        let savedMelody = bgmMelody
        isBusy = true
        showGeneratingOverlay = true
        await Task.yield()
        defer {
            isBusy = false
            showGeneratingOverlay = false
        }
        do {
            let (mappedRecipe, _) = try await service.generateAsync(intent)
            guard !Task.isCancelled else { return }
            mapped = mappedRecipe
            syncFineTuneFromMapped(mappedRecipe)
            // Keep fine-tune pitch/rhythm/melody across mood-driven remaps.
            bgmPitch = savedPitch
            bgmRhythm = savedRhythm
            bgmMelody = savedMelody
            applyCurrentBGMParamsToMapped()
            if let mapped {
                _ = await service.generateMappedAsync(mapped, intent: intent)
            }
            catalogDirty = false
            try service.playLast(loop: loopEnabled)
            monitor.start(duration: mapped?.durationSeconds ?? 1, looping: loopEnabled)
        } catch is CancellationError {
            return
        } catch {
            errorText = error.localizedDescription
            showError = true
        }
    }

    private func applyPurposeGroupInline(_ group: String) {
        let purposes = Catalog.sfxPurposes(in: group)
        guard let first = purposes.first else { return }
        if !purposes.contains(where: { $0.rawValue == purposeId }) {
            purposeId = first.rawValue
            suppressFineTuneReact = true
            sfxDurationMs = Double(first.category.defaultDurationMs)
            lengthId = nearestSFXLengthId(ms: Int(sfxDurationMs.rounded()))
            Task { @MainActor in suppressFineTuneReact = false }
        }
    }

    private func markSFXCatalogDirty() {
        guard soundType == .sfx else { return }
        catalogDirty = true
        exportURL = nil
        fineTuneTask?.cancel()
        service.stop()
        monitor.stopMonitoring()
    }

    private func markSFXParamsEdited() {
        guard soundType == .sfx, !suppressFineTuneReact else { return }
        exportURL = nil
    }

    private func syncSFXSlidersFromMood() {
        switch Catalog.Mood(rawValue: moodId) ?? .neutral {
        case .bright:
            sfxPitch = 1.35
            sfxTimbre = 0.15
            sfxIntensity = 0.55
        case .neutral:
            sfxPitch = 1.0
            sfxTimbre = 0.45
            sfxIntensity = 0.7
        case .tense:
            sfxPitch = 1.12
            sfxTimbre = 0.85
            sfxIntensity = 0.95
        case .dark:
            sfxPitch = 0.68
            sfxTimbre = 0.9
            sfxIntensity = 0.8
        }
    }

    private func applyCurrentSFXParamsToMapped() {
        guard case .sfx(var recipe) = mapped else { return }
        recipe.params.pitch = Float(sfxPitch)
        recipe.params.timbre = Float(sfxTimbre)
        recipe.params.intensity = Float(sfxIntensity)
        recipe.params.durationMs = Int(sfxDurationMs.rounded())
        recipe.params.count = Int(sfxNoteCount.rounded())
        lengthId = nearestSFXLengthId(ms: recipe.params.durationMs)
        mapped = .sfx(recipe)
    }

    private func nearestSFXLengthId(ms: Int) -> String {
        let candidates = Catalog.SFXLength.allCases
        let best = candidates.min(by: { abs($0.durationMs - ms) < abs($1.durationMs - ms) }) ?? .medium
        return best.rawValue
    }

    // MARK: Debounced updates

    private func scheduleFineTune() {
        guard soundType == .bgm else { return }
        guard !suppressFineTuneReact else { return }
        guard mapped != nil, !catalogDirty else { return }
        exportURL = nil
        fineTuneTask?.cancel()
        // Not playing: keep edits for the next 再生; don't auto-start.
        guard monitor.isPlaying else { return }
        fineTuneTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            guard !suppressFineTuneReact else { return }
            guard mapped != nil, !catalogDirty, monitor.isPlaying else { return }
            applyFineTuneAndPlay()
        }
    }

    // MARK: Actions

    private func applyDefaultIfNeeded() {
        guard initialIntent == nil else { return }
        if soundType == .sfx {
            purposeGroup = "バトル"
            purposeId = Catalog.SFXPurpose.attackLight.rawValue
            sfxDurationMs = Double(Catalog.SFXPurpose.attackLight.category.defaultDurationMs)
            lengthId = nearestSFXLengthId(ms: Int(sfxDurationMs.rounded()))
            sfxNoteCount = 1
            moodId = Catalog.Mood.neutral.rawValue
            genreId = Catalog.Genre.cardBattle.rawValue
            syncSFXSlidersFromMood()
        } else if let scene = Catalog.BGMScene.resolve(sceneId) {
            sceneId = scene.rawValue
            sceneGroup = scene.group
            instrumentId = Catalog.Instrument.defaultFor(scene: scene).rawValue
            moodId = scene.defaultMood.rawValue
            lengthId = scene.defaultLength.rawValue
            genreId = Catalog.Genre.cardBattle.rawValue
        }
    }

    private func currentIntent() -> SoundIntent {
        SoundIntent(
            soundType: soundType,
            genreId: genreId,
            sceneId: soundType == .bgm ? sceneId : nil,
            purposeId: soundType == .sfx ? purposeId : nil,
            moodId: moodId,
            lengthId: lengthId,
            instrumentId: soundType == .bgm ? instrumentId : nil,
            seed: seed
        )
    }

    private func playNow(newSeed: Bool) {
        playTask?.cancel()
        playTask = Task { @MainActor in
            await playNowAsync(newSeed: newSeed)
        }
    }

    private func playNowAsync(newSeed: Bool) async {
        if newSeed {
            seed = UInt64.random(in: 1...999_999)
            catalogDirty = true
        }
        let intent = currentIntent()
        let needsGenerate = mapped == nil || catalogDirty || newSeed
        let showOverlay = soundType == .bgm && needsGenerate

        isBusy = true
        if showOverlay {
            showGeneratingOverlay = true
            // Allow the overlay to paint before heavy work.
            await Task.yield()
        }
        defer {
            isBusy = false
            showGeneratingOverlay = false
        }

        do {
            if needsGenerate {
                if soundType == .bgm {
                    // 別パターン must keep UI conditions; only seed changes.
                    let savedTempo = bgmTempo
                    let savedPitch = bgmPitch
                    let savedRhythm = bgmRhythm
                    let savedMelody = bgmMelody
                    let savedInstrument = instrumentId
                    let (mappedRecipe, _) = try await service.generateAsync(intent)
                    guard !Task.isCancelled else { return }
                    mapped = mappedRecipe
                    if newSeed {
                        bgmTempo = savedTempo
                        bgmPitch = savedPitch
                        bgmRhythm = savedRhythm
                        bgmMelody = savedMelody
                        instrumentId = savedInstrument
                        applyCurrentBGMParamsToMapped()
                        if let mapped {
                            _ = await service.generateMappedAsync(mapped, intent: intent)
                        }
                    } else {
                        syncFineTuneFromMapped(mappedRecipe)
                    }
                } else {
                    let (mappedRecipe, _) = try service.generate(intent)
                    guard !Task.isCancelled else { return }
                    mapped = mappedRecipe
                    // Keep current slider values (mood/purpose already synced them when edited).
                }
                catalogDirty = false
            } else if soundType == .bgm {
                applyCurrentBGMParamsToMapped()
                if let mapped {
                    _ = await service.generateMappedAsync(mapped, intent: intent)
                }
            }
            guard !Task.isCancelled else { return }
            if soundType == .sfx {
                applyCurrentSFXParamsToMapped()
                if let mapped {
                    _ = service.generate(mapped: mapped, intent: intent)
                }
            }
            try service.playLast(loop: loopEnabled && soundType == .bgm)
            let duration = mapped?.durationSeconds ?? 1
            monitor.start(duration: duration, looping: loopEnabled && soundType == .bgm)
        } catch is CancellationError {
            return
        } catch {
            errorText = error.localizedDescription
            showError = true
        }
    }

    private func applyFineTuneAndPlay() {
        // Never generate+play from fine-tune when nothing has been heard yet
        // (avoids appear-time slider onChange accidentally starting playback).
        guard let existing = mapped else { return }
        guard !catalogDirty else {
            playNow(newSeed: false)
            return
        }
        var current = existing
        switch current {
        case .sfx(var recipe):
            recipe.params.pitch = Float(sfxPitch)
            recipe.params.timbre = Float(sfxTimbre)
            recipe.params.intensity = Float(sfxIntensity)
            recipe.params.durationMs = Int(sfxDurationMs.rounded())
            recipe.params.count = Int(sfxNoteCount.rounded())
            lengthId = nearestSFXLengthId(ms: recipe.params.durationMs)
            current = .sfx(recipe)
        case .bgm(var recipe):
            recipe.params.tempoBpm = Int(bgmTempo.rounded())
            recipe.params.pitchSemitones = Int(bgmPitch.rounded())
            recipe.params.rhythm = Float(bgmRhythm)
            recipe.params.melody = bgmMelody
            recipe.params.instrumentId = Catalog.Instrument.resolve(instrumentId).rawValue
            current = .bgm(recipe)
        }
        mapped = current
        let intent = currentIntent()
        playTask?.cancel()
        playTask = Task { @MainActor in
            isBusy = true
            let showOverlay = soundType == .bgm
            if showOverlay {
                showGeneratingOverlay = true
                await Task.yield()
            }
            defer {
                isBusy = false
                showGeneratingOverlay = false
            }
            do {
                if soundType == .bgm {
                    _ = await service.generateMappedAsync(current, intent: intent)
                } else {
                    _ = service.generate(mapped: current, intent: intent)
                }
                guard !Task.isCancelled else { return }
                try service.playLast(loop: loopEnabled && soundType == .bgm)
                monitor.start(
                    duration: current.durationSeconds,
                    looping: loopEnabled && soundType == .bgm
                )
            } catch {
                errorText = error.localizedDescription
                showError = true
            }
        }
    }

    private func exportAndShare() {
        run {
            if mapped == nil || catalogDirty {
                let (mappedRecipe, _) = try service.generate(currentIntent())
                mapped = mappedRecipe
                syncFineTuneFromMapped(mappedRecipe)
                catalogDirty = false
            } else if service.lastBuffer == nil, let mapped {
                _ = service.generate(mapped: mapped, intent: currentIntent())
            }
            let url = try service.exportLastToDocuments()
            exportURL = url
            showShareSheet = true
        }
    }

    private func saveLibrary() {
        run {
            if mapped == nil || catalogDirty {
                let (mappedRecipe, _) = try service.generate(currentIntent())
                mapped = mappedRecipe
                syncFineTuneFromMapped(mappedRecipe)
                catalogDirty = false
            }
            try library.save(currentIntent(), exportFileName: mapped?.exportFileName)
            showToast("ライブラリに保存しました")
        }
    }

    private func syncFineTuneFromMapped(_ mapped: MappedRecipe) {
        suppressFineTuneReact = true
        defer {
            Task { @MainActor in
                suppressFineTuneReact = false
            }
        }
        switch mapped {
        case .sfx(let recipe):
            sfxPitch = Double(recipe.params.pitch)
            sfxTimbre = Double(recipe.params.timbre)
            sfxIntensity = Double(recipe.params.intensity)
            sfxDurationMs = Double(recipe.params.durationMs)
            sfxNoteCount = Double(recipe.params.count)
        case .bgm(let recipe):
            bgmTempo = Double(recipe.params.tempoBpm)
            bgmPitch = Double(recipe.params.pitchSemitones)
            bgmRhythm = Double(recipe.params.rhythm)
            bgmMelody = recipe.params.melody
            instrumentId = recipe.params.instrumentId
        }
    }

    private func showToast(_ message: String) {
        withAnimation {
            toast = message
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                if toast == message { toast = nil }
            }
        }
    }

    private func run(_ work: () throws -> Void) {
        isBusy = true
        defer { isBusy = false }
        do {
            try work()
        } catch {
            errorText = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Library

private enum LibrarySort: String, CaseIterable, Identifiable {
    case newest
    case type
    case genre

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest: return "新しい順"
        case .type: return "種類"
        case .genre: return "ゲームタイプ"
        }
    }
}

struct LibraryView: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject private var library = LibraryStore.shared
    @State private var sort: LibrarySort = .newest
    @State private var playingId: UUID?
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var showError = false
    /// Explicit delete mode (system EditMode conflicts with play + NavigationLink rows).
    @State private var isDeleting = false

    private var service: GenerationService { GenerationService.shared }

    private var sortedEntries: [LibraryEntry] {
        switch sort {
        case .newest:
            return library.entries.sorted { $0.savedAt > $1.savedAt }
        case .type:
            return library.entries.sorted {
                if $0.intent.soundType != $1.intent.soundType {
                    return $0.intent.soundType.rawValue < $1.intent.soundType.rawValue
                }
                return $0.savedAt > $1.savedAt
            }
        case .genre:
            return library.entries.sorted {
                if $0.intent.genreId != $1.intent.genreId {
                    return $0.intent.genreId < $1.intent.genreId
                }
                return $0.savedAt > $1.savedAt
            }
        }
    }

    var body: some View {
        List {
            if library.entries.isEmpty {
                ContentUnavailableView(
                    "保存した音はまだありません",
                    systemImage: "books.vertical",
                    description: Text("制作画面右上の共有メニューから保存できます。")
                )
                .themedListRowBackground(theme)
            } else {
                ForEach(sortedEntries) { entry in
                    libraryRow(entry)
                        .swipeActions(edge: .trailing, allowsFullSwipe: !isDeleting) {
                            Button(role: .destructive) {
                                remove(entry)
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                }
                .themedListRowBackground(theme)
            }
        }
        .navigationTitle("ライブラリ")
        .themedListBackground(theme)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !library.entries.isEmpty {
                    Button(isDeleting ? "完了" : "削除") {
                        hapticLight()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isDeleting.toggle()
                            if isDeleting {
                                service.stop()
                                playingId = nil
                            }
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !library.entries.isEmpty {
                    Menu {
                        Picker("並び替え", selection: $sort) {
                            ForEach(LibrarySort.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                    } label: {
                        Label("並び替え", systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(isDeleting)
                }
            }
        }
        .onAppear { library.load() }
        .onDisappear {
            service.stop()
            playingId = nil
            isDeleting = false
        }
        .onChange(of: library.entries.isEmpty) { _, empty in
            if empty { isDeleting = false }
        }
        .alert("エラー", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "不明なエラーです")
        }
    }

    @ViewBuilder
    private func libraryRow(_ entry: LibraryEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if isDeleting {
                Button {
                    hapticMedium()
                    remove(entry)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("削除")
            } else {
                Button {
                    hapticMedium()
                    togglePlayback(entry)
                } label: {
                    Image(systemName: playingId == entry.id ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityLabel(playingId == entry.id ? "停止" : "再生")
            }

            if isDeleting {
                libraryText(entry)
            } else {
                NavigationLink {
                    StudioView(intent: entry.intent, autoPlay: false)
                } label: {
                    libraryText(entry)
                }
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if !isDeleting {
                Button {
                    togglePlayback(entry)
                } label: {
                    Label(playingId == entry.id ? "停止" : "再生", systemImage: playingId == entry.id ? "stop.fill" : "play.fill")
                }
            }
            Button(role: .destructive) {
                remove(entry)
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }

    private func libraryText(_ entry: LibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.intent.title)
                .font(.body.weight(.medium))
                .foregroundStyle(theme.primaryText)
            Text(subtitle(entry))
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
            Text(dateText(entry.savedAt))
                .font(.caption2)
                .foregroundStyle(theme.secondaryText.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func subtitle(_ entry: LibraryEntry) -> String {
        let mood = Catalog.Mood(rawValue: entry.intent.moodId)?.displayName ?? entry.intent.moodId
        if entry.intent.soundType == .bgm {
            let genre = Catalog.Genre(rawValue: entry.intent.genreId)?.displayName ?? entry.intent.genreId
            let scene = Catalog.BGMScene.resolve(entry.intent.sceneId)?.displayName
                ?? entry.intent.sceneId
                ?? "BGM"
            return "\(genre) · \(scene) · \(mood)"
        } else {
            let purpose = Catalog.SFXPurpose(rawValue: entry.intent.purposeId ?? "")?.displayName
                ?? entry.intent.purposeId
                ?? "SE"
            return "\(purpose) · \(mood)"
        }
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func remove(_ entry: LibraryEntry) {
        if playingId == entry.id {
            service.stop()
            playingId = nil
        }
        try? library.remove(entry)
        if library.entries.isEmpty {
            isDeleting = false
        }
    }

    private func togglePlayback(_ entry: LibraryEntry) {
        if playingId == entry.id {
            service.stop()
            playingId = nil
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try service.play(entry.intent, loop: entry.intent.soundType == .bgm)
            playingId = entry.id
        } catch {
            errorText = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    @AppStorage("appThemeID") private var themeIDRaw = AppThemeID.lime.rawValue
    @AppStorage("appThemeRandomPick") private var themeRandomPick = AppThemeID.lime.rawValue

    var body: some View {
        List {
            Section("テーマカラー") {
                ForEach(AppThemeID.allCases) { option in
                    Button {
                        hapticLight()
                        selectTheme(option)
                    } label: {
                        HStack(spacing: 12) {
                            themeSwatch(for: option)
                            Text(option.title)
                                .foregroundStyle(theme.primaryText)
                            Spacer()
                            if AppThemeID.resolveStored(themeIDRaw) == option {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(theme.accent)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .themedListRowBackground(theme)

            Section("アプリ") {
                LabeledContent("バージョン", value: "0.3.4 (UI磨き)")
                LabeledContent("カタログ", value: "カードバトル MVP")
                LabeledContent("サンプルレート", value: "44100 Hz")
            }
            .themedListRowBackground(theme)

            Section("開発用") {
                NavigationLink("旧スタジオ (SE/BGM 詳細)") {
                    LegacyStudioView()
                }
            }
            .themedListRowBackground(theme)

            Section("について") {
                Text("外部AIは使わず、端末内の手続き生成だけで動作します。")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
            }
            .themedListRowBackground(theme)
        }
        .navigationTitle("設定")
        .themedListBackground(theme)
    }

    private func selectTheme(_ option: AppThemeID) {
        if option == .random {
            themeRandomPick = AppTheme.rollRandomPick().rawValue
        }
        themeIDRaw = option.rawValue
    }

    @ViewBuilder
    private func themeSwatch(for option: AppThemeID) -> some View {
        if option == .random {
            Circle()
                .fill(
                    AngularGradient(
                        colors: AppThemeID.randomPool.map { AppTheme.resolved($0).accent } + [AppTheme.resolved(.lime).accent],
                        center: .center
                    )
                )
                .frame(width: 14, height: 14)
                .overlay {
                    Circle().strokeBorder(theme.secondaryText.opacity(0.35), lineWidth: 0.5)
                }
        } else {
            Circle()
                .fill(AppTheme.resolved(option).accent)
                .frame(width: 14, height: 14)
                .overlay {
                    Circle().strokeBorder(theme.secondaryText.opacity(0.35), lineWidth: 0.5)
                }
        }
    }
}

// MARK: - Share

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ContentView()
}
