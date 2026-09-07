---
layout: game
title: "VenusBlood-DESIRE-"
game_id: "venus-blood-desire"
permalink: /games/venus-blood-desire/
---

## 対象バージョン

- パッケージ版（製品版 Ver.1.00）
- 読み取り元：`data.xp3` 内の `game_system/macro.ks`
- 作成先：`patch.xp3`

パッチを実行すると、`data.xp3` 内の対象スクリプトを自動で確認します。対応外のファイルは変更しません。

## ボイスキープにする方法

この作品では、共通の改ページマクロ `p2` が、ページ送りのたびに0番の音声バッファを停止しています。そのため、次のテキストにボイスがなくても再生中のボイスが止まります。

付属のパッチは、`p2` にある停止命令だけを外した `patch.xp3` を作成します。次のボイスも同じバッファで再生されるため、その時点で前のボイスから通常どおり切り替わります。

`data.xp3` は変更しません。

## パッチの使い方

1. ゲームを終了します。
2. [`patch/patch-voice-keep.ps1`](patch/patch-voice-keep.ps1) をダウンロードします。
3. PowerShellで次のように実行します。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voice-keep.ps1" -GameDirectory "D:\Games\VenusBlood-Desire-"
```

`-GameDirectory` には、実際のゲームフォルダーを指定してください。省略した場合は、実行時に入力できます。

状態だけを確認する場合：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voice-keep.ps1" -Mode Check -GameDirectory "D:\Games\VenusBlood-Desire-"
```

すでに別の `patch.xp3` がある場合は上書きしません。

## 元に戻す方法

次のコマンドで、このパッチが作成した `patch.xp3` を削除できます。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voice-keep.ps1" -Mode Restore -GameDirectory "D:\Games\VenusBlood-Desire-"
```

内容がこのパッチの作成したファイルと一致しない場合は削除しません。

## 補足

スクリプト内の `ボイスカット` という変数は、キャラクターボイス自体を再生するかどうかの切り替えに使われています。ここで扱うボイスキープの設定ではありません。
