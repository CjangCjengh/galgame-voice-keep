# 肛拡姉妹～義父に徹底開発される連れ子アナル～

## 対象バージョン

- DL版
- 対象ファイル：`肛拡姉妹.exe`

パッチを実行すると、対応しているファイルかどうかを自動で確認します。対応外のファイルは変更しません。

## ボイスキープにする方法

この作品では、次のテキストへ進むたびに、Bruns側の共通処理でボイス用ストリームが停止します。

付属のパッチは、その停止呼び出しだけを無効にするように `肛拡姉妹.exe` を変更します。次のボイスを再生する処理や、BGM・効果音の処理は変更しません。

## パッチの使い方

1. ゲームを終了します。
2. [`patch/patch-voice-keep.ps1`](patch/patch-voice-keep.ps1) をダウンロードします。
3. PowerShellで次のように実行します。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voice-keep.ps1" -GameDirectory "D:\Games\肛拡姉妹"
```

`-GameDirectory` には、実際のゲームフォルダーを指定してください。省略した場合は、実行時に入力できます。

状態だけを確認する場合：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voice-keep.ps1" -Mode Check -GameDirectory "D:\Games\肛拡姉妹"
```

## 元に戻す方法

初回適用時に `肛拡姉妹.exe.before-voice-keep-patch.bak` が作成されます。次のコマンドで元に戻せます。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\patch-voice-keep.ps1" -Mode Restore -GameDirectory "D:\Games\肛拡姉妹"
```

復元後もバックアップは削除されません。

## 補足

Brunsでは、シナリオに明示的な停止命令がなくても、テキストの待機解除を完了する共通処理からボイス停止が呼ばれることがあります。スクリプトだけでなく、実行時の呼び出し元も確認する必要があります。
