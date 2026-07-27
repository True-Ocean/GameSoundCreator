import AVFoundation
import XCTest
@testable import AudioGenCore

final class AudioGenCoreTests: XCTestCase {
    func testSineBufferHasExpectedFrameCount() {
        let buffer = SineWaveGenerator(durationSeconds: 1.0, sampleRate: 44_100).generate()
        XCTAssertEqual(buffer.frameLength, 44_100)
        XCTAssertEqual(buffer.format.sampleRate, 44_100, accuracy: 0.1)
        XCTAssertEqual(buffer.format.channelCount, 1)
    }

    func testWAVExportWritesNonEmptyFile() throws {
        let buffer = SineWaveGenerator(durationSeconds: 0.1).generate()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("audiogencore_test_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try WAVExporter().export(buffer: buffer, to: url)

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs[.size] as? NSNumber
        XCTAssertNotNil(size)
        XCTAssertGreaterThan(size?.intValue ?? 0, 1000)
    }

    func testSFXRecipeJSONRoundTrip() throws {
        let recipe = SFXRecipe.make(category: .attackLight, seed: 42, pitch: 1.1, timbre: 0.3, intensity: 0.8, variation: 2)
        let json = try recipe.jsonString()
        let decoded = try SFXRecipe.from(json: json)
        XCTAssertEqual(decoded, recipe)
    }

    func testSameRecipeProducesIdenticalWaveform() {
        let recipe = SFXRecipe.make(category: .skillCast, seed: 99, variation: 3)
        let engine = SFXEngine()
        let a = engine.generate(recipe)
        let b = engine.generate(recipe)
        XCTAssertEqual(a.frameLength, b.frameLength)
        assertBuffersEqual(a, b)
    }

    func testDifferentSeedsDiffer() {
        let a = SFXEngine().generate(SFXRecipe.make(category: .cardDraw, seed: 1))
        let b = SFXEngine().generate(SFXRecipe.make(category: .cardDraw, seed: 2))
        XCTAssertFalse(buffersEqual(a, b))
    }

    func testDifferentSeedsAreAudiblyDistant() {
        // Ensure seed changes structural params, not only tiny noise differences.
        let engine = SFXEngine()
        for category in SFXCategory.allCases {
            let a = engine.generate(SFXRecipe.make(category: category, seed: 10))
            let b = engine.generate(SFXRecipe.make(category: category, seed: 999))
            XCTAssertGreaterThan(
                meanAbsoluteDifference(a, b),
                0.02,
                "seed change too subtle for \(category.rawValue)"
            )
        }
    }

    func testAllCategoriesGenerateNonSilentAudio() {
        let engine = SFXEngine()
        for category in SFXCategory.allCases {
            let buffer = engine.generate(SFXRecipe.make(category: category, seed: 7))
            XCTAssertGreaterThan(buffer.frameLength, 0, category.rawValue)
            XCTAssertTrue(hasEnergy(buffer), "silent: \(category.rawValue)")
        }
    }

    func testExportFileNameIncludesCategoryAndSeed() {
        let recipe = SFXRecipe.make(category: .uiTap, seed: 123)
        XCTAssertEqual(recipe.exportFileName, "sfx_ui_tap_seed123.wav")
    }

    func testBGMPresetsGenerateInReasonableTime() {
        let engine = BGMEngine()
        for preset in BGMPreset.allCases {
            let recipe = preset.makeRecipe(seed: 3)
            let started = Date()
            let buffer = engine.generate(recipe)
            let elapsed = Date().timeIntervalSince(started)
            XCTAssertGreaterThan(buffer.frameLength, 1000, preset.rawValue)
            XCTAssertTrue(hasEnergy(buffer), preset.rawValue)
            // CI / laptop budget; device should be similar order.
            XCTAssertLessThan(elapsed, 8.0, "slow generate for \(preset.rawValue): \(elapsed)s")
        }
    }

    func testBGMSameSeedReproducible() {
        let recipe = BGMPreset.battleNormal.makeRecipe(seed: 11)
        let engine = BGMEngine()
        let a = engine.generate(recipe)
        let b = engine.generate(recipe)
        assertBuffersEqual(a, b)
    }

    func testBGMDifferentSeedsDiffer() {
        let engine = BGMEngine()
        let a = engine.generate(BGMPreset.menuMain.makeRecipe(seed: 1))
        let b = engine.generate(BGMPreset.menuMain.makeRecipe(seed: 2))
        XCTAssertFalse(buffersEqual(a, b))
    }

    func testBGMEstimatedDurationMatchesBuffer() {
        let recipe = BGMPreset.battleNormal.makeRecipe(seed: 1)
        let buffer = BGMEngine().generate(recipe)
        let expectedFrames = recipe.estimatedDurationSeconds * AudioFormatDefaults.sampleRate
        XCTAssertEqual(Double(buffer.frameLength), expectedFrames, accuracy: AudioFormatDefaults.sampleRate * 0.05)
    }

    func testIntentMapperSFXRoundTripSeed() throws {
        let intent = SoundIntent(
            soundType: .sfx,
            purposeId: "attack_light",
            moodId: "tense",
            lengthId: "sfx_medium",
            seed: 42
        )
        let mapped = try IntentMapper().map(intent)
        guard case .sfx(let recipe) = mapped else {
            return XCTFail("expected sfx")
        }
        XCTAssertEqual(recipe.params.seed, 42)
        XCTAssertEqual(recipe.category, .attackLight)
    }

    func testIntentMapperBGMBarsFollowLength() throws {
        let intent = SoundIntent(
            soundType: .bgm,
            sceneId: "battle_normal",
            moodId: "bright",
            lengthId: "bars_8",
            seed: 7
        )
        let mapped = try IntentMapper().map(intent)
        guard case .bgm(let recipe) = mapped else {
            return XCTFail("expected bgm")
        }
        XCTAssertEqual(recipe.params.key.mode, .major)
        XCTAssertEqual(recipe.params.bars, 8)
    }

    func testBGMBufferLengthMatchesBarGrid() {
        var recipe = BGMPreset.battleNormal.makeRecipe(seed: 1)
        recipe.params.bars = 8
        let buffer = BGMEngine().generate(recipe)
        let secondsPerBeat = 60.0 / Double(recipe.params.tempoBpm)
        let stepFrames = Int((secondsPerBeat / 4.0 * AudioFormatDefaults.sampleRate).rounded())
        let expected = 8 * 16 * stepFrames
        XCTAssertEqual(Int(buffer.frameLength), expected)
    }

    func testLegacySecLengthIdMapsToBars() throws {
        let intent = SoundIntent(
            soundType: .bgm,
            sceneId: "menu_main",
            moodId: "neutral",
            lengthId: "sec_30",
            seed: 1
        )
        let mapped = try IntentMapper().map(intent)
        guard case .bgm(let recipe) = mapped else {
            return XCTFail("expected bgm")
        }
        XCTAssertEqual(recipe.params.bars, 16)
    }

    func testBrightAndDarkMoodsDifferAudibly() throws {
        let bright = SoundIntent(
            soundType: .bgm,
            sceneId: "battle_normal",
            moodId: "bright",
            lengthId: "bars_8",
            seed: 42
        )
        let dark = SoundIntent(
            soundType: .bgm,
            sceneId: "battle_normal",
            moodId: "dark",
            lengthId: "bars_8",
            seed: 42
        )
        let engine = BGMEngine()
        let mapper = IntentMapper()
        guard case .bgm(var bRecipe) = try mapper.map(bright),
              case .bgm(var dRecipe) = try mapper.map(dark) else {
            return XCTFail("expected bgm")
        }
        XCTAssertEqual(bRecipe.params.key.mode, .major)
        XCTAssertEqual(dRecipe.params.key.mode, .minor)
        XCTAssertGreaterThan(bRecipe.params.brightness, dRecipe.params.brightness)
        XCTAssertGreaterThan(bRecipe.params.tempoBpm, dRecipe.params.tempoBpm)

        // Same tempo/bars so buffer lengths match for a fair waveform distance check.
        bRecipe.params.tempoBpm = 120
        dRecipe.params.tempoBpm = 120
        let a = engine.generate(bRecipe)
        let b = engine.generate(dRecipe)
        XCTAssertEqual(a.frameLength, b.frameLength)
        XCTAssertTrue(hasEnergy(a))
        XCTAssertTrue(hasEnergy(b))
        XCTAssertGreaterThan(meanAbsoluteDifference(a, b), 0.03)
    }

    func testCatalogAvailableGenresOnlyCardBattle() {
        let available = Catalog.availableGenres.filter(\.isAvailable)
        XCTAssertEqual(available.map(\.id), ["card_battle"])
    }

    // MARK: - Helpers

    private func assertBuffersEqual(_ a: AVAudioPCMBuffer, _ b: AVAudioPCMBuffer, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(buffersEqual(a, b), "buffers differ", file: file, line: line)
    }

    private func buffersEqual(_ a: AVAudioPCMBuffer, _ b: AVAudioPCMBuffer) -> Bool {
        guard a.frameLength == b.frameLength,
              let ac = a.floatChannelData?[0],
              let bc = b.floatChannelData?[0] else { return false }
        for i in 0..<Int(a.frameLength) {
            if ac[i] != bc[i] { return false }
        }
        return true
    }

    private func hasEnergy(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard let channel = buffer.floatChannelData?[0] else { return false }
        var peak: Float = 0
        for i in 0..<Int(buffer.frameLength) {
            peak = max(peak, abs(channel[i]))
        }
        return peak > 0.01
    }

    private func meanAbsoluteDifference(_ a: AVAudioPCMBuffer, _ b: AVAudioPCMBuffer) -> Float {
        guard a.frameLength == b.frameLength,
              let ac = a.floatChannelData?[0],
              let bc = b.floatChannelData?[0] else { return 0 }
        let n = Int(a.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n {
            sum += abs(ac[i] - bc[i])
        }
        return sum / Float(n)
    }
}
