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
$targetPath = Join-Path $GameDirectory 'shiryo.exe'
$backupPath = "$targetPath.before-voice-keep-patch.bak"
$originalSize = 1966592
$originalHash = '09246844C2FD9E05E29F00298AB7DE678117B23667981C83D95B718D874FD591'
$patchedHash = 'ADDE46EB3CA75EA01ACB2D7E32533C570B12E2FB5016C432C9767C8D614D4FB9'

$siteOffset = 0x1476E6
$caveOffset = 0x126064
$originalSite = [byte[]](0x8B, 0x45, 0xC8, 0x8B, 0x88, 0x68, 0x70, 0x00, 0x00)
$originalCave = [byte[]]::new(28)
for ($i = 0; $i -lt $originalCave.Length; $i++) {
    $originalCave[$i] = 0xCC
}
$patchedSite = [byte[]](0xE9, 0x79, 0xE9, 0xFD, 0xFF, 0x90, 0x90, 0x90, 0x90)
$patchedCave = [byte[]](
    0x83, 0x7D, 0xE8, 0x00,
    0x0F, 0x84, 0xC0, 0x17, 0x02, 0x00,
    0x8B, 0x45, 0xC8,
    0x8B, 0x88, 0x68, 0x70, 0x00, 0x00,
    0xE9, 0x73, 0x16, 0x02, 0x00
)

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
        'NotFound' { 'shiryo.exe が見つかりません' }
        default { '未対応または変更済み' }
    }
    [pscustomobject]@{
        状態 = $label
        対象 = $targetPath
    }
    exit 0
}

if ((Get-Process -Name 'shiryo' -ErrorAction SilentlyContinue)) {
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
    throw "shiryo.exe が見つかりません: $targetPath"
}
if ($state -ne 'Original') {
    throw 'shiryo.exe は未対応版または変更済みです。変更は行いませんでした。'
}

if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
    if ((Get-State $backupPath) -ne 'Original') {
        throw '既存のバックアップが対応版のオリジナルと一致しません。'
    }
} else {
    Copy-Item -LiteralPath $targetPath -Destination $backupPath
}

$data = [System.IO.File]::ReadAllBytes($targetPath)
if (-not (Test-Bytes $data $siteOffset $originalSite)) {
    throw 'パッチ位置の内容が対応版と一致しません。'
}
if (-not (Test-Bytes $data $caveOffset $originalCave)) {
    throw '使用予定のコード領域が空いていません。'
}

[Array]::Copy($patchedSite, 0, $data, $siteOffset, $patchedSite.Length)
[Array]::Copy($patchedCave, 0, $data, $caveOffset, $patchedCave.Length)
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
