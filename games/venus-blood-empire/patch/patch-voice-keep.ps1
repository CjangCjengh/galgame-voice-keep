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
$targetPath = Join-Path $GameDirectory 'patch.xp3'
$backupPath = "$targetPath.before-voice-keep-patch.bak"
$originalSize = [int64]86549914
$patchedSize = [int64]86807487
$testedPatchedSize = [int64]86576421
$originalHash = 'DDB5D388C94906B848D77840E2206A007491457ADDE52D60D7D7E797AC82956E'
$patchedHash = 'BE96D3CA12E6E87DCE26E56561D3693E080899FC8086247CD618AC70E1CC6938'
$testedPatchedHash = '8121057470B4D64B3A187A1D7E5CBCF28C8697D6CAD9857DD72EB8777006E3C0'

if (-not ('VoiceKeepXp3Patch' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;

public static class VoiceKeepXp3Patch
{
    private const long OldIndexOffset = 86529772;
    private const int IndexPointerOffset = 32;
    private const int ExpectedIndexSize = 112130;
    private const int ExpectedMacroSize = 165586;
    private const string OriginalMacroHash = "7796ECC5646138C5AF7C4085A247CF9EFC621844F5E817332EB8592EB153D58E";
    private const string PatchedMacroHash = "50CFF7C68EACA03AE26F4417E002C3539F116FCBA120074C09835DDF608E6736";

    private sealed class EntryLocation
    {
        public int InfoOriginal;
        public int InfoStored;
        public int SegmentFlags;
        public int SegmentOffset;
        public int SegmentOriginal;
        public int SegmentStored;
        public int Adler32;
    }

    private static ushort ReadUInt16(byte[] data, int offset)
    {
        EnsureRange(data, offset, 2);
        return BitConverter.ToUInt16(data, offset);
    }

    private static uint ReadUInt32(byte[] data, int offset)
    {
        EnsureRange(data, offset, 4);
        return BitConverter.ToUInt32(data, offset);
    }

    private static ulong ReadUInt64(byte[] data, int offset)
    {
        EnsureRange(data, offset, 8);
        return BitConverter.ToUInt64(data, offset);
    }

    private static void WriteUInt32(byte[] data, int offset, uint value)
    {
        byte[] encoded = BitConverter.GetBytes(value);
        Buffer.BlockCopy(encoded, 0, data, offset, encoded.Length);
    }

    private static void WriteUInt64(byte[] data, int offset, ulong value)
    {
        byte[] encoded = BitConverter.GetBytes(value);
        Buffer.BlockCopy(encoded, 0, data, offset, encoded.Length);
    }

    private static void EnsureRange(byte[] data, int offset, int length)
    {
        if (offset < 0 || length < 0 || offset > data.Length - length)
            throw new InvalidDataException("XP3データの範囲が不正です。");
    }

    private static string ReadTag(byte[] data, int offset)
    {
        EnsureRange(data, offset, 4);
        return Encoding.ASCII.GetString(data, offset, 4);
    }

    private static byte[] Slice(byte[] data, int offset, int length)
    {
        EnsureRange(data, offset, length);
        byte[] result = new byte[length];
        Buffer.BlockCopy(data, offset, result, 0, length);
        return result;
    }

    private static uint Adler32(byte[] data)
    {
        const uint Mod = 65521;
        uint a = 1;
        uint b = 0;
        for (int offset = 0; offset < data.Length; )
        {
            int end = Math.Min(offset + 5552, data.Length);
            for (; offset < end; offset++)
            {
                a += data[offset];
                b += a;
            }
            a %= Mod;
            b %= Mod;
        }
        return (b << 16) | a;
    }

    private static byte[] ExpandZlib(byte[] zlib, int expectedLength)
    {
        if (zlib.Length < 6)
            throw new InvalidDataException("zlibデータが短すぎます。");
        int cmf = zlib[0];
        int flg = zlib[1];
        if ((cmf & 15) != 8 || (((cmf << 8) + flg) % 31) != 0 || (flg & 32) != 0)
            throw new InvalidDataException("未対応のzlibヘッダーです。");

        byte[] result;
        using (MemoryStream input = new MemoryStream(zlib, 2, zlib.Length - 6, false))
        using (DeflateStream deflate = new DeflateStream(input, CompressionMode.Decompress))
        using (MemoryStream output = new MemoryStream())
        {
            deflate.CopyTo(output);
            result = output.ToArray();
        }
        if (result.Length != expectedLength)
            throw new InvalidDataException("zlib展開後のサイズが一致しません。");

        int end = zlib.Length;
        uint expectedAdler = ((uint)zlib[end - 4] << 24)
            | ((uint)zlib[end - 3] << 16)
            | ((uint)zlib[end - 2] << 8)
            | zlib[end - 1];
        if (Adler32(result) != expectedAdler)
            throw new InvalidDataException("zlibデータのチェックサムが一致しません。");
        return result;
    }

    private static string Sha256(byte[] data)
    {
        using (SHA256 sha = SHA256.Create())
            return BitConverter.ToString(sha.ComputeHash(data)).Replace("-", "");
    }

    private static int CheckedInt(ulong value, string label)
    {
        if (value > Int32.MaxValue)
            throw new InvalidDataException(label + "が大きすぎます。");
        return (int)value;
    }

    private static EntryLocation LocateEntry(byte[] index, string wantedName)
    {
        EntryLocation found = null;
        int offset = 0;
        while (offset < index.Length)
        {
            string tag = ReadTag(index, offset);
            int size = CheckedInt(ReadUInt64(index, offset + 4), "XP3チャンク");
            int body = checked(offset + 12);
            int bodyEnd = checked(body + size);
            EnsureRange(index, body, size);

            if (tag == "File")
            {
                string name = null;
                EntryLocation candidate = new EntryLocation();
                int segmentCount = 0;
                int inner = body;
                while (inner < bodyEnd)
                {
                    string subtag = ReadTag(index, inner);
                    int subsize = CheckedInt(ReadUInt64(index, inner + 4), "XP3サブチャンク");
                    int subbody = checked(inner + 12);
                    int subend = checked(subbody + subsize);
                    if (subend > bodyEnd)
                        throw new InvalidDataException("XP3サブチャンクがFileチャンクを越えています。");

                    if (subtag == "info")
                    {
                        if (subsize < 22)
                            throw new InvalidDataException("XP3 infoチャンクが短すぎます。");
                        int nameLength = ReadUInt16(index, subbody + 20);
                        int nameBytes = checked(nameLength * 2);
                        EnsureRange(index, subbody + 22, nameBytes);
                        name = Encoding.Unicode.GetString(index, subbody + 22, nameBytes);
                        candidate.InfoOriginal = subbody + 4;
                        candidate.InfoStored = subbody + 12;
                    }
                    else if (subtag == "segm")
                    {
                        if (subsize == 0 || subsize % 28 != 0)
                            throw new InvalidDataException("XP3 segmチャンクのサイズが不正です。");
                        for (int segment = subbody; segment < subend; segment += 28)
                        {
                            segmentCount++;
                            candidate.SegmentFlags = segment;
                            candidate.SegmentOffset = segment + 4;
                            candidate.SegmentOriginal = segment + 12;
                            candidate.SegmentStored = segment + 20;
                        }
                    }
                    else if (subtag == "adlr")
                    {
                        if (subsize < 4)
                            throw new InvalidDataException("XP3 adlrチャンクが短すぎます。");
                        candidate.Adler32 = subbody;
                    }
                    inner = subend;
                }
                if (inner != bodyEnd)
                    throw new InvalidDataException("XP3 Fileチャンクの終端が一致しません。");

                if (name == wantedName)
                {
                    if (found != null)
                        throw new InvalidDataException("対象ファイルがXP3内に複数あります。");
                    if (segmentCount != 1 || candidate.Adler32 == 0)
                        throw new InvalidDataException("対象ファイルのXP3構造に対応していません。");
                    found = candidate;
                }
            }
            offset = bodyEnd;
        }
        if (offset != index.Length || found == null)
            throw new InvalidDataException("macro.ksのXP3エントリーが見つかりません。");
        return found;
    }

    private static int FindUnique(byte[] data, byte[] pattern)
    {
        int found = -1;
        for (int offset = 0; offset <= data.Length - pattern.Length; offset++)
        {
            bool matches = true;
            for (int index = 0; index < pattern.Length; index++)
            {
                if (data[offset + index] != pattern[index])
                {
                    matches = false;
                    break;
                }
            }
            if (matches)
            {
                if (found >= 0)
                    throw new InvalidDataException("対象の停止命令が複数見つかりました。");
                found = offset;
            }
        }
        if (found < 0)
            throw new InvalidDataException("対象の停止命令が見つかりません。");
        return found;
    }

    public static string Build(string sourcePath, string outputPath)
    {
        byte[] archive = File.ReadAllBytes(sourcePath);
        if (ReadUInt64(archive, IndexPointerOffset) != (ulong)OldIndexOffset)
            throw new InvalidDataException("XP3インデックス位置が想定と一致しません。");
        if (archive[OldIndexOffset] != 1)
            throw new InvalidDataException("XP3インデックスの圧縮形式が想定と一致しません。");

        int indexStored = CheckedInt(ReadUInt64(archive, (int)OldIndexOffset + 1), "XP3インデックス");
        int indexOriginal = CheckedInt(ReadUInt64(archive, (int)OldIndexOffset + 9), "XP3インデックス");
        byte[] indexZlib = Slice(archive, (int)OldIndexOffset + 17, indexStored);
        byte[] index = ExpandZlib(indexZlib, indexOriginal);
        if (index.Length != ExpectedIndexSize)
            throw new InvalidDataException("XP3インデックスのサイズが想定と一致しません。");

        EntryLocation location = LocateEntry(index, "macro.ks");
        uint segmentFlags = ReadUInt32(index, location.SegmentFlags);
        int segmentOffset = CheckedInt(ReadUInt64(index, location.SegmentOffset), "macro.ksの位置");
        int segmentOriginal = CheckedInt(ReadUInt64(index, location.SegmentOriginal), "macro.ks");
        int segmentStored = CheckedInt(ReadUInt64(index, location.SegmentStored), "macro.ks");
        if (segmentOriginal != ExpectedMacroSize)
            throw new InvalidDataException("macro.ksのサイズが想定と一致しません。");

        byte[] storedMacro = Slice(archive, segmentOffset, segmentStored);
        byte[] macro = (segmentFlags & 1) != 0
            ? ExpandZlib(storedMacro, segmentOriginal)
            : storedMacro;
        if (Sha256(macro) != OriginalMacroHash)
            throw new InvalidDataException("macro.ksの内容が対応版と一致しません。");

        byte[] context = Encoding.ASCII.GetBytes(
            "[ws canskip=true cond=\"kag.autoMode\"]\r\n[p]\r\n[stopse]\r\n[hr]\r\n");
        byte[] beforeStop = Encoding.ASCII.GetBytes(
            "[ws canskip=true cond=\"kag.autoMode\"]\r\n[p]\r\n");
        byte[] stopLine = Encoding.ASCII.GetBytes("[stopse]\r\n");
        int contextOffset = FindUnique(macro, context);
        int removeOffset = checked(contextOffset + beforeStop.Length);
        byte[] patchedMacro = new byte[macro.Length - stopLine.Length];
        Buffer.BlockCopy(macro, 0, patchedMacro, 0, removeOffset);
        Buffer.BlockCopy(
            macro,
            removeOffset + stopLine.Length,
            patchedMacro,
            removeOffset,
            macro.Length - removeOffset - stopLine.Length);
        if (Sha256(patchedMacro) != PatchedMacroHash)
            throw new InvalidDataException("変更後のmacro.ksが想定した内容と一致しません。");

        WriteUInt64(index, location.InfoOriginal, (ulong)patchedMacro.Length);
        WriteUInt64(index, location.InfoStored, (ulong)patchedMacro.Length);
        WriteUInt32(index, location.SegmentFlags, 0);
        WriteUInt64(index, location.SegmentOffset, (ulong)OldIndexOffset);
        WriteUInt64(index, location.SegmentOriginal, (ulong)patchedMacro.Length);
        WriteUInt64(index, location.SegmentStored, (ulong)patchedMacro.Length);
        WriteUInt32(index, location.Adler32, Adler32(patchedMacro));

        long newIndexOffset = checked(OldIndexOffset + patchedMacro.Length);
        int patchedLength = checked((int)(newIndexOffset + 9 + index.Length));
        byte[] patched = new byte[patchedLength];
        Buffer.BlockCopy(archive, 0, patched, 0, (int)OldIndexOffset);
        WriteUInt64(patched, IndexPointerOffset, (ulong)newIndexOffset);
        Buffer.BlockCopy(patchedMacro, 0, patched, (int)OldIndexOffset, patchedMacro.Length);
        patched[(int)newIndexOffset] = 0;
        WriteUInt64(patched, (int)newIndexOffset + 1, (ulong)index.Length);
        Buffer.BlockCopy(index, 0, patched, (int)newIndexOffset + 9, index.Length);
        File.WriteAllBytes(outputPath, patched);
        return Sha256(patched);
    }
}
'@
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-State([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return 'NotFound'
    }
    $file = Get-Item -LiteralPath $Path
    if ($file.Length -eq $originalSize -and (Get-Sha256 $Path) -eq $originalHash) {
        return 'Original'
    }
    if ($file.Length -eq $patchedSize -and (Get-Sha256 $Path) -eq $patchedHash) {
        return 'Patched'
    }
    if ($file.Length -eq $testedPatchedSize -and (Get-Sha256 $Path) -eq $testedPatchedHash) {
        return 'Patched'
    }
    return 'Unsupported'
}

$state = Get-State $targetPath

if ($Mode -eq 'Check') {
    $label = switch ($state) {
        'Original' { '未適用（対応版）' }
        'Patched' { '適用済み' }
        'NotFound' { 'patch.xp3 が見つかりません' }
        default { '未対応または変更済み' }
    }
    [pscustomobject]@{
        状態 = $label
        対象 = $targetPath
    }
    exit 0
}

if (Get-Process -Name 'EMPIRE' -ErrorAction SilentlyContinue) {
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
    throw "patch.xp3 が見つかりません: $targetPath"
}
if ($state -ne 'Original') {
    throw 'patch.xp3 は未対応版または変更済みです。変更は行いませんでした。'
}

if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
    if ((Get-State $backupPath) -ne 'Original') {
        throw '既存のバックアップが対応版のオリジナルと一致しません。'
    }
} else {
    Copy-Item -LiteralPath $targetPath -Destination $backupPath
}

$tempPath = Join-Path $GameDirectory ('.voice-keep-' + [guid]::NewGuid().ToString('N') + '.tmp')
try {
    $resultHash = [VoiceKeepXp3Patch]::Build($targetPath, $tempPath)
    if ($resultHash -ne $patchedHash) {
        throw '適用後の一時ファイルが想定した内容と一致しません。'
    }
    Copy-Item -LiteralPath $tempPath -Destination $targetPath -Force
    if ((Get-State $targetPath) -ne 'Patched') {
        Copy-Item -LiteralPath $backupPath -Destination $targetPath -Force
        throw '適用後の確認に失敗したため、オリジナルへ戻しました。'
    }
}
finally {
    if (Test-Path -LiteralPath $tempPath) {
        [System.IO.File]::Delete($tempPath)
    }
}

[pscustomobject]@{
    結果 = 'ボイスキープ用パッチを適用しました'
    対象 = $targetPath
    バックアップ = $backupPath
}
