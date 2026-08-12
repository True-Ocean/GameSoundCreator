import AudioGenCore
import StoreKit
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

@MainActor
@Observable
final class ProStore {
    static let shared = ProStore()

    static let productID = "com.trueocean.GameSoundCreator.pro"
    static let freeLibraryLimit = 10
    static let freeDailyExportLimit = 3

    private let defaults = UserDefaults.standard
    private var updatesTask: Task<Void, Never>?

    private(set) var product: Product?
    private(set) var isPro = false
    private(set) var isLoading = true
    private(set) var isPurchasing = false
    private(set) var errorMessage: String?

    private init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self.refreshEntitlements()
                }
            }
        }
        Task { await configure() }
    }

    func configure() async {
        await refreshEntitlements()
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            errorMessage = "購入情報を読み込めませんでした。通信状況を確認して、もう一度お試しください。"
        }
        isLoading = false
    }

    func purchase() async {
        if product == nil {
            await configure()
        }
        guard let product else {
            errorMessage = "購入情報を読み込めませんでした。時間をおいてもう一度お試しください。"
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else {
                    errorMessage = "購入内容を確認できませんでした。"
                    return
                }
                await transaction.finish()
                await refreshEntitlements()
            case .pending:
                errorMessage = "購入の承認待ちです。承認後にもう一度お試しください。"
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "購入を完了できませんでした。もう一度お試しください。"
        }
    }

    func restore() async {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isPro {
                errorMessage = "復元できる購入が見つかりませんでした。"
            }
        } catch {
            errorMessage = "購入の復元を完了できませんでした。もう一度お試しください。"
        }
    }

    var canSaveToLibrary: Bool {
        isPro || LibraryStore.shared.entries.count < Self.freeLibraryLimit
    }

    var librarySlotsRemaining: Int {
        guard !isPro else { return .max }
        return max(0, Self.freeLibraryLimit - LibraryStore.shared.entries.count)
    }

    var exportsRemainingToday: Int {
        guard !isPro else { return .max }
        return max(0, Self.freeDailyExportLimit - exportsUsedToday)
    }

    var canExport: Bool {
        isPro || exportsRemainingToday > 0
    }

    func recordExport() {
        guard !isPro else { return }
        let count = exportsUsedToday
        let today = Self.dayFormatter.string(from: Date())
        defaults.set(today, forKey: "proStore.exportDay")
        defaults.set(count + 1, forKey: "proStore.exportCount")
    }

    func dismissError() {
        errorMessage = nil
    }

    private var exportsUsedToday: Int {
        let today = Self.dayFormatter.string(from: Date())
        guard defaults.string(forKey: "proStore.exportDay") == today else {
            return 0
        }
        return defaults.integer(forKey: "proStore.exportCount")
    }

    private func refreshEntitlements() async {
        var hasPro = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.productID, transaction.revocationDate == nil {
                hasPro = true
            }
        }
        isPro = hasPro
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct ProUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Bindable var store: ProStore

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(theme.accent)

                Text("レトロサウンド Pro")
                    .font(.title2.bold())
                    .foregroundStyle(theme.primaryText)

                Text("ライブラリ保存とWAV書き出し・共有を、回数を気にせず使えます。")
                    .foregroundStyle(theme.secondaryText)

                VStack(alignment: .leading, spacing: 10) {
                    Label("ライブラリ保存が無制限", systemImage: "bookmark.fill")
                    Label("WAV書き出し・共有が無制限", systemImage: "waveform")
                    Label("一度の購入でずっと利用可能", systemImage: "checkmark.seal.fill")
                }
                .foregroundStyle(theme.primaryText)

                Spacer()

                if store.isPro {
                    Label("Proをご利用中です", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Button {
                            Task { await store.purchase() }
                        } label: {
                            HStack {
                                Spacer()
                                if store.isPurchasing {
                                    ProgressView().tint(.black)
                                } else {
                                    Text(store.product.map { "\($0.displayPrice)でProにする" } ?? "Proにする")
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.accent)
                        .disabled(store.isPurchasing || store.isLoading)

                        Button("購入を復元") {
                            Task { await store.restore() }
                        }
                        .buttonStyle(.bordered)
                        .tint(theme.accent)
                        .disabled(store.isPurchasing)
                    }
                    .frame(maxWidth: .infinity)
                    .controlSize(.large)
                }
            }
            .padding(24)
            .navigationTitle("Proにアップグレード")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("購入情報", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.dismissError() } }
            )) {
                Button("OK", role: .cancel) { store.dismissError() }
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }
}

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

    @State private var generationState = StudioGenerationState()
    @State private var generationViewModel = StudioGenerationViewModel()
    @State private var loopEnabled = true
    @State private var errorText: String?
    @State private var showError = false
    @State private var toast: String?
    @State private var showShareSheet = false
    @State private var didAppear = false
    @State private var patternFlash = false
    @State private var suppressFineTuneReact = false
    @State private var fineTuneTask: Task<Void, Never>?
    @State private var exportTask: Task<Void, Never>?

    @State private var monitor = PlaybackMonitor()
    @State private var library = LibraryStore.shared
    @State private var proStore = ProStore.shared
    @State private var showProUpgrade = false

    @State private var sfxPitch: Double = 1
    @State private var sfxTimbre: Double = 0.5
    @State private var sfxIntensity: Double = 0.7
    @State private var sfxDurationMs: Double = 280
    @State private var sfxNoteCount: Double = 1
    @State private var bgmTempo: Double = 120
    @State private var bgmPitch: Double = 0
    @State private var bgmRhythm: Double = 0.5
    @State private var bgmMelody = true
    /// Tempo for the current scene's default mood (set on scene apply / generate sync).
    @State private var bgmSceneDefaultTempo: Double?

    private var service: GenerationService { GenerationService.shared }
    private var operationState: StudioOperationState { generationViewModel.operationState }

    private var mapped: MappedRecipe? {
        get { generationState.mapped }
        nonmutating set { generationState.mapped = newValue }
    }

    private var catalogDirty: Bool {
        get { generationState.catalogDirty }
        nonmutating set { generationState.catalogDirty = newValue }
    }

    private var exportURL: URL? {
        get { generationState.exportURL }
        nonmutating set { generationState.exportURL = newValue }
    }

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
            let scene = Catalog.BGMScene.title
            let instrument = Catalog.Instrument.defaultFor(scene: scene).rawValue
            let mood = scene.defaultMood.rawValue
            let length = scene.defaultLength.rawValue
            _sceneGroup = State(initialValue: scene.group)
            _sceneId = State(initialValue: scene.rawValue)
            _moodId = State(initialValue: mood)
            _lengthId = State(initialValue: length)
            _instrumentId = State(initialValue: instrument)
            if let tempo = Self.mappedBGMTempo(
                genreId: Catalog.Genre.cardBattle.rawValue,
                sceneId: scene.rawValue,
                moodId: mood,
                lengthId: length,
                instrumentId: instrument
            ) {
                _bgmTempo = State(initialValue: tempo)
                _bgmSceneDefaultTempo = State(initialValue: tempo)
            }
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
        if intent.soundType == .bgm {
            let instrument = Catalog.Instrument.resolve(intent.instrumentId).rawValue
            let defaultMood = scene.defaultMood.rawValue
            if let tempo = Self.mappedBGMTempo(
                genreId: intent.genreId,
                sceneId: scene.rawValue,
                moodId: defaultMood,
                lengthId: intent.lengthId.isEmpty ? scene.defaultLength.rawValue : intent.lengthId,
                instrumentId: instrument
            ) {
                _bgmSceneDefaultTempo = State(initialValue: tempo)
                if intent.moodId == defaultMood {
                    _bgmTempo = State(initialValue: tempo)
                }
            }
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
            .sheet(isPresented: $showProUpgrade) {
                ProUpgradeSheet(store: proStore)
            }
            .overlay { generatingOverlay }
            .animation(.easeOut(duration: 0.15), value: operationState.showsGeneratingOverlay)
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
                    Label(
                        proStore.isPro ? "ライブラリに保存" : "ライブラリに保存（残り \(proStore.librarySlotsRemaining) 件）",
                        systemImage: "bookmark"
                    )
                }
                Button {
                    exportAndShare()
                } label: {
                    Label(
                        proStore.isPro ? "WAVを書き出して共有" : "WAVを書き出して共有（残り \(proStore.exportsRemainingToday) 回）",
                        systemImage: "square.and.arrow.up"
                    )
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(operationState.isBusy)
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
        if operationState.showsGeneratingOverlay {
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
            .onReceive(NotificationCenter.default.publisher(
                for: AudioPlaybackNotification.stopped,
                object: service
            )) { notification in
                handleSystemPlaybackStop(notification)
            }
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
        generationViewModel.cancelPlayback()
        exportTask?.cancel()
        operationState.cancel()
        service.stop()
        monitor.stopMonitoring()
    }

    private func handleSystemPlaybackStop(_ notification: Notification) {
        let wasPlaying = monitor.isPlaying
        fineTuneTask?.cancel()
        generationViewModel.cancelPlayback()
        monitor.stopMonitoring()
        guard wasPlaying,
              let rawReason = notification.userInfo?[AudioPlaybackNotification.reasonKey] as? String,
              let reason = PlaybackStopReason(rawValue: rawReason) else {
            return
        }
        switch reason {
        case .interruption:
            showToast("他の音声再生のため停止しました")
        case .outputDeviceDisconnected:
            showToast("出力デバイスが切断されたため停止しました")
        }
    }

    /// SFX: all controls on one screen (no modal, no scroll).
    private var sfxStudioBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                studioValueMenu(
                    accessibilityLabel: "カテゴリ",
                    selection: sfxPurposeGroupBinding,
                    options: Catalog.sfxPurposeGroupOrder.map { ($0, $0) }
                )

                studioValueMenu(
                    accessibilityLabel: "用途",
                    selection: sfxPurposeIdBinding,
                    options: Catalog.sfxPurposes(in: purposeGroup).map { ($0.rawValue, $0.displayName) }
                )
            }

            Spacer(minLength: 12)

            studioPlaybackUnit

            Spacer(minLength: 12)

            VStack(spacing: 12) {
                Picker("雰囲気", selection: sfxMoodIdBinding) {
                    ForEach(Catalog.moods) { item in
                        Text(item.displayName).tag(item.id)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("雰囲気")

                compactSlider("高さ", value: $sfxPitch, range: 0.5...2.0)
                compactSlider("音色", value: $sfxTimbre, range: 0...1)
                compactSlider("強さ", value: $sfxIntensity, range: 0...1)
                compactSlider("長さ", value: $sfxDurationMs, range: 50...1200, step: 10)
                compactSlider("音数", value: $sfxNoteCount, range: 1...8, step: 1)

                studioResetDefaultsButton(action: resetSFXToDefaults)
            }
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
        VStack(spacing: 0) {
            // Catalog: stops playback when changed.
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    studioValueMenu(
                        accessibilityLabel: "カテゴリ",
                        selection: bgmSceneGroupBinding,
                        options: Catalog.bgmSceneGroupOrder.map { ($0, $0) }
                    )

                    studioValueMenu(
                        accessibilityLabel: "用途",
                        selection: bgmSceneIdBinding,
                        options: Catalog.bgmScenes(in: sceneGroup).map { ($0.rawValue, $0.displayName) }
                    )
                }

                studioMenuRow(title: "音色イメージ") {
                    studioInlineValueMenu(
                        accessibilityLabel: "音色イメージ",
                        selection: bgmInstrumentIdBinding,
                        options: Catalog.instruments.map { ($0.id, $0.displayName) }
                    )
                }

                Picker("長さ", selection: bgmLengthIdBinding) {
                    ForEach(Catalog.bgmLengths) { item in
                        Text(item.displayName).tag(item.id)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("長さ")
            }

            Spacer(minLength: 12)

            studioPlaybackUnit

            Spacer(minLength: 12)

            // Fine-tune: keeps playing; regenerates in the background.
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

                studioResetDefaultsButton(action: resetBGMToDefaults)
            }
        }
    }

    /// Loop / progress / play / pattern — primary actions after catalog selection.
    private var studioPlaybackUnit: some View {
        VStack(spacing: 10) {
            studioToggleRow(title: "ループ", isOn: studioLoopBinding)

            StudioPlaybackProgress(monitor: monitor)

            HStack(spacing: 10) {
                playControlButton
                patternControlButton
            }

            Text("Seed \(seed)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.accent.opacity(0.35), lineWidth: 1)
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

    /// Value-only menu chrome: selected title on one centered line (role via accessibility).
    private func studioValueMenu(
        accessibilityLabel: String,
        selection: Binding<String>,
        options: [(id: String, title: String)]
    ) -> some View {
        studioInlineValueMenu(
            accessibilityLabel: accessibilityLabel,
            selection: selection,
            options: options,
            centered: true
        )
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Menu control showing the selected title (optionally centered) with a chevron.
    private func studioInlineValueMenu(
        accessibilityLabel: String,
        selection: Binding<String>,
        options: [(id: String, title: String)],
        centered: Bool = false
    ) -> some View {
        let title = options.first(where: { $0.id == selection.wrappedValue })?.title ?? accessibilityLabel
        return Menu {
            Picker(selection: selection) {
                ForEach(options, id: \.id) { option in
                    Text(option.title).tag(option.id)
                }
            } label: {
                EmptyView()
            }
        } label: {
            HStack(spacing: 4) {
                if centered { Spacer(minLength: 0) }
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .layoutPriority(1)
                if centered { Spacer(minLength: 0) }
            }
            .foregroundStyle(theme.accent)
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(title)
    }

    private func studioResetDefaultsButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("設定リセット")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(theme.accent)
        .disabled(operationState.isBusy)
    }

    private func studioToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            studioParamLabel(title)
            Spacer(minLength: 0)
            Toggle(isOn: isOn) {
                EmptyView()
            }
            .labelsHidden()
            .controlSize(.small)
            .font(.subheadline)
        }
        .frame(minHeight: 32)
    }

    // MARK: Catalog bindings
    // Studio layout (BGM / SE):
    //   カタログ選択 → 再生操作ユニット（ループ／バー／再生／別パターン）→ 微調整
    // BGM catalog: カテゴリ／用途／音色イメージ／長さ → 停止して再生待ち
    // BGM fine-tune: 雰囲気・テンポ／ピッチ／リズム・メロディ → 再生中は裏生成して切替
    // SFX catalog: カテゴリ／用途 → 停止して再生待ち
    // SFX fine-tune: 雰囲気・スライダー → 次回再生時に反映
    //   設定リセット → 雰囲気・スライダー等を用途既定へ戻す
    //   ループ → 再生中は即反映

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

    private var studioLoopBinding: Binding<Bool> {
        Binding(
            get: { loopEnabled },
            set: { newValue in
                guard newValue != loopEnabled else { return }
                loopEnabled = newValue
                applyLoopImmediate()
            }
        )
    }

    // MARK: Compact chrome

    @ViewBuilder
    private var playControlButton: some View {
        let showStop = monitor.isPlaying && !operationState.isBusy
        let label = HStack(spacing: 6) {
            if operationState.isBusy {
                ProgressView()
                    .tint(theme.accent)
            } else {
                Image(systemName: showStop ? "stop.fill" : "play.fill")
            }
            Text(operationState.isBusy ? "生成中" : (showStop ? "停止" : "再生"))
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
        .disabled(operationState.isBusy)
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
        .disabled(operationState.isBusy)
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
            studioParamLabel(title)
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
        .frame(minHeight: 32)
    }

    private func studioParamLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.regular))
            .foregroundStyle(theme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(width: 56, alignment: .leading)
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
        applyBGMSceneDefaultFineTune(for: scene)
    }

    /// Resets pitch/rhythm/melody and sets tempo to the scene's default-mood mapping.
    private func applyBGMSceneDefaultFineTune(for scene: Catalog.BGMScene) {
        suppressFineTuneReact = true
        bgmPitch = 0
        bgmRhythm = 0.5
        bgmMelody = true
        if let tempo = Self.mappedBGMTempo(
            genreId: genreId,
            sceneId: scene.rawValue,
            moodId: scene.defaultMood.rawValue,
            lengthId: lengthId,
            instrumentId: instrumentId
        ) {
            bgmTempo = tempo
            bgmSceneDefaultTempo = tempo
        } else {
            bgmSceneDefaultTempo = nil
        }
        Task { @MainActor in suppressFineTuneReact = false }
    }

    private static func mappedBGMTempo(
        genreId: String,
        sceneId: String,
        moodId: String,
        lengthId: String,
        instrumentId: String
    ) -> Double? {
        let intent = SoundIntent(
            soundType: .bgm,
            genreId: genreId,
            sceneId: sceneId,
            purposeId: nil,
            moodId: moodId,
            lengthId: lengthId,
            instrumentId: instrumentId,
            seed: 1
        )
        guard let mapped = try? IntentMapper().map(intent),
              case .bgm(let recipe) = mapped else { return nil }
        return Double(recipe.params.tempoBpm)
    }

    private func markBGMStructuralDirty() {
        guard soundType == .bgm else { return }
        catalogDirty = true
        exportURL = nil
        fineTuneTask?.cancel()
        generationViewModel.cancelPlayback()
        exportTask?.cancel()
        operationState.cancel()
        service.stop()
        monitor.stopMonitoring()
    }

    /// Mood / fine-tune: keep current audio, regenerate, then switch when ready.
    private func scheduleBGMLiveFromIntent() {
        guard soundType == .bgm, !suppressFineTuneReact else { return }
        exportURL = nil
        exportTask?.cancel()
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
            startLiveBGMReload()
        }
    }

    private func applyLoopImmediate() {
        guard monitor.isPlaying, mapped != nil else { return }
        service.setLooping(loopEnabled)
        monitor.setLooping(loopEnabled)
    }

    private func resetSFXToDefaults() {
        guard soundType == .sfx else { return }
        hapticMedium()
        let wasPlaying = monitor.isPlaying
        suppressFineTuneReact = true
        moodId = Catalog.Mood.neutral.rawValue
        syncSFXSlidersFromMood()
        if let purpose = Catalog.SFXPurpose(rawValue: purposeId) {
            sfxDurationMs = Double(purpose.category.defaultDurationMs)
            lengthId = nearestSFXLengthId(ms: Int(sfxDurationMs.rounded()))
        }
        sfxNoteCount = 1
        Task { @MainActor in suppressFineTuneReact = false }
        markSFXCatalogDirty()
        if wasPlaying {
            playNow(newSeed: false)
        }
    }

    private func resetBGMToDefaults() {
        guard soundType == .bgm else { return }
        guard let scene = Catalog.BGMScene.resolve(sceneId) else { return }

        let targetMood = scene.defaultMood.rawValue
        let targetPitch = 0.0
        let targetRhythm = 0.5
        let targetMelody = true
        let targetTempo =
            bgmSceneDefaultTempo
            ?? Self.mappedBGMTempo(
                genreId: genreId,
                sceneId: scene.rawValue,
                moodId: targetMood,
                lengthId: lengthId,
                instrumentId: instrumentId
            )
            ?? bgmTempo

        let alreadyDefault =
            moodId == targetMood
            && bgmPitch == targetPitch
            && bgmRhythm == targetRhythm
            && bgmMelody == targetMelody
            && Int(bgmTempo.rounded()) == Int(targetTempo.rounded())
        guard !alreadyDefault else {
            hapticMedium()
            return
        }

        hapticMedium()
        let wasPlaying = monitor.isPlaying
        suppressFineTuneReact = true
        moodId = targetMood
        bgmPitch = targetPitch
        bgmRhythm = targetRhythm
        bgmMelody = targetMelody
        bgmTempo = targetTempo
        bgmSceneDefaultTempo = targetTempo
        Task { @MainActor in suppressFineTuneReact = false }
        exportURL = nil
        fineTuneTask?.cancel()
        if wasPlaying, mapped != nil, !catalogDirty {
            fineTuneTask = Task { @MainActor in
                startLiveBGMReload(preservePitchRhythmMelody: false)
            }
        } else {
            catalogDirty = true
        }
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

    private func startLiveBGMReload(preservePitchRhythmMelody: Bool = true) {
        generationViewModel.startPlayback(
            showsGeneratingOverlay: true,
            work: {
                try await reloadBGMFromIntentLive(
                    preservePitchRhythmMelody: preservePitchRhythmMelody
                )
            },
            onError: presentError
        )
    }

    private func reloadBGMFromIntentLive(preservePitchRhythmMelody: Bool = true) async throws {
        let intent = currentIntent()
        let savedPitch = bgmPitch
        let savedRhythm = bgmRhythm
        let savedMelody = bgmMelody
        let mappedRecipe = try service.map(intent)
        try Task.checkCancellation()
        mapped = mappedRecipe
        syncFineTuneFromMapped(mappedRecipe)
        if preservePitchRhythmMelody {
            // Keep fine-tune pitch/rhythm/melody across mood-driven remaps.
            bgmPitch = savedPitch
            bgmRhythm = savedRhythm
            bgmMelody = savedMelody
        } else {
            bgmPitch = 0
            bgmRhythm = 0.5
            bgmMelody = true
        }
        applyCurrentBGMParamsToMapped()
        guard let mapped else { throw AudioPlayerError.emptyBuffer }
        try await generationViewModel.generateAndPlay(
            recipe: mapped,
            intent: intent,
            loopEnabled: loopEnabled
        )
        catalogDirty = false
        monitor.start(duration: mapped.durationSeconds, looping: loopEnabled)
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
        exportTask?.cancel()
        service.stop()
        monitor.stopMonitoring()
    }

    private func markSFXParamsEdited() {
        guard soundType == .sfx, !suppressFineTuneReact else { return }
        exportURL = nil
        exportTask?.cancel()
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
        exportTask?.cancel()
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
        let needsGenerate = mapped == nil || catalogDirty || newSeed
        generationViewModel.startPlayback(
            showsGeneratingOverlay: soundType == .bgm && needsGenerate,
            work: { try await playNowAsync(newSeed: newSeed) },
            onError: presentError
        )
    }

    private func playNowAsync(newSeed: Bool) async throws {
        if newSeed {
            switch mapped {
            case .bgm(let recipe):
                seed = service.withDistinctBGMSeed(currentIntent(), avoiding: recipe).seed ?? seed
            case .sfx(let recipe):
                seed = service.withDistinctSFXSeed(currentIntent(), avoiding: recipe).seed ?? seed
            case nil:
                seed = service.withNewSeed(currentIntent()).seed ?? seed
            }
            catalogDirty = true
        }
        let intent = currentIntent()
        let needsGenerate = mapped == nil || catalogDirty || newSeed
        if needsGenerate {
            if soundType == .bgm {
                // 別パターン must keep UI conditions; only seed changes.
                let savedTempo = bgmTempo
                let savedPitch = bgmPitch
                let savedRhythm = bgmRhythm
                let savedMelody = bgmMelody
                let savedInstrument = instrumentId
                let mappedRecipe = try service.map(intent)
                try Task.checkCancellation()
                mapped = mappedRecipe
                if newSeed {
                    bgmTempo = savedTempo
                    bgmPitch = savedPitch
                    bgmRhythm = savedRhythm
                    bgmMelody = savedMelody
                    instrumentId = savedInstrument
                } else {
                    syncFineTuneFromMapped(mappedRecipe)
                }
                // A newly mapped BGM has no buffer yet. Apply the visible
                // controls before the shared generation/playback path runs.
                applyCurrentBGMParamsToMapped()
            } else {
                let mappedRecipe = try service.map(intent)
                try Task.checkCancellation()
                mapped = mappedRecipe
                // Keep current slider values (mood/purpose already synced them when edited).
            }
            catalogDirty = false
        } else if soundType == .bgm {
            applyCurrentBGMParamsToMapped()
        }
        try Task.checkCancellation()
        if soundType == .sfx {
            applyCurrentSFXParamsToMapped()
        }
        guard let mapped else { throw AudioPlayerError.emptyBuffer }
        try await generationViewModel.generateAndPlay(
            recipe: mapped,
            intent: intent,
            loopEnabled: loopEnabled
        )
        monitor.start(duration: mapped.durationSeconds, looping: loopEnabled)
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
        generationViewModel.startPlayback(
            showsGeneratingOverlay: soundType == .bgm,
            work: {
                try await generationViewModel.generateAndPlay(
                    recipe: current,
                    intent: intent,
                    loopEnabled: loopEnabled
                )
                monitor.start(
                    duration: current.durationSeconds,
                    looping: loopEnabled
                )
            },
            onError: presentError
        )
    }

    private func exportAndShare() {
        exportTask?.cancel()
        exportTask = Task { @MainActor in
            await exportAndShareAsync()
        }
    }

    private func exportAndShareAsync() async {
        guard proStore.canExport else {
            showProUpgrade = true
            return
        }
        let operationID = operationState.begin(kind: .export)
        defer { operationState.end(operationID) }
        do {
            let mapped = try resolvedRecipeForCurrentControls()
            let intent = currentIntent()
            let url = try await generationViewModel.export(recipe: mapped, intent: intent)
            exportURL = url
            proStore.recordExport()
            showShareSheet = true
        } catch is CancellationError {
            return
        } catch {
            errorText = error.localizedDescription
            showError = true
        }
    }

    /// Produces a recipe from the visible controls immediately before an action.
    /// This avoids using an older cached recipe after a slider edit.
    private func resolvedRecipeForCurrentControls() throws -> MappedRecipe {
        if mapped == nil || catalogDirty {
            let mappedRecipe = try service.map(currentIntent())
            mapped = mappedRecipe
            syncFineTuneFromMapped(mappedRecipe)
            catalogDirty = false
        }
        if soundType == .bgm {
            applyCurrentBGMParamsToMapped()
        } else {
            applyCurrentSFXParamsToMapped()
        }
        guard let mapped else { throw AudioPlayerError.emptyBuffer }
        return mapped
    }

    private func saveLibrary() {
        guard proStore.canSaveToLibrary else {
            showProUpgrade = true
            return
        }
        run {
            let currentRecipe = try resolvedRecipeForCurrentControls()
            // Persist a file reference only when the most recently exported buffer
            // is exactly the recipe being saved.
            let exportFileName = service.lastMapped == currentRecipe
                ? service.lastExportURL?.lastPathComponent
                : nil
            try library.save(currentIntent(), exportFileName: exportFileName)
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
            if let scene = Catalog.BGMScene.resolve(sceneId),
               moodId == scene.defaultMood.rawValue {
                bgmSceneDefaultTempo = Double(recipe.params.tempoBpm)
            }
        }
    }

    private func presentError(_ error: Error) {
        errorText = error.localizedDescription
        showError = true
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
        let operationID = operationState.begin(kind: .librarySave)
        defer { operationState.end(operationID) }
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
    @State private var playbackViewModel = LibraryPlaybackViewModel()
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
                                playbackViewModel.stop()
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
        .onAppear {
            library.load()
            if let loadError = library.consumeLoadError() {
                errorText = loadError
                showError = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: AudioPlaybackNotification.stopped,
            object: service
        )) { _ in
            playbackViewModel.handleSystemStop()
        }
        .onDisappear {
            playbackViewModel.stop()
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
                    Image(systemName: playbackViewModel.isPlaying(entry) ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(playbackViewModel.isBusy)
                .accessibilityLabel(playbackViewModel.isPlaying(entry) ? "停止" : "再生")
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
                    Label(
                        playbackViewModel.isPlaying(entry) ? "停止" : "再生",
                        systemImage: playbackViewModel.isPlaying(entry) ? "stop.fill" : "play.fill"
                    )
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
        playbackViewModel.stopIfActive(entry)
        do {
            try library.remove(entry)
        } catch {
            errorText = error.localizedDescription
            showError = true
            return
        }
        if library.entries.isEmpty {
            isDeleting = false
        }
    }

    private func togglePlayback(_ entry: LibraryEntry) {
        playbackViewModel.toggle(entry) { error in
            errorText = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    @State private var proStore = ProStore.shared
    @State private var showProUpgrade = false
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

            Section("レトロサウンド Pro") {
                if proStore.isPro {
                    Label("Proをご利用中です", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent)
                } else {
                    Text("無料版はライブラリ保存10件、WAV書き出し・共有は1日3回までです。")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText)
                    Button("Proにアップグレード") {
                        showProUpgrade = true
                    }
                    .foregroundStyle(theme.accent)
                    Button("購入を復元") {
                        Task { await proStore.restore() }
                    }
                    .foregroundStyle(theme.accent)
                }
            }
            .themedListRowBackground(theme)

            Section("アプリ") {
                LabeledContent("バージョン", value: appVersion)
            }
            .themedListRowBackground(theme)

            Section("レトロサウンドについて") {
                Text("レトロサウンドは、外部AIを使わず、端末内の手続き生成とシンセサイザーでゲーム向けのBGM・効果音をつくるアプリです。生成した音は、ご自身のゲームや作品で利用できます。")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)

                policyLink(title: "公式サイト", url: AppStoreLinks.website)
                policyLink(title: "プライバシーポリシー", url: AppStoreLinks.privacyPolicy)
                policyLink(title: "利用規約", url: AppStoreLinks.termsOfUse)
                policyLink(title: "サポート", url: AppStoreLinks.support)
            }
            .themedListRowBackground(theme)
        }
        .navigationTitle("設定")
        .themedListBackground(theme)
        .sheet(isPresented: $showProUpgrade) {
            ProUpgradeSheet(store: proStore)
        }
        .alert("購入情報", isPresented: Binding(
            get: { proStore.errorMessage != nil },
            set: { if !$0 { proStore.dismissError() } }
        )) {
            Button("OK", role: .cancel) { proStore.dismissError() }
        } message: {
            Text(proStore.errorMessage ?? "")
        }
    }

    private func selectTheme(_ option: AppThemeID) {
        if option == .random {
            themeRandomPick = AppTheme.rollRandomPick().rawValue
        }
        themeIDRaw = option.rawValue
    }

    private var appVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(shortVersion) (\(build))"
    }

    @ViewBuilder
    private func policyLink(title: String, url: URL?) -> some View {
        if let url {
            Link(title, destination: url)
                .foregroundStyle(theme.accent)
        } else {
            Text("\(title)は公開準備中です")
                .font(.footnote)
                .foregroundStyle(theme.secondaryText)
        }
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
