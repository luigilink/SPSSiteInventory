function Export-SPSSolutionReport {
    <#
        .SYNOPSIS
        Exports the farm-solution (WSP) map to CSV and JSON.

        .DESCRIPTION
        Writes the enriched farm-solution map (as produced by Get-SPSFarmSolutionMap) to
        two files in the output folder, which is created when missing:

        - a CSV file for review in Excel, with the array-valued columns (FeatureScopes,
          FeatureIds) flattened to semicolon-separated strings so the file stays readable;
        - a JSON file that keeps the full structure (arrays intact) for automation.

        This makes the WSP estate a first-class deliverable next to the site inventory:
        which solutions are custom, which are full-trust code (a SharePoint Online
        blocker), where they are deployed and what they register.

        Returns a PSCustomObject with the two output paths.

        .PARAMETER InputObject
        The farm-solution map records to export (from Get-SPSFarmSolutionMap).

        .PARAMETER OutputFolder
        Folder where the CSV and JSON files are written.

        .PARAMETER BaseName
        Base file name (without extension). Defaults to 'SPSSiteInventory'. The suffix
        '-solutions' and a timestamp are appended to keep successive runs side by side.

        .EXAMPLE
        Export-SPSSolutionReport -InputObject $map -OutputFolder C:\Inventory
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Object[]]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [System.String]
        $OutputFolder,

        [Parameter()]
        [System.String]
        $BaseName = 'SPSSiteInventory'
    )

    if (-not (Test-Path -Path $OutputFolder)) {
        $null = New-Item -Path $OutputFolder -ItemType Directory -Force
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmm'
    $csvPath = Join-Path -Path $OutputFolder -ChildPath ('{0}-solutions-{1}.csv' -f $BaseName, $timestamp)
    $jsonPath = Join-Path -Path $OutputFolder -ChildPath ('{0}-solutions-{1}.json' -f $BaseName, $timestamp)

    # Flatten array-valued columns for the CSV so Export-Csv does not emit
    # 'System.Object[]'. The JSON keeps the arrays intact.
    $csvRows = foreach ($record in @($InputObject)) {
        [PSCustomObject]@{
            SolutionName                   = $record.SolutionName
            SolutionId                     = $record.SolutionId
            Deployed                       = $record.Deployed
            DeploymentState                = $record.DeploymentState
            IsCustom                       = $record.IsCustom
            ContainsGlobalAssembly         = $record.ContainsGlobalAssembly
            ContainsCasPolicy              = $record.ContainsCasPolicy
            ContainsWebApplicationResource = $record.ContainsWebApplicationResource
            IsFullTrustCode                = $record.IsFullTrustCode
            DeployedWebApplicationCount    = $record.DeployedWebApplicationCount
            DeployedServerCount            = $record.DeployedServerCount
            FeatureCount                   = $record.FeatureCount
            FeatureScopes                  = (@($record.FeatureScopes) -join '; ')
            FeatureIds                     = (@($record.FeatureIds) -join '; ')
        }
    }

    @($csvRows) | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    $json = ConvertTo-Json -InputObject @($InputObject) -Depth 6
    Set-Content -Path $jsonPath -Value $json -Encoding UTF8

    return [PSCustomObject]@{
        CsvPath  = $csvPath
        JsonPath = $jsonPath
    }
}
