# 妹調教日記～こんなツンデレが俺の妹なわけない！！～

## 対象バージョン

- パッケージ版
- 実行ファイルのバージョン：`1.0.1.10`
- 対象ファイル：`scene.int`

パッチを実行すると、対応しているファイルかどうかを自動で確認します。対応外のファイルは変更しません。

## ボイスキープにする方法

まず、画面上部のメニューバーにある設定からボイスカットをオフにしてください。これだけでも、地の文や主人公の台詞へ進んだときは再生中のボイスが止まらなくなります。

ただし、男Ａや男Ｂなど一部のボイスがない台詞では、設定をオフにしても直前のボイスが止まります。シーンデータに音声再生命令がある一方で、参照先の音声ファイルが製品データに入っていないためです。

付属のパッチは、実在しない音声ファイルを参照している407か所の `pcm` 命令だけを無効にします。実在するボイスの再生命令は変更しません。

## パッチの使い方

1. ゲームを終了します。
2. [`patch/patch-voice-keep.ps1`](patch/patch-voice-keep.ps1) をダウンロードします。
3. PowerShellで次のように実行します。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voice-keep.ps1" -GameDirectory "D:\Games\妹調教日記"
```

`-GameDirectory` には、実際のインストール先を指定してください。省略した場合は、実行時に入力できます。

状態だけを確認する場合：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voice-keep.ps1" -Mode Check -GameDirectory "D:\Games\妹調教日記"
```

## 元に戻す方法

初回適用時に `scene.int.before-voice-keep-patch.bak` が作成されます。次のコマンドで元に戻せます。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voice-keep.ps1" -Mode Restore -GameDirectory "D:\Games\妹調教日記"
```

復元後もバックアップは削除されません。

## 補足

CatSystem2では、ボイスがない台詞でもシーンデータに `pcm` 命令だけが残っている場合があります。参照先が存在しなくても、その命令を処理した時点で再生中のボイスが止まるため、話者名ではなく音声ファイルの有無を基準に調べる必要があります。
