import AudioGenCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView()
            }
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

// MARK: - Shared UI

private struct CreateCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
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

// MARK: - Home

struct HomeView: View {
    @State private var library = LibraryStore.shared
    @State private var genreId = Catalog.Genre.cardBattle.rawValue

    private var selectedGenreAvailable: Bool {
        Catalog.Genre(rawValue: genreId)?.isAvailable == true
    }

    var body: some View {
        List {
            Section {
                Text("ジャンルを選んでから、BGM か効果音を作ります。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("ジャンル", selection: $genreId) {
                    ForEach(Catalog.availableGenres.filter(\.isAvailable)) { item in
                        Text(item.displayName).tag(item.id)
                    }
                }
                .pickerStyle(.menu)

                if selectedGenreAvailable {
                    NavigationLink {
                        StudioView(genreId: genreId, soundType: .bgm)
                    } label: {
                        CreateCard(
                            title: "BGMを作る",
                            subtitle: "戦闘・メニューなどのループ曲",
                            systemImage: "music.note.list"
                        )
                    }
                    NavigationLink {
                        StudioView(genreId: genreId, soundType: .sfx)
                    } label: {
                        CreateCard(
                            title: "効果音を作る",
                            subtitle: "攻撃・カード・UIなどの短い音",
                            systemImage: "waveform"
                        )
                    }
                } else {
                    Text("対応ジャンルを選んでください。")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("新しく作る")
            }

            if !library.recent.isEmpty {
                Section("最近作った音") {
                    ForEach(library.recent) { entry in
                        NavigationLink {
                            StudioView(intent: entry.intent, autoPlay: true)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.intent.title)
                                    .font(.body.weight(.medium))
                                Text(recentSubtitle(entry.intent))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .navigationTitle("GameSoundCreator")
        .onAppear { library.load() }
    }

    private func recentSubtitle(_ intent: SoundIntent) -> String {
        let genre = Catalog.Genre(rawValue: intent.genreId)?.displayName ?? intent.genreId
        let mood = Catalog.Mood(rawValue: intent.moodId)?.displayName ?? intent.moodId
        return "\(genre) · \(intent.soundType.displayName) · \(mood)"
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
    @State private var showSceneSheet = false
    @State private var showInstrumentSheet = false
    @State private var showPurposeSheet = false
    @State private var isBusy = false
    @State private var didAppear = false
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
        List {
            playbackSection
            fineTuneSection
            patternSection
            catalogSection
        }
        .navigationTitle(soundType == .bgm ? "BGM" : "効果音")
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
        .sheet(isPresented: $showSceneSheet) {
            scenePickerSheet
        }
        .sheet(isPresented: $showInstrumentSheet) {
            instrumentPickerSheet
        }
        .sheet(isPresented: $showPurposeSheet) {
            purposePickerSheet
        }
        .onChange(of: sfxPitch) { _, _ in scheduleFineTune() }
        .onChange(of: sfxTimbre) { _, _ in scheduleFineTune() }
        .onChange(of: sfxIntensity) { _, _ in scheduleFineTune() }
        .onChange(of: bgmTempo) { _, _ in scheduleFineTune() }
        .onChange(of: bgmEnergy) { _, _ in scheduleFineTune() }
        .onChange(of: bgmDensity) { _, _ in scheduleFineTune() }
        .onChange(of: bgmMelody) { _, _ in scheduleFineTune() }
    }

    // MARK: Sections

    private var playbackSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView(value: monitor.progress)
                    .tint(.accentColor)
                HStack {
                    Text(monitor.currentTimeText)
                    Spacer()
                    Text(monitor.durationText)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        playNow(newSeed: false)
                    } label: {
                        Label("再生", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)

                    Button(role: .destructive) {
                        service.stop()
                        monitor.stopMonitoring()
                    } label: {
                        Label("停止", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                }

                if soundType == .bgm {
                    Toggle("ループ再生", isOn: $loopEnabled)
                }

                Text(genreName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("再生")
        }
    }

    private var fineTuneSection: some View {
        Section {
            if soundType == .sfx {
                sliderRow("高さ", value: $sfxPitch, range: 0.5...2.0)
                sliderRow("音色", value: $sfxTimbre, range: 0...1)
                sliderRow("強さ", value: $sfxIntensity, range: 0...1)
            } else {
                sliderRow("速さ", value: $bgmTempo, range: 80...160, step: 1)
                sliderRow("迫力", value: $bgmEnergy, range: 0...1)
                sliderRow("密度", value: $bgmDensity, range: 0...1)
                Toggle("メロディ", isOn: $bgmMelody)
            }
        } header: {
            Text("微調整")
        } footer: {
            Text("動かした内容はすぐ音に反映されます。")
        }
    }

    private var patternSection: some View {
        Section {
            Button {
                playNow(newSeed: true)
            } label: {
                Label("別パターン", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
            }
            .disabled(isBusy)
            .listRowBackground(Color.accentColor.opacity(0.12))
        } footer: {
            Text("同じ条件のまま、別のフレーズやリズムを試します。")
        }
    }

    private var catalogSection: some View {
        Section {
            if soundType == .bgm {
                Button {
                    showSceneSheet = true
                } label: {
                    LabeledContent("シーン", value: Catalog.BGMScene(rawValue: sceneId)?.displayName ?? sceneId)
                }

                Button {
                    showInstrumentSheet = true
                } label: {
                    LabeledContent(
                        "音色",
                        value: Catalog.Instrument.resolve(instrumentId).displayName
                    )
                }
            } else {
                Button {
                    showPurposeSheet = true
                } label: {
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
        } header: {
            Text("条件")
        } footer: {
            Text("シーンや用途は一覧から選べます。")
        }
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(step != nil ? String(format: "%.0f", value.wrappedValue) : String(format: "%.2f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let step {
                Slider(value: value, in: range, step: step)
            } else {
                Slider(value: value, in: range)
            }
        }
        .padding(.vertical, 2)
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

    // MARK: Sheets

    private var scenePickerSheet: some View {
        NavigationStack {
            List {
                ForEach(Catalog.availableBGMScenes) { item in
                    CatalogChoiceRow(
                        title: item.displayName,
                        subtitle: nil,
                        selected: sceneId == item.id
                    ) {
                        applyScene(item.id)
                        showSceneSheet = false
                    }
                }
            }
            .navigationTitle("シーン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { showSceneSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var instrumentPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(Catalog.instruments) { item in
                    CatalogChoiceRow(
                        title: item.displayName,
                        subtitle: Catalog.Instrument(rawValue: item.id)?.hint,
                        selected: instrumentId == item.id
                    ) {
                        instrumentId = item.id
                        markCatalogDirtyAndRefresh()
                        showInstrumentSheet = false
                    }
                }
            }
            .navigationTitle("音色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { showInstrumentSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var purposePickerSheet: some View {
        NavigationStack {
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
                                showPurposeSheet = false
                            }
                        }
                    }
                }
            }
            .navigationTitle("用途")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { showPurposeSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
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

    /// Play regenerates when needed. `newSeed` forces a different pattern.
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

struct LibraryView: View {
    @State private var library = LibraryStore.shared

    var body: some View {
        List {
            if library.entries.isEmpty {
                ContentUnavailableView(
                    "保存した音はまだありません",
                    systemImage: "books.vertical",
                    description: Text("制作画面右上の共有メニューから保存できます。")
                )
            } else {
                ForEach(library.entries) { entry in
                    NavigationLink {
                        StudioView(intent: entry.intent, autoPlay: false)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.intent.title)
                            Text("\(Catalog.Genre(rawValue: entry.intent.genreId)?.displayName ?? "") · \(entry.intent.soundType.displayName) · \(Catalog.Mood(rawValue: entry.intent.moodId)?.displayName ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        try? library.remove(library.entries[index])
                    }
                }
            }
        }
        .navigationTitle("ライブラリ")
        .onAppear { library.load() }
    }
}

// MARK: - Settings

struct SettingsView: View {
    var body: some View {
        List {
            Section("アプリ") {
                LabeledContent("バージョン", value: "0.3.3 (制作UI刷新)")
                LabeledContent("カタログ", value: "カードバトル MVP")
                LabeledContent("サンプルレート", value: "44100 Hz")
            }
            Section("開発用") {
                NavigationLink("旧スタジオ (SE/BGM 詳細)") {
                    LegacyStudioView()
                }
            }
            Section("について") {
                Text("外部AIは使わず、端末内の手続き生成だけで動作します。再生ですぐ聴き、微調整はリアルタイムに反映されます。")
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
