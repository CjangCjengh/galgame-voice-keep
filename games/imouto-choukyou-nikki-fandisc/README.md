# 妹調教日記ファンディスク

## 対象バージョン

- パッケージ版
- 実行ファイルのバージョン：`1.0.1.10`
- 対象ファイル：`scene.int`、`UPDATE00.INT`

パッチを実行すると、対応しているファイルかどうかを自動で確認します。対応外のファイルは変更しません。

## ボイスカットを無効にする方法

まず、画面上部のメニューバーにある設定からボイスカットをオフにしてください。これだけでも、地の文や主人公の台詞へ進んだときは再生中のボイスが止まらなくなります。

ただし、一部のボイスがない台詞では、設定をオフにしても直前のボイスが止まります。シーンデータに音声再生命令がある一方で、参照先の音声ファイルが製品データに入っていないためです。

付属のパッチは、実在しない音声ファイルを参照している120か所の `pcm` 命令だけを無効にします。実在するボイスの再生命令は変更しません。

## パッチの使い方

1. ゲームを終了します。
2. [`patch/patch-voicecut.ps1`](patch/patch-voicecut.ps1) をダウンロードします。
3. PowerShellで次のように実行します。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voicecut.ps1" -GameDirectory "D:\Games\妹調教日記ファンディスク"
```

`-GameDirectory` には、実際のインストール先を指定してください。省略した場合は、実行時に入力できます。

状態だけを確認する場合：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voicecut.ps1" -Mode Check -GameDirectory "D:\Games\妹調教日記ファンディスク"
```

## 元に戻す方法

初回適用時に `scene.int.before-voicecut-patch.bak` と `UPDATE00.INT.before-voicecut-patch.bak` が作成されます。次のコマンドで元に戻せます。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voicecut.ps1" -Mode Restore -GameDirectory "D:\Games\妹調教日記ファンディスク"
```

復元後もバックアップは削除されません。

## 補足

この作品では `UPDATE00.INT` 内のシーンが `scene.int` 内の同名シーンより優先されます。パッチは実際に使われるシーンだけを対象にし、更新前のシーンに残っている命令は変更しません。
