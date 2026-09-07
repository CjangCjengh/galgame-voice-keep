param(
    [ValidateSet('Apply', 'Check', 'Restore')]
    [string]$Mode = 'Apply',
    [string]$GameDirectory
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($GameDirectory)) {
    $GameDirectory = Read-Host 'ゲームフォルダーを入力してください'
}

$GameDirectory = [System.IO.Path]::GetFullPath($GameDirectory.Trim('"'))
$targetPath = Join-Path $GameDirectory '肛拡姉妹.exe'
$backupPath = "$targetPath.before-voice-keep-patch.bak"
$originalSize = 1681408
$originalHash = 'A966FEECD51E94E670FDB29D446EDE2A11C7660EEC37F81F5EC2E134F0C6E42D'
$patchedHash = '426CD54387B8B34BB87EFA2EB1D318D8D0B07420288F3934A1320334B800E19E'
$patchOffset = 0x5CD43
$originalBytes = [byte[]](0xE8, 0xA8, 0x06, 0x01, 0x00)
$patchedBytes = [byte[]](0x90, 0x90, 0x90, 0x90, 0x90)

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Test-Bytes(
    [byte[]]$Data,
    [int]$Offset,
    [byte[]]$Expected
) {
    if ($Offset -lt 0 -or $Offset + $Expected.Length -gt $Data.Length) {
        return $false
    }
    for ($i = 0; $i -lt $Expected.Length; $i++) {
        if ($Data[$Offset + $i] -ne $Expected[$i]) {
            return $false
        }
    }
    return $true
}

function Get-State([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return 'NotFound'
    }
    $file = Get-Item -LiteralPath $Path
    if ($file.Length -ne $originalSize) {
        return 'Unsupported'
    }
    $hash = Get-Sha256 $Path
    if ($hash -eq $originalHash) {
        return 'Original'
    }
    if ($hash -eq $patchedHash) {
        return 'Patched'
    }
    return 'Unsupported'
}

$state = Get-State $targetPath

if ($Mode -eq 'Check') {
    $label = switch ($state) {
        'Original' { '未適用（対応版）' }
        'Patched' { '適用済み' }
        'NotFound' { '肛拡姉妹.exe が見つかりません' }
        default { '未対応または変更済み' }
    }
    [pscustomobject]@{
        状態 = $label
        対象 = $targetPath
    }
    exit 0
}

if (Get-Process -Name '肛拡姉妹' -ErrorAction SilentlyContinue) {
    throw 'ゲームを終了してから実行してください。'
}

if ($Mode -eq 'Restore') {
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        throw "バックアップが見つかりません: $backupPath"
    }
    if ((Get-State $backupPath) -ne 'Original') {
        throw 'バックアップが対応版のオリジナルと一致しません。'
    }
    Copy-Item -LiteralPath $backupPath -Destination $targetPath -Force
    if ((Get-State $targetPath) -ne 'Original') {
        throw '復元後の確認に失敗しました。'
    }
    [pscustomobject]@{
        結果 = 'オリジナルへ復元しました'
        対象 = $targetPath
        バックアップ = $backupPath
    }
    exit 0
}

if ($state -eq 'Patched') {
    Write-Output 'ボイスキープ用パッチはすでに適用されています。変更は行いませんでした。'
    exit 0
}
if ($state -eq 'NotFound') {
    throw "肛拡姉妹.exe が見つかりません: $targetPath"
}
if ($state -ne 'Original') {
    throw '肛拡姉妹.exe は未対応版または変更済みです。変更は行いませんでした。'
}

if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
    if ((Get-State $backupPath) -ne 'Original') {
        throw '既存のバックアップが対応版のオリジナルと一致しません。'
    }
} else {
    Copy-Item -LiteralPath $targetPath -Destination $backupPath
}

$data = [System.IO.File]::ReadAllBytes($targetPath)
if (-not (Test-Bytes $data $patchOffset $originalBytes)) {
    throw 'パッチ位置の内容が対応版と一致しません。'
}

[Array]::Copy($patchedBytes, 0, $data, $patchOffset, $patchedBytes.Length)
[System.IO.File]::WriteAllBytes($targetPath, $data)

if ((Get-State $targetPath) -ne 'Patched') {
    Copy-Item -LiteralPath $backupPath -Destination $targetPath -Force
    throw '適用後の確認に失敗したため、オリジナルへ戻しました。'
}

[pscustomobject]@{
    結果 = 'ボイスキープ用パッチを適用しました'
    対象 = $targetPath
    バックアップ = $backupPath
}
