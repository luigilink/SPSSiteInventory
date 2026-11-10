function Get-SPSSolutionAssemblyIndex {
    <#
        .SYNOPSIS
        Indexes the assemblies of the inspected solution packages by name, to find the solution that ships an assembly.

        .DESCRIPTION
        Reads the records of Get-SPSSolutionPackageInfo and returns a hashtable whose keys are the assembly
        names in lower case and whose values are the packages that ship an assembly of that name: the name
        and the farm solution of the package, the public key token and the version of the assembly. An
        assembly that two packages ship has two entries. A satellite assembly, which only holds resources,
        and a file that is not a .NET assembly are left out.

        The index is empty, and not null, when the packages ship no assembly. That tells
        Resolve-SPSAssemblySolution that the packages were inspected and that none of them ships the
        assembly, which is not the same as no package having been inspected.

        Private because it is an implementation detail of the event receiver report.

        .PARAMETER SolutionPackages
        The package records (from Get-SPSSolutionPackageInfo).

        .EXAMPLE
        $index = Get-SPSSolutionAssemblyIndex -SolutionPackages (Get-SPSSolutionPackageInfo -Path D:\Packages)
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.Object[]]
        $SolutionPackages = @()
    )

    $index = @{}
    foreach ($package in @($SolutionPackages | Where-Object { $null -ne $_ })) {
        foreach ($assembly in @($package.Assemblies | Where-Object { $null -ne $_ })) {
            $name = ([System.String]$assembly.Name).Trim()
            if ([System.String]::IsNullOrWhiteSpace($name) -or $assembly.IsSatellite -eq $true -or $assembly.IsManaged -eq $false) {
                continue
            }
            $key = $name.ToLowerInvariant()
            if (-not $index.ContainsKey($key)) {
                $index[$key] = [System.Collections.Generic.List[object]]::new()
            }
            $index[$key].Add([PSCustomObject]@{
                    PackageName      = [System.String]$package.PackageName
                    FarmSolutionName = [System.String]$package.FarmSolutionName
                    PublicKeyToken   = ([System.String]$assembly.PublicKeyToken).Trim().ToLowerInvariant()
                    Version          = [System.String]$assembly.Version
                })
        }
    }

    return $index
}
