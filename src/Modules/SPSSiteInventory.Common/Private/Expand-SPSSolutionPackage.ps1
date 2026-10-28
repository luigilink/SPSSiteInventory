function Expand-SPSSolutionPackage {
    <#
        .SYNOPSIS
        Expands a WSP (a cabinet) into a folder, after checking what it lists.

        .DESCRIPTION
        The package is first checked without being expanded (see Get-SPSCabinetEntry): it is refused
        when it lists a file name that is not safe to extract (a name that goes up with '..', is
        rooted or has a drive or a stream), more files than the limit, or when its declared size is
        above the size limit. It is then expanded by the cabinet tool of the machine:

        - expand.exe on Windows, which is part of the system;
        - cabextract elsewhere, when it is installed.

        The package is copied to the work folder first, so that the tool never sees the original path
        (a path with odd characters, a network share, the extension). The files are then checked: all
        of them must be under the expanded folder.

        The expanded files are only ever read as text (XML) and as bytes (assemblies): nothing in
        them is run or loaded.

        Private because it is an implementation detail of Get-SPSSolutionPackageInfo.

        .PARAMETER Path
        The path of the WSP.

        .PARAMETER WorkFolder
        A folder that does not exist yet, or is empty. The copy of the package goes in it, and the files
        in its 'expanded' subfolder. The caller removes it.

        .PARAMETER MaximumFileCount
        The number of files above which the package is refused. Defaults to 20000.

        .PARAMETER MaximumMegabyte
        The declared size, in MB, above which the package is refused. Defaults to 512.

        .OUTPUTS
        An object with Path (the expanded folder), FileCount and DeclaredBytes.

        .EXAMPLE
        Expand-SPSSolutionPackage -Path .\Contoso.Intranet.wsp -WorkFolder $env:TEMP\wsp1
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter(Mandatory = $true)]
        [System.String]
        $WorkFolder,

        [Parameter()]
        [ValidateRange(1, 1000000)]
        [System.Int32]
        $MaximumFileCount = 20000,

        [Parameter()]
        [ValidateRange(1, 4096)]
        [System.Int32]
        $MaximumMegabyte = 512
    )

    $entry = @(Get-SPSCabinetEntry -Path $Path)
    if ($entry.Count -eq 0) {
        throw 'The package has no file.'
    }
    if ($entry.Count -gt $MaximumFileCount) {
        throw "The package lists $($entry.Count) files, more than the limit of $MaximumFileCount."
    }
    $unsafe = @($entry | Where-Object { -not $_.Safe })
    if ($unsafe.Count -gt 0) {
        throw "The package lists a file name that is not safe to extract: '$($unsafe[0].Name)' ($($unsafe[0].Problem))"
    }
    $declared = [System.Int64]0
    foreach ($item in $entry) {
        $declared += $item.Size
    }
    if ($declared -gt ([System.Int64]$MaximumMegabyte * 1MB)) {
        throw ('The package expands to {0} MB, more than the limit of {1} MB.' -f [System.Math]::Round($declared / 1MB), $MaximumMegabyte)
    }

    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        $tool = Join-Path -Path ([System.Environment]::SystemDirectory) -ChildPath 'expand.exe'
        if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
            $found = Get-Command -Name 'expand.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -eq $found) {
                throw 'expand.exe was not found.'
            }
            $tool = $found.Source
        }
    }
    else {
        $found = Get-Command -Name 'cabextract' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $found) {
            throw 'Expanding a package needs expand.exe (Windows) or cabextract. Expand the package with another tool and give the folder to -Path.'
        }
        $tool = $found.Source
    }

    $expanded = Join-Path -Path $WorkFolder -ChildPath 'expanded'
    $null = New-Item -Path $expanded -ItemType Directory -Force
    $copy = Join-Path -Path $WorkFolder -ChildPath 'package.cab'
    Copy-Item -LiteralPath $Path -Destination $copy -Force

    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        $argument = @($copy, '-F:*', $expanded)
    }
    else {
        $argument = @('-q', '-d', $expanded, $copy)
    }

    # A native command that writes to stderr must not become a terminating error here.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $text = (& $tool @argument 2>&1 | ForEach-Object { [System.String]$_ }) -join ' '
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
    if ($exitCode -ne 0) {
        throw ('{0} could not expand the package (exit code {1}): {2}' -f [System.IO.Path]::GetFileName($tool), $exitCode, $text.Trim())
    }

    $expandedFull = [System.IO.Path]::GetFullPath($expanded).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $fileCount = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $expanded -Recurse -Force -File)) {
        if (-not $file.FullName.StartsWith($expandedFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'The expansion wrote a file outside of its folder.'
        }
        $fileCount++
    }

    return [PSCustomObject]@{
        Path          = $expanded
        FileCount     = $fileCount
        DeclaredBytes = $declared
    }
}
