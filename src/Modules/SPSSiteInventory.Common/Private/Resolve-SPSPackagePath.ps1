function Resolve-SPSPackagePath {
    <#
        .SYNOPSIS
        Resolves a location that a package gives, and says whether it can be read safely.

        .DESCRIPTION
        A location in a manifest comes from a file that is not trusted. It is followed only when it stays
        in the package:

        - it must be relative: a location that is rooted (it starts with a separator or has a drive) is
          refused, and is not read as a path under the package;
        - the full path must be under the root of the package. The comparison does not ignore the case
          except on Windows: on another platform the file system tells 'package' from 'PACKAGE', so
          '..\PACKAGE\Feature.xml' leaves a package that is in a folder named 'package';
        - no part of the path, from the folder under the root down to the file, may be a symbolic link or
          a junction. A link would lead out of the package, and the file would be read from there. The
          root itself is the one that the caller chose and is not checked.

        The function reads nothing: it only resolves the path and looks at the items on the way to it.
        A file that does not exist is not a problem here (the caller says that it is missing).

        Private because it is an implementation detail of Get-SPSExpandedPackageInfo.

        .PARAMETER Root
        The folder that holds the expanded package.

        .PARAMETER Base
        The folder that the location is relative to: the root for the manifest, the folder of a feature
        for its element manifests.

        .PARAMETER Location
        The location, as written in the manifest (with '\' or '/').

        .OUTPUTS
        An object with Path (the full path when it can be followed, $null otherwise), Problem ('' when
        it can be followed, or 'Empty', 'Outside' or 'Link') and Detail (the reason, in words).

        .EXAMPLE
        Resolve-SPSPackagePath -Root $folder -Base $folder -Location 'FeatureA\Feature.xml'
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Root,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Base,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Location
    )

    $refuse = {
        param ([System.String] $Problem, [System.String] $Detail)
        return [PSCustomObject]@{ Path = $null; Problem = $Problem; Detail = $Detail }
    }

    if ([System.String]::IsNullOrWhiteSpace($Location)) {
        return (& $refuse 'Empty' 'The location is empty.')
    }
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $alternate = [System.IO.Path]::AltDirectorySeparatorChar
    $comparison = if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }

    if ($Location.Trim() -match '^[\\/]' -or $Location.Trim() -match '^[A-Za-z]:') {
        return (& $refuse 'Outside' 'The location is outside of the package.')
    }

    try {
        $relative = $Location.Trim() -replace '[\\/]', $separator
        $full = [System.IO.Path]::GetFullPath((Join-Path -Path $Base -ChildPath $relative))
        $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd($separator, $alternate) + $separator
    }
    catch {
        return (& $refuse 'Outside' 'The location is outside of the package.')
    }
    if (-not $full.StartsWith($rootFull, $comparison)) {
        return (& $refuse 'Outside' 'The location is outside of the package.')
    }

    $current = $full
    while ($current.Length -gt $rootFull.Length) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if (Test-SPSFileSystemLink -Item $item) {
            return (& $refuse 'Link' 'The location goes through a link (a symbolic link or a junction), which is not followed.')
        }
        $current = [System.IO.Path]::GetDirectoryName($current)
        if ($null -eq $current) {
            break
        }
    }

    return [PSCustomObject]@{ Path = $full; Problem = ''; Detail = '' }
}
