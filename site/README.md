# レトロサウンド公開サイト

GitHub Pagesで公開する静的サイトです。`site/` 以下には、トップページ、プライバシーポリシー、利用規約、サポートページが含まれます。

## 公開前に行うこと

1. `site/support/index.html` のサポート用メールアドレス案内を、実際に受信できる連絡先へ置き換える。
2. 独自ドメインを取得する場合は、GitHub Pagesの設定画面でドメインを接続し、表示されるDNSレコードをドメイン管理会社へ設定する。
3. GitHubリポジトリの **Settings → Pages** で **GitHub Actions** を公開元として選ぶ。
4. 公開後の各ページURLを `App/AppStoreLinks.swift` に設定する。

独自ドメインへ切り替えた場合は、`site/index.html` の `og:image` も新しいドメインのURLへ更新する。

## ページURL

独自ドメインのルートへ公開した場合のURLです。

- `/` — トップページ
- `/privacy/` — プライバシーポリシー
- `/terms/` — 利用規約
- `/support/` — サポート
