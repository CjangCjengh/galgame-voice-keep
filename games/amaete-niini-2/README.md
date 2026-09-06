# あまえて☆にぃに2〜バブみのある妹たちは、にぃにの××をえらいえらいしてあげたいんです♪

## 対象バージョン

- DL版
- 対象ファイル：`resources/app.asar`
- 元ファイルのSHA-256：`B1F07DD06617EE99FA4F8E0462C95B87DE298D5AE64627D38D149C987347E933`

上記ハッシュと異なる版にはパッチを適用できません。

## 症状

ボイス再生中に次のテキストへ進むと、次の行にボイスがなくても現在のボイスが停止します。ゲーム内にこの動作を切り替える設定は確認できません。

## ボイスカットを無効にする方法

この作品ではキャラクターボイスをSE buffer 1で再生し、各テキストの終了後に同じbufferで `mute.ogg` を再生することでボイスを停止しています。

付属パッチは、シナリオ内の該当する停止命令1870か所だけを同じ長さの空白へ置き換えます。ASARのサイズや索引は変更しません。次のキャラクターボイスも同じbufferを使用するため、新しいボイスが始まった時点で古いボイスは通常どおり停止します。

## パッチの使い方

1. ゲームを終了します。
2. [`patch/patch-voicecut.ps1`](patch/patch-voicecut.ps1) をダウンロードします。
3. PowerShellで次のように実行します。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voicecut.ps1" -GameDirectory "D:\Games\あまえて☆にぃに2"
```

`-GameDirectory` には、ゲームの実際のインストール先を指定してください。省略した場合は実行時に入力できます。

状態だけを確認する場合：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voicecut.ps1" -Mode Check -GameDirectory "D:\Games\あまえて☆にぃに2"
```

## 元に戻す方法

初回適用時に `resources/app.asar.before-voicecut-patch.bak` が作成されます。次のコマンドで元に戻せます。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voicecut.ps1" -Mode Restore -GameDirectory "D:\Games\あまえて☆にぃに2"
```

復元後もバックアップは削除されません。

## 動作上の変化

- ボイスのないテキストへ進んでも、現在のボイスは継続します。
- 次のキャラクターボイスが始まると、現在のボイスは停止して切り替わります。
- buffer 0の効果音や、シナリオで明示された通常の停止命令は変更しません。
- セーブデータやゲーム設定は変更しません。

## このゲームから得られた知見

TyranoScript作品では、ボイス専用の仕組みではなくSE bufferを使ってキャラクターボイスを管理している場合があります。設定画面だけでなく、`voconfig`、`playse`、`mute.ogg` とbuffer番号の関係を確認すると、ボイスカットの実装箇所を特定しやすくなります。
