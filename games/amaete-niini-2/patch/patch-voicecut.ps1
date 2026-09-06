[CmdletBinding()]
param(
    [ValidateSet('Patch', 'Check', 'Restore')]
    [string]$Mode = 'Patch',

    [string]$GameDirectory
)

$ErrorActionPreference = 'Stop'

$expectedOriginalSha256 = 'B1F07DD06617EE99FA4F8E0462C95B87DE298D5AE64627D38D149C987347E933'
$expectedPatchedSha256 = '842BF1738CD918DA5ECD1560CC5F65EBFBF11F4C213B015D086E7D3183AD478A'
$expectedAsarSize = 234881640
$expectedCutTagCount = 1870
$cutTagText = '[playse buf=1 storage="mute.ogg"]'
$requiredPrefixText = '[l][cm]'
$latin1 = [Text.Encoding]::GetEncoding(28591)

function Read-Exactly {
    param(
        [IO.Stream]$Stream,
        [byte[]]$Buffer,
        [int]$Count
    )

    $readTotal = 0
    while ($readTotal -lt $Count) {
        $readNow = $Stream.Read($Buffer, $readTotal, $Count - $readTotal)
        if ($readNow -eq 0) {
            throw 'ASARの読み込み中に予期しないファイル終端へ到達しました。'
        }
        $readTotal += $readNow
    }
}

function Get-AsarIndex {
    param([string]$Path)

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $prefix = New-Object byte[] 16
        Read-Exactly -Stream $stream -Buffer $prefix -Count $prefix.Length

        $picklePayloadSize = [BitConverter]::ToUInt32($prefix, 0)
        $headerBlockSize = [BitConverter]::ToUInt32($prefix, 4)
        $jsonLength = [BitConverter]::ToUInt32($prefix, 12)
        if ($picklePayloadSize -ne 4 -or $jsonLength -le 0 -or $jsonLength -gt $headerBlockSize) {
            throw '想定している形式のASARヘッダーではありません。'
        }

        $jsonBytes = New-Object byte[] $jsonLength
        Read-Exactly -Stream $stream -Buffer $jsonBytes -Count $jsonBytes.Length
        $header = ([Text.Encoding]::UTF8.GetString($jsonBytes) | ConvertFrom-Json)

        [pscustomobject]@{
            Header = $header
            DataOffset = [int64](8 + $headerBlockSize)
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-AsarFiles {
    param(
        [object]$Node,
        [string]$Prefix = ''
    )

    if ($null -eq $Node.files) {
        return
    }

    foreach ($property in $Node.files.PSObject.Properties) {
        $relativePath = if ($Prefix) { "$Prefix/$($property.Name)" } else { $property.Name }
        $child = $property.Value

        if ($null -ne $child.files) {
            Get-AsarFiles -Node $child -Prefix $relativePath
        }
        elseif ($null -ne $child.size -and $null -ne $child.offset) {
            [pscustomobject]@{
                Path = $relativePath
                Offset = [int64]::Parse([string]$child.offset)
                Size = [int64]$child.size
            }
        }
    }
}

function Get-CutTagPatches {
    param([string]$Path)

    $index = Get-AsarIndex -Path $Path
    $scenarioFiles = @(
        Get-AsarFiles -Node $index.Header |
            Where-Object { $_.Path -like 'data/scenario/*.ks' }
    )

    if ($scenarioFiles.Count -eq 0) {
        throw 'ASAR内にTyranoScriptのシナリオファイルが見つかりません。'
    }

    $patches = [Collections.Generic.List[object]]::new()
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        foreach ($entry in $scenarioFiles) {
            if ($entry.Size -gt [int]::MaxValue) {
                throw "シナリオファイルのサイズが想定外です: $($entry.Path)"
            }

            $bytes = New-Object byte[] ([int]$entry.Size)
            $stream.Position = $index.DataOffset + $entry.Offset
            Read-Exactly -Stream $stream -Buffer $bytes -Count $bytes.Length

            if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
                $encoding = [Text.Encoding]::Unicode
            }
            elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
                $encoding = [Text.Encoding]::BigEndianUnicode
            }
            else {
                $encoding = [Text.Encoding]::UTF8
            }

            # 1文字を1バイトとして扱い、検索位置をASAR内のバイト位置と一致させる。
            $byteText = $latin1.GetString($bytes)
            $encodedCutTag = $latin1.GetString($encoding.GetBytes($cutTagText))
            $encodedPrefix = $latin1.GetString($encoding.GetBytes($requiredPrefixText))
            $encodedSpaces = $encoding.GetBytes((' ' * $cutTagText.Length))

            $searchAt = 0
            while ($true) {
                $matchAt = $byteText.IndexOf($encodedCutTag, $searchAt, [StringComparison]::Ordinal)
                if ($matchAt -lt 0) {
                    break
                }

                if ($matchAt -lt $encodedPrefix.Length -or
                    $byteText.Substring($matchAt - $encodedPrefix.Length, $encodedPrefix.Length) -ne $encodedPrefix) {
                    throw "想定した[l][cm]形式以外の停止命令が見つかりました: $($entry.Path)"
                }

                $patches.Add([pscustomobject]@{
                    Offset = $index.DataOffset + $entry.Offset + $matchAt
                    Bytes = $encodedSpaces
                })
                $searchAt = $matchAt + $encodedCutTag.Length
            }
        }
    }
    finally {
        $stream.Dispose()
    }

    [pscustomobject]@{
        Count = $patches.Count
        Patches = $patches
        ScenarioFileCount = $scenarioFiles.Count
    }
}

function Get-PatchState {
    param(
        [string]$Hash,
        [int]$CutTagCount
    )

    if ($Hash -eq $expectedOriginalSha256 -and $CutTagCount -eq $expectedCutTagCount) {
        return '未適用'
    }
    if ($Hash -eq $expectedPatchedSha256 -and $CutTagCount -eq 0) {
        return '適用済み'
    }
    return '未対応または変更済み'
}

if ([string]::IsNullOrWhiteSpace($GameDirectory)) {
    $GameDirectory = Read-Host 'ゲームのインストールフォルダーを入力してください'
}

$GameDirectory = $GameDirectory.Trim().Trim('"')
if (-not (Test-Path -LiteralPath $GameDirectory -PathType Container)) {
    throw "ゲームフォルダーが見つかりません: $GameDirectory"
}

$gameDirectoryFull = (Resolve-Path -LiteralPath $GameDirectory).Path.TrimEnd('\')
$asarPath = Join-Path $gameDirectoryFull 'resources\app.asar'
$backupPath = "$asarPath.before-voicecut-patch.bak"

if ($Mode -ne 'Check') {
    try {
        $runningProcesses = @(
            Get-CimInstance Win32_Process -ErrorAction Stop |
                Where-Object {
                    $_.ExecutablePath -and
                    $_.ExecutablePath.StartsWith($gameDirectoryFull, [StringComparison]::OrdinalIgnoreCase)
                }
        )
        if ($runningProcesses.Count -gt 0) {
            throw 'ゲームが実行中です。ゲームを終了してからもう一度実行してください。'
        }
    }
    catch {
        if ($_.Exception.Message -eq 'ゲームが実行中です。ゲームを終了してからもう一度実行してください。') {
            throw
        }
        Write-Warning '実行中プロセスを確認できませんでした。ゲームが終了していることを確認してください。'
    }
}

if ($Mode -eq 'Restore') {
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        throw "バックアップが見つかりません: $backupPath"
    }

    $backupHash = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash
    if ($backupHash -ne $expectedOriginalSha256) {
        throw "バックアップのSHA-256が対応する元ファイルと一致しません: $backupHash"
    }

    [IO.File]::Copy($backupPath, $asarPath, $true)
    Write-Output "元のファイルへ復元しました: $asarPath"
    exit 0
}

if (-not (Test-Path -LiteralPath $asarPath -PathType Leaf)) {
    throw "対象ファイルが見つかりません: $asarPath"
}

$asarItem = Get-Item -LiteralPath $asarPath
if ($asarItem.Length -ne $expectedAsarSize) {
    throw "対象ファイルのサイズが対応版と異なります: $($asarItem.Length) bytes"
}

$hashBefore = (Get-FileHash -LiteralPath $asarPath -Algorithm SHA256).Hash
$scan = Get-CutTagPatches -Path $asarPath
$state = Get-PatchState -Hash $hashBefore -CutTagCount $scan.Count

if ($Mode -eq 'Check') {
    [pscustomobject]@{
        状態 = $state
        対象ファイル = $asarPath
        SHA256 = $hashBefore
        残存する停止命令 = $scan.Count
        シナリオファイル数 = $scan.ScenarioFileCount
        バックアップ = Test-Path -LiteralPath $backupPath -PathType Leaf
    }
    exit 0
}

if ($state -eq '適用済み') {
    Write-Output 'ボイスカット無効化パッチはすでに適用されています。変更は行いませんでした。'
    exit 0
}

if ($state -ne '未適用') {
    throw "未対応または変更済みのASARです。SHA-256: $hashBefore。変更は行いませんでした。"
}

if (Test-Path -LiteralPath $backupPath) {
    $existingBackupHash = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash
    if ($existingBackupHash -ne $expectedOriginalSha256) {
        throw "既存バックアップのSHA-256が一致しないため上書きしません: $backupPath"
    }
}
else {
    [IO.File]::Copy($asarPath, $backupPath, $false)
}

$backupHash = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash
if ($backupHash -ne $expectedOriginalSha256) {
    throw "バックアップの検証に失敗しました。SHA-256: $backupHash"
}

$stream = [IO.File]::Open($asarPath, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    foreach ($patch in $scan.Patches) {
        $stream.Position = $patch.Offset
        $stream.Write($patch.Bytes, 0, $patch.Bytes.Length)
    }
    $stream.Flush($true)
}
finally {
    $stream.Dispose()
}

$scanAfter = Get-CutTagPatches -Path $asarPath
$hashAfter = (Get-FileHash -LiteralPath $asarPath -Algorithm SHA256).Hash
if ($scanAfter.Count -ne 0 -or $hashAfter -ne $expectedPatchedSha256) {
    throw "適用後の検証に失敗しました。バックアップから復元してください: $backupPath"
}

[pscustomobject]@{
    結果 = 'ボイスカット無効化パッチを適用しました'
    置換数 = $scan.Count
    パッチ後SHA256 = $hashAfter
    バックアップ = $backupPath
}
