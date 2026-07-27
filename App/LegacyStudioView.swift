import AudioGenCore
import SwiftUI

/// Phase 1–2 debug studio, kept under Settings.
struct LegacyStudioView: View {
    var body: some View {
        TabView {
            LegacySFXStudioView()
                .tabItem { Label("効果音", systemImage: "waveform") }
            LegacyBGMStudioView()
                .tabItem { Label("BGM", systemImage: "music.note.list") }
        }
        .navigationTitle("旧スタジオ")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { stopAllPlayback() }
        .onDisappear { stopAllPlayback() }
    }
}

private struct LegacySFXStudioView: View {
    @State private var studio = SFXStudioController()
    @State private var category: SFXCategory = .attackLight
    @State private var seed: Double = 1
    @State private var pitch: Double = 1.0
    @State private var timbre: Double = 0.5
    @State private var intensity: Double = 0.7
    @State private var variation: Double = 0
    @State private var statusText = "カテゴリを選んで再生"
    @State private var isBusy = false

    private var recipe: SFXRecipe {
        SFXRecipe.make(
            category: category,
            seed: UInt64(seed.rounded()),
            pitch: Float(pitch),
            timbre: Float(timbre),
            intensity: Float(intensity),
            variation: Int(variation.rounded())
        )
    }

    var body: some View {
        Form {
            Picker("カテゴリ", selection: $category) {
                ForEach(SFXCategory.allCases) { Text($0.displayName).tag($0) }
            }
            Slider(value: $seed, in: 1...9999, step: 1)
            Slider(value: $pitch, in: 0.5...2)
            Slider(value: $timbre, in: 0...1)
            Slider(value: $intensity, in: 0...1)
            Slider(value: $variation, in: 0...7, step: 1)
            Button("再生") {
                isBusy = true
                defer { isBusy = false }
                do {
                    try studio.play(recipe)
                    statusText = "再生中"
                } catch {
                    statusText = error.localizedDescription
                }
            }
            .disabled(isBusy)
            Button("停止", role: .destructive, action: studio.stop)
            Text(statusText).font(.footnote)
        }
    }
}

private struct LegacyBGMStudioView: View {
    @State private var studio = BGMStudioController()
    @State private var preset: BGMPreset = .battleNormal
    @State private var seed: Double = 1
    @State private var statusText = "BGM"
    @State private var isBusy = false

    private var recipe: BGMRecipe {
        preset.makeRecipe(seed: UInt64(seed.rounded()))
    }

    var body: some View {
        Form {
            Picker("プリセット", selection: $preset) {
                ForEach(BGMPreset.allCases) { Text($0.displayName).tag($0) }
            }
            Slider(value: $seed, in: 1...9999, step: 1)
            Button("一回再生") { play(loop: false) }
            Button("ループ再生") { play(loop: true) }
            Button("停止", role: .destructive, action: studio.stop)
            Text(statusText).font(.footnote)
        }
    }

    private func play(loop: Bool) {
        isBusy = true
        defer { isBusy = false }
        do {
            try studio.play(recipe, loop: loop)
            statusText = loop ? "ループ中" : "一回再生"
        } catch {
            statusText = error.localizedDescription
        }
    }
}
