import AudioGenCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @AppStorage("appThemeID") private var themeIDRaw = AppThemeID.system.rawValue
    @State private var selectedTab = 0

    private var theme: AppTheme {
        AppTheme.resolved(AppThemeID(rawValue: themeIDRaw) ?? .system)
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
    let subtitle: String
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
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
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

private struct CatalogChoiceRow: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let subtitle: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(theme.primaryText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.accent)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
    }
}

/// Wraps children as whole units (no mid-segment line breaks).
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

private struct ConditionsWrap: Layout {
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widthUsed: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            x += size.width
            widthUsed = max(widthUsed, x)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : widthUsed, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Home

private struct CreateDestination: Hashable {
    let soundType: SoundType
    let genreId: String
}

struct HomeView: View {
    @Environment(\.appTheme) private var theme
    @State private var genreId = Catalog.Genre.cardBattle.rawValue
    @State private var path = NavigationPath()

    private var selectedGenreAvailable: Bool {
        Catalog.Genre(rawValue: genreId)?.isAvailable == true
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    HomeHeroTitle()
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 12, trailing: 16))
                }

                Section {
                    Picker("ジャンル", selection: $genreId) {
                        ForEach(Catalog.availableGenres.filter(\.isAvailable)) { item in
                            Text(item.displayName).tag(item.id)
                        }
                    }
                    .pickerStyle(.menu)

                    if selectedGenreAvailable {
                        createRow(
                            type: .bgm,
                            title: "BGMスタジオ",
                            subtitle: "戦闘・メニューなどのループ曲",
                            systemImage: "music.note.list"
                        )
                        createRow(
                            type: .sfx,
                            title: "効果音スタジオ",
                            subtitle: "攻撃・カード・UIなどの短い音",
                            systemImage: "waveform"
                        )
                    } else {
                        Text("対応ジャンルを選んでください。")
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                .themedListRowBackground(theme)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .themedListBackground(theme)
            .navigationDestination(for: CreateDestination.self) { dest in
                StudioView(genreId: dest.genreId, soundType: dest.soundType)
            }
        }
    }

    private func createRow(
        type: SoundType,
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        NavigationLink(value: CreateDestination(soundType: type, genreId: genreId)) {
            CreateCard(title: title, subtitle: subtitle, systemImage: systemImage, showsChevron: false)
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
    @State private var sceneId = Catalog.BGMScene.battleNormal.rawValue
    @State private var purposeGroup = "戦闘"
    @State private var purposeId = Catalog.SFXPurpose.attackLight.rawValue
    @State private var moodId = Catalog.Mood.tense.rawValue
    @State private var lengthId = Catalog.BGMLength.bars16.rawValue
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
    @State private var showConditionsEditor = false
    @State private var conditionsRoute: ConditionsRoute?
    @State private var draftSceneId = Catalog.BGMScene.battleNormal.rawValue
    @State private var draftPurposeGroup = "戦闘"
    @State private var draftPurposeId = Catalog.SFXPurpose.attackLight.rawValue
    @State private var draftMoodId = Catalog.Mood.tense.rawValue
    @State private var draftLengthId = Catalog.BGMLength.bars16.rawValue
    @State private var draftInstrumentId = Catalog.Instrument.leadSynth.rawValue
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
    @State private var bgmTempo: Double = 120
    @State private var bgmEnergy: Double = 0.5
    @State private var bgmDensity: Double = 0.5
    @State private var bgmMelody = true

    private var service: GenerationService { GenerationService.shared }

    private var genreName: String {
        Catalog.Genre(rawValue: genreId)?.displayName ?? genreId
    }

    private var titleText: String {
        let kind = soundType == .bgm ? "BGM" : "効果音"
        return "\(kind) · \(genreName)"
    }

    private var conditionsSegments: [String] {
        if soundType == .bgm {
            let scene = Catalog.BGMScene(rawValue: sceneId)?.displayName ?? sceneId
            let instrument = Catalog.Instrument.resolve(instrumentId).displayName
            let mood = Catalog.Mood(rawValue: moodId)?.displayName ?? moodId
            let length = Catalog.BGMLength.resolve(lengthId).displayName
            return [scene, "音色：\(instrument)", "雰囲気：\(mood)", "長さ：\(length)"]
        } else {
            let purpose = Catalog.SFXPurpose(rawValue: purposeId)
            let purposeLabel = purpose.map { "\($0.group)/\($0.displayName)" } ?? purposeId
            let mood = Catalog.Mood(rawValue: moodId)?.displayName ?? moodId
            let length = Catalog.SFXLength(rawValue: lengthId)?.displayName ?? lengthId
            return [purposeLabel, "雰囲気：\(mood)", "長さ：\(length)"]
        }
    }

    init(genreId: String, soundType: SoundType, autoPlay: Bool = false) {
        self.soundType = soundType
        self.autoPlay = autoPlay
        self.initialIntent = nil
        _genreId = State(initialValue: genreId)
        _loopEnabled = State(initialValue: soundType == .bgm)
    }

    init(intent: SoundIntent, autoPlay: Bool = false) {
        self.soundType = intent.soundType
        self.autoPlay = autoPlay
        self.initialIntent = intent
        _genreId = State(initialValue: intent.genreId)
        _loopEnabled = State(initialValue: intent.soundType == .bgm)
        _sceneId = State(initialValue: intent.sceneId ?? Catalog.BGMScene.battleNormal.rawValue)
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
        VStack(spacing: 0) {
            conditionsBar

            Spacer(minLength: 14)

            if soundType == .bgm {
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

                Spacer(minLength: 14)
            }

            HStack(spacing: 10) {
                playControlButton

                if soundType == .bgm {
                    Button {
                        hapticLight()
                        service.stop()
                        monitor.stopMonitoring()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                            Text("停止")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(theme.accent)
                    .disabled(isBusy)
                }
            }

            Spacer(minLength: 14)

            if soundType == .bgm {
                HStack {
                    HStack(spacing: 8) {
                        Text("ループ")
                            .font(.subheadline)
                        Toggle("ループ", isOn: $loopEnabled)
                            .labelsHidden()
                    }
                    Spacer(minLength: 24)
                    HStack(spacing: 8) {
                        Text("メロディ")
                            .font(.subheadline)
                        Toggle("メロディ", isOn: $bgmMelody)
                            .labelsHidden()
                    }
                }

                Spacer(minLength: 14)
            }

            VStack(spacing: 18) {
                if soundType == .sfx {
                    compactSlider("高さ", value: $sfxPitch, range: 0.5...2.0)
                    compactSlider("音色", value: $sfxTimbre, range: 0...1)
                    compactSlider("強さ", value: $sfxIntensity, range: 0...1)
                } else {
                    compactSlider("速さ", value: $bgmTempo, range: 80...160, step: 1)
                    compactSlider("迫力", value: $bgmEnergy, range: 0...1)
                    compactSlider("密度", value: $bgmDensity, range: 0...1)
                }
            }

            Spacer(minLength: 14)

            VStack(spacing: 10) {
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

                Text("Seed \(seed)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(theme.background)
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .safeAreaInset(edge: .bottom) {
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
        .onAppear {
            guard !didAppear else { return }
            didAppear = true
            stopAllPlayback()
            applyDefaultIfNeeded()
            if autoPlay {
                playNow(newSeed: false)
            }
        }
        .onDisappear {
            fineTuneTask?.cancel()
            playTask?.cancel()
            service.stop()
            monitor.stopMonitoring()
        }
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
        .overlay {
            if showConditionsEditor {
                conditionsFloatingOverlay
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .overlay {
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
        .animation(.easeOut(duration: 0.2), value: showConditionsEditor)
        .animation(.easeOut(duration: 0.15), value: showGeneratingOverlay)
        .onChange(of: sfxPitch) { _, _ in scheduleFineTune() }
        .onChange(of: sfxTimbre) { _, _ in scheduleFineTune() }
        .onChange(of: sfxIntensity) { _, _ in scheduleFineTune() }
        .onChange(of: bgmTempo) { _, _ in scheduleFineTune() }
        .onChange(of: bgmEnergy) { _, _ in scheduleFineTune() }
        .onChange(of: bgmDensity) { _, _ in scheduleFineTune() }
        .onChange(of: bgmMelody) { _, _ in scheduleFineTune() }
    }

    // MARK: Compact chrome

    @ViewBuilder
    private var playControlButton: some View {
        let label = HStack(spacing: 6) {
            if isBusy {
                ProgressView()
                    .tint(monitor.isPlaying ? Color.white : theme.accent)
            } else {
                Image(systemName: "play.fill")
            }
            Text(isBusy ? "生成中" : "再生")
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)

        Button {
            hapticMedium()
            playNow(newSeed: false)
        } label: {
            label
                .foregroundStyle(monitor.isPlaying ? Color.white : theme.accent)
        }
        .disabled(isBusy || showConditionsEditor)
        .modifier(PlayButtonChrome(isPlaying: monitor.isPlaying))
    }

    private var conditionsBar: some View {
        Button {
            hapticLight()
            openConditionsEditor()
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("条件設定")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.secondaryText)
                    ConditionsWrap {
                        ForEach(Array(conditionsSegments.enumerated()), id: \.offset) { index, segment in
                            let isLast = index == conditionsSegments.count - 1
                            Text(isLast ? segment : "\(segment)、 ")
                                .font(.subheadline)
                                .foregroundStyle(theme.primaryText)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryText.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(showConditionsEditor)
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
                .frame(width: 36, alignment: .leading)
            if let step {
                Slider(value: value, in: range, step: step)
            } else {
                Slider(value: value, in: range)
            }
            Text(step != nil ? String(format: "%.0f", value.wrappedValue) : String(format: "%.2f", value.wrappedValue))
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.secondaryText)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: Conditions editor (floating draft → apply)

    private enum ConditionsRoute: Hashable {
        case scene
        case instrument
        case purpose
    }

    private var conditionsFloatingOverlay: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .allowsHitTesting(true)

            conditionsEditorCard
                .frame(maxWidth: 440)
                .frame(maxHeight: 560)
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
        }
    }

    private var conditionsEditorCard: some View {
        VStack(spacing: 0) {
            conditionsEditorHeader

            Group {
                switch conditionsRoute {
                case .none:
                    conditionsRootList
                case .scene:
                    draftScenePickerList
                case .instrument:
                    draftInstrumentPickerList
                case .purpose:
                    draftPurposePickerList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if conditionsRoute == nil {
                Button {
                    hapticMedium()
                    applyConditionsAndPlay()
                } label: {
                    Text("反映して再生")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .disabled(isBusy)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(theme.panel)
            }
        }
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.secondaryText.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
    }

    private var conditionsEditorHeader: some View {
        ZStack {
            Text(conditionsEditorTitle)
                .font(.headline)

            HStack {
                if conditionsRoute != nil {
                    Button {
                        hapticLight()
                        conditionsRoute = nil
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("戻る")
                        }
                    }
                } else {
                    Button("キャンセル") {
                        hapticLight()
                        cancelConditionsEditor()
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(theme.panel)
    }

    private var conditionsEditorTitle: String {
        switch conditionsRoute {
        case .none: return "条件設定"
        case .scene: return "シーン"
        case .instrument: return "音色"
        case .purpose: return "用途"
        }
    }

    private var conditionsRootList: some View {
        List {
            if soundType == .bgm {
                Button {
                    conditionsRoute = .scene
                } label: {
                    LabeledContent("シーン", value: Catalog.BGMScene(rawValue: draftSceneId)?.displayName ?? draftSceneId)
                }
                .listRowBackground(theme.panel)

                Button {
                    conditionsRoute = .instrument
                } label: {
                    LabeledContent("音色", value: Catalog.Instrument.resolve(draftInstrumentId).displayName)
                }
                .listRowBackground(theme.panel)
            } else {
                Button {
                    conditionsRoute = .purpose
                } label: {
                    let purpose = Catalog.SFXPurpose(rawValue: draftPurposeId)
                    LabeledContent(
                        "用途",
                        value: purpose.map { "\($0.group) / \($0.displayName)" } ?? draftPurposeId
                    )
                }
                .listRowBackground(theme.panel)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("雰囲気")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                Picker("雰囲気", selection: $draftMoodId) {
                    ForEach(Catalog.moods) { item in
                        Text(item.displayName).tag(item.id)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 2)
            .listRowBackground(theme.panel)

            VStack(alignment: .leading, spacing: 8) {
                Text("長さ")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                Picker("長さ", selection: $draftLengthId) {
                    ForEach(soundType == .bgm ? Catalog.bgmLengths : Catalog.sfxLengths) { item in
                        Text(item.displayName).tag(item.id)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 2)
            .listRowBackground(theme.panel)
        }
        .scrollContentBackground(.hidden)
        .background(theme.panel)
    }

    private var draftScenePickerList: some View {
        List {
            ForEach(Catalog.availableBGMScenes) { item in
                CatalogChoiceRow(
                    title: item.displayName,
                    subtitle: nil,
                    selected: draftSceneId == item.id
                ) {
                    applyDraftScene(item.id)
                    conditionsRoute = nil
                }
                .listRowBackground(theme.panel)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.panel)
    }

    private var draftInstrumentPickerList: some View {
        List {
            ForEach(Catalog.instruments) { item in
                CatalogChoiceRow(
                    title: item.displayName,
                    subtitle: Catalog.Instrument(rawValue: item.id)?.hint,
                    selected: draftInstrumentId == item.id
                ) {
                    draftInstrumentId = item.id
                    conditionsRoute = nil
                }
                .listRowBackground(theme.panel)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.panel)
    }

    private var draftPurposePickerList: some View {
        List {
            ForEach(Catalog.sfxPurposeGroupOrder, id: \.self) { group in
                Section(group) {
                    ForEach(Catalog.sfxPurposes(in: group), id: \.rawValue) { purpose in
                        CatalogChoiceRow(
                            title: purpose.displayName,
                            subtitle: nil,
                            selected: draftPurposeId == purpose.rawValue
                        ) {
                            draftPurposeGroup = group
                            draftPurposeId = purpose.rawValue
                            draftLengthId = purpose.defaultLength.rawValue
                            conditionsRoute = nil
                        }
                        .listRowBackground(theme.panel)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.panel)
    }

    private func openConditionsEditor() {
        draftSceneId = sceneId
        draftPurposeGroup = purposeGroup
        draftPurposeId = purposeId
        draftMoodId = moodId
        draftLengthId = lengthId
        draftInstrumentId = instrumentId
        conditionsRoute = nil
        showConditionsEditor = true
    }

    private func cancelConditionsEditor() {
        conditionsRoute = nil
        showConditionsEditor = false
    }

    private func applyConditionsAndPlay() {
        sceneId = draftSceneId
        purposeGroup = draftPurposeGroup
        purposeId = draftPurposeId
        moodId = draftMoodId
        lengthId = draftLengthId
        instrumentId = draftInstrumentId
        catalogDirty = true
        exportURL = nil
        conditionsRoute = nil
        showConditionsEditor = false
        // Immediate apply — no debounce, so the button feels like the commit.
        playNow(newSeed: false)
    }

    private func applyDraftScene(_ id: String) {
        draftSceneId = id
        if let scene = Catalog.BGMScene(rawValue: id) {
            draftMoodId = scene.defaultMood.rawValue
            draftLengthId = scene.defaultLength.rawValue
            draftInstrumentId = Catalog.Instrument.defaultFor(scene: scene).rawValue
        }
    }

    // MARK: Debounced updates

    private func scheduleFineTune() {
        guard !suppressFineTuneReact else { return }
        guard mapped != nil, !catalogDirty else { return }
        fineTuneTask?.cancel()
        let delay: Duration = soundType == .bgm ? .milliseconds(450) : .milliseconds(120)
        fineTuneTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            applyFineTuneAndPlay()
        }
    }

    // MARK: Actions

    private func applyDefaultIfNeeded() {
        guard initialIntent == nil else { return }
        if soundType == .sfx {
            purposeGroup = "戦闘"
            purposeId = Catalog.SFXPurpose.attackLight.rawValue
            lengthId = Catalog.SFXPurpose.attackLight.defaultLength.rawValue
            moodId = Catalog.Mood.neutral.rawValue
        } else if let scene = Catalog.BGMScene(rawValue: sceneId) {
            instrumentId = Catalog.Instrument.defaultFor(scene: scene).rawValue
            moodId = scene.defaultMood.rawValue
            lengthId = scene.defaultLength.rawValue
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
                    let (mappedRecipe, _) = try await service.generateAsync(intent)
                    guard !Task.isCancelled else { return }
                    mapped = mappedRecipe
                    syncFineTuneFromMapped(mappedRecipe)
                } else {
                    let (mappedRecipe, _) = try service.generate(intent)
                    guard !Task.isCancelled else { return }
                    mapped = mappedRecipe
                    syncFineTuneFromMapped(mappedRecipe)
                }
                catalogDirty = false
            }
            guard !Task.isCancelled else { return }
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
        guard var current = mapped, !catalogDirty else {
            playNow(newSeed: false)
            return
        }
        switch current {
        case .sfx(var recipe):
            recipe.params.pitch = Float(sfxPitch)
            recipe.params.timbre = Float(sfxTimbre)
            recipe.params.intensity = Float(sfxIntensity)
            current = .sfx(recipe)
        case .bgm(var recipe):
            recipe.params.tempoBpm = Int(bgmTempo.rounded())
            recipe.params.energy = Float(bgmEnergy)
            recipe.params.density = Float(bgmDensity)
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
        case .bgm(let recipe):
            bgmTempo = Double(recipe.params.tempoBpm)
            bgmEnergy = Double(recipe.params.energy)
            bgmDensity = Double(recipe.params.density)
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
        case .genre: return "ジャンル"
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
        let genre = Catalog.Genre(rawValue: entry.intent.genreId)?.displayName ?? entry.intent.genreId
        let mood = Catalog.Mood(rawValue: entry.intent.moodId)?.displayName ?? entry.intent.moodId
        return "\(genre) · \(entry.intent.soundType.displayName) · \(mood)"
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
    @AppStorage("appThemeID") private var themeIDRaw = AppThemeID.system.rawValue

    var body: some View {
        List {
            Section("見た目") {
                ForEach(AppThemeID.allCases) { option in
                    Button {
                        hapticLight()
                        themeIDRaw = option.rawValue
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(AppTheme.resolved(option).accent)
                                .frame(width: 14, height: 14)
                                .overlay {
                                    Circle().strokeBorder(theme.secondaryText.opacity(0.35), lineWidth: 0.5)
                                }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .foregroundStyle(theme.primaryText)
                                Text(option.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryText)
                            }
                            Spacer()
                            if themeIDRaw == option.rawValue {
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
