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

// MARK: - Home

struct HomeView: View {
    @State private var library = LibraryStore.shared

    var body: some View {
        List {
            Section {
                Text("ジャンルやシーンを選ぶだけで、ゲーム用の音を作れます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            Section("新しく作る") {
                NavigationLink {
                    WizardView(soundType: .bgm)
                } label: {
                    Label("BGMを作る", systemImage: "music.note.list")
                }
                NavigationLink {
                    WizardView(soundType: .sfx)
                } label: {
                    Label("効果音を作る", systemImage: "waveform")
                }
            }

            if !library.recent.isEmpty {
                Section("最近作った音") {
                    ForEach(library.recent) { entry in
                        NavigationLink {
                            ResultView(intent: entry.intent, autoPlay: true)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.intent.title)
                                Text(entry.intent.soundType.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("GameSoundCreator")
        .onAppear { library.load() }
    }
}

// MARK: - Wizard

struct WizardView: View {
    let soundType: SoundType

    @State private var genreId = Catalog.Genre.cardBattle.rawValue
    @State private var sceneId = Catalog.BGMScene.battleNormal.rawValue
    @State private var purposeId = Catalog.SFXPurpose.attackLight.rawValue
    @State private var moodId = Catalog.Mood.tense.rawValue
    @State private var lengthId = Catalog.BGMLength.bars16.rawValue

    var body: some View {
        List {
            Section("ジャンル") {
                ForEach(Catalog.availableGenres) { item in
                    genreRow(item)
                }
            }

            Section(soundType == .bgm ? "シーン" : "用途") {
                if soundType == .bgm {
                    ForEach(Catalog.availableBGMScenes) { item in
                        selectRow(title: item.displayName, selected: sceneId == item.id) {
                            sceneId = item.id
                            if let scene = Catalog.BGMScene(rawValue: item.id) {
                                moodId = scene.defaultMood.rawValue
                                lengthId = scene.defaultLength.rawValue
                            }
                        }
                    }
                } else {
                    ForEach(Catalog.availableSFXPurposes) { item in
                        selectRow(
                            title: "\(item.group ?? "") · \(item.displayName)",
                            selected: purposeId == item.id
                        ) {
                            purposeId = item.id
                            if let purpose = Catalog.SFXPurpose(rawValue: item.id) {
                                lengthId = purpose.defaultLength.rawValue
                            }
                        }
                    }
                }
            }

            Section("雰囲気") {
                Picker("雰囲気", selection: $moodId) {
                    ForEach(Catalog.moods) { item in
                        Text(item.displayName).tag(item.id)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("長さ") {
                Picker("長さ", selection: $lengthId) {
                    ForEach(soundType == .bgm ? Catalog.bgmLengths : Catalog.sfxLengths) { item in
                        Text(item.displayName).tag(item.id)
                    }
                }
                .pickerStyle(.segmented)
                if soundType == .bgm, let length = Catalog.BGMLength(rawValue: lengthId) {
                    Text("\(length.approximateSecondsHint)。ループは小節の頭（4/4）で繋がります。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                NavigationLink {
                    ResultView(intent: makeIntent(), autoPlay: true)
                } label: {
                    Text("生成して聴く")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(soundType == .bgm ? "BGMを作る" : "効果音を作る")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            stopAllPlayback()
            if soundType == .sfx {
                lengthId = Catalog.SFXPurpose.attackLight.defaultLength.rawValue
                moodId = Catalog.Mood.neutral.rawValue
            }
        }
    }

    private func makeIntent() -> SoundIntent {
        SoundIntent(
            soundType: soundType,
            genreId: genreId,
            sceneId: soundType == .bgm ? sceneId : nil,
            purposeId: soundType == .sfx ? purposeId : nil,
            moodId: moodId,
            lengthId: lengthId,
            seed: UInt64.random(in: 1...999_999)
        )
    }

    private func genreRow(_ item: Catalog.Item) -> some View {
        HStack {
            Text(item.displayName)
            Spacer()
            if item.isAvailable {
                if genreId == item.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            } else {
                Text("準備中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if item.isAvailable { genreId = item.id }
        }
        .foregroundStyle(item.isAvailable ? .primary : .secondary)
    }

    private func selectRow(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
        }
    }
}

// MARK: - Result

struct ResultView: View {
    @State private var intent: SoundIntent
    var autoPlay: Bool

    private var service: GenerationService { GenerationService.shared }
    @State private var monitor = PlaybackMonitor()
    @State private var mapped: MappedRecipe?
    @State private var loopEnabled = true
    @State private var status = "生成中…"
    @State private var errorText: String?
    @State private var exportURL: URL?
    @State private var showFineTune = false
    @State private var showShare = false
    @State private var isBusy = false
    @State private var library = LibraryStore.shared

    // Fine-tune mirrors
    @State private var sfxPitch: Double = 1
    @State private var sfxTimbre: Double = 0.5
    @State private var sfxIntensity: Double = 0.7
    @State private var bgmTempo: Double = 120
    @State private var bgmEnergy: Double = 0.5
    @State private var bgmDensity: Double = 0.5
    @State private var bgmMelody = true

    init(intent: SoundIntent, autoPlay: Bool) {
        _intent = State(initialValue: intent)
        self.autoPlay = autoPlay
        _loopEnabled = State(initialValue: intent.soundType == .bgm)
    }

    var body: some View {
        List {
            Section("いまの設定") {
                LabeledContent("種類", value: intent.soundType.displayName)
                LabeledContent("内容", value: intent.title)
                LabeledContent("雰囲気", value: Catalog.Mood(rawValue: intent.moodId)?.displayName ?? intent.moodId)
                LabeledContent("長さ", value: lengthLabel)
                if let seed = intent.seed {
                    LabeledContent("Seed", value: "\(seed)")
                }
            }

            Section("再生") {
                ProgressView(value: monitor.progress)
                    .tint(.accentColor)
                HStack {
                    Text(monitor.currentTimeText)
                    Spacer()
                    Text(monitor.durationText)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

                if intent.soundType == .bgm {
                    Toggle("ループ再生", isOn: $loopEnabled)
                }

                Button("再生") { play(loop: loopEnabled && intent.soundType == .bgm) }
                    .disabled(isBusy)
                Button("停止", role: .destructive) {
                    service.stop()
                    monitor.stopMonitoring()
                    status = "停止しました"
                }
            }

            Section {
                Button("別パターン") {
                    intent = service.withNewSeed(intent)
                    generateAndPlay()
                }
                .font(.headline)
                .disabled(isBusy)
            }

            Section("あとから調整") {
                Button("微調整") { showFineTune = true }
                NavigationLink("条件をやり直す") {
                    WizardView(soundType: intent.soundType)
                }
            }

            Section("保存・書き出し") {
                Button("ライブラリに保存") { saveLibrary() }
                    .disabled(isBusy)
                Button("WAVを書き出し") { exportWAV() }
                    .disabled(isBusy)
                if exportURL != nil {
                    Button("共有…") { showShare = true }
                }
            }

            Section("状態") {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("結果")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if mapped == nil {
                generateAndPlay(auto: autoPlay)
            }
        }
        .onDisappear {
            service.stop()
            monitor.stopMonitoring()
        }
        .sheet(isPresented: $showFineTune) {
            fineTuneSheet
        }
        .sheet(isPresented: $showShare) {
            if let exportURL {
                ShareSheet(items: [exportURL])
            }
        }
    }

    private var lengthLabel: String {
        if intent.soundType == .bgm {
            return Catalog.BGMLength(rawValue: intent.lengthId)?.displayName ?? intent.lengthId
        }
        return Catalog.SFXLength(rawValue: intent.lengthId)?.displayName ?? intent.lengthId
    }

    private var fineTuneSheet: some View {
        NavigationStack {
            Form {
                if intent.soundType == .sfx {
                    slider("高さ (Pitch)", value: $sfxPitch, range: 0.5...2.0)
                    slider("音色 (Timbre)", value: $sfxTimbre, range: 0...1)
                    slider("強さ (Intensity)", value: $sfxIntensity, range: 0...1)
                } else {
                    slider("速さ (Tempo)", value: $bgmTempo, range: 80...160, step: 1)
                    slider("迫力 (Energy)", value: $bgmEnergy, range: 0...1)
                    slider("密度 (Density)", value: $bgmDensity, range: 0...1)
                    Toggle("メロディ", isOn: $bgmMelody)
                }
            }
            .navigationTitle("微調整")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { showFineTune = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("適用して再生") {
                        applyFineTune()
                        showFineTune = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double? = nil) -> some View {
        HStack {
            Text(title)
            if let step {
                Slider(value: value, in: range, step: step)
            } else {
                Slider(value: value, in: range)
            }
        }
    }

    private func generateAndPlay(auto: Bool = true) {
        run {
            let (mappedRecipe, _) = try service.generate(intent)
            mapped = mappedRecipe
            syncFineTune(from: mappedRecipe)
            status = String(format: "生成完了 (%.2f秒)", service.lastGenerationSeconds)
            errorText = nil
            if auto {
                play(loop: loopEnabled && intent.soundType == .bgm)
            }
        }
    }

    private func play(loop: Bool) {
        run {
            if mapped == nil {
                let (mappedRecipe, _) = try service.generate(intent)
                mapped = mappedRecipe
                syncFineTune(from: mappedRecipe)
            }
            try service.playLast(loop: loop)
            let duration = mapped?.durationSeconds ?? 1
            monitor.start(duration: duration, looping: loop)
            status = loop ? "ループ再生中" : "一回再生中"
            errorText = nil
        }
    }

    private func exportWAV() {
        run {
            if mapped == nil {
                _ = try service.generate(intent)
            } else if service.lastBuffer == nil {
                _ = service.generate(mapped: mapped!, intent: intent)
            }
            let url = try service.exportLastToDocuments()
            exportURL = url
            status = "書き出し完了: \(url.lastPathComponent)"
        }
    }

    private func saveLibrary() {
        run {
            try library.save(intent, exportFileName: mapped?.exportFileName)
            status = "ライブラリに保存しました"
        }
    }

    private func syncFineTune(from mapped: MappedRecipe) {
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
        }
    }

    private func applyFineTune() {
        guard var current = mapped else { return }
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
            current = .bgm(recipe)
        }
        mapped = current
        run {
            try service.play(mapped: current, intent: intent, loop: loopEnabled && intent.soundType == .bgm)
            monitor.start(duration: current.durationSeconds, looping: loopEnabled && intent.soundType == .bgm)
            status = "微調整を適用して再生中"
        }
    }

    private func run(_ work: () throws -> Void) {
        isBusy = true
        defer { isBusy = false }
        do {
            try work()
        } catch {
            errorText = error.localizedDescription
            status = "エラーが発生しました"
        }
    }
}

// MARK: - Library

struct LibraryView: View {
    @State private var library = LibraryStore.shared

    var body: some View {
        List {
            if library.entries.isEmpty {
                Text("保存した音はまだありません。「結果」画面から保存できます。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(library.entries) { entry in
                    NavigationLink {
                        ResultView(intent: entry.intent, autoPlay: false)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.intent.title)
                            Text("\(entry.intent.soundType.displayName) · Seed \(entry.intent.seed.map(String.init) ?? "-")")
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
                LabeledContent("バージョン", value: "0.3.0 (Phase 3)")
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
