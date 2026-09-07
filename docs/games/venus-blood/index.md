---
layout: game
title: "VenusBlood"
game_id: "venus-blood"
permalink: /games/venus-blood/
---

## 対象バージョン

- 10th AnniversaryPack版
- 読み取り元：`data.xp3`（731,761,145バイト）
- 作成先：`patch2.xp3`

パッチを実行すると、対応しているファイルかどうかを自動で確認します。対応外のファイルは変更しません。

## ボイスキープにする方法

この作品では、新しいテキストを表示する前に呼ばれる `cm2` マクロが、0番の音声バッファを毎回停止しています。ボイスもこのバッファを使うため、次のテキストにボイスがなくても再生中のボイスが止まります。

付属のパッチは、`data.xp3` 内の `macro.ks` を読み取り、`cm2` にある停止命令だけを外した `patch2.xp3` を作成します。次のボイスは `voice` マクロ側で前のボイスを停止してから再生されるため、その時点で通常どおり切り替わります。

`data.xp3` と既存の `patch.xp3` は変更しません。`patch.xp3` でセーブ先などを変更している場合も、その内容はそのまま残ります。

## パッチの使い方

1. ゲームを終了します。
2. [`patch/patch-voice-keep.ps1`](patch/patch-voice-keep.ps1) をダウンロードします。
3. PowerShellで次のように実行します。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voice-keep.ps1" -GameDirectory "D:\Games\VenusBlood"
```

`-GameDirectory` には、実際のゲームフォルダーを指定してください。省略した場合は、実行時に入力できます。

状態だけを確認する場合：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voice-keep.ps1" -Mode Check -GameDirectory "D:\Games\VenusBlood"
```

すでに別の `patch2.xp3` がある場合は上書きしません。

## 元に戻す方法

次のコマンドで、このパッチが作成した `patch2.xp3` を削除できます。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voice-keep.ps1" -Mode Restore -GameDirectory "D:\Games\VenusBlood"
```

内容がこのパッチの作成したファイルと一致しない場合は削除しません。

## 補足

この作品は `patch.xp3` の後に `patch2.xp3` を読み込む仕組みを持っています。既存の `patch.xp3` に手を加えず、ボイスキープ用の `macro.ks` だけを後から優先させています。
