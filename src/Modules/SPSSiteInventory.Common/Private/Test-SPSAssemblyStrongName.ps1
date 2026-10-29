function Test-SPSAssemblyStrongName {
    <#
        .SYNOPSIS
        Checks the strong-name signature of an assembly that is held in memory as bytes, without
        loading it.

        .DESCRIPTION
        The public key token of an assembly is a hash of the public key that the assembly declares:
        it says nothing about who signed the assembly. An assembly that is only delay-signed, or that
        was altered after it was signed, still carries the token of the key. This function checks the
        signature itself, so that a token can be trusted:

        - the CLR header must say that the assembly is signed and must point to a signature;
        - the hash of the file (the headers and the sections, without the checksum, the certificate
          table entry and the signature itself) is computed with the algorithm of the public key;
        - the signature is checked against the public key with RSA.

        Nothing is loaded or run: the bytes are only hashed. The function never throws.

        Status:

        - Valid: the signature is valid for the public key of the assembly.
        - Invalid: the assembly is signed and the signature does not match (it was altered, or the
          signature was forged).
        - NotSigned: the assembly has a public key but no signature: it is delay-signed, or "public
          signed", as the assemblies that Microsoft builds in the open are (the key is declared, the
          flag of a signed assembly is set, and the room for the signature is filled with zeros).
        - NotVerified: the signature could not be checked here (a public key that is not an RSA key,
          such as the standard key of the ECMA assemblies, an algorithm that is not known, or an
          error). It is neither proven nor refuted.

        Private because it is an implementation detail of Get-SPSAssemblyFileInfo.

        .PARAMETER Bytes
        The content of the assembly file.

        .PARAMETER PublicKey
        The public key of the assembly (AssemblyName.GetPublicKey()), with its 12-byte header.

        .OUTPUTS
        An object with Status and Detail (why, when it is not Valid).

        .EXAMPLE
        Test-SPSAssemblyStrongName -Bytes ([System.IO.File]::ReadAllBytes($dll)) -PublicKey $name.GetPublicKey()
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Byte[]]
        $Bytes,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.Byte[]]
        $PublicKey
    )

    $result = {
        param ([System.String] $Status, [System.String] $Detail)
        return [PSCustomObject]@{ Status = $Status; Detail = $Detail }
    }

    try {
        # The public key: SigAlgId, HashAlgId and the size, then a CAPI public key blob (RSA1).
        if ($null -eq $PublicKey -or $PublicKey.Length -lt 32 -or [System.BitConverter]::ToUInt32($PublicKey, 12 + 8) -ne 0x31415352) {
            return (& $result 'NotVerified' 'The public key is not an RSA key, so there is no signature to check.')
        }
        $hashAlgorithmId = [System.BitConverter]::ToUInt32($PublicKey, 4)
        $hashName = switch ($hashAlgorithmId) {
            0 { 'SHA1' }
            0x8004 { 'SHA1' }
            0x800C { 'SHA256' }
            0x800D { 'SHA384' }
            0x800E { 'SHA512' }
            default { '' }
        }
        if (-not $hashName) {
            return (& $result 'NotVerified' "The hash algorithm of the public key (0x$($hashAlgorithmId.ToString('x'))) is not known.")
        }
        $bitLength = [System.BitConverter]::ToUInt32($PublicKey, 12 + 12)
        $keyLength = [System.Int32]($bitLength / 8)
        if ($bitLength -lt 512 -or $bitLength -gt 16384 -or ($bitLength % 8) -ne 0 -or $PublicKey.Length -lt (12 + 20 + $keyLength)) {
            return (& $result 'NotVerified' 'The public key is not well formed.')
        }

        # The PE image: the headers, the sections and the CLR header.
        $length = [System.Int64]$Bytes.Length
        $peOffset = [System.Int32][System.BitConverter]::ToUInt32($Bytes, 0x3C)
        $sectionCount = [System.Int32][System.BitConverter]::ToUInt16($Bytes, $peOffset + 6)
        $optional = $peOffset + 24
        $sectionTable = $optional + [System.BitConverter]::ToUInt16($Bytes, $peOffset + 20)
        $headerEnd = $sectionTable + (40 * $sectionCount)
        $magic = [System.BitConverter]::ToUInt16($Bytes, $optional)
        $directory = if ($magic -eq 0x10B) { $optional + 96 } elseif ($magic -eq 0x20B) { $optional + 112 } else { 0 }
        if ($directory -eq 0 -or $headerEnd -gt $length) {
            return (& $result 'NotVerified' 'The headers of the file are not valid.')
        }
        $checksumOffset = $optional + 64
        $certificateOffset = $directory + (4 * 8)

        $toOffset = {
            param ([System.UInt32] $Rva)
            for ($section = 0; $section -lt $sectionCount; $section++) {
                $entry = $sectionTable + (40 * $section)
                $virtualAddress = [System.BitConverter]::ToUInt32($Bytes, $entry + 12)
                $span = [System.Math]::Max([System.BitConverter]::ToUInt32($Bytes, $entry + 8), [System.BitConverter]::ToUInt32($Bytes, $entry + 16))
                if ($Rva -ge $virtualAddress -and $Rva -lt ($virtualAddress + $span)) {
                    return [System.Int64][System.BitConverter]::ToUInt32($Bytes, $entry + 20) + ([System.Int64]$Rva - [System.Int64]$virtualAddress)
                }
            }
            return [System.Int64]-1
        }

        $clr = & $toOffset ([System.BitConverter]::ToUInt32($Bytes, $directory + (14 * 8)))
        if ($clr -lt 0 -or ($clr + 40) -gt $length) {
            return (& $result 'NotVerified' 'The .NET header of the file is outside of the file.')
        }
        $flags = [System.BitConverter]::ToUInt32($Bytes, [System.Int32]$clr + 16)
        $signatureLength = [System.Int64][System.BitConverter]::ToUInt32($Bytes, [System.Int32]$clr + 36)
        $signatureOffset = & $toOffset ([System.BitConverter]::ToUInt32($Bytes, [System.Int32]$clr + 32))
        if (($flags -band 0x8) -eq 0 -or $signatureLength -eq 0) {
            return (& $result 'NotSigned' 'The assembly has a public key but no strong-name signature (it is delay-signed, or signed with the public key only).')
        }
        if ($signatureOffset -lt 0 -or ($signatureOffset + $signatureLength) -gt $length -or $signatureLength -ne $keyLength) {
            return (& $result 'Invalid' 'The strong-name signature is not where the assembly says, or is not the size of the key.')
        }
        $filled = $false
        for ($index = 0; $index -lt $signatureLength; $index++) {
            if ($Bytes[[System.Int32]$signatureOffset + $index] -ne 0) {
                $filled = $true
                break
            }
        }
        if (-not $filled) {
            return (& $result 'NotSigned' 'The assembly has a public key and room for a signature, but the signature is empty (it is delay-signed, or signed with the public key only).')
        }

        # What is hashed: the headers (the checksum and the certificate table entry count as zero), then every section
        # as stored, except the signature itself.
        $hasher = [System.Security.Cryptography.HashAlgorithm]::Create($hashName)
        try {
            $header = New-Object -TypeName System.Byte[] -ArgumentList $headerEnd
            [System.Array]::Copy($Bytes, 0, $header, 0, $headerEnd)
            for ($index = 0; $index -lt 4; $index++) {
                $header[$checksumOffset + $index] = 0
            }
            for ($index = 0; $index -lt 8; $index++) {
                $header[$certificateOffset + $index] = 0
            }
            $null = $hasher.TransformBlock($header, 0, $headerEnd, $null, 0)

            for ($section = 0; $section -lt $sectionCount; $section++) {
                $entry = $sectionTable + (40 * $section)
                $rawSize = [System.Int64][System.BitConverter]::ToUInt32($Bytes, $entry + 16)
                $rawPointer = [System.Int64][System.BitConverter]::ToUInt32($Bytes, $entry + 20)
                if ($rawSize -eq 0) {
                    continue
                }
                if (($rawPointer + $rawSize) -gt $length) {
                    return (& $result 'Invalid' 'A section of the file is outside of the file.')
                }
                if ($signatureOffset -ge $rawPointer -and $signatureOffset -lt ($rawPointer + $rawSize)) {
                    $before = $signatureOffset - $rawPointer
                    $after = $rawPointer + $rawSize - ($signatureOffset + $signatureLength)
                    if ($before -gt 0) {
                        $null = $hasher.TransformBlock($Bytes, [System.Int32]$rawPointer, [System.Int32]$before, $null, 0)
                    }
                    if ($after -gt 0) {
                        $null = $hasher.TransformBlock($Bytes, [System.Int32]($signatureOffset + $signatureLength), [System.Int32]$after, $null, 0)
                    }
                }
                else {
                    $null = $hasher.TransformBlock($Bytes, [System.Int32]$rawPointer, [System.Int32]$rawSize, $null, 0)
                }
            }
            $null = $hasher.TransformFinalBlock((New-Object -TypeName System.Byte[] -ArgumentList 0), 0, 0)
            $hash = $hasher.Hash
        }
        finally {
            $hasher.Dispose()
        }

        # The signature is stored in the reverse order of the bytes that RSA expects, as the modulus of the key is.
        $signature = New-Object -TypeName System.Byte[] -ArgumentList $keyLength
        [System.Array]::Copy($Bytes, [System.Int32]$signatureOffset, $signature, 0, $keyLength)
        [System.Array]::Reverse($signature)
        $modulus = New-Object -TypeName System.Byte[] -ArgumentList $keyLength
        [System.Array]::Copy($PublicKey, 12 + 20, $modulus, 0, $keyLength)
        [System.Array]::Reverse($modulus)
        $exponent = [System.BitConverter]::GetBytes([System.BitConverter]::ToUInt32($PublicKey, 12 + 16))
        [System.Array]::Reverse($exponent)
        $first = 0
        while ($first -lt ($exponent.Length - 1) -and $exponent[$first] -eq 0) {
            $first++
        }
        $parameter = [System.Security.Cryptography.RSAParameters]@{
            Modulus  = $modulus
            Exponent = [System.Byte[]]$exponent[$first..($exponent.Length - 1)]
        }

        $rsa = [System.Security.Cryptography.RSA]::Create()
        try {
            $rsa.ImportParameters($parameter)
            $deformatter = New-Object -TypeName System.Security.Cryptography.RSAPKCS1SignatureDeformatter -ArgumentList $rsa
            $deformatter.SetHashAlgorithm($hashName)
            $valid = $deformatter.VerifySignature($hash, $signature)
        }
        finally {
            $rsa.Dispose()
        }
        if ($valid) {
            return (& $result 'Valid' '')
        }
        return (& $result 'Invalid' 'The strong-name signature does not match the assembly and its public key: the assembly was altered after it was signed, or the signature is not genuine.')
    }
    catch {
        return (& $result 'NotVerified' "The signature could not be checked: $($_.Exception.Message)")
    }
}
