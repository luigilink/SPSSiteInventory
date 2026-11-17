function Resolve-SPSAssemblySolution {
    <#
        .SYNOPSIS
        Finds the inspected packages, and the farm solutions, that ship an assembly.

        .DESCRIPTION
        Looks the assembly up in the index of Get-SPSSolutionAssemblyIndex by its name. When the
        registered assembly and the one of the package both have a public key token, the tokens have to
        be the same, and the match is AssemblyNameAndKey. When one of them has none (an assembly that
        is not signed, or a token that could not be read) the name is all there is to compare, and the
        match is AssemblyName. The version is not compared: a package often ships a newer version than
        the one an event receiver is registered with.

        Returns $null when no package ships the assembly. Otherwise returns MatchedBy, PackageName (the
        names of the packages, sorted and separated by '; ') and FarmSolutionName (the farm solutions of
        those packages, empty when none of them is deployed in the farm). A match on name and key wins
        over a match on name alone.

        Private because it is an implementation detail of the event receiver report.

        .PARAMETER AssemblyName
        The display name of the assembly, as an event receiver registers it.

        .PARAMETER Index
        The index from Get-SPSSolutionAssemblyIndex, a hashtable. PowerShell turns another kind of dictionary into
        one, so a dictionary that is not a hashtable is read the same way.

        .EXAMPLE
        Resolve-SPSAssemblySolution -AssemblyName $receiver.Assembly -Index $index
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $AssemblyName,

        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]
        $Index
    )

    $identity = ConvertFrom-SPSAssemblyName -DisplayName $AssemblyName
    if ([System.String]::IsNullOrWhiteSpace($identity.Name)) {
        return $null
    }
    $key = $identity.Name.ToLowerInvariant()
    if (-not $Index.ContainsKey($key)) {
        return $null
    }

    $sameKey = [System.Collections.Generic.List[object]]::new()
    $sameName = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($Index[$key])) {
        if ($identity.PublicKeyToken -and $entry.PublicKeyToken) {
            if ($identity.PublicKeyToken -eq $entry.PublicKeyToken) {
                $sameKey.Add($entry)
            }
        }
        else {
            $sameName.Add($entry)
        }
    }

    $matchedBy = 'AssemblyNameAndKey'
    $matched = $sameKey
    if ($sameKey.Count -eq 0) {
        $matchedBy = 'AssemblyName'
        $matched = $sameName
    }
    if ($matched.Count -eq 0) {
        return $null
    }

    return [PSCustomObject]@{
        MatchedBy        = $matchedBy
        PackageName      = (@($matched | ForEach-Object { $_.PackageName } | Where-Object { $_ } | Sort-Object -Unique) -join '; ')
        FarmSolutionName = (@($matched | ForEach-Object { $_.FarmSolutionName } | Where-Object { $_ } | Sort-Object -Unique) -join '; ')
    }
}
