# 開発環境セットアップガイド

GameSoundCreator（Swift / iOS）を始めるための環境構築手順です。  
**Python / Vite 経験者向け**に、「何が必要で、何がまだ不要か」から説明します。

| 項目 | 内容 |
|------|------|
| 最終更新 | 2026-07-26 |
| 対象マシン（作成時） | Apple Silicon Mac、macOS 26.x、Homebrew あり、**Xcode 未インストール** |

---

## 0. 先に全体像（Vite との対比）

これまで:

| 役割 | Web 開発で使っていたもの |
|------|--------------------------|
| コードを書く | Cursor / VS Code |
| ビルド・プレビュー | Vite（ターミナル） |
| ブラウザで確認 | Chrome など |

これから（iOS）:

| 役割 | 使うもの |
|------|----------|
| コードを書く | **Cursor**（今まで通りでOK） |
| プロジェクト作成・ビルド・実機/シミュレータ実行 | **Xcode**（必須・新規） |
| 言語 | **Swift**（JavaScript の代わり） |
| UI | **SwiftUI**（HTML/CSS/React に近い「画面の書き方」） |
| パッケージ | **Swift Package Manager**（npm に近い公式の仕組み） |

重要:

- **Cursor だけでは iPhone アプリをビルド／実行できない**（いまのところ）
- **Xcode は必須**。App Store から入れる大きな開発ツールです
- 日常は「Cursor で編集 → Xcode で Run」または「両方で同じフォルダを開く」 Dual 運用が一般的です

---

## 1. いまの Mac で足りているもの／足りないもの

セットアップ確認時点の状態:

| 項目 | 状態 | 意味 |
|------|------|------|
| Mac（Apple Silicon） | あり | iOS 開発に問題なし |
| macOS | あり（26.x） | OK |
| 空き容量 | 十分（目安 40GB 以上あると安心） | Xcode は大きい |
| Homebrew | あり | 任意ツールのインストールに使える |
| Command Line Tools + Swift | あり | ターミナルで `swift` は動くが **iOSアプリ用ではない** |
| **Xcode.app** | **なし ← 最優先で入れる** | シミュレータ・iOS SDK・Interface がここに入る |
| Apple Developer 有料会員 | まだ不要 | 実機の簡易テストは無料 Apple ID で可能なことが多い。**Store 公開時に有料が必要** |

---

## 2. やることリスト（この順で）

1. Xcode をインストールする  
2. Xcode を一度起動し、追加コンポーネントを入れる  
3. ライセンス同意・シミュレータが動くか確認する  
4. （推奨）iPhone を用意し、ケーブル接続できる状態にする  
5. Cursor でこのリポジトリを開き続けられることを確認する  
6. Apple ID を Xcode にサインインする（無料で可）  
7. 動作確認用の「Hello」アプリを1つ作って Run する  

**今は不要なもの:** Node、Vite、Python 仮想環境、Docker、Android Studio、有料の Apple Developer（公開まで）。

---

## 3. Step 1 — Xcode をインストールする

### 方法A（おすすめ）: App Store

1. Mac で **App Store** を開く  
2. 「**Xcode**」で検索（発行元: Apple）  
3. **入手 / インストール**（無料、ただし **10〜20GB超**、通信・展開含め時間がかかります）  
4. インストール完了まで Mac をスリープさせない方が安全です  

### 方法B: Apple Developer サイト

[https://developer.apple.com/xcode/](https://developer.apple.com/xcode/) から入手する方法もあります。通常は App Store で十分です。

### インストール後にターミナルで確認

```bash
ls /Applications/Xcode.app
xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

期待する結果の例:

```text
Xcode 16.x  （またはその時点の最新）
Build version ...
```

`xcode-select -s ...` は、いま入っている「Command Line Tools だけ」の状態から、**本物の Xcode を使うよう切り替え**ます。初回は管理者パスワードを求められることがあります。

---

## 4. Step 2 — Xcode 初回セットアップ

1. **Launchpad または Applications から Xcode を起動**  
2. ライセンスに同意  
3. 「Additional Components」などのダウンロードが出たら **Install**（シミュレータ等）  
4. 終わるまで待つ（ここも時間がかかることがあります）  

### シミュレータの確認

1. Xcode メニュー **Xcode → Settings（Settings）→ Platforms**（名称は版で多少違う場合あり）  
2. **iOS** のランタイムが入っていることを確認。無ければ Get / Download  

---

## 5. Step 3 — 最初の「Hello」で動作確認（超重要）

本リポジトリの本実装の前に、**空のサンプルアプリが Run できること**を確認します。

1. Xcode を開く → **Create New Project**  
2. **iOS** → **App** → Next  
3. 例:  
   - Product Name: `HelloSound`  
   - Interface: **SwiftUI**  
   - Language: **Swift**  
   - Storage: None で可  
4. 保存場所は `Desktop` など一時でOK（GameSoundCreator とは別でよい）  
5. 画面上のデバイス選択で **iPhone 16** などシミュレータを選ぶ  
6. ▶（Run）を押す  

シミュレータが起動し、「Hello, world!」系の画面が出れば **環境OK** です。

うまくいかないとき:

| 症状 | 確認 |
|------|------|
| Run がグレー／失敗 | Platforms に iOS が入っているか |
| Signing エラー | 次の Step（Apple ID）へ |
| シミュレータが真っ黒 | 初回は待つ。だめなら別機種のシミュレータを試す |

---

## 6. Step 4 — Apple ID を Xcode に入れる

1. **Xcode → Settings → Accounts**  
2. **+** で **Apple ID** を追加（普段の Apple ID で可）  
3. Hello プロジェクトの左側でプロジェクト名をクリック → **Signing & Capabilities**  
4. **Team** に自分の名前（Personal Team）が出ることを確認  
5. 「Signing for ... requires a development team」系が出ていたら、ここで解消されることが多いです  

### 無料 Apple ID でできること / できないこと

| できる | まだできない（有料プログラムが必要） |
|--------|--------------------------------------|
| シミュレータで実行 | App Store への公開 |
| 自分の iPhone へのインストール（制限あり・定期の再署名など） | 広い TestFlight 配布や本番審査 |

有料の **Apple Developer Program**（年額）は、**App Store 販売の直前フェーズ**で加入すれば十分です。今は急がなくて大丈夫です。

---

## 7. Step 5 — 実機（iPhone）について（強く推奨）

このアプリは **音** が本体なので、最終確認は実機が必要です。

1. iPhone を USB-C / Lightning で Mac に接続  
2. iPhone 側で「このコンピュータを信頼」  
3. Xcode のデバイス一覧に iPhone 名が出る  
4. Run 先をシミュレータから iPhone に変更して ▶  

初回は「開発元を信頼」を iPhone の **設定 → 一般 → VPNとデバイス管理** あたりで行う必要があります（iOS の版で文言が少し違います）。

シミュレータでも音は出ますが、**レイテンシや実スピーカ感は実機が正解**です。

---

## 8. Cursor との付き合い方

### 推奨ワークフロー

1. **Cursor** で `/Users/trueocean/Desktop/Cursor/GameSoundCreator` を開いて仕様・Swift を編集  
2. **Xcode** で同じプロジェクト（`.xcodeproj` / `.xcworkspace`）を開いて ▶ で実行  
3. エラーの赤い表示は Xcode の方が分かりやすいことが多い  

### Cursor でできること / 苦手なこと

| Cursor 向き | Xcode の方がよい |
|-------------|------------------|
| SPEC・コード編集、リファクタ、説明 | 新規 iOS プロジェクト作成ウィザード |
| Git、ドキュメント | Signing、シミュレータ管理、実機インストール |
| エージェントに実装を頼む | 初回の Run、Capabilities、Assets |

Cursor Pro のままで問題ありません。**追加で「Cursor 用の特別な有料プラン」は不要**です。必要なのは Xcode です。

### エディタ設定（任意）

- Cursor に **Swift** 関連の拡張が入っていればシンタックスハイライトが楽になります  
- ただし「ビルドの真実」は常に Xcode / `xcodebuild` 側にあります  

---

## 9. アカウント・費用の見通し

| 項目 | いつ | 費用感 |
|------|------|--------|
| Xcode | 今すぐ | 無料 |
| Apple ID | 今すぐ（Signing用） | 無料 |
| Apple Developer Program | TestFlight 本格利用・Store 提出前 | 年額（時期により変動、公式を確認） |
| 有料音源・フォント | 使うときだけ | 基本は自作合成でゼロを目指す |
| AdMob 等 | 広告を入れる判断をしたとき | 基本無料枠あり |

---

## 10. インストール完了チェックリスト

全部にチェックが付いたら、環境は整っています。

- [ ] `/Applications/Xcode.app` がある  
- [ ] `xcodebuild -version` が Xcode の版を表示する  
- [ ] Xcode が起動し、追加コンポーネントの導入が終わっている  
- [ ] 空の SwiftUI アプリがシミュレータで Run できる  
- [ ] Xcode Accounts に Apple ID が入っている  
- [ ] （推奨）実機 iPhone でも一度 Run できた  
- [ ] Cursor で本リポジトリが開ける  

確認コマンド:

```bash
xcodebuild -version
xcode-select -p
# 期待: /Applications/Xcode.app/Contents/Developer
swift --version
```

---

## 11. 次にやること（環境が整ったら）

Phase 0 のプロジェクトはリポジトリに作成済みです。

1. `GameSoundCreator.xcodeproj` を Xcode で開く  
2. Team を選んでシミュレータまたは実機で Run  
3. サイン波の再生と WAV 書き出しを確認  
4. 問題なければ Phase 1（効果音エンジン）へ  

詳細は [ROADMAP.md](ROADMAP.md) を参照。

---

## 12. よくある不安への短答

**Q. Python や Vite の知識は無駄？**  
A. いいえ。モジュール分割、JSON、Git、UIの状態、非同期の感覚はそのまま活きます。書き方が Swift / SwiftUI に変わるだけです。

**Q. 全部 Cursor だけで完結したい**  
A. 編集は可能ですが、**実行・署名・シミュレータは Xcode が必要**です。最初は Dual 運用を推奨します。

**Q. 今すぐ有料 Developer に入るべき？**  
A. いいえ。シミュレータ開発が先。公開フェーズで十分です。

**Q. Windows や Linux では？**  
A. 本製品の本線（iOS）は **Mac + Xcode が必須**です。いまの Mac で問題ありません。
