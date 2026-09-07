param(
    [ValidateSet('Launch', 'Attach', 'Check')]
    [string]$Mode = 'Launch',
    [string]$GameDirectory
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($GameDirectory)) {
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'musume.exe') -PathType Leaf) {
        $GameDirectory = $PSScriptRoot
    } else {
        $GameDirectory = Read-Host 'ゲームフォルダーを入力してください'
    }
}

$GameDirectory = [System.IO.Path]::GetFullPath($GameDirectory.Trim('"')).TrimEnd('\')
$targetPath = Join-Path $GameDirectory 'musume.exe'
$expectedSize = 795648
$expectedHash = '637B80D078C338A01A7260C664E082AF773DBC8E5F453623A6B44B32BD739A6D'
$patchRva = 0x15E0B7
$originalBytes = [byte[]](0xE8, 0xE4, 0x13, 0xFF, 0xFF)
$patchedBytes = [byte[]](0x83, 0xC4, 0x04, 0x90, 0x90)

if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
    throw "musume.exe が見つかりません: $targetPath"
}
$target = Get-Item -LiteralPath $targetPath
if ($target.Length -ne $expectedSize -or
    (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'musume.exe は未対応版または変更済みです。処理は行いませんでした。'
}

if (-not ('VoiceKeepNativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class VoiceKeepNativeMethods
{
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(uint access, bool inheritHandle, uint processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ReadProcessMemory(
        IntPtr process, IntPtr address, byte[] buffer, UIntPtr size, out UIntPtr read);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool WriteProcessMemory(
        IntPtr process, IntPtr address, byte[] buffer, UIntPtr size, out UIntPtr written);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool VirtualProtectEx(
        IntPtr process, IntPtr address, UIntPtr size, uint newProtect, out uint oldProtect);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool FlushInstructionCache(IntPtr process, IntPtr address, UIntPtr size);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CloseHandle(IntPtr handle);
}
'@
}

function Test-Bytes([byte[]]$Actual, [byte[]]$Expected) {
    if ($Actual.Length -ne $Expected.Length) {
        return $false
    }
    for ($i = 0; $i -lt $Actual.Length; $i++) {
        if ($Actual[$i] -ne $Expected[$i]) {
            return $false
        }
    }
    return $true
}

function Get-GameProcesses {
    return @(
        Get-Process -Name 'musume' -ErrorAction SilentlyContinue | Where-Object {
            try {
                [System.IO.Path]::GetFullPath($_.Path).Equals(
                    $targetPath,
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            } catch {
                $false
            }
        }
    )
}

function Open-GameProcess([System.Diagnostics.Process]$Process) {
    $processAccess = 0x0400 -bor 0x0008 -bor 0x0010 -bor 0x0020
    $handle = [VoiceKeepNativeMethods]::OpenProcess($processAccess, $false, [uint32]$Process.Id)
    if ($handle -eq [IntPtr]::Zero) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "ゲームプロセスを開けませんでした。Win32 error: $errorCode"
    }
    return $handle
}

function Read-Bytes([IntPtr]$Handle, [IntPtr]$Address, [int]$Length) {
    $buffer = New-Object byte[] $Length
    [UIntPtr]$read = [UIntPtr]::Zero
    $ok = [VoiceKeepNativeMethods]::ReadProcessMemory(
        $Handle,
        $Address,
        $buffer,
        [UIntPtr]::new([uint64]$Length),
        [ref]$read
    )
    if (-not $ok -or $read.ToUInt64() -ne [uint64]$Length) {
        return $null
    }
    return $buffer
}

function Get-PatchAddress([System.Diagnostics.Process]$Process) {
    $Process.Refresh()
    $baseAddress = $Process.MainModule.BaseAddress.ToInt64()
    return [IntPtr]($baseAddress + $patchRva)
}

function Set-RuntimePatch([System.Diagnostics.Process]$Process) {
    $handle = Open-GameProcess $Process
    try {
        $deadline = [DateTime]::UtcNow.AddSeconds(20)
        $address = [IntPtr]::Zero
        $currentBytes = $null
        while ([DateTime]::UtcNow -lt $deadline) {
            if ($Process.HasExited) {
                throw 'パッチ適用前にゲームが終了しました。'
            }
            try {
                $address = Get-PatchAddress $Process
                $currentBytes = Read-Bytes $handle $address $originalBytes.Length
                if ((Test-Bytes $currentBytes $originalBytes) -or
                    (Test-Bytes $currentBytes $patchedBytes)) {
                    break
                }
            } catch {
                $currentBytes = $null
            }
            Start-Sleep -Milliseconds 20
        }

        if (Test-Bytes $currentBytes $patchedBytes) {
            return [pscustomobject]@{
                結果 = 'ボイスキープ用パッチは適用済みです'
                プロセスID = $Process.Id
            }
        }
        if (-not (Test-Bytes $currentBytes $originalBytes)) {
            throw '確認済みの実行時コードを検出できませんでした。処理は行いませんでした。'
        }

        [uint32]$oldProtect = 0
        $size = [UIntPtr]::new([uint64]$patchedBytes.Length)
        if (-not [VoiceKeepNativeMethods]::VirtualProtectEx(
            $handle, $address, $size, 0x40, [ref]$oldProtect
        )) {
            $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "メモリ保護を変更できませんでした。Win32 error: $errorCode"
        }
        try {
            [UIntPtr]$written = [UIntPtr]::Zero
            if (-not [VoiceKeepNativeMethods]::WriteProcessMemory(
                $handle, $address, $patchedBytes, $size, [ref]$written
            ) -or $written.ToUInt64() -ne [uint64]$patchedBytes.Length) {
                $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                throw "実行時パッチを書き込めませんでした。Win32 error: $errorCode"
            }
        } finally {
            [uint32]$ignoredProtect = 0
            [void][VoiceKeepNativeMethods]::VirtualProtectEx(
                $handle, $address, $size, $oldProtect, [ref]$ignoredProtect
            )
        }
        [void][VoiceKeepNativeMethods]::FlushInstructionCache($handle, $address, $size)

        $verifiedBytes = Read-Bytes $handle $address $patchedBytes.Length
        if (-not (Test-Bytes $verifiedBytes $patchedBytes)) {
            throw '適用後の確認に失敗しました。ゲームを終了してください。'
        }

        return [pscustomobject]@{
            結果 = 'ボイスキープ用パッチを実行中のゲームへ適用しました'
            プロセスID = $Process.Id
        }
    } finally {
        [void][VoiceKeepNativeMethods]::CloseHandle($handle)
    }
}

$processes = @(Get-GameProcesses)

if ($Mode -eq 'Check') {
    if ($processes.Count -eq 0) {
        [pscustomobject]@{
            状態 = '対応版・ゲーム停止中'
            対象 = $targetPath
        }
        return
    }
    if ($processes.Count -ne 1) {
        throw '対象のゲームプロセスが複数見つかりました。'
    }
    $process = $processes[0]
    $handle = Open-GameProcess $process
    try {
        $address = Get-PatchAddress $process
        $currentBytes = Read-Bytes $handle $address $originalBytes.Length
        $state = if (Test-Bytes $currentBytes $patchedBytes) {
            '実行時パッチ適用済み'
        } elseif (Test-Bytes $currentBytes $originalBytes) {
            'ゲーム実行中・未適用'
        } else {
            '起動処理中または未対応'
        }
        [pscustomobject]@{
            状態 = $state
            対象 = $targetPath
            プロセスID = $process.Id
        }
    } finally {
        [void][VoiceKeepNativeMethods]::CloseHandle($handle)
    }
    return
}

if ($Mode -eq 'Attach') {
    if ($processes.Count -eq 0) {
        throw '実行中の娘姉妹が見つかりません。'
    }
    if ($processes.Count -ne 1) {
        throw '対象のゲームプロセスが複数見つかりました。'
    }
    Set-RuntimePatch $processes[0]
    return
}

if ($processes.Count -ne 0) {
    throw '娘姉妹はすでに起動しています。終了してからLaunchモードを実行するか、Attachモードを使ってください。'
}

$process = Start-Process -FilePath $targetPath -WorkingDirectory $GameDirectory -PassThru
Set-RuntimePatch $process
