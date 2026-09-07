# 娘姉妹

## 対象バージョン

- 製品版 Ver.1.00
- 対象ファイル：`musume.exe`

ランチャーを実行すると、対応しているファイルと実行時コードかどうかを自動で確認します。対応外のバージョンは変更しません。

## ボイスキープにする方法

この作品では、テキストを進めるたびに、再生中のボイスを300ミリ秒で停止する処理が呼ばれます。次のボイスを再生するときにも、同じ停止関数が別の箇所から呼ばれます。

付属のランチャーは、テキスト送り側の停止呼び出しだけを実行中のメモリ上で無効にします。次のボイスを再生するときの切り替えや、BGM・効果音の処理は変更しません。

`musume.exe` は実行時に展開されるため、ゲームを起動するたびにランチャーを使う必要があります。ゲーム本体のファイルは書き換えません。

## ランチャーの使い方

1. ゲームを終了します。
2. [`patch/launch-voice-keep.cmd`](patch/launch-voice-keep.cmd) と [`patch/patch-voice-keep.ps1`](patch/patch-voice-keep.ps1) をゲームフォルダーへ保存します。
3. `launch-voice-keep.cmd` をダブルクリックします。

別のフォルダーから実行する場合：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voice-keep.ps1" -Mode Launch -GameDirectory "D:\Games\娘姉妹"
```

すでにゲームを起動している場合：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voice-keep.ps1" -Mode Attach -GameDirectory "D:\Games\娘姉妹"
```

## 元に戻す方法

ゲームを終了するだけで元に戻ります。ディスク上の `musume.exe` やシナリオは変更されません。

## 補足

GLib2では、テキスト送りと次のボイス開始の両方から同じ停止関数が呼ばれることがあります。停止関数そのものではなく、テキスト送り側の呼び出しだけを分けて変更する必要があります。
