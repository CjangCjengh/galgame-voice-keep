# あまえて☆にぃに2〜バブみのある妹たちは、にぃにの××をえらいえらいしてあげたいんです♪

## 対象バージョン

- DL版
- 対象ファイル：`resources/app.asar`

パッチを実行すると、対応しているファイルかどうかを自動で確認します。対応外のファイルは変更しません。

## ボイスカットを無効にする方法

この作品ではキャラクターボイスをSEバッファー1で再生し、各テキストの終わりに同じバッファーで `mute.ogg` を流してボイスを止めています。

付属のパッチでは、シナリオ内にある1870か所の停止命令だけを、同じ長さの空白に置き換えます。ASARのサイズや内部のファイル配置は変えません。次のキャラクターボイスも同じバッファーで再生されるので、新しいボイスが始まれば古いボイスは通常どおり止まります。

## パッチの使い方

1. ゲームを終了します。
2. [`patch/patch-voicecut.ps1`](patch/patch-voicecut.ps1) をダウンロードします。
3. PowerShellで次のように実行します。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voicecut.ps1" -GameDirectory "D:\Games\あまえて☆にぃに2"
```

`-GameDirectory` には、実際のインストール先を指定してください。省略した場合は、実行時に入力できます。

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

- ボイスのないテキストへ進んでも、今のボイスは止まりません。
- 次のキャラクターボイスが始まると、今のボイスが止まり、新しいボイスに切り替わります。
- バッファー0の効果音や、シナリオ内の通常の停止命令は変更しません。
- セーブデータやゲーム設定は変更しません。

## 補足

TyranoScript製のゲームでは、ボイス専用の仕組みではなく、SEバッファーでキャラクターボイスを管理していることがあります。設定画面だけでなく、`voconfig`、`playse`、`mute.ogg` とバッファー番号の関係を調べると、どこでボイスを止めているのか見つけやすくなります。
