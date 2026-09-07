[CmdletBinding()]
param(
    [ValidateSet('Patch', 'Check', 'Restore')]
    [string]$Mode = 'Patch',

    [string]$GameDirectory
)

$ErrorActionPreference = 'Stop'

$expectedSceneSha256 = 'B335550C298DE8CE73283146BC54F3AFEF993BDD48361C6E871AF4523993EEAC'
$expectedUpdateSha256 = 'BC5E07FA8F53599641CACB061347224CAEEFDE823F7E52F3A673E0375821BCB2'
$expectedSceneSize = 287911
$expectedUpdateSize = 2378262
$expectedVoiceArchiveCount = 3
$expectedAudioNameCount = 2471
$expectedSceneMissingCommandCount = 20
$expectedSceneValidCommandCount = 745
$expectedSceneAffectedCount = 3
$expectedUpdateMissingCommandCount = 100
$expectedUpdateValidCommandCount = 1719
$expectedUpdateAffectedCount = 20
$expectedMissingCommandCount = 120
$expectedAffectedSceneCount = 23
$scriptEncoding = [Text.Encoding]::GetEncoding(932)
$ascii = [Text.Encoding]::ASCII

function Get-UInt16 {
    param([byte[]]$Bytes, [int]$Offset)
    [BitConverter]::ToUInt16($Bytes, $Offset)
}

function Get-UInt32 {
    param([byte[]]$Bytes, [int]$Offset)
    [BitConverter]::ToUInt32($Bytes, $Offset)
}

function Add-KifNames {
    param(
        [string]$Path,
        [Collections.Generic.HashSet[string]]$Names
    )

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $reader = [IO.BinaryReader]::new($stream)
        if ($ascii.GetString($reader.ReadBytes(4)) -ne "KIF`0") {
            throw "KIFアーカイブではありません: $Path"
        }

        $count = $reader.ReadUInt32()
        $tableEnd = 8L + ([int64]$count * 72L)
        if ($count -eq 0 -or $tableEnd -gt $stream.Length) {
            throw "KIFのファイル一覧が壊れています: $Path"
        }

        for ($index = 0; $index -lt $count; $index++) {
            $nameBytes = $reader.ReadBytes(64)
            if ($nameBytes.Length -ne 64) {
                throw "KIFのファイル一覧を最後まで読み込めません: $Path"
            }
            $nullAt = [Array]::IndexOf($nameBytes, [byte]0)
            if ($nullAt -lt 0) { $nullAt = 64 }
            $name = $scriptEncoding.GetString($nameBytes, 0, $nullAt)
            [void]$reader.ReadUInt32()
            [void]$reader.ReadUInt32()
            [void]$Names.Add($name)
        }
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        else { $stream.Dispose() }
    }
}

function Read-KifEntries {
    param([string]$Path)

    $archive = [IO.File]::ReadAllBytes($Path)
    if ($archive.Length -lt 8 -or $ascii.GetString($archive, 0, 4) -ne "KIF`0") {
        throw "KIFアーカイブではありません: $Path"
    }

    $count = Get-UInt32 -Bytes $archive -Offset 4
    $tableEnd = 8L + ([int64]$count * 72L)
    if ($count -eq 0 -or $tableEnd -gt $archive.Length) {
        throw "KIFのファイル一覧が壊れています: $Path"
    }

    $entries = [Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $count; $index++) {
        $entryAt = 8 + ($index * 72)
        $nullAt = $entryAt
        while ($nullAt -lt ($entryAt + 64) -and $archive[$nullAt] -ne 0) {
            $nullAt++
        }
        $name = $scriptEncoding.GetString($archive, $entryAt, $nullAt - $entryAt)
        $offset = Get-UInt32 -Bytes $archive -Offset ($entryAt + 64)
        $size = Get-UInt32 -Bytes $archive -Offset ($entryAt + 68)
        if ($offset -lt $tableEnd -or ([int64]$offset + $size) -gt $archive.Length) {
            throw "scene.int内のファイル位置が不正です: $name"
        }

        $data = [byte[]]::new($size)
        [Array]::Copy($archive, $offset, $data, 0, $size)
        $entries.Add([pscustomobject]@{ Name = $name; Data = $data })
    }
    $entries
}

function Expand-Zlib {
    param(
        [byte[]]$Bytes,
        [int]$Offset,
        [int]$Length,
        [int]$ExpectedLength
    )

    if ($Length -lt 6) {
        throw 'CST内の圧縮データが短すぎます。'
    }
    $cmf = $Bytes[$Offset]
    $flg = $Bytes[$Offset + 1]
    if (($cmf -band 0x0F) -ne 8 -or ((($cmf * 256) + $flg) % 31) -ne 0 -or ($flg -band 0x20)) {
        throw '対応していないzlibヘッダーです。'
    }

    $input = [IO.MemoryStream]::new($Bytes, $Offset + 2, $Length - 6, $false)
    $output = [IO.MemoryStream]::new()
    try {
        $deflate = [IO.Compression.DeflateStream]::new($input, [IO.Compression.CompressionMode]::Decompress)
        try { $deflate.CopyTo($output) }
        finally { $deflate.Dispose() }
        $raw = $output.ToArray()
    }
    finally {
        $output.Dispose()
        $input.Dispose()
    }

    if ($raw.Length -ne $ExpectedLength) {
        throw "CSTの展開後サイズが一致しません: $($raw.Length)"
    }
    return ,$raw
}

function Get-Adler32 {
    param([byte[]]$Bytes)

    [uint64]$a = 1
    [uint64]$b = 0
    foreach ($value in $Bytes) {
        $a = ($a + $value) % 65521
        $b = ($b + $a) % 65521
    }
    [uint32](($b -shl 16) -bor $a)
}

function Compress-Zlib {
    param([byte[]]$Bytes)

    $deflatedStream = [IO.MemoryStream]::new()
    try {
        $deflate = [IO.Compression.DeflateStream]::new(
            $deflatedStream,
            [IO.Compression.CompressionLevel]::Optimal,
            $true
        )
        try { $deflate.Write($Bytes, 0, $Bytes.Length) }
        finally { $deflate.Dispose() }
        $deflated = $deflatedStream.ToArray()
    }
    finally {
        $deflatedStream.Dispose()
    }

    $result = [byte[]]::new($deflated.Length + 6)
    $result[0] = 0x78
    $result[1] = 0x9C
    [Array]::Copy($deflated, 0, $result, 2, $deflated.Length)
    $adler = Get-Adler32 -Bytes $Bytes
    $result[$result.Length - 4] = ($adler -shr 24) -band 0xFF
    $result[$result.Length - 3] = ($adler -shr 16) -band 0xFF
    $result[$result.Length - 2] = ($adler -shr 8) -band 0xFF
    $result[$result.Length - 1] = $adler -band 0xFF
    return ,$result
}

function Read-Cst {
    param([byte[]]$Data)

    if ($Data.Length -lt 16 -or $ascii.GetString($Data, 0, 8) -ne 'CatScene') {
        throw 'scene.int内に想定外のCSTファイルがあります。'
    }
    $compressedLength = Get-UInt32 -Bytes $Data -Offset 8
    $rawLength = Get-UInt32 -Bytes $Data -Offset 12

    if ($compressedLength -eq 0) {
        if ((16L + $rawLength) -gt $Data.Length) {
            throw 'CSTのデータサイズが不正です。'
        }
        $raw = [byte[]]::new($rawLength)
        [Array]::Copy($Data, 16, $raw, 0, $rawLength)
    }
    else {
        if ((16L + $compressedLength) -gt $Data.Length) {
            throw 'CSTの圧縮データサイズが不正です。'
        }
        $raw = Expand-Zlib -Bytes $Data -Offset 16 -Length $compressedLength -ExpectedLength $rawLength
    }

    [pscustomobject]@{
        Raw = $raw
        WasCompressed = ($compressedLength -ne 0)
    }
}

function New-Cst {
    param(
        [byte[]]$Raw,
        [bool]$Compress
    )

    $payload = if ($Compress) { Compress-Zlib -Bytes $Raw } else { $Raw }
    $stream = [IO.MemoryStream]::new()
    try {
        $writer = [IO.BinaryWriter]::new($stream)
        try {
            $writer.Write($ascii.GetBytes('CatScene'))
            $writer.Write([uint32]$(if ($Compress) { $payload.Length } else { 0 }))
            $writer.Write([uint32]$Raw.Length)
            $writer.Write($payload)
            $writer.Flush()
            $result = $stream.ToArray()
        }
        finally { $writer.Dispose() }
    }
    finally { $stream.Dispose() }
    return ,$result
}

function Test-AudioName {
    param(
        [string]$Name,
        [Collections.Generic.HashSet[string]]$AudioNames
    )
    $AudioNames.Contains($Name) -or
        $AudioNames.Contains("$Name.ogg") -or
        $AudioNames.Contains("$Name.wav")
}

function Update-Cst {
    param(
        [byte[]]$Data,
        [Collections.Generic.HashSet[string]]$AudioNames,
        [bool]$Apply
    )

    $cst = Read-Cst -Data $Data
    $raw = $cst.Raw
    if ($raw.Length -lt 16) { throw 'CSTのスクリプトヘッダーが壊れています。' }

    $scriptLength = Get-UInt32 -Bytes $raw -Offset 0
    $offsetTable = Get-UInt32 -Bytes $raw -Offset 8
    $stringTable = Get-UInt32 -Bytes $raw -Offset 12
    if ((16L + $scriptLength) -ne $raw.Length -or
        $stringTable -lt $offsetTable -or
        (($stringTable - $offsetTable) % 4) -ne 0) {
        throw 'CSTのスクリプト構造が想定と異なります。'
    }

    $missingActive = 0
    $missingDisabled = 0
    $validActive = 0
    $changed = $false
    $count = ($stringTable - $offsetTable) / 4
    for ($index = 0; $index -lt $count; $index++) {
        $relative = Get-UInt32 -Bytes $raw -Offset (16 + $offsetTable + ($index * 4))
        $position = 16L + $stringTable + $relative
        if (($position + 2) -gt $raw.Length) { throw 'CST内の文字列位置が不正です。' }

        $kind = Get-UInt16 -Bytes $raw -Offset ([int]$position)
        if ($kind -ne 0x3001 -and $kind -ne 0xF001) { continue }

        $end = [int]$position + 2
        while ($end -lt $raw.Length -and $raw[$end] -ne 0) { $end++ }
        if ($end -eq $raw.Length) { throw 'CST内に終端のない文字列があります。' }
        $content = $scriptEncoding.GetString($raw, [int]$position + 2, $end - ([int]$position + 2))
        if (-not $content.StartsWith('pcm ', [StringComparison]::OrdinalIgnoreCase)) { continue }

        $parts = $content -split '\s+'
        if ($parts.Count -lt 2) { continue }
        $exists = Test-AudioName -Name $parts[1] -AudioNames $AudioNames

        if ($kind -eq 0x3001) {
            if ($exists) {
                $validActive++
            }
            else {
                $missingActive++
                if ($Apply) {
                    # 0xF001 is debug metadata ignored by the CatSystem2 scene dispatcher.
                    $raw[[int]$position + 1] = 0xF0
                    $changed = $true
                }
            }
        }
        elseif (-not $exists) {
            $missingDisabled++
        }
    }

    $updated = if ($changed) { New-Cst -Raw $raw -Compress $cst.WasCompressed } else { $Data }
    [pscustomobject]@{
        Data = $updated
        MissingActive = $missingActive
        MissingDisabled = $missingDisabled
        ValidActive = $validActive
        Changed = $changed
    }
}

function Get-SceneResult {
    param(
        [string]$Path,
        [Collections.Generic.HashSet[string]]$AudioNames,
        [bool]$Apply,
        [Collections.Generic.HashSet[string]]$SkippedScenes
    )

    $entries = @(Read-KifEntries -Path $Path)
    $missingActive = 0
    $missingDisabled = 0
    $validActive = 0
    $affectedScenes = 0

    foreach ($entry in $entries) {
        if (-not $entry.Name.EndsWith('.cst', [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($null -ne $SkippedScenes -and $SkippedScenes.Contains($entry.Name)) { continue }
        $result = Update-Cst -Data $entry.Data -AudioNames $AudioNames -Apply $Apply
        $entry.Data = $result.Data
        $missingActive += $result.MissingActive
        $missingDisabled += $result.MissingDisabled
        $validActive += $result.ValidActive
        if ($result.Changed) { $affectedScenes++ }
    }

    [pscustomobject]@{
        Entries = $entries
        MissingActive = $missingActive
        MissingDisabled = $missingDisabled
        ValidActive = $validActive
        AffectedScenes = $affectedScenes
    }
}

function Write-KifEntries {
    param(
        [string]$Path,
        [object[]]$Entries
    )

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $writer = [IO.BinaryWriter]::new($stream)
        try {
            $writer.Write($ascii.GetBytes("KIF`0"))
            $writer.Write([uint32]$Entries.Count)
            [uint64]$offset = 8 + ($Entries.Count * 72)
            foreach ($entry in $Entries) {
                $nameBytes = $scriptEncoding.GetBytes($entry.Name)
                if ($nameBytes.Length -ge 64) { throw "KIF内のファイル名が長すぎます: $($entry.Name)" }
                $field = [byte[]]::new(64)
                [Array]::Copy($nameBytes, $field, $nameBytes.Length)
                $writer.Write($field)
                $writer.Write([uint32]$offset)
                $writer.Write([uint32]$entry.Data.Length)
                $offset += $entry.Data.Length
            }
            foreach ($entry in $Entries) { $writer.Write([byte[]]$entry.Data) }
            $writer.Flush()
        }
        finally { $writer.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Get-PatchState {
    param(
        [object]$SceneResult,
        [object]$UpdateResult,
        [string]$SceneHash,
        [string]$UpdateHash
    )

    if ($SceneHash -eq $expectedSceneSha256 -and
        $UpdateHash -eq $expectedUpdateSha256 -and
        $SceneResult.MissingActive -eq $expectedSceneMissingCommandCount -and
        $SceneResult.MissingDisabled -eq 0 -and
        $SceneResult.ValidActive -eq $expectedSceneValidCommandCount -and
        $UpdateResult.MissingActive -eq $expectedUpdateMissingCommandCount -and
        $UpdateResult.MissingDisabled -eq 0 -and
        $UpdateResult.ValidActive -eq $expectedUpdateValidCommandCount) {
        return '未適用'
    }
    if ($SceneResult.MissingActive -eq 0 -and
        $SceneResult.MissingDisabled -eq $expectedSceneMissingCommandCount -and
        $SceneResult.ValidActive -eq $expectedSceneValidCommandCount -and
        $UpdateResult.MissingActive -eq 0 -and
        $UpdateResult.MissingDisabled -eq $expectedUpdateMissingCommandCount -and
        $UpdateResult.ValidActive -eq $expectedUpdateValidCommandCount) {
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
$scenePath = Join-Path $gameDirectoryFull 'scene.int'
$updatePath = Join-Path $gameDirectoryFull 'UPDATE00.INT'
$sceneBackupPath = "$scenePath.before-voice-keep-patch.bak"
$updateBackupPath = "$updatePath.before-voice-keep-patch.bak"
$legacySceneBackupPath = "$scenePath.before-voicecut-patch.bak"
$legacyUpdateBackupPath = "$updatePath.before-voicecut-patch.bak"
if (-not (Test-Path -LiteralPath $sceneBackupPath -PathType Leaf) -and
    (Test-Path -LiteralPath $legacySceneBackupPath -PathType Leaf)) {
    $sceneBackupPath = $legacySceneBackupPath
}
if (-not (Test-Path -LiteralPath $updateBackupPath -PathType Leaf) -and
    (Test-Path -LiteralPath $legacyUpdateBackupPath -PathType Leaf)) {
    $updateBackupPath = $legacyUpdateBackupPath
}
$sceneTemporaryPath = "$scenePath.voice-keep-patch.tmp"
$updateTemporaryPath = "$updatePath.voice-keep-patch.tmp"

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
        if ($_.Exception.Message -eq 'ゲームが実行中です。ゲームを終了してからもう一度実行してください。') { throw }
        Write-Warning '実行中プロセスを確認できませんでした。ゲームが終了していることを確認してください。'
    }
}

if ($Mode -eq 'Restore') {
    foreach ($backupPath in @($sceneBackupPath, $updateBackupPath)) {
        if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            throw "バックアップが見つかりません: $backupPath"
        }
    }
    $sceneBackupHash = (Get-FileHash -LiteralPath $sceneBackupPath -Algorithm SHA256).Hash
    $updateBackupHash = (Get-FileHash -LiteralPath $updateBackupPath -Algorithm SHA256).Hash
    if ($sceneBackupHash -ne $expectedSceneSha256 -or $updateBackupHash -ne $expectedUpdateSha256) {
        throw 'バックアップが対応する元ファイルと一致しないため、復元しませんでした。'
    }
    [IO.File]::Copy($sceneBackupPath, $scenePath, $true)
    [IO.File]::Copy($updateBackupPath, $updatePath, $true)
    Write-Output 'scene.intとUPDATE00.INTを元の状態へ復元しました。'
    exit 0
}

foreach ($targetPath in @($scenePath, $updatePath)) {
    if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        throw "対象ファイルが見つかりません: $targetPath"
    }
}

$updateEntries = @(Read-KifEntries -Path $updatePath)
$voiceArchives = @(Get-ChildItem -LiteralPath $gameDirectoryFull -Filter 'pcm_*.int' -File)
if ($voiceArchives.Count -ne $expectedVoiceArchiveCount) {
    throw "音声アーカイブの数が対応版と異なります: $($voiceArchives.Count)"
}
$audioNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($archive in $voiceArchives) { Add-KifNames -Path $archive.FullName -Names $audioNames }
foreach ($entry in $updateEntries) {
    if ($entry.Name.EndsWith('.ogg', [StringComparison]::OrdinalIgnoreCase) -or
        $entry.Name.EndsWith('.wav', [StringComparison]::OrdinalIgnoreCase)) {
        [void]$audioNames.Add($entry.Name)
    }
}
if ($audioNames.Count -ne $expectedAudioNameCount) {
    throw "音声ファイルの一覧が対応版と異なります: $($audioNames.Count)"
}

$overriddenScenes = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $updateEntries) {
    if ($entry.Name.EndsWith('.cst', [StringComparison]::OrdinalIgnoreCase)) {
        [void]$overriddenScenes.Add($entry.Name)
    }
}

$sceneHashBefore = (Get-FileHash -LiteralPath $scenePath -Algorithm SHA256).Hash
$updateHashBefore = (Get-FileHash -LiteralPath $updatePath -Algorithm SHA256).Hash
$sceneScan = Get-SceneResult -Path $scenePath -AudioNames $audioNames -Apply $false -SkippedScenes $overriddenScenes
$updateScan = Get-SceneResult -Path $updatePath -AudioNames $audioNames -Apply $false
$state = Get-PatchState -SceneResult $sceneScan -UpdateResult $updateScan -SceneHash $sceneHashBefore -UpdateHash $updateHashBefore

if ($Mode -eq 'Check') {
    [pscustomobject]@{
        状態 = $state
        対象ファイル = 'scene.int, UPDATE00.INT'
        無効化前の欠落参照 = $sceneScan.MissingActive + $updateScan.MissingActive
        無効化済みの欠落参照 = $sceneScan.MissingDisabled + $updateScan.MissingDisabled
        正常な音声参照 = $sceneScan.ValidActive + $updateScan.ValidActive
        バックアップ = ((Test-Path -LiteralPath $sceneBackupPath -PathType Leaf) -and
            (Test-Path -LiteralPath $updateBackupPath -PathType Leaf))
    }
    exit 0
}

if ($state -eq '適用済み') {
    Write-Output 'ボイスキープ用パッチはすでに適用されています。変更は行いませんでした。'
    exit 0
}
if ($state -ne '未適用' -or
    (Get-Item -LiteralPath $scenePath).Length -ne $expectedSceneSize -or
    (Get-Item -LiteralPath $updatePath).Length -ne $expectedUpdateSize) {
    throw '未対応または変更済みのscene.intまたはUPDATE00.INTです。変更は行いませんでした。'
}

$backupDefinitions = @(
    [pscustomobject]@{ Source = $scenePath; Backup = $sceneBackupPath; Hash = $expectedSceneSha256 },
    [pscustomobject]@{ Source = $updatePath; Backup = $updateBackupPath; Hash = $expectedUpdateSha256 }
)
foreach ($definition in $backupDefinitions) {
    if (Test-Path -LiteralPath $definition.Backup -PathType Leaf) {
        $existingBackupHash = (Get-FileHash -LiteralPath $definition.Backup -Algorithm SHA256).Hash
        if ($existingBackupHash -ne $definition.Hash) {
            throw "既存のバックアップが対応する元ファイルと一致しないため、上書きしません: $($definition.Backup)"
        }
    }
    else {
        [IO.File]::Copy($definition.Source, $definition.Backup, $false)
    }
}

try {
    $patchedScene = Get-SceneResult -Path $scenePath -AudioNames $audioNames -Apply $true -SkippedScenes $overriddenScenes
    $patchedUpdate = Get-SceneResult -Path $updatePath -AudioNames $audioNames -Apply $true
    if ($patchedScene.MissingActive -ne $expectedSceneMissingCommandCount -or
        $patchedScene.MissingDisabled -ne 0 -or
        $patchedScene.ValidActive -ne $expectedSceneValidCommandCount -or
        $patchedScene.AffectedScenes -ne $expectedSceneAffectedCount -or
        $patchedUpdate.MissingActive -ne $expectedUpdateMissingCommandCount -or
        $patchedUpdate.MissingDisabled -ne 0 -or
        $patchedUpdate.ValidActive -ne $expectedUpdateValidCommandCount -or
        $patchedUpdate.AffectedScenes -ne $expectedUpdateAffectedCount) {
        throw '変更対象の確認に失敗しました。'
    }

    Write-KifEntries -Path $sceneTemporaryPath -Entries $patchedScene.Entries
    Write-KifEntries -Path $updateTemporaryPath -Entries $patchedUpdate.Entries
    $verifyScene = Get-SceneResult -Path $sceneTemporaryPath -AudioNames $audioNames -Apply $false -SkippedScenes $overriddenScenes
    $verifyUpdate = Get-SceneResult -Path $updateTemporaryPath -AudioNames $audioNames -Apply $false
    if ($verifyScene.MissingActive -ne 0 -or
        $verifyScene.MissingDisabled -ne $expectedSceneMissingCommandCount -or
        $verifyScene.ValidActive -ne $expectedSceneValidCommandCount -or
        $verifyUpdate.MissingActive -ne 0 -or
        $verifyUpdate.MissingDisabled -ne $expectedUpdateMissingCommandCount -or
        $verifyUpdate.ValidActive -ne $expectedUpdateValidCommandCount) {
        throw '適用後の検証に失敗しました。元のファイルは変更していません。'
    }

    try {
        [IO.File]::Copy($sceneTemporaryPath, $scenePath, $true)
        [IO.File]::Copy($updateTemporaryPath, $updatePath, $true)
    }
    catch {
        [IO.File]::Copy($sceneBackupPath, $scenePath, $true)
        [IO.File]::Copy($updateBackupPath, $updatePath, $true)
        throw
    }
}
finally {
    foreach ($temporaryPath in @($sceneTemporaryPath, $updateTemporaryPath)) {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            [IO.File]::Delete($temporaryPath)
        }
    }
}

[pscustomobject]@{
    結果 = 'ボイスキープ用パッチを適用しました'
    無効化した命令 = $expectedMissingCommandCount
    対象シーン = $expectedAffectedSceneCount
    バックアップ = "$sceneBackupPath, $updateBackupPath"
}
