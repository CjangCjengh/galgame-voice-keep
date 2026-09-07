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
$sourcePath = Join-Path $GameDirectory 'data.xp3'
$targetPath = Join-Path $GameDirectory 'patch.xp3'
$targetSize = [int64]138201
$targetHash = 'B62D5E8C39694DD00CEB0E0D4FF14E67A5BD4F7BF6C329A40D6E076BEB686EE1'

if (-not ('DesireVoiceKeepPatch' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;

public static class DesireVoiceKeepPatch
{
    private static readonly byte[] Xp3Signature = new byte[] {
        0x58, 0x50, 0x33, 0x0D, 0x0A, 0x20, 0x0A, 0x1A, 0x8B, 0x67, 0x01
    };
    private const int ExpectedIndexSize = 1114638;
    private const int ExpectedMacroSize = 138065;
    private const string OriginalMacroHash = "FE8237284C4648153DF348E5149356606CFF4BC455398EB369DB06909D24F40E";
    private const string PatchedMacroHash = "0F76C8FC5638341A24FA34C9D33E2441FC38362D623A2D550B57793896E37160";

    private sealed class EntryLocation
    {
        public int SegmentFlags;
        public int SegmentOffset;
        public int SegmentOriginal;
        public int SegmentStored;
    }

    private static void EnsureRange(byte[] data, int offset, int length)
    {
        if (offset < 0 || length < 0 || offset > data.Length - length)
            throw new InvalidDataException("XP3データの範囲が不正です。");
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

    private static string ReadTag(byte[] data, int offset)
    {
        EnsureRange(data, offset, 4);
        return Encoding.ASCII.GetString(data, offset, 4);
    }

    private static int CheckedInt(ulong value, string label)
    {
        if (value > Int32.MaxValue)
            throw new InvalidDataException(label + "が大きすぎます。");
        return (int)value;
    }

    private static long CheckedLong(ulong value, string label)
    {
        if (value > Int64.MaxValue)
            throw new InvalidDataException(label + "が大きすぎます。");
        return (long)value;
    }

    private static byte[] ReadAt(FileStream stream, long offset, int length)
    {
        if (offset < 0 || length < 0 || offset > stream.Length - length)
            throw new InvalidDataException("XP3ファイルの範囲が不正です。");
        byte[] result = new byte[length];
        stream.Position = offset;
        int read = 0;
        while (read < result.Length)
        {
            int count = stream.Read(result, read, result.Length - read);
            if (count == 0)
                throw new EndOfStreamException("XP3ファイルを最後まで読み取れませんでした。");
            read += count;
        }
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

    private static byte[] ReadIndex(FileStream archive)
    {
        byte[] header = ReadAt(archive, 0, Xp3Signature.Length + 8);
        for (int signatureIndex = 0; signatureIndex < Xp3Signature.Length; signatureIndex++)
        {
            if (header[signatureIndex] != Xp3Signature[signatureIndex])
                throw new InvalidDataException("data.xp3のヘッダーが一致しません。");
        }

        long indexOffset = CheckedLong(ReadUInt64(header, Xp3Signature.Length), "XP3インデックス位置");
        using (MemoryStream combined = new MemoryStream())
        {
            for (int partCount = 0; partCount < 16; partCount++)
            {
                byte flags = ReadAt(archive, indexOffset, 1)[0];
                int encoding = flags & 7;
                long nextPointerOffset;
                byte[] part;
                if (encoding == 0)
                {
                    byte[] sizeData = ReadAt(archive, indexOffset + 1, 8);
                    int storedSize = CheckedInt(ReadUInt64(sizeData, 0), "XP3インデックス");
                    part = ReadAt(archive, indexOffset + 9, storedSize);
                    nextPointerOffset = checked(indexOffset + 9 + storedSize);
                }
                else if (encoding == 1)
                {
                    byte[] sizeData = ReadAt(archive, indexOffset + 1, 16);
                    int storedSize = CheckedInt(ReadUInt64(sizeData, 0), "XP3インデックス");
                    int originalSize = CheckedInt(ReadUInt64(sizeData, 8), "XP3インデックス");
                    part = ExpandZlib(ReadAt(archive, indexOffset + 17, storedSize), originalSize);
                    nextPointerOffset = checked(indexOffset + 17 + storedSize);
                }
                else
                {
                    throw new InvalidDataException("未対応のXP3インデックス形式です。");
                }

                combined.Write(part, 0, part.Length);
                if ((flags & 0x80) == 0)
                    return combined.ToArray();

                byte[] nextData = ReadAt(archive, nextPointerOffset, 8);
                indexOffset = CheckedLong(ReadUInt64(nextData, 0), "次のXP3インデックス位置");
            }
        }
        throw new InvalidDataException("XP3インデックスの分割数が多すぎます。");
    }

    private static EntryLocation LocateEntry(byte[] indexData, string wantedName)
    {
        EntryLocation found = null;
        int offset = 0;
        while (offset < indexData.Length)
        {
            string tag = ReadTag(indexData, offset);
            int size = CheckedInt(ReadUInt64(indexData, offset + 4), "XP3チャンク");
            int body = checked(offset + 12);
            int bodyEnd = checked(body + size);
            EnsureRange(indexData, body, size);

            if (tag == "File")
            {
                string name = null;
                EntryLocation candidate = new EntryLocation();
                int segmentCount = 0;
                int inner = body;
                while (inner < bodyEnd)
                {
                    string subtag = ReadTag(indexData, inner);
                    int subsize = CheckedInt(ReadUInt64(indexData, inner + 4), "XP3サブチャンク");
                    int subbody = checked(inner + 12);
                    int subend = checked(subbody + subsize);
                    if (subend > bodyEnd)
                        throw new InvalidDataException("XP3サブチャンクがFileチャンクを越えています。");

                    if (subtag == "info")
                    {
                        if (subsize < 22)
                            throw new InvalidDataException("XP3 infoチャンクが短すぎます。");
                        int nameLength = ReadUInt16(indexData, subbody + 20);
                        int nameBytes = checked(nameLength * 2);
                        EnsureRange(indexData, subbody + 22, nameBytes);
                        name = Encoding.Unicode.GetString(indexData, subbody + 22, nameBytes);
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
                    inner = subend;
                }
                if (inner != bodyEnd)
                    throw new InvalidDataException("XP3 Fileチャンクの終端が一致しません。");

                if (name == wantedName)
                {
                    if (found != null)
                        throw new InvalidDataException("対象ファイルがXP3内に複数あります。");
                    if (segmentCount != 1)
                        throw new InvalidDataException("対象ファイルのXP3構造に対応していません。");
                    found = candidate;
                }
            }
            offset = bodyEnd;
        }
        if (offset != indexData.Length || found == null)
            throw new InvalidDataException("macro.ksのXP3エントリーが見つかりません。");
        return found;
    }

    private static int FindUnique(byte[] data, byte[] pattern)
    {
        int found = -1;
        for (int offset = 0; offset <= data.Length - pattern.Length; offset++)
        {
            bool matches = true;
            for (int patternIndex = 0; patternIndex < pattern.Length; patternIndex++)
            {
                if (data[offset + patternIndex] != pattern[patternIndex])
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

    private static byte[] LoadMacro(string sourcePath)
    {
        byte[] macro;
        using (FileStream archive = new FileStream(sourcePath, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            byte[] indexData = ReadIndex(archive);
            if (indexData.Length != ExpectedIndexSize)
                throw new InvalidDataException("XP3インデックスのサイズが想定と一致しません。");

            EntryLocation location = LocateEntry(indexData, "game_system/macro.ks");
            uint segmentFlags = ReadUInt32(indexData, location.SegmentFlags);
            long segmentOffset = CheckedLong(ReadUInt64(indexData, location.SegmentOffset), "macro.ksの位置");
            int segmentOriginal = CheckedInt(ReadUInt64(indexData, location.SegmentOriginal), "macro.ks");
            int segmentStored = CheckedInt(ReadUInt64(indexData, location.SegmentStored), "macro.ks");
            if (segmentOriginal != ExpectedMacroSize)
                throw new InvalidDataException("macro.ksのサイズが想定と一致しません。");

            byte[] storedMacro = ReadAt(archive, segmentOffset, segmentStored);
            macro = (segmentFlags & 1) != 0
                ? ExpandZlib(storedMacro, segmentOriginal)
                : storedMacro;
        }

        if (Sha256(macro) != OriginalMacroHash)
            throw new InvalidDataException("macro.ksの内容が対応版と一致しません。");
        return macro;
    }

    private static byte[] PatchMacro(byte[] macro)
    {
        byte[] context = Encoding.ASCII.GetBytes(
            "[macro name=p2]\r\n" +
            "[endhact]\r\n" +
            "[ws canskip=true cond=\"kag.autoMode\"]\r\n" +
            "[p]\r\n" +
            "[stopse]\r\n" +
            "[hr]\r\n");
        byte[] beforeStop = Encoding.ASCII.GetBytes(
            "[macro name=p2]\r\n" +
            "[endhact]\r\n" +
            "[ws canskip=true cond=\"kag.autoMode\"]\r\n" +
            "[p]\r\n");
        byte[] stopLine = Encoding.ASCII.GetBytes("[stopse]\r\n");
        int contextOffset = FindUnique(macro, context);
        int removeOffset = checked(contextOffset + beforeStop.Length);
        byte[] patched = new byte[macro.Length - stopLine.Length];
        Buffer.BlockCopy(macro, 0, patched, 0, removeOffset);
        Buffer.BlockCopy(
            macro,
            removeOffset + stopLine.Length,
            patched,
            removeOffset,
            macro.Length - removeOffset - stopLine.Length);
        if (Sha256(patched) != PatchedMacroHash)
            throw new InvalidDataException("変更後のmacro.ksが想定した内容と一致しません。");
        return patched;
    }

    private static byte[] Chunk(string tag, byte[] body)
    {
        using (MemoryStream stream = new MemoryStream())
        using (BinaryWriter writer = new BinaryWriter(stream))
        {
            writer.Write(Encoding.ASCII.GetBytes(tag));
            writer.Write((ulong)body.Length);
            writer.Write(body);
            return stream.ToArray();
        }
    }

    private static byte[] Concat(params byte[][] parts)
    {
        int length = 0;
        foreach (byte[] part in parts)
            length = checked(length + part.Length);
        byte[] result = new byte[length];
        int offset = 0;
        foreach (byte[] part in parts)
        {
            Buffer.BlockCopy(part, 0, result, offset, part.Length);
            offset += part.Length;
        }
        return result;
    }

    private static byte[] BuildArchive(byte[] macro)
    {
        byte[] name = Encoding.Unicode.GetBytes("macro.ks");
        byte[] info;
        using (MemoryStream stream = new MemoryStream())
        using (BinaryWriter writer = new BinaryWriter(stream))
        {
            writer.Write((uint)0x80000000);
            writer.Write((ulong)macro.Length);
            writer.Write((ulong)macro.Length);
            writer.Write((ushort)(name.Length / 2));
            writer.Write(name);
            info = stream.ToArray();
        }

        byte[] segment;
        using (MemoryStream stream = new MemoryStream())
        using (BinaryWriter writer = new BinaryWriter(stream))
        {
            writer.Write((uint)0);
            writer.Write((ulong)(Xp3Signature.Length + 8));
            writer.Write((ulong)macro.Length);
            writer.Write((ulong)macro.Length);
            segment = stream.ToArray();
        }

        byte[] adler = BitConverter.GetBytes(Adler32(macro));
        byte[] fileEntry = Chunk(
            "File",
            Concat(Chunk("info", info), Chunk("segm", segment), Chunk("adlr", adler)));

        using (MemoryStream stream = new MemoryStream())
        using (BinaryWriter writer = new BinaryWriter(stream))
        {
            writer.Write(Xp3Signature);
            writer.Write((ulong)(Xp3Signature.Length + 8 + macro.Length));
            writer.Write(macro);
            writer.Write((byte)0);
            writer.Write((ulong)fileEntry.Length);
            writer.Write(fileEntry);
            return stream.ToArray();
        }
    }

    public static void Validate(string sourcePath)
    {
        PatchMacro(LoadMacro(sourcePath));
    }

    public static string Build(string sourcePath, string outputPath)
    {
        byte[] output = BuildArchive(PatchMacro(LoadMacro(sourcePath)));
        File.WriteAllBytes(outputPath, output);
        return Sha256(output);
    }
}
'@
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-SourceState {
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        return 'NotFound'
    }
    try {
        [DesireVoiceKeepPatch]::Validate($sourcePath)
        return 'Supported'
    }
    catch {
        return 'Unsupported'
    }
}

function Get-TargetState {
    if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        return 'NotFound'
    }
    $file = Get-Item -LiteralPath $targetPath
    if ($file.Length -eq $targetSize -and (Get-Sha256 $targetPath) -eq $targetHash) {
        return 'Patched'
    }
    return 'Unsupported'
}

$targetState = Get-TargetState

if ($Mode -eq 'Check') {
    $sourceState = Get-SourceState
    $label = if ($targetState -eq 'Patched') {
        '適用済み'
    } elseif ($targetState -eq 'Unsupported') {
        '別の patch.xp3 が存在します'
    } elseif ($sourceState -eq 'Supported') {
        '未適用（対応版）'
    } elseif ($sourceState -eq 'NotFound') {
        'data.xp3 が見つかりません'
    } else {
        '未対応または変更済み'
    }
    [pscustomobject]@{
        状態 = $label
        読み取り元 = $sourcePath
        作成先 = $targetPath
    }
    exit 0
}

if (Get-Process -Name 'DESIRE' -ErrorAction SilentlyContinue) {
    throw 'ゲームを終了してから実行してください。'
}

if ($Mode -eq 'Restore') {
    if ($targetState -eq 'NotFound') {
        Write-Output 'ボイスキープ用の patch.xp3 はありません。変更は行いませんでした。'
        exit 0
    }
    if ($targetState -ne 'Patched') {
        throw 'patch.xp3 はこのパッチが作成した内容と一致しないため、削除しませんでした。'
    }
    [System.IO.File]::Delete($targetPath)
    if ((Get-TargetState) -ne 'NotFound') {
        throw 'patch.xp3 の削除後の確認に失敗しました。'
    }
    [pscustomobject]@{
        結果 = 'ボイスキープ用パッチを削除しました'
        対象 = $targetPath
    }
    exit 0
}

if ($targetState -eq 'Patched') {
    Write-Output 'ボイスキープ用パッチはすでに適用されています。変更は行いませんでした。'
    exit 0
}
if ($targetState -eq 'Unsupported') {
    throw '別の patch.xp3 がすでに存在します。上書きは行いませんでした。'
}

$sourceState = Get-SourceState
if ($sourceState -eq 'NotFound') {
    throw "data.xp3 が見つかりません: $sourcePath"
}
if ($sourceState -ne 'Supported') {
    throw 'data.xp3 内の macro.ks は未対応版または変更済みです。変更は行いませんでした。'
}

$tempPath = Join-Path $GameDirectory ('.voice-keep-' + [guid]::NewGuid().ToString('N') + '.tmp')
try {
    $resultHash = [DesireVoiceKeepPatch]::Build($sourcePath, $tempPath)
    $tempFile = Get-Item -LiteralPath $tempPath
    if ($tempFile.Length -ne $targetSize -or $resultHash -ne $targetHash) {
        throw '作成した一時ファイルが想定した内容と一致しません。'
    }
    [System.IO.File]::Move($tempPath, $targetPath)
    if ((Get-TargetState) -ne 'Patched') {
        if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
            [System.IO.File]::Delete($targetPath)
        }
        throw '適用後の確認に失敗したため、作成したファイルを削除しました。'
    }
}
finally {
    if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
        [System.IO.File]::Delete($tempPath)
    }
}

[pscustomobject]@{
    結果 = 'ボイスキープ用パッチを適用しました'
    作成 = $targetPath
}
