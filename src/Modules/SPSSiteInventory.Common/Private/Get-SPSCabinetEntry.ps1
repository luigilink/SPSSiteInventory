function Get-SPSCabinetEntry {
    <#
        .SYNOPSIS
        Lists the files of a cabinet (CAB) archive, such as a WSP, without extracting anything.

        .DESCRIPTION
        A WSP is a cabinet. Get-SPSCabinetEntry reads the header and the table of files of the
        cabinet, and nothing else: no file is decompressed and nothing is written. It returns the
        name and the declared size of every file, and says whether the name can be extracted
        under a folder without risk. A name is not safe when it is empty, rooted, has a drive or
        a stream (a colon), goes up with '..', or has a character that a file name cannot hold.

        Expand-SPSSolutionPackage uses it to refuse a package, and to check its declared size,
        before it expands anything.

        It throws when the file is not a cabinet, is a part of a set of cabinets (a WSP is a
        single cabinet), or is cut short.

        Private because it is an implementation detail of Expand-SPSSolutionPackage.

        .PARAMETER Path
        The path of the cabinet file.

        .OUTPUTS
        One object per file with Name (as stored in the cabinet), Size (the declared size in
        bytes), Safe and Problem (why the name is not safe, empty when it is).

        .EXAMPLE
        Get-SPSCabinetEntry -Path .\Contoso.Intranet.wsp
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    $latin1 = [System.Text.Encoding]::GetEncoding(28591)
    $utf8 = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    $badCharacter = [System.Char[]]@('*', '?', '"', '<', '>', '|', ':')

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        $reader = New-Object -TypeName System.IO.BinaryReader -ArgumentList $stream
        try {
            if ($stream.Length -lt 36) {
                throw 'The file is too short to be a cabinet.'
            }
            $signature = $reader.ReadBytes(4)
            if ($signature[0] -ne 0x4D -or $signature[1] -ne 0x53 -or $signature[2] -ne 0x43 -or $signature[3] -ne 0x46) {
                throw 'The file is not a cabinet (CAB) archive.'
            }
            $null = $reader.ReadUInt32()
            $null = $reader.ReadUInt32()
            $null = $reader.ReadUInt32()
            $filesOffset = $reader.ReadUInt32()
            $null = $reader.ReadUInt32()
            $null = $reader.ReadByte()
            $majorVersion = $reader.ReadByte()
            $null = $reader.ReadUInt16()
            $fileCount = $reader.ReadUInt16()
            $flags = $reader.ReadUInt16()

            if ($majorVersion -ne 1) {
                throw 'The cabinet has a version that is not supported.'
            }
            if (($flags -band 0x3) -ne 0) {
                throw 'The cabinet is a part of a set of cabinets, which is not supported.'
            }
            if ($filesOffset -lt 36 -or $filesOffset -ge $stream.Length) {
                throw 'The table of files of the cabinet is outside of the file.'
            }

            $null = $stream.Seek([System.Int64]$filesOffset, [System.IO.SeekOrigin]::Begin)
            $entry = [System.Collections.Generic.List[object]]::new()
            for ($index = 0; $index -lt $fileCount; $index++) {
                $size = $reader.ReadUInt32()
                $null = $reader.ReadUInt32()
                $null = $reader.ReadUInt16()
                $null = $reader.ReadUInt16()
                $null = $reader.ReadUInt16()
                $attribute = $reader.ReadUInt16()

                $nameBytes = [System.Collections.Generic.List[byte]]::new()
                while ($true) {
                    $byte = $reader.ReadByte()
                    if ($byte -eq 0) {
                        break
                    }
                    if ($nameBytes.Count -ge 512) {
                        throw 'A file name of the cabinet is not terminated.'
                    }
                    $nameBytes.Add($byte)
                }
                $encoding = if (($attribute -band 0x80) -ne 0) { $utf8 } else { $latin1 }
                $name = $encoding.GetString($nameBytes.ToArray())

                $problem = ''
                if ($name.Length -eq 0) {
                    $problem = 'The name is empty.'
                }
                elseif ($name -match '[\x00-\x1F]') {
                    $problem = 'The name has a control character.'
                }
                elseif ($name -match '^[\\/]' -or $name -match '^[A-Za-z]:') {
                    $problem = 'The name is rooted.'
                }
                elseif ($name.IndexOfAny($badCharacter) -ge 0) {
                    $problem = 'The name has a character that a file name cannot have.'
                }
                elseif (@($name -split '[\\/]') -contains '..') {
                    $problem = 'The name goes up with ''..''.'
                }

                $entry.Add([PSCustomObject]@{
                        Name    = $name
                        Size    = [System.Int64]$size
                        Safe    = ($problem -eq '')
                        Problem = $problem
                    })
            }
            return $entry.ToArray()
        }
        finally {
            $reader.Dispose()
        }
    }
    catch [System.IO.EndOfStreamException] {
        throw 'The cabinet is cut short.'
    }
    finally {
        $stream.Dispose()
    }
}
