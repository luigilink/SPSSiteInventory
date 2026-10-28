function Get-SPSAssemblyFileInfo {
    <#
        .SYNOPSIS
        Reads what identifies a .NET assembly file (its strong name, the runtime and the target
        framework it was built for), without loading or running it.

        .DESCRIPTION
        The file is only read as bytes and as an assembly name: nothing in it is executed and it is
        not loaded in the session, so it is safe to point at a DLL that comes from a package that
        is not trusted.

        - Name, Version, Culture and PublicKeyToken come from the assembly manifest. The token is
          the 16 hexadecimal digits of the strong name key, or empty for an assembly that is not
          signed. It tells a Microsoft assembly from a custom one without guessing from a name.
        - RuntimeVersion is the version of the runtime that the assembly asks for, read from its
          metadata: 'v2.0.50727' is the runtime of .NET 2.0 to 3.5 (SharePoint 2010 and before),
          'v4.0.30319' that of .NET 4.x.
        - TargetFramework is the framework named by the TargetFramework attribute, for example
          '.NETFramework,Version=v4.8', when the assembly has one (an assembly built before .NET
          4.0 does not).
        - Architecture is 'AnyCPU', 'x86', 'x64', 'ARM' or 'ARM64'.

        A file that is not a .NET assembly (a native DLL, a text file) is reported with
        IsManaged = $false and the reason in Detail; the function does not throw for a bad file.

        Private because it is an implementation detail of Get-SPSSolutionPackageInfo.

        .PARAMETER Path
        The path of the DLL.

        .PARAMETER MaximumMegabyte
        The size above which the file is not read. Defaults to 256.

        .OUTPUTS
        An object with Path, IsManaged, Name, Version, Culture, PublicKeyToken, IsSigned,
        RuntimeVersion, TargetFramework, Architecture and Detail.

        .EXAMPLE
        Get-SPSAssemblyFileInfo -Path .\Contoso.Intranet.dll
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [ValidateRange(1, 4096)]
        [System.Int32]
        $MaximumMegabyte = 256
    )

    $info = [ordered]@{
        Path            = $Path
        IsManaged       = $false
        Name            = ''
        Version         = ''
        Culture         = ''
        PublicKeyToken  = ''
        IsSigned        = $false
        RuntimeVersion  = ''
        TargetFramework = ''
        Architecture    = ''
        Detail          = ''
    }

    $length = (Get-Item -LiteralPath $Path -ErrorAction Stop).Length
    if ($length -gt ([System.Int64]$MaximumMegabyte * 1MB)) {
        $info['Detail'] = "The file is larger than $MaximumMegabyte MB and was not read."
        return [PSCustomObject]$info
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)

        if ($bytes.Length -lt 64 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
            $info['Detail'] = 'The file is not a Windows executable image (DLL).'
            return [PSCustomObject]$info
        }
        $peOffset = [System.BitConverter]::ToInt32($bytes, 0x3C)
        if ($peOffset -lt 64 -or ($peOffset + 24) -gt $bytes.Length -or
            $bytes[$peOffset] -ne 0x50 -or $bytes[$peOffset + 1] -ne 0x45 -or $bytes[$peOffset + 2] -ne 0 -or $bytes[$peOffset + 3] -ne 0) {
            $info['Detail'] = 'The file has no PE header.'
            return [PSCustomObject]$info
        }

        $machine = [System.BitConverter]::ToUInt16($bytes, $peOffset + 4)
        $sectionCount = [System.BitConverter]::ToUInt16($bytes, $peOffset + 6)
        $optionalSize = [System.BitConverter]::ToUInt16($bytes, $peOffset + 20)
        $optional = $peOffset + 24
        $magic = [System.BitConverter]::ToUInt16($bytes, $optional)
        if ($magic -eq 0x10B) {
            $directoryCountOffset = $optional + 92
        }
        elseif ($magic -eq 0x20B) {
            $directoryCountOffset = $optional + 108
        }
        else {
            $info['Detail'] = 'The file has an optional header that is not recognized.'
            return [PSCustomObject]$info
        }
        $directoryCount = [System.BitConverter]::ToUInt32($bytes, $directoryCountOffset)
        if ($directoryCount -lt 15) {
            $info['Detail'] = 'The file is a native DLL (it has no .NET header).'
            return [PSCustomObject]$info
        }
        $clrRva = [System.BitConverter]::ToUInt32($bytes, $directoryCountOffset + 4 + (14 * 8))
        if ($clrRva -eq 0) {
            $info['Detail'] = 'The file is a native DLL (it has no .NET header).'
            return [PSCustomObject]$info
        }

        $sectionTable = $optional + $optionalSize
        $toOffset = {
            param ([System.UInt32] $Rva)
            for ($section = 0; $section -lt $sectionCount; $section++) {
                $entry = $sectionTable + (40 * $section)
                if (($entry + 40) -gt $bytes.Length) {
                    break
                }
                $virtualSize = [System.BitConverter]::ToUInt32($bytes, $entry + 8)
                $virtualAddress = [System.BitConverter]::ToUInt32($bytes, $entry + 12)
                $rawSize = [System.BitConverter]::ToUInt32($bytes, $entry + 16)
                $rawPointer = [System.BitConverter]::ToUInt32($bytes, $entry + 20)
                $span = [System.Math]::Max($virtualSize, $rawSize)
                if ($Rva -ge $virtualAddress -and $Rva -lt ($virtualAddress + $span)) {
                    return [System.Int64]$rawPointer + ([System.Int64]$Rva - [System.Int64]$virtualAddress)
                }
            }
            return [System.Int64]-1
        }

        $clrOffset = & $toOffset $clrRva
        if ($clrOffset -lt 0 -or ($clrOffset + 20) -gt $bytes.Length) {
            $info['Detail'] = 'The .NET header of the file is outside of the file.'
            return [PSCustomObject]$info
        }
        $metadataRva = [System.BitConverter]::ToUInt32($bytes, [System.Int32]$clrOffset + 8)
        $corFlags = [System.BitConverter]::ToUInt32($bytes, [System.Int32]$clrOffset + 16)
        $metadataOffset = & $toOffset $metadataRva
        if ($metadataOffset -lt 0 -or ($metadataOffset + 16) -gt $bytes.Length -or
            [System.BitConverter]::ToUInt32($bytes, [System.Int32]$metadataOffset) -ne 0x424A5342) {
            $info['Detail'] = 'The .NET metadata of the file is not valid.'
            return [PSCustomObject]$info
        }
        $versionLength = [System.BitConverter]::ToUInt32($bytes, [System.Int32]$metadataOffset + 12)
        if ($versionLength -gt 255 -or ($metadataOffset + 16 + $versionLength) -gt $bytes.Length) {
            $info['Detail'] = 'The .NET metadata of the file is not valid.'
            return [PSCustomObject]$info
        }
        $runtime = [System.Text.Encoding]::UTF8.GetString($bytes, [System.Int32]$metadataOffset + 16, [System.Int32]$versionLength).TrimEnd([char]0)

        $info['IsManaged'] = $true
        $info['RuntimeVersion'] = $runtime
        $info['Architecture'] = switch ($machine) {
            0x14C {
                # ILONLY without 32BITREQUIRED is AnyCPU, whatever the machine type says.
                if (($corFlags -band 0x1) -ne 0 -and ($corFlags -band 0x2) -eq 0) { 'AnyCPU' } else { 'x86' }
            }
            0x8664 { 'x64' }
            0x1C4 { 'ARM' }
            0xAA64 { 'ARM64' }
            default { 'Other' }
        }

        # The TargetFramework attribute keeps its argument as text in the metadata.
        $text = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
        $framework = [regex]::Match($text, '\.NET(?:Framework|CoreApp|Standard),Version=v[0-9]+(?:\.[0-9]+){1,3}(?:,Profile=[A-Za-z0-9]+)?')
        if ($framework.Success) {
            $info['TargetFramework'] = $framework.Value
        }
    }
    catch {
        $info['Detail'] = "The file could not be read: $($_.Exception.Message)"
        return [PSCustomObject]$info
    }

    try {
        $assemblyName = [System.Reflection.AssemblyName]::GetAssemblyName($Path)
        $token = ($assemblyName.GetPublicKeyToken() | ForEach-Object { $_.ToString('x2') }) -join ''
        $info['Name'] = $assemblyName.Name
        $info['Version'] = [System.String]$assemblyName.Version
        $info['Culture'] = [System.String]$assemblyName.CultureName
        $info['PublicKeyToken'] = $token
        $info['IsSigned'] = ($token.Length -gt 0)
    }
    catch {
        $info['Detail'] = "The assembly name could not be read: $($_.Exception.Message)"
    }
    return [PSCustomObject]$info
}
