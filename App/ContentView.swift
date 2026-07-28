import AudioGenCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedTab = 0

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
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct CatalogChoiceRow: View {
    let title: String
    let subtitle: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
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
    let isPlaying: Bool

    func body(content: Content) -> some View {
        if isPlaying {
            content.buttonStyle(.borderedProminent)
        } else {
            content
                .buttonStyle(.bordered)
                .tint(.accentColor)
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
    @State private var genreId = Catalog.Genre.cardBattle.rawValue
    @State private var path = NavigationPath()
    @State private var pressedType: SoundType?

    private var selectedGenreAvailable: Bool {
        Catalog.Genre(rawValue: genreId)?.isAvailable == true
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    VStack(spacing: 4) {
                        Text("レトロゲーム")
                        Text("サウンドクリエイター")
                    }
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
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
                            title: "BGMを作る",
                            subtitle: "戦闘・メニューなどのループ曲",
                            systemImage: "music.note.list"
                        )
                        createRow(
                            type: .sfx,
                            title: "効果音を作る",
                            subtitle: "攻撃・カード・UIなどの短い音",
                            systemImage: "waveform"
                        )
                    } else {
                        Text("対応ジャンルを選んでください。")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
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
        Button {
            guard pressedType == nil else { return }
            hapticMedium()
            withAnimation(.easeOut(duration: 0.12)) {
                pressedType = type
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                path.append(CreateDestination(soundType: type, genreId: genreId))
                pressedType = nil
            }
        } label: {
            CreateCard(title: title, subtitle: subtitle, systemImage: systemImage)
                .opacity(pressedType == type ? 0.55 : 1)
                .scaleEffect(pressedType == type ? 0.98 : 1)
                .animation(.easeOut(duration: 0.12), value: pressedType)
        }
        .buttonStyle(.plain)
        .disabled(pressedType != nil)
    }
}

// MARK: - Studio

struct StudioView: View {
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
    @State private var showConditionsSheet = false
    @State private var conditionsPath = NavigationPath()
    @State private var isBusy = false
    @State private var didAppear = false
    @State private var patternFlash = false
    @State private var suppressFineTuneReact = false
    @State private var fineTuneTask: Task<Void, Never>?
    @State private var catalogTask: Task<Void, Never>?

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

            VStack(spacing: 8) {
                ProgressView(value: monitor.progress)
                    .tint(.accentColor)
                HStack {
                    Text(monitor.currentTimeText)
                    Spacer()
                    Text(monitor.durationText)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 14)

            HStack(spacing: 10) {
                playControlButton

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
                .tint(.accentColor)
                .disabled(isBusy)
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
                .tint(.accentColor)
                .disabled(isBusy)
                .opacity(patternFlash ? 0.7 : 1)
                .animation(.easeOut(duration: 0.12), value: patternFlash)

                Text("Seed \(seed)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Color(.systemGroupedBackground))
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
            catalogTask?.cancel()
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
        .sheet(isPresented: $showConditionsSheet, onDismiss: {
            conditionsPath = NavigationPath()
        }) {
            conditionsEditorSheet
        }
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
                    .tint(monitor.isPlaying ? Color.white : Color.accentColor)
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
                .foregroundStyle(monitor.isPlaying ? Color.white : Color.accentColor)
        }
        .disabled(isBusy)
        .modifier(PlayButtonChrome(isPlaying: monitor.isPlaying))
    }

    private var conditionsBar: some View {
        Button {
            hapticLight()
            conditionsPath = NavigationPath()
            showConditionsSheet = true
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("条件設定")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ConditionsWrap {
                        ForEach(Array(conditionsSegments.enumerated()), id: \.offset) { index, segment in
                            let isLast = index == conditionsSegments.count - 1
                            Text(isLast ? segment : "\(segment)、 ")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: Catalog bindings

    private var moodBinding: Binding<String> {
        Binding(
            get: { moodId },
            set: { newValue in
                guard moodId != newValue else { return }
                moodId = newValue
                markCatalogDirtyAndRefresh()
            }
        )
    }

    private var lengthBinding: Binding<String> {
        Binding(
            get: { lengthId },
            set: { newValue in
                guard lengthId != newValue else { return }
                lengthId = newValue
                markCatalogDirtyAndRefresh()
            }
        )
    }

    private func markCatalogDirtyAndRefresh() {
        catalogDirty = true
        exportURL = nil
        scheduleCatalogRefresh()
    }

    // MARK: Conditions navigation (single sheet, push pickers)

    private enum ConditionsRoute: Hashable {
        case scene
        case instrument
        case purpose
    }

    private var conditionsEditorSheet: some View {
        NavigationStack(path: $conditionsPath) {
            List {
                if soundType == .bgm {
                    NavigationLink(value: ConditionsRoute.scene) {
                        LabeledContent("シーン", value: Catalog.BGMScene(rawValue: sceneId)?.displayName ?? sceneId)
                    }
                    NavigationLink(value: ConditionsRoute.instrument) {
                        LabeledContent("音色", value: Catalog.Instrument.resolve(instrumentId).displayName)
                    }
                } else {
                    NavigationLink(value: ConditionsRoute.purpose) {
                        let purpose = Catalog.SFXPurpose(rawValue: purposeId)
                        LabeledContent(
                            "用途",
                            value: purpose.map { "\($0.group) / \($0.displayName)" } ?? purposeId
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("雰囲気")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("雰囲気", selection: moodBinding) {
                        ForEach(Catalog.moods) { item in
                            Text(item.displayName).tag(item.id)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text("長さ")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("長さ", selection: lengthBinding) {
                        ForEach(soundType == .bgm ? Catalog.bgmLengths : Catalog.sfxLengths) { item in
                            Text(item.displayName).tag(item.id)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 2)
            }
            .navigationTitle("条件設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { showConditionsSheet = false }
                }
            }
            .navigationDestination(for: ConditionsRoute.self) { route in
                switch route {
                case .scene:
                    scenePickerList
                case .instrument:
                    instrumentPickerList
                case .purpose:
                    purposePickerList
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var scenePickerList: some View {
        List {
            ForEach(Catalog.availableBGMScenes) { item in
                CatalogChoiceRow(
                    title: item.displayName,
                    subtitle: nil,
                    selected: sceneId == item.id
                ) {
                    applyScene(item.id)
                    conditionsPath.removeLast()
                }
            }
        }
        .navigationTitle("シーン")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var instrumentPickerList: some View {
        List {
            ForEach(Catalog.instruments) { item in
                CatalogChoiceRow(
                    title: item.displayName,
                    subtitle: Catalog.Instrument(rawValue: item.id)?.hint,
                    selected: instrumentId == item.id
                ) {
                    instrumentId = item.id
                    markCatalogDirtyAndRefresh()
                    conditionsPath.removeLast()
                }
            }
        }
        .navigationTitle("音色")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var purposePickerList: some View {
        List {
            ForEach(Catalog.sfxPurposeGroupOrder, id: \.self) { group in
                Section(group) {
                    ForEach(Catalog.sfxPurposes(in: group), id: \.rawValue) { purpose in
                        CatalogChoiceRow(
                            title: purpose.displayName,
                            subtitle: nil,
                            selected: purposeId == purpose.rawValue
                        ) {
                            purposeGroup = group
                            purposeId = purpose.rawValue
                            lengthId = purpose.defaultLength.rawValue
                            markCatalogDirtyAndRefresh()
                            conditionsPath.removeLast()
                        }
                    }
                }
            }
        }
        .navigationTitle("用途")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func applyScene(_ id: String) {
        sceneId = id
        if let scene = Catalog.BGMScene(rawValue: id) {
            moodId = scene.defaultMood.rawValue
            lengthId = scene.defaultLength.rawValue
            instrumentId = Catalog.Instrument.defaultFor(scene: scene).rawValue
        }
        markCatalogDirtyAndRefresh()
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

    private func scheduleCatalogRefresh() {
        catalogTask?.cancel()
        fineTuneTask?.cancel()
        let delay: Duration = soundType == .bgm ? .milliseconds(350) : .milliseconds(100)
        catalogTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            playNow(newSeed: false)
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
        if newSeed {
            seed = UInt64.random(in: 1...999_999)
            catalogDirty = true
        }
        run {
            let intent = currentIntent()
            let needsGenerate = mapped == nil || catalogDirty || newSeed
            if needsGenerate {
                let (mappedRecipe, _) = try service.generate(intent)
                mapped = mappedRecipe
                syncFineTuneFromMapped(mappedRecipe)
                catalogDirty = false
            }
            try service.playLast(loop: loopEnabled && soundType == .bgm)
            let duration = mapped?.durationSeconds ?? 1
            monitor.start(duration: duration, looping: loopEnabled && soundType == .bgm)
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
        run {
            try service.play(mapped: current, intent: currentIntent(), loop: loopEnabled && soundType == .bgm)
            monitor.start(duration: current.durationSeconds, looping: loopEnabled && soundType == .bgm)
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
    @State private var library = LibraryStore.shared
    @State private var sort: LibrarySort = .newest
    @State private var playingId: UUID?
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var showError = false
    @State private var editMode: EditMode = .inactive

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
            } else {
                ForEach(sortedEntries) { entry in
                    libraryRow(entry)
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("ライブラリ")
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !library.entries.isEmpty {
                    EditButton()
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
                }
            }
        }
        .onAppear { library.load() }
        .onDisappear {
            service.stop()
            playingId = nil
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
            Button {
                hapticMedium()
                togglePlayback(entry)
            } label: {
                Image(systemName: playingId == entry.id ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isBusy || editMode.isEditing)
            .accessibilityLabel(playingId == entry.id ? "停止" : "再生")

            if editMode.isEditing {
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
            Button {
                togglePlayback(entry)
            } label: {
                Label(playingId == entry.id ? "停止" : "再生", systemImage: playingId == entry.id ? "stop.fill" : "play.fill")
            }
            Button(role: .destructive) {
                try? library.remove(entry)
                if playingId == entry.id {
                    service.stop()
                    playingId = nil
                }
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }

    private func libraryText(_ entry: LibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.intent.title)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
            Text(subtitle(entry))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(dateText(entry.savedAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
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

    private func delete(at offsets: IndexSet) {
        let targets = offsets.map { sortedEntries[$0] }
        for entry in targets {
            try? library.remove(entry)
            if playingId == entry.id {
                service.stop()
                playingId = nil
            }
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
    var body: some View {
        List {
            Section("アプリ") {
                LabeledContent("バージョン", value: "0.3.4 (UI磨き)")
                LabeledContent("カタログ", value: "カードバトル MVP")
                LabeledContent("サンプルレート", value: "44100 Hz")
            }
            Section("開発用") {
                NavigationLink("旧スタジオ (SE/BGM 詳細)") {
                    LegacyStudioView()
                }
            }
            Section("について") {
                Text("外部AIは使わず、端末内の手続き生成だけで動作します。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("設定")
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
