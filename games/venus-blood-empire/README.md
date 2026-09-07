# VenusBlood-EMPIRE-

## 対象バージョン

- パッケージ版
- 対象ファイル：`patch.xp3`（86,549,914バイト）

パッチを実行すると、対応しているファイルかどうかを自動で確認します。対応外のファイルは変更しません。

## ボイスキープにする方法

この作品では、共通の改ページマクロ `p2` が、ページ送りのたびに0番の音声バッファを停止しています。ボイスもこのバッファを使うため、次のページにボイスがなくても再生中のボイスが止まります。

付属のパッチは、`patch.xp3` 内の `macro.ks` から、この停止命令だけを外します。次のボイスは同じバッファで再生されるため、その時点で前のボイスから通常どおり切り替わります。

`data.xp3` は変更しません。セーブ先などを別途変更している場合も、その内容はそのまま残ります。

## パッチの使い方

1. ゲームを終了します。
2. [`patch/patch-voice-keep.ps1`](patch/patch-voice-keep.ps1) をダウンロードします。
3. PowerShellで次のように実行します。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voice-keep.ps1" -GameDirectory "D:\Games\VenusBlood-EMPIRE-"
```

`-GameDirectory` には、実際のゲームフォルダーを指定してください。省略した場合は、実行時に入力できます。

状態だけを確認する場合：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voice-keep.ps1" -Mode Check -GameDirectory "D:\Games\VenusBlood-EMPIRE-"
```

## 元に戻す方法

初回適用時に `patch.xp3.before-voice-keep-patch.bak` が作成されます。次のコマンドで元に戻せます。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voice-keep.ps1" -Mode Restore -GameDirectory "D:\Games\VenusBlood-EMPIRE-"
```

復元後もバックアップは削除されません。

## 補足

KiriKiri2では、同名のスクリプトが複数のXP3に入っている場合、後から読み込まれるアーカイブ側が使われることがあります。この作品では `data.xp3` ではなく、実際に使われる `patch.xp3` 側の `macro.ks` を確認する必要がありました。
