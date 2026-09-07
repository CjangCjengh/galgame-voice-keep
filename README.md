# ギャルゲーのボイスキープ化メモ

ゲーム内でボイスキープを選べないギャルゲー向けに、次のボイスが流れるまで再生中のボイスを止めないようにする方法やパッチをまとめています。

ゲーム内の設定画面に項目がなくても、ウィンドウ上部のメニューバーから変更できることがあります。その設定だけで目的の動作になる作品は、ここでは扱いません。

## 対応ゲーム

| ゲームタイトル | エンジン | 対応方法 |
| --- | --- | --- |
| [あまえて☆にぃに2〜バブみのある妹たちは、にぃにの××をえらいえらいしてあげたいんです♪](games/amaete-niini-2/) | TyranoScript | PowerShellパッチ |
| [妹調教日記～こんなツンデレが俺の妹なわけない！！～](games/imouto-choukyou-nikki/) | CatSystem2 | PowerShellパッチ |
| [妹調教日記ファンディスク](games/imouto-choukyou-nikki-fandisc/) | CatSystem2 | PowerShellパッチ |
| [VenusBlood](games/venus-blood/) | KiriKiri2 | PowerShellパッチ |
| [VenusBlood-EMPIRE-](games/venus-blood-empire/) | KiriKiri2 | PowerShellパッチ |
| [VenusBlood -CHIMERA-](games/venus-blood-chimera/) | KiriKiri2 | PowerShellパッチ |
| [VenusBlood-DESIRE-](games/venus-blood-desire/) | KiriKiri2 | PowerShellパッチ |
| [肛拡姉妹～義父に徹底開発される連れ子アナル～](games/koukaku-shimai/) | Bruns | PowerShellパッチ |
| [復讐の死霊魔術師 ～望むのは死の痛み～](games/fukushuu-no-shiryou-majutsushi/) | System-NNN | PowerShellパッチ |
| [娘姉妹](games/musume-shimai/) | GLib2 | PowerShellランチャー |

表記ゆれを含む検索用の一覧は [`games/catalog.yml`](games/catalog.yml) にあります。

ブラウザーから探す場合は、[検索ページ](https://cjangcjengh.github.io/galgame-voice-keep/)を使えます。

## ボイスカットとボイスキープ

ここでは、次のテキストへ進んだ時点で再生中のボイスを止める動作を「ボイスカット」、ボイスのないテキストでは止めず、次のボイスが流れた時点で切り替える動作を「ボイスキープ」と呼びます。

## 注意事項

- 必ずゲームを終了してから作業してください。
- 対応しているバージョンを各ゲームのページで確認してください。
- セーブデータとは別に、変更するファイルのバックアップも残してください。
- ゲーム本体、シナリオ、画像、音声などは含めていません。
- 自己責任で使ってください。このパッチについて販売元や開発元へ問い合わせないでください。

## ライセンス

ここにあるスクリプトと文書は、特に記載がない限りMIT Licenseで公開しています。ゲーム名、製品名、各種素材の権利は、それぞれの権利者に帰属します。
