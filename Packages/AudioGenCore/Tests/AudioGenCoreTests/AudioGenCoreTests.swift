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

    func testIntentMapperDefaultsInstrumentByScene() throws {
        let intent = SoundIntent(
            soundType: .bgm,
            sceneId: "menu_main",
            moodId: "bright",
            lengthId: "bars_8",
            seed: 1
        )
        let mapped = try IntentMapper().map(intent)
        guard case .bgm(let recipe) = mapped else {
            return XCTFail("expected bgm")
        }
        XCTAssertEqual(recipe.params.instrumentId, Catalog.Instrument.piano.rawValue)
    }

    func testDefaultInstrumentForExploreIsBass() throws {
        let intent = SoundIntent(
            soundType: .bgm,
            sceneId: "explore",
            moodId: "neutral",
            lengthId: "bars_8",
            seed: 11
        )
        let mapped = try IntentMapper().map(intent)
        guard case .bgm(let recipe) = mapped else {
            return XCTFail("expected bgm")
        }
        XCTAssertEqual(recipe.params.instrumentId, Catalog.Instrument.bass.rawValue)
        XCTAssertEqual(Catalog.Instrument.defaultFor(scene: .adventure), .guitar)
    }

    func testIntentMapperHonorsExplicitInstrument() throws {
        let intent = SoundIntent(
            soundType: .bgm,
            sceneId: "battle_normal",
            moodId: "tense",
            lengthId: "bars_8",
            instrumentId: Catalog.Instrument.pad.rawValue,
            seed: 3
        )
        let mapped = try IntentMapper().map(intent)
        guard case .bgm(let recipe) = mapped else {
            return XCTFail("expected bgm")
        }
        XCTAssertEqual(recipe.params.instrumentId, "pad")
    }

    func testPianoAndPadInstrumentsDifferAudibly() throws {
        let piano = SoundIntent(
            soundType: .bgm,
            sceneId: "battle_normal",
            moodId: "neutral",
            lengthId: "bars_8",
            instrumentId: "piano",
            seed: 55
        )
        let pad = SoundIntent(
            soundType: .bgm,
            sceneId: "battle_normal",
            moodId: "neutral",
            lengthId: "bars_8",
            instrumentId: "pad",
            seed: 55
        )
        let mapper = IntentMapper()
        let engine = BGMEngine()
        guard case .bgm(let pRecipe) = try mapper.map(piano),
              case .bgm(let dRecipe) = try mapper.map(pad) else {
            return XCTFail("expected bgm")
        }
        let a = engine.generate(pRecipe)
        let b = engine.generate(dRecipe)
        XCTAssertEqual(a.frameLength, b.frameLength)
        XCTAssertGreaterThan(meanAbsoluteDifference(a, b), 0.03)
    }

    func testFMToneOffIsInactive() {
        XCTAssertFalse(FMTone.off.isActive)
        XCTAssertTrue(FMTone(ratio: 2, index: 0.8).isActive)
    }

    func testFMOscDiffersFromPlainOsc() {
        let plain = SynthDSP.osc(.sine, phase: 0.13)
        let fm = SynthDSP.fmOsc(shape: .sine, carrierPhase: 0.13, modulatorPhase: 0.37, index: 1.2)
        XCTAssertNotEqual(plain, fm)
        XCTAssertEqual(
            SynthDSP.fmOsc(shape: .sine, carrierPhase: 0.13, modulatorPhase: 0.37, index: 0),
            plain
        )
    }

    func testLeadAndBassInstrumentsDifferAudibly() throws {
        let lead = SoundIntent(
            soundType: .bgm,
            sceneId: "battle_normal",
            moodId: "tense",
            lengthId: "bars_8",
            instrumentId: "lead_synth",
            seed: 77
        )
        let bass = SoundIntent(
            soundType: .bgm,
            sceneId: "battle_normal",
            moodId: "tense",
            lengthId: "bars_8",
            instrumentId: "bass",
            seed: 77
        )
        let mapper = IntentMapper()
        let engine = BGMEngine()
        guard case .bgm(let leadRecipe) = try mapper.map(lead),
              case .bgm(let bassRecipe) = try mapper.map(bass) else {
            return XCTFail("expected bgm")
        }
        let a = engine.generate(leadRecipe)
        let b = engine.generate(bassRecipe)
        XCTAssertEqual(a.frameLength, b.frameLength)
        XCTAssertGreaterThan(meanAbsoluteDifference(a, b), 0.04)
    }

    func testInstrumentPaletteFMAssignments() {
        let lead = InstrumentPalette.from(instrumentId: "lead_synth")
        XCTAssertEqual(lead.leadShape, .square)
        XCTAssertGreaterThan(lead.leadFM.index, lead.chordFM.index)
        XCTAssertLessThan(lead.leadFM.index, 1.1)
        XCTAssertGreaterThan(lead.leadAmpScale, lead.chordAmpScale)
        XCTAssertGreaterThan(lead.muteBias, 0)
        XCTAssertGreaterThan(lead.leadTail.fmDecay, 0.05)
        XCTAssertGreaterThan(lead.leadTail.ringOut, 0.02)

        let pad = InstrumentPalette.from(instrumentId: "pad")
        XCTAssertGreaterThan(pad.chordAmpScale, pad.leadAmpScale)
        XCTAssertTrue(pad.sustainChords)
        XCTAssertLessThan(pad.drumAmpScale, 0.55)
        XCTAssertLessThan(pad.chordFM.index, 0.55)
        XCTAssertGreaterThan(pad.chordTail.fmDecay, 0.3)
        XCTAssertEqual(pad.leadOctaveBias, 0)
        XCTAssertGreaterThan(pad.leadAmpScale, 0.7)
        XCTAssertGreaterThan(pad.filterCutoffScale, 0.9)

        let bass = InstrumentPalette.from(instrumentId: "bass")
        XCTAssertGreaterThan(bass.bassAmpScale, bass.chordAmpScale)
        XCTAssertTrue(bass.bassRootHeavy)
        XCTAssertGreaterThan(bass.bassFM.index, 0.45)
        XCTAssertLessThan(bass.bassFM.index, 0.8)
        XCTAssertGreaterThan(bass.filterCutoffScale, 0.7)
        XCTAssertEqual(bass.chordOctaveBias, 0)
        XCTAssertGreaterThan(bass.bassEnv.sustain, 0.6)
        XCTAssertGreaterThan(bass.bassDurationScale, 1.3)
        XCTAssertGreaterThan(bass.bassTail.ringOut, 0.15)
        XCTAssertGreaterThan(bass.bassTail.fmDecay, 0.05)

        let musicBox = InstrumentPalette.from(instrumentId: "music_box")
        XCTAssertEqual(musicBox.leadOctaveBias, 0)
        // Softer integer-ratio FM: brief tine flash without piercing highs.
        XCTAssertEqual(musicBox.leadFM.ratio.truncatingRemainder(dividingBy: 1), 0, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(musicBox.leadFM.ratio, 2.0)
        XCTAssertGreaterThan(musicBox.leadFM.index, 0.4)
        XCTAssertLessThan(musicBox.leadFM.index, 0.65)
        XCTAssertEqual(musicBox.filterCutoffScale, 1.0, accuracy: 0.001)
        XCTAssertGreaterThan(musicBox.muteBias, 0.12)
        XCTAssertLessThan(musicBox.drumAmpScale, 0.5)
        XCTAssertLessThan(musicBox.leadDurationScale, 1.1)
        XCTAssertGreaterThan(musicBox.leadTail.ringOut, 1.0)
        XCTAssertLessThan(musicBox.leadTail.fmDecay, 0.12)
        XCTAssertGreaterThan(musicBox.chordTail.ringOut, 0.4)
        let piano = InstrumentPalette.from(instrumentId: "piano")
        XCTAssertTrue(piano.pianoVoice)
        XCTAssertFalse(InstrumentPalette.from(instrumentId: "lead_synth").pianoVoice)
        XCTAssertEqual(piano.leadOctaveBias, 0)
        XCTAssertGreaterThan(piano.leadTail.ringOut, 0.5)
        XCTAssertGreaterThan(piano.filterCutoffScale, 1.0)

        let organ = InstrumentPalette.from(instrumentId: "organ")
        XCTAssertTrue(organ.sustainChords)
        XCTAssertEqual(organ.chordShape, .triangle)
        XCTAssertEqual(organ.leadShape, .triangle)
        XCTAssertEqual(organ.bassShape, .sine)
        XCTAssertGreaterThan(organ.leadEnv.attack, 0.12)
        XCTAssertGreaterThan(organ.leadEnv.sustain, 0.75)
        XCTAssertGreaterThan(organ.leadDurationScale, 1.5)
        XCTAssertLessThan(organ.drumAmpScale, 0.45)
        XCTAssertLessThan(organ.leadFM.index, 0.4)
        XCTAssertGreaterThan(organ.chordTail.fmDecay, 0.3)
        XCTAssertEqual(organ.chordTail.ringOut, 0, accuracy: 0.001)

        let guitar = InstrumentPalette.from(instrumentId: "guitar")
        XCTAssertFalse(guitar.sustainChords)
        XCTAssertEqual(guitar.leadShape, .saw)
        XCTAssertEqual(guitar.leadFM.ratio, 2.0, accuracy: 0.001)
        XCTAssertLessThan(guitar.leadFM.index, 0.6)
        XCTAssertGreaterThan(guitar.muteBias, 0.1)
        XCTAssertLessThan(guitar.filterCutoffScale, 1.05)
        XCTAssertGreaterThan(guitar.leadTail.ringOut, 0.2)
        XCTAssertGreaterThan(guitar.leadTail.fmDecay, 0.05)
        XCTAssertGreaterThan(guitar.chordTail.ringOut, 0.1)
        XCTAssertTrue(guitar.bassRootHeavy)
        XCTAssertLessThan(guitar.drumAmpScale, 0.9)
    }

    func testMusicBoxAndOrganDifferAudibly() throws {
        let musicBox = SoundIntent(
            soundType: .bgm,
            sceneId: "shop",
            moodId: "bright",
            lengthId: "bars_8",
            instrumentId: "music_box",
            seed: 77
        )
        let organ = SoundIntent(
            soundType: .bgm,
            sceneId: "shop",
            moodId: "bright",
            lengthId: "bars_8",
            instrumentId: "organ",
            seed: 77
        )
        let mapper = IntentMapper()
        guard case .bgm(let aRecipe) = try mapper.map(musicBox),
              case .bgm(let bRecipe) = try mapper.map(organ) else {
            return XCTFail("expected bgm")
        }
        let engine = BGMEngine()
        let a = engine.generate(aRecipe)
        let b = engine.generate(bRecipe)
        XCTAssertGreaterThan(meanAbsoluteDifference(a, b), 0.03)
    }

    func testDefaultInstrumentForGachaIsMusicBox() throws {
        let intent = SoundIntent(
            soundType: .bgm,
            sceneId: "gacha_or_reward",
            moodId: "bright",
            lengthId: "bars_8",
            seed: 2
        )
        let mapped = try IntentMapper().map(intent)
        guard case .bgm(let recipe) = mapped else {
            return XCTFail("expected bgm")
        }
        XCTAssertEqual(recipe.params.instrumentId, Catalog.Instrument.musicBox.rawValue)
    }

    func testBGMParamsInstrumentRoundTripDefaultsMissingKey() throws {
        let json = """
        {"bars":8,"brightness":0.5,"density":0.5,"energy":0.5,"key":{"mode":"major","root":0},"melody":true,"moodId":"neutral","seed":1,"tempoBpm":120}
        """
        let data = Data(json.utf8)
        let params = try JSONDecoder().decode(BGMParams.self, from: data)
        XCTAssertEqual(params.instrumentId, Catalog.Instrument.leadSynth.rawValue)
        XCTAssertEqual(params.pitchSemitones, 0)
        XCTAssertEqual(params.rhythm, 0.5, accuracy: 0.001)
    }

    func testBGMPitchAndRhythmChangeAudibly() {
        var low = BGMPreset.menuMain.makeRecipe(seed: 42)
        low.params.bars = 8
        low.params.pitchSemitones = -6
        low.params.rhythm = 0.05
        var high = low
        high.params.pitchSemitones = 6
        high.params.rhythm = 0.95
        let engine = BGMEngine()
        let a = engine.generate(low)
        let b = engine.generate(high)
        XCTAssertGreaterThan(meanAbsoluteDifference(a, b), 0.02)
    }

    func testCatalogAvailableGenresIncludeCoreTypes() {
        let available = Catalog.availableGenres.filter(\.isAvailable).map(\.id)
        XCTAssertEqual(available, ["card_battle", "rpg", "puzzle"])
    }

    func testCatalogBGMScenesAreGrouped() {
        XCTAssertEqual(Catalog.bgmSceneGroupOrder, ["画面", "プレイ中", "結果"])
        XCTAssertEqual(Catalog.bgmScenes(in: "画面").map(\.rawValue), [
            "title", "menu_main", "shop", "gacha_or_reward", "settings"
        ])
        XCTAssertEqual(Catalog.bgmScenes(in: "プレイ中").map(\.rawValue), [
            "story", "town", "adventure", "explore", "puzzle", "rest", "battle_normal", "battle_boss"
        ])
        XCTAssertEqual(Catalog.bgmScenes(in: "結果").map(\.rawValue), [
            "result_win", "result_lose"
        ])
        XCTAssertEqual(Catalog.availableBGMScenes.count, 15)
        XCTAssertFalse(Catalog.BGMScene.opening.isAvailable)
        XCTAssertFalse(Catalog.BGMScene.battleEasy.isAvailable)
        XCTAssertFalse(Catalog.BGMScene.resultHappyEnd.isAvailable)
        XCTAssertEqual(Catalog.BGMScene.town.group, "プレイ中")
        XCTAssertEqual(Catalog.BGMScene.puzzle.displayName, "パズル／思考")
        XCTAssertEqual(Catalog.BGMScene.rest.displayName, "休憩")
    }

    func testBGMSceneResolveCollapsesLegacyIDs() {
        XCTAssertEqual(Catalog.BGMScene.resolve("opening"), .title)
        XCTAssertEqual(Catalog.BGMScene.resolve("battle_easy"), .battleNormal)
        XCTAssertEqual(Catalog.BGMScene.resolve("battle_hard"), .battleNormal)
        XCTAssertEqual(Catalog.BGMScene.resolve("battle_extra"), .battleNormal)
        XCTAssertEqual(Catalog.BGMScene.resolve("battle_pinch"), .battleNormal)
        XCTAssertEqual(Catalog.BGMScene.resolve("result_happy_end"), .resultWin)
        XCTAssertEqual(Catalog.BGMScene.resolve("result_bad_end"), .resultLose)
        XCTAssertEqual(Catalog.BGMScene.resolve("town"), .town)
    }

    func testIntentMapperAcceptsLegacyAndNewBGMScenes() throws {
        let mapper = IntentMapper()
        for sceneId in [
            "opening", "explore", "battle_easy", "battle_hard", "battle_extra",
            "result_happy_end", "result_bad_end", "town", "puzzle", "rest"
        ] {
            let intent = SoundIntent(
                soundType: .bgm,
                genreId: "card_battle",
                sceneId: sceneId,
                moodId: "neutral",
                lengthId: "bars_16",
                seed: 3
            )
            let mapped = try mapper.map(intent)
            guard case .bgm(let recipe) = mapped else {
                return XCTFail("expected bgm for \(sceneId)")
            }
            if sceneId == "town" {
                XCTAssertEqual(recipe.params.instrumentId, Catalog.Instrument.guitar.rawValue)
            }
            if sceneId == "rest" {
                XCTAssertEqual(recipe.params.instrumentId, Catalog.Instrument.pad.rawValue)
            }
            if sceneId == "puzzle" {
                XCTAssertEqual(recipe.params.instrumentId, Catalog.Instrument.piano.rawValue)
            }
        }
    }

    func testDefaultInstrumentsForTownPuzzleRest() {
        XCTAssertEqual(Catalog.Instrument.defaultFor(scene: .town), .guitar)
        XCTAssertEqual(Catalog.Instrument.defaultFor(scene: .puzzle), .piano)
        XCTAssertEqual(Catalog.Instrument.defaultFor(scene: .rest), .pad)
    }

    func testTitleAndVictoryRecipesDifferAudibly() throws {
        let mapper = IntentMapper()
        let titleIntent = SoundIntent(
            soundType: .bgm,
            sceneId: "title",
            moodId: "bright",
            lengthId: "bars_4",
            seed: 42
        )
        let winIntent = SoundIntent(
            soundType: .bgm,
            sceneId: "result_win",
            moodId: "bright",
            lengthId: "bars_4",
            seed: 42
        )
        guard case .bgm(let title) = try mapper.map(titleIntent),
              case .bgm(let win) = try mapper.map(winIntent) else {
            return XCTFail("expected bgm")
        }
        XCTAssertEqual(title.params.instrumentId, Catalog.Instrument.piano.rawValue)
        XCTAssertEqual(win.params.instrumentId, Catalog.Instrument.leadSynth.rawValue)
        XCTAssertGreaterThan(win.params.tempoBpm, title.params.tempoBpm + 15)
        XCTAssertGreaterThan(win.params.density, title.params.density + 0.2)
        XCTAssertGreaterThan(win.params.energy, title.params.energy + 0.15)
        XCTAssertNotEqual(title.params.key.root, win.params.key.root)

        // Equalize tempo so lengths match; remaining diff is timbre / arrangement.
        var titleEq = title
        var winEq = win
        titleEq.params.tempoBpm = 120
        winEq.params.tempoBpm = 120
        let engine = BGMEngine()
        let a = engine.generate(titleEq)
        let b = engine.generate(winEq)
        XCTAssertEqual(a.frameLength, b.frameLength)
        XCTAssertTrue(hasEnergy(a))
        XCTAssertTrue(hasEnergy(b))
        XCTAssertGreaterThan(meanAbsoluteDifference(a, b), 0.04)
    }

    func testCatalogSFXPurposesMapOneToOne() {
        XCTAssertEqual(Catalog.SFXPurpose.magicFire.category, .magicFire)
        XCTAssertEqual(Catalog.SFXPurpose.cardShuffle.category, .cardShuffle)
        XCTAssertEqual(Catalog.SFXPurpose.gachaSpin.category, .gachaSpin)
        XCTAssertEqual(Catalog.SFXPurpose.attackSlash.category, .attackSlash)
        let cats = Catalog.SFXPurpose.allCases.map(\.category)
        XCTAssertEqual(Set(cats).count, cats.count, "each purpose must map to a unique engine category")
        XCTAssertEqual(Catalog.SFXPurpose.allCases.count, SFXCategory.allCases.count)
    }

    func testNewSFXPurposesUseTheirDedicatedCategoriesAndGroups() {
        let expected: [(Catalog.SFXPurpose, SFXCategory, String)] = [
            (.uiWarning, .uiWarning, "UI・テキスト"),
            (.uiError, .uiError, "UI・テキスト"),
            (.uiUnlock, .uiUnlock, "UI・テキスト"),
            (.uiText, .uiText, "UI・テキスト"),
            (.rewardCoin, .rewardCoin, "報酬・成長"),
            (.rewardChest, .rewardChest, "報酬・成長"),
            (.rewardLevelUp, .rewardLevelUp, "報酬・成長"),
            (.puzzleClear, .puzzleClear, "パズル・ミニゲーム"),
            (.puzzleCombo, .puzzleCombo, "パズル・ミニゲーム"),
            (.attackCritical, .attackCritical, "バトル"),
            (.defendParry, .defendParry, "バトル"),
            (.moveWarp, .moveWarp, "移動・フィールド"),
        ]

        for (purpose, category, group) in expected {
            XCTAssertEqual(purpose.category, category)
            XCTAssertEqual(purpose.group, group)
            XCTAssertTrue(purpose.isAvailable)
        }
    }

    func testIntentMapperAcceptsRPGGenreAndNewScene() throws {
        let intent = SoundIntent(
            soundType: .bgm,
            genreId: "rpg",
            sceneId: "adventure",
            moodId: "neutral",
            lengthId: "bars_16",
            seed: 3
        )
        let mapped = try IntentMapper().map(intent)
        guard case .bgm(let recipe) = mapped else {
            return XCTFail("expected bgm")
        }
        XCTAssertEqual(recipe.params.bars, 16)
        XCTAssertLessThan(recipe.params.tempoBpm, 120)
    }

    func testDistinctPurposesSoundDifferent() throws {
        let pairs: [(String, String)] = [
            ("attack_slash", "gacha_spin"),
            ("card_shuffle", "magic_fire"),
            ("attack_bash", "magic_ice"),
            ("move_walk", "ui_tap"),
            ("reward_coin", "reward_chest"),
            ("ui_warning", "ui_error"),
            ("puzzle_combo", "attack_critical"),
            ("defend_parry", "move_warp"),
        ]
        let engine = SFXEngine()
        let mapper = IntentMapper()
        for (aId, bId) in pairs {
            let aIntent = SoundIntent(soundType: .sfx, purposeId: aId, moodId: "neutral", lengthId: "sfx_medium", seed: 11)
            let bIntent = SoundIntent(soundType: .sfx, purposeId: bId, moodId: "neutral", lengthId: "sfx_medium", seed: 11)
            guard case .sfx(let aRecipe) = try mapper.map(aIntent),
                  case .sfx(let bRecipe) = try mapper.map(bIntent) else {
                return XCTFail("expected sfx")
            }
            XCTAssertNotEqual(aRecipe.category, bRecipe.category)
            var aFixed = aRecipe
            var bFixed = bRecipe
            aFixed.params.durationMs = 280
            bFixed.params.durationMs = 280
            let aBuf = engine.generate(aFixed)
            let bBuf = engine.generate(bFixed)
            XCTAssertGreaterThan(
                meanAbsoluteDifference(aBuf, bBuf),
                0.05,
                "\(aId) vs \(bId) too similar"
            )
        }
    }

    func testMelodyComposerIsDeterministic() {
        let progression = [0, 5, 2, 6]
        let a = MelodyComposer.compose(
            bars: 8,
            progression: progression,
            density: 0.55,
            moodId: "tense",
            melodyEnabled: true,
            melodyChanceScale: 1.0,
            seed: 12345
        )
        let b = MelodyComposer.compose(
            bars: 8,
            progression: progression,
            density: 0.55,
            moodId: "tense",
            melodyEnabled: true,
            melodyChanceScale: 1.0,
            seed: 12345
        )
        XCTAssertEqual(a, b)
        XCTAssertFalse(a.notes.isEmpty)
    }

    func testMelodyComposerRepeatsMotifRhythmInLoop() {
        let progression = [0, 5, 2, 6]
        let plan = MelodyComposer.compose(
            bars: 4,
            progression: progression,
            density: 0.7,
            moodId: "neutral",
            melodyEnabled: true,
            melodyChanceScale: 1.15,
            seed: 99
        )
        XCTAssertEqual(plan.form, .loop)
        XCTAssertEqual(plan.motifBars, 2)
        let first = plan.notes.filter { $0.bar == 0 }.map(\.step)
        let again = plan.notes.filter { $0.bar == 2 }.map(\.step)
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, again, "motif rhythm should repeat each motif cycle")
    }

    func testMelodyFormFollowsBarCount() {
        let progression = [0, 5, 2, 6]
        let loop = MelodyComposer.compose(
            bars: 4, progression: progression, density: 0.55, moodId: "neutral",
            melodyEnabled: true, melodyChanceScale: 1, seed: 3
        )
        let two = MelodyComposer.compose(
            bars: 8, progression: progression, density: 0.55, moodId: "neutral",
            melodyEnabled: true, melodyChanceScale: 1, seed: 3
        )
        let four = MelodyComposer.compose(
            bars: 16, progression: progression, density: 0.55, moodId: "neutral",
            melodyEnabled: true, melodyChanceScale: 1, seed: 3
        )
        XCTAssertEqual(loop.form, .loop)
        XCTAssertEqual(two.form, .statementResponse)
        XCTAssertEqual(four.form, .kiShoTenKetsu)

        // 中・2メロ: second half uses contrasting motif family.
        let earlyDeg = two.notes.filter { $0.bar == 0 }.map { $0.degree - progression[0] }
        let lateDeg = two.notes.filter { $0.bar == 4 }.map { $0.degree - progression[0] }
        XCTAssertFalse(earlyDeg.isEmpty)
        XCTAssertFalse(lateDeg.isEmpty)
        XCTAssertNotEqual(earlyDeg, lateDeg, "8-bar 2メロ should change melody shape in second half")

        // 長・4メロ: 転 (3rd quarter) differs from 起.
        let ki = four.notes.filter { $0.bar < 4 }.map(\.degree)
        let ten = four.notes.filter { $0.bar >= 8 && $0.bar < 12 }.map(\.degree)
        XCTAssertFalse(ki.isEmpty)
        XCTAssertFalse(ten.isEmpty)
        XCTAssertNotEqual(Set(ki), Set(ten), "16-bar 転 should differ from 起")
    }

    func testBGMLengthDisplayAndResolve() {
        XCTAssertEqual(Catalog.BGMLength.bars4.displayName, "短・1メロ")
        XCTAssertEqual(Catalog.BGMLength.bars8.displayName, "中・2メロ")
        XCTAssertEqual(Catalog.BGMLength.bars16.displayName, "長・4メロ")
        XCTAssertEqual(Catalog.BGMLength.bars4.barCount, 4)
        XCTAssertEqual(Catalog.BGMLength.bars8.barCount, 8)
        XCTAssertEqual(Catalog.BGMLength.bars16.barCount, 16)
        XCTAssertEqual(Catalog.BGMLength.resolve("bars_4"), .bars4)
        XCTAssertEqual(Catalog.BGMLength.resolve("bars_24"), .bars16)
        XCTAssertEqual(Catalog.BGMLength.resolve("sec_15"), .bars4)
        XCTAssertEqual(Catalog.BGMLength.resolve("sec_30").barCount, 16)
    }

    func testDifferentSeedsPickDifferentMelodyPlans() {
        let progression = [0, 4, 5, 3]
        let plans = (0..<24).map { seed -> MelodyPlan in
            MelodyComposer.compose(
                bars: 8,
                progression: progression,
                density: 0.6,
                moodId: "bright",
                melodyEnabled: true,
                melodyChanceScale: 1.0,
                seed: UInt64(seed + 1)
            )
        }
        let signatures = Set(plans.map { "\($0.rhythmId)-\($0.contourId)-\($0.motifBars)" })
        XCTAssertGreaterThan(signatures.count, 6, "seeds should explore multiple motif families")
    }

    func testMotifDictionaryFamiliesDifferByMood() {
        let progression = [0, 5, 3, 4]
        let seed: UInt64 = 17
        let bright = MelodyComposer.compose(
            bars: 8, progression: progression, density: 0.55, moodId: "bright",
            melodyEnabled: true, melodyChanceScale: 1, seed: seed, sceneBias: .general
        )
        let dark = MelodyComposer.compose(
            bars: 8, progression: progression, density: 0.55, moodId: "dark",
            melodyEnabled: true, melodyChanceScale: 1, seed: seed, sceneBias: .general
        )
        XCTAssertNotEqual(bright.notes, dark.notes)
        // Family indices stay in dictionary range (8 templates).
        XCTAssertLessThan(bright.rhythmId, 8)
        XCTAssertLessThan(dark.rhythmId, 8)
    }

    func testBGMVariationProfilesExploreScaleAndPhraseStructure() {
        let engine = BGMEngine()
        let signatures = (1...64).map { seed in
            engine.variationSignature(for: BGMPreset.menuMain.makeRecipe(seed: UInt64(seed)))
        }

        XCTAssertGreaterThan(Set(signatures.map(\.mode)).count, 1)
        XCTAssertGreaterThan(Set(signatures.map(\.progression)).count, 8)
        let phraseProfiles = Set(signatures.map {
            "\($0.melodyRhythmID)-\($0.melodyContourID)-\($0.motifBars)"
        })
        XCTAssertGreaterThan(phraseProfiles.count, 14)
        XCTAssertGreaterThan(Set(signatures.map(\.compositionStyle)).count, 4)
    }

    func testCompositionStylesChangeShortBGMPhraseAndHarmony() {
        let seed: UInt64 = 314
        let baseProgression = MusicTheory.progression(
            for: .menuMain, moodId: "neutral", pick: 9, style: .hook
        )
        let progressions = BGMCompositionStyle.allCases.map { style in
            MusicTheory.progression(for: .menuMain, moodId: "neutral", pick: 9, style: style)
        }
        XCTAssertEqual(Set(progressions).count, BGMCompositionStyle.allCases.count)

        let questionAnswer = MelodyComposer.compose(
            bars: 4,
            progression: baseProgression,
            density: 0.6,
            moodId: "neutral",
            melodyEnabled: true,
            melodyChanceScale: 1,
            seed: seed,
            style: .questionAnswer
        )
        XCTAssertEqual(questionAnswer.form, .statementResponse)
        let opening = questionAnswer.notes.filter { $0.bar == 0 }.map(\.step)
        let response = questionAnswer.notes.filter { $0.bar == 2 }.map(\.step)
        XCTAssertFalse(opening.isEmpty)
        XCTAssertNotEqual(opening, response)
    }

    func testNegativeScaleDegreeStaysBelowTheTonic() {
        let belowTonic = MusicTheory.midi(root: 0, degree: -1, octave: 5, mode: .major)
        let leadingToneBelow = MusicTheory.midi(root: 0, degree: 6, octave: 4, mode: .major)
        XCTAssertEqual(belowTonic, leadingToneBelow)
    }

    func testVariationModesStayWithinStablePalette() {
        let modes = (1...64).map { seed in
            MusicTheory.variationMode(base: .major, moodId: "neutral", seed: UInt64(seed))
        }
        XCTAssertTrue(modes.allSatisfy { $0 == .major || $0 == .mixolydian })
        XCTAssertTrue(modes.contains(.major))
        XCTAssertTrue(modes.contains(.mixolydian))
    }

    func testPhraseVoiceLeadingLimitsIntervalsAndEndsOnStableTone() {
        let progression = [0, 5, 2, 6]
        for seed in 1...24 {
            let plan = MelodyComposer.compose(
                bars: 8,
                progression: progression,
                density: 0.9,
                moodId: "neutral",
                melodyEnabled: true,
                melodyChanceScale: 1.2,
                seed: UInt64(seed),
                style: .questionAnswer
            )
            let ordered = plan.notes.sorted { ($0.bar, $0.step) < ($1.bar, $1.step) }
            XCTAssertGreaterThan(ordered.count, 2)
            for index in 1..<ordered.count {
                XCTAssertLessThanOrEqual(abs(ordered[index].degree - ordered[index - 1].degree), 3)
            }
            guard let ending = ordered.last else { return XCTFail("missing phrase ending") }
            let chordDegree = progression[ending.bar % progression.count]
            let relative = ((ending.degree - chordDegree) % 7 + 7) % 7
            XCTAssertTrue([0, 2].contains(relative), "seed \(seed) did not end on root or third")
        }
    }

    func testDistinctSeedSelectsTheMostDistantStructuralCandidate() throws {
        let engine = BGMEngine()
        let current = BGMPreset.battleNormal.makeRecipe(seed: 42)
        let candidates = (1...32).map(UInt64.init)
        let selected = try XCTUnwrap(engine.distinctSeed(from: candidates, comparedTo: current))

        var selectedRecipe = current
        selectedRecipe.params.seed = selected
        let selectedDistance = engine.structuralDistance(between: current, and: selectedRecipe)
        let bestDistance = candidates.map { seed -> Int in
            var candidate = current
            candidate.params.seed = seed
            return engine.structuralDistance(between: current, and: candidate)
        }.max()
        XCTAssertEqual(selectedDistance, bestDistance)
        XCTAssertGreaterThanOrEqual(selectedDistance, 12)
        XCTAssertNotEqual(
            engine.variationSignature(for: current).compositionStyle,
            engine.variationSignature(for: selectedRecipe).compositionStyle
        )
    }

    func testSceneBiasCanChangeMotifFamilyOrdering() {
        let progression = [0, 4, 5, 3]
        var differed = false
        for seed in 1...24 {
            let battle = MelodyComposer.compose(
                bars: 8, progression: progression, density: 0.55, moodId: "neutral",
                melodyEnabled: true, melodyChanceScale: 1, seed: UInt64(seed), sceneBias: .battle
            )
            let menu = MelodyComposer.compose(
                bars: 8, progression: progression, density: 0.55, moodId: "neutral",
                melodyEnabled: true, melodyChanceScale: 1, seed: UInt64(seed), sceneBias: .menu
            )
            if battle.rhythmId != menu.rhythmId || battle.notes != menu.notes {
                differed = true
                break
            }
        }
        XCTAssertTrue(differed, "battle vs menu scene bias should reorder motif families")
    }

    func testDifferentSeedsVaryOpeningPhrase() {
        let progression = [0, 5, 2, 6]
        let openings = (0..<32).map { seed -> String in
            let plan = MelodyComposer.compose(
                bars: 8,
                progression: progression,
                density: 0.55,
                moodId: "neutral",
                melodyEnabled: true,
                melodyChanceScale: 1.0,
                seed: UInt64(seed + 10)
            )
            let head = plan.notes
                .filter { $0.bar < 2 }
                .map { "\($0.step):\($0.degree - progression[$0.bar % progression.count])" }
            return head.joined(separator: ",")
        }
        let unique = Set(openings)
        XCTAssertGreaterThan(unique.count, 10, "別パターン should change the audible opening phrase")

        let firstRels = (0..<32).compactMap { seed -> Int? in
            let plan = MelodyComposer.compose(
                bars: 8,
                progression: progression,
                density: 0.55,
                moodId: "neutral",
                melodyEnabled: true,
                melodyChanceScale: 1.0,
                seed: UInt64(seed + 10)
            )
            guard let first = plan.notes.first(where: { $0.bar == 0 }) else { return nil }
            return first.degree - progression[0]
        }
        XCTAssertGreaterThan(Set(firstRels).count, 2, "opening degree should not always be tonic")
    }

    func testBrightMoodAvoidsLeadingToneDips() {
        let progression = [0, 4, 5, 3]
        for seed in 1...40 {
            let plan = MelodyComposer.compose(
                bars: 8,
                progression: progression,
                density: 0.6,
                moodId: "bright",
                melodyEnabled: true,
                melodyChanceScale: 1.0,
                seed: UInt64(seed)
            )
            for note in plan.notes {
                let rel = note.degree - progression[note.bar % progression.count]
                XCTAssertFalse(
                    rel == -1 || rel == -3,
                    "bright mood should not use leading-tone dips (seed \(seed), rel \(rel))"
                )
            }
        }
    }

    func testMoodPitchPoolsChangeMelodyCharacter() {
        let progression = [0, 5, 2, 6]
        let seed: UInt64 = 42
        let bright = MelodyComposer.compose(
            bars: 8, progression: progression, density: 0.55, moodId: "bright",
            melodyEnabled: true, melodyChanceScale: 1, seed: seed
        )
        let dark = MelodyComposer.compose(
            bars: 8, progression: progression, density: 0.55, moodId: "dark",
            melodyEnabled: true, melodyChanceScale: 1, seed: seed
        )
        let tense = MelodyComposer.compose(
            bars: 8, progression: progression, density: 0.55, moodId: "tense",
            melodyEnabled: true, melodyChanceScale: 1, seed: seed
        )
        XCTAssertNotEqual(bright.notes, dark.notes, "bright vs dark should differ at same seed")
        XCTAssertNotEqual(bright.notes, tense.notes, "bright vs tense should differ at same seed")

        func averageRel(_ plan: MelodyPlan) -> Double {
            let rels = plan.notes.map { $0.degree - progression[$0.bar % progression.count] }
            guard !rels.isEmpty else { return 0 }
            return Double(rels.reduce(0, +)) / Double(rels.count)
        }
        XCTAssertGreaterThan(
            averageRel(bright),
            averageRel(dark) - 0.25,
            "bright phrases should sit at least as high as dark on average"
        )
    }

    func testBrightMelodyPrefersStepwiseMotion() {
        let progression = [0, 0, 0, 0]
        var intervals = 0
        var wideLeaps = 0
        for seed in 1...36 {
            let plan = MelodyComposer.compose(
                bars: 4,
                progression: progression,
                density: 0.7,
                moodId: "bright",
                melodyEnabled: true,
                melodyChanceScale: 1.0,
                seed: UInt64(seed)
            )
            let degrees = plan.notes
                .sorted { ($0.bar, $0.step) < ($1.bar, $1.step) }
                .map(\.degree)
            guard degrees.count >= 2 else { continue }
            for index in 1..<degrees.count {
                let span = abs(degrees[index] - degrees[index - 1])
                intervals += 1
                if span >= 4 { wideLeaps += 1 }
            }
        }
        XCTAssertGreaterThan(intervals, 20)
        XCTAssertLessThan(
            Double(wideLeaps) / Double(intervals),
            0.22,
            "bright mood should keep most motion stepwise"
        )
    }

    func testMelodicLeapTendsToResolveOpposite() {
        let progression = [0, 0, 0, 0]
        var leapCases = 0
        var resolved = 0
        for seed in 1...48 {
            let plan = MelodyComposer.compose(
                bars: 4,
                progression: progression,
                density: 0.75,
                moodId: "tense",
                melodyEnabled: true,
                melodyChanceScale: 1.15,
                seed: UInt64(seed)
            )
            let degrees = plan.notes
                .sorted { ($0.bar, $0.step) < ($1.bar, $1.step) }
                .map(\.degree)
            guard degrees.count >= 3 else { continue }
            for index in 1..<(degrees.count - 1) {
                let leap = degrees[index] - degrees[index - 1]
                guard abs(leap) >= 3 else { continue }
                leapCases += 1
                let recovery = degrees[index + 1] - degrees[index]
                // Recovery steps back toward the pre-leap note.
                if leap > 0, recovery < 0 { resolved += 1 }
                if leap < 0, recovery > 0 { resolved += 1 }
            }
        }
        XCTAssertGreaterThan(leapCases, 3, "expected some leaps in tense motifs")
        XCTAssertGreaterThanOrEqual(
            resolved * 2,
            leapCases,
            "most leaps should be followed by opposite motion"
        )
    }

    func testDarkMoodClampsSoaringRelatives() {
        let progression = [0, 4, 5, 3]
        for seed in 1...24 {
            let plan = MelodyComposer.compose(
                bars: 16,
                progression: progression,
                density: 0.6,
                moodId: "dark",
                melodyEnabled: true,
                melodyChanceScale: 1.0,
                seed: UInt64(seed)
            )
            for note in plan.notes {
                let rel = note.degree - progression[note.bar % progression.count]
                XCTAssertLessThan(rel, 6, "dark mood should not soar (seed \(seed), rel \(rel))")
            }
        }
    }

    func testTenSectionDoesNotRaiseLeadOctave() {
        for mood in ["bright", "dark", "tense", "neutral"] {
            let ten = MelodyComposer.arrangementScale(form: .kiShoTenKetsu, section: 2, moodId: mood)
            XCTAssertEqual(ten.leadOctaveBias, 0, "転 should contrast without +1 octave (\(mood))")
        }
        let brightTen = MelodyComposer.arrangementScale(form: .kiShoTenKetsu, section: 2, moodId: "bright")
        XCTAssertTrue(brightTen.forceFill)
        let darkTen = MelodyComposer.arrangementScale(form: .kiShoTenKetsu, section: 2, moodId: "dark")
        XCTAssertTrue(darkTen.chordSparse, "dark 転 should sparsify chords")
        XCTAssertLessThan(darkTen.drum, brightTen.drum)
        let ki = MelodyComposer.arrangementScale(form: .kiShoTenKetsu, section: 0)
        XCTAssertEqual(ki.leadOctaveBias, 0)
    }

    func testTenSectionUsesMildDegreeBias() {
        let progression = [0, 5, 2, 6]
        let plan = MelodyComposer.compose(
            bars: 16,
            progression: progression,
            density: 0.55,
            moodId: "neutral",
            melodyEnabled: true,
            melodyChanceScale: 1.0,
            seed: 21
        )
        XCTAssertEqual(plan.form, .kiShoTenKetsu)
        let kiRels = plan.notes.filter { $0.bar < 4 }.map { $0.degree - progression[$0.bar % progression.count] }
        let tenRels = plan.notes.filter { $0.bar >= 8 && $0.bar < 12 }.map {
            $0.degree - progression[$0.bar % progression.count]
        }
        XCTAssertFalse(kiRels.isEmpty)
        XCTAssertFalse(tenRels.isEmpty)
        // Mild lift only: average should stay modest vs 起.
        let kiAvg = Double(kiRels.reduce(0, +)) / Double(kiRels.count)
        let tenAvg = Double(tenRels.reduce(0, +)) / Double(tenRels.count)
        XCTAssertLessThan(tenAvg - kiAvg, 5.0, "転 should not soar far above 起")
    }

    func testTenSectionContrastsByDensityNotHeight() {
        let progression = [0, 5, 2, 6]
        let seed: UInt64 = 33
        let bright = MelodyComposer.compose(
            bars: 16, progression: progression, density: 0.6, moodId: "bright",
            melodyEnabled: true, melodyChanceScale: 1, seed: seed
        )
        let dark = MelodyComposer.compose(
            bars: 16, progression: progression, density: 0.6, moodId: "dark",
            melodyEnabled: true, melodyChanceScale: 1, seed: seed
        )
        let brightTen = bright.notes.filter { $0.bar >= 8 && $0.bar < 12 }
        let darkTen = dark.notes.filter { $0.bar >= 8 && $0.bar < 12 }
        let brightKi = bright.notes.filter { $0.bar < 4 }
        XCTAssertFalse(brightTen.isEmpty)
        XCTAssertFalse(darkTen.isEmpty)
        // Dark 転 thins more than bright 転.
        XCTAssertLessThan(darkTen.count, brightTen.count + 2)

        func avgRel(_ notes: [MelodyNote]) -> Double {
            let rels = notes.map { $0.degree - progression[$0.bar % progression.count] }
            return Double(rels.reduce(0, +)) / Double(max(1, rels.count))
        }
        // Bright 転 should not jump far above 起 in register.
        XCTAssertLessThan(avgRel(brightTen) - avgRel(brightKi), 4.0)

        // Bright 転 tends to be shorter/punchier articulations than 起.
        let kiDur = Double(brightKi.map(\.durationSteps).reduce(0, +)) / Double(max(1, brightKi.count))
        let tenDur = Double(brightTen.map(\.durationSteps).reduce(0, +)) / Double(max(1, brightTen.count))
        XCTAssertLessThanOrEqual(tenDur, kiDur + 0.35)
    }

    func testProgressionPickCanStartOffTonic() {
        var sawNonTonicStart = false
        for pick in 0..<64 {
            let prog = MusicTheory.progression(for: .battleNormal, moodId: "bright", pick: pick)
            XCTAssertFalse(prog.isEmpty)
            if prog[0] != 0 { sawNonTonicStart = true }
        }
        XCTAssertTrue(sawNonTonicStart, "progression pool/rotation should allow non-tonic openings")
    }

    func testSeedTransposeIsMildAndDeterministic() {
        XCTAssertEqual(MusicTheory.seedTransposeSemitones(seed: 1), MusicTheory.seedTransposeSemitones(seed: 1))
        let values = Set((0..<16).map { MusicTheory.seedTransposeSemitones(seed: UInt64($0)) })
        XCTAssertGreaterThan(values.count, 3)
        for value in values {
            XCTAssertLessThanOrEqual(abs(value), 7)
        }
    }

    func testMelodyDisabledYieldsNoNotes() {
        let plan = MelodyComposer.compose(
            bars: 8,
            progression: [0, 5, 3, 4],
            density: 0.8,
            moodId: "neutral",
            melodyEnabled: false,
            melodyChanceScale: 1.0,
            seed: 7
        )
        XCTAssertTrue(plan.notes.isEmpty)
    }

    func testSpaceFXLowpassChangesBrightImpulse() {
        var bright = [Float](repeating: 0, count: 2_048)
        bright[100] = 1
        var filtered = bright
        SpaceFX.applyLowpass(&filtered, cutoffHz: 800, sampleRate: 44_100)
        XCTAssertNotEqual(filtered[100], bright[100])
        // Energy spreads forward after the impulse.
        let tail = filtered[101..<180].map(abs).reduce(0, +)
        XCTAssertGreaterThan(tail, 0.05)
    }

    func testSpaceFXReverbIsDeterministicAndMixes() {
        let dry = (0..<4_096).map { i -> Float in
            sin(Float(i) * 0.07) * 0.4
        }
        var a = dry
        var b = dry
        SpaceFX.applyShortReverb(&a, mix: 0.3, decay: 0.45, sampleRate: 44_100)
        SpaceFX.applyShortReverb(&b, mix: 0.3, decay: 0.45, sampleRate: 44_100)
        XCTAssertEqual(a, b)
        var diff: Float = 0
        for i in 0..<4_096 { diff += abs(a[i] - dry[i]) }
        XCTAssertGreaterThan(diff / 4_096, 0.001)
    }

    func testBGMWithSpaceFXIsDeterministic() throws {
        let intent = SoundIntent(
            soundType: .bgm,
            sceneId: "battle_normal",
            moodId: "dark",
            lengthId: "bars_8",
            instrumentId: "pad",
            seed: 77
        )
        let mapper = IntentMapper()
        let engine = BGMEngine()
        guard case .bgm(let recipe) = try mapper.map(intent) else {
            return XCTFail("expected bgm")
        }
        let a = engine.generate(recipe)
        let b = engine.generate(recipe)
        assertBuffersEqual(a, b)
        XCTAssertTrue(hasEnergy(a))
    }

    @MainActor
    func testNewerGenerationWinsWhenOlderBackgroundSynthesisCompletes() async throws {
        let service = GenerationService()
        var slowRecipe = BGMPreset.battleNormal.makeRecipe(seed: 31)
        slowRecipe.params.bars = 32
        let old = MappedRecipe.bgm(slowRecipe)
        let latest = MappedRecipe.sfx(SFXRecipe.make(category: .uiConfirm, seed: 99))

        let oldTask: Task<Void, Error> = Task { @MainActor in
            _ = try await service.generateMappedAsync(old)
        }
        // Let the old task reserve a generation request and enter its background work.
        await Task.yield()
        _ = service.generate(mapped: latest)

        do {
            _ = try await oldTask.value
            XCTFail("A superseded generation must not publish a result")
        } catch is CancellationError {
            // Expected: the newer synchronous request owns the service state.
        }

        XCTAssertEqual(service.lastMapped, latest)
        XCTAssertEqual(service.lastIntent, nil)
        XCTAssertNotNil(service.lastBuffer)
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
