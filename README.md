# GameSoundCreator

カードバトルなどゲーム向けの **BGM / 効果音を、完全ローカルで手続き的に生成する** iOSアプリ（兼・自作ゲーム用ツール）の開発リポジトリです。

外部クラウドAIは使いません。端末上の合成・ルールベース生成のみで動作します。

---

## 目指すもの

| 短期 | 中期 | 長期 |
|------|------|------|
| 自作カードバトル用のBGM・SEを量産できる | ジャンル・シーン・用途などを選ぶだけで試聴・書き出しできるiOSアプリ | App Storeで広告 or 買い切り販売 |

---

## 言語・技術の選定（結論）

**メイン言語は Swift。UI は SwiftUI。音声は AVAudioEngine（必要に応じて AudioKit）。**

| 候補 | 判定 | 理由 |
|------|------|------|
| **Swift + SwiftUI** | **採用** | App Store直結、完全オフライン、オーディオAPIが強力、一人開発でも一貫しやすい |
| Python | 不採用（本線） | 試作向きだが iOS 製品化で再実装コストが大きい |
| Kotlin Multiplatform / Flutter | 見送り | 音声の低レイヤ制御と「完全ローカル生成」で複雑さが増す。まず iOS を固める |
| C++ / Rust コア + Swift UI | Phase 4 以降の選択肢 | 品質・パフォーマンスが足りないときだけコアを切り出す |

**方針:** 最初から「売れる iOS アプリのコード」を書く。自作カードバトル用アセットも、同じエンジンから WAV/AAC 書き出しして流用する。

詳細は [docs/SPEC.md](docs/SPEC.md)、進め方は [docs/ROADMAP.md](docs/ROADMAP.md) を参照。

---

## 現実的な進め方（要約）

1. **製品を三層で考える**  
   - **アプリ層:** 意図ウィザード（ジャンル／シーン／用途／雰囲気／長さ）、試聴、書き出し、課金  
   - **Intent Mapper:** ユーザー意図 → Recipe  
   - **エンジン層:** Recipe → 音声バッファ / ファイル  

2. **最初のジャンルは1つに絞る**  
   MVP はカードバトルをフル対応。他ジャンルはカタログ拡充で追加する。

3. **効果音 → 短いループBGM の順**  
   SEは手続き生成と相性が良く、すぐ自作ゲームに使える。BGMはループ境界とハーモニーの設計が本体。

4. **ゲーム組み込みは「書き出し優先」**  
   ランタイム合成は後回し。まず WAV/M4A を書き出してカードバトル側に配置する運用で十分。

5. **収益化は後から差し込める設計**  
   コア生成は無料体験可能にし、書き出し上限・プリセット解放・広告除去を課金/広告で制御する想定（仕様書参照）。

6. **著作権は最初から意識する**  
   同梱サンプル音源は自作 or 明示的に商用可のライセンスのみ。生成結果の利用規約もアプリ内で明記する。

---

## ドキュメント

| ファイル | 内容 |
|----------|------|
| [docs/SPEC.md](docs/SPEC.md) | 製品仕様書（要件・画面・エンジン・非機能・収益化） |
| [docs/ROADMAP.md](docs/ROADMAP.md) | フェーズ別ロードマップとマイルストーン |
| [docs/SOUND_PLAN.md](docs/SOUND_PLAN.md) | 音質ゴールと音色・合成の実装方針（Phase 3.5） |
| [docs/ENVIRONMENT.md](docs/ENVIRONMENT.md) | 開発環境セットアップ（Xcode / Apple ID / Cursor） |

---

## リポジトリ構成（Phase 0–3）

```
GameSoundCreator.xcodeproj/   … iOS アプリ
App/                          … SwiftUI（ホーム / ウィザード / 結果 / ライブラリ）
Packages/AudioGenCore/        … 音声生成エンジン（Swift Package）
  Intent/                     … SoundIntent / Catalog / Mapper
  Models/                     … SFXRecipe / BGMRecipe
  Synth/ SFX/ BGM/
docs/                         … 仕様・ロードマップ・環境手順
```

### 開き方

1. `GameSoundCreator.xcodeproj` を Xcode で開く  
2. Signing の **Team** を選んで ▶  
3. **ホーム** から「BGMを作る」または「効果音を作る」  
4. ジャンル・シーン（または用途）・雰囲気・長さを選んで「生成して聴く」  
5. 結果画面で **再生バー**・別パターン・保存・書き出し・共有  

旧スタジオ（詳細パラメータ）は **設定 → 開発用** に残しています。

Bundle ID 初期値: `com.trueocean.GameSoundCreator`
