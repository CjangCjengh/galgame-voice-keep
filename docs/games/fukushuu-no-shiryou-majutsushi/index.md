---
layout: game
title: "復讐の死霊魔術師 ～望むのは死の痛み～"
game_id: "fukushuu-no-shiryou-majutsushi"
permalink: /games/fukushuu-no-shiryou-majutsushi/
---

## 対象バージョン

- DL版
- 対象ファイル：`shiryo.exe`

パッチを実行すると、対応しているファイルかどうかを自動で確認します。対応外のファイルは変更しません。

## ボイスキープにする方法

この作品では、ボイスのある台詞の前に再生命令が入り、その後のボイスがないテキストへ移る前に0番の音声チャンネルを止める命令が入っています。

付属のパッチは、ファイル名を指定せずに0番の音声チャンネルを止める処理だけを無視するように `shiryo.exe` を変更します。次のボイスを再生する処理や、別チャンネルの効果音を止める処理は変更しません。

## パッチの使い方

1. ゲームを終了します。
2. [`patch/patch-voice-keep.ps1`](patch/patch-voice-keep.ps1) をダウンロードします。
3. PowerShellで次のように実行します。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voice-keep.ps1" -GameDirectory "D:\Games\復讐の死霊魔術師"
```

`-GameDirectory` には、実際のゲームフォルダーを指定してください。省略した場合は、実行時に入力できます。

状態だけを確認する場合：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voice-keep.ps1" -Mode Check -GameDirectory "D:\Games\復讐の死霊魔術師"
```

## 元に戻す方法

初回適用時に `shiryo.exe.before-voice-keep-patch.bak` が作成されます。次のコマンドで元に戻せます。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voice-keep.ps1" -Mode Restore -GameDirectory "D:\Games\復讐の死霊魔術師"
```

復元後もバックアップは削除されません。

## 補足

System-NNNでは、ボイスのない台詞への切り替えが、ファイル名を持たないボイス再生命令として入っている場合があります。命令そのものを一括で消すのではなく、引数と音声チャンネルを分けて確認する必要があります。
