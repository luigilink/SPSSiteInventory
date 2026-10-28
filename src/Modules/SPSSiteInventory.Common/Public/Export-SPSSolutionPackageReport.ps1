function Export-SPSSolutionPackageReport {
    <#
        .SYNOPSIS
        Exports the WSP package inspection (Get-SPSSolutionPackageInfo) to CSV and JSON.

        .DESCRIPTION
        Writes three files to the output folder, which is created when missing:

        - a CSV file with one row per package, for review in Excel, with the array-valued columns
          (target frameworks, feature scopes, feature ids, differences with the farm) flattened to
          semicolon-separated strings;
        - a CSV file with one row per assembly (the strong name, the public key token, the framework,
          where it is deployed and whether it is Microsoft or custom), tied to its package;
        - a JSON file that keeps the full structure (assemblies and features included) for automation.

        The text of a package (names, titles, paths) comes from files that are not trusted, so the
        CSV cells that a spreadsheet could read as a formula are neutralized, as in the other reports.

        Returns a PSCustomObject with the three output paths.

        .PARAMETER InputObject
        The package records (from Get-SPSSolutionPackageInfo). Pass them through the pipeline or as
        an array.

        .PARAMETER OutputFolder
        Folder where the files are written.

        .PARAMETER BaseName
        Base file name (without extension). Defaults to 'SPSSiteInventory'. The suffix
        '-solution-packages' (or '-solution-assemblies') and a timestamp are appended to keep
        successive runs side by side.

        .EXAMPLE
        Get-SPSSolutionPackageInfo -Path D:\Packages | Export-SPSSolutionPackageReport -OutputFolder C:\Inventory
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
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

    begin {
        $record = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($item in @($InputObject)) {
            if ($null -ne $item) {
                $record.Add($item)
            }
        }
    }

    end {
        if (-not (Test-Path -Path $OutputFolder)) {
            $null = New-Item -Path $OutputFolder -ItemType Directory -Force
        }

        $timestamp = Get-Date -Format 'yyyyMMdd-HHmm'
        $packageCsvPath = Join-Path -Path $OutputFolder -ChildPath ('{0}-solution-packages-{1}.csv' -f $BaseName, $timestamp)
        $assemblyCsvPath = Join-Path -Path $OutputFolder -ChildPath ('{0}-solution-assemblies-{1}.csv' -f $BaseName, $timestamp)
        $jsonPath = Join-Path -Path $OutputFolder -ChildPath ('{0}-solution-packages-{1}.json' -f $BaseName, $timestamp)

        $join = { param ($Value) return (@($Value) -join '; ') }

        $packageRow = foreach ($item in $record) {
            [PSCustomObject]@{
                PackageName                    = $item.PackageName
                PackagePath                    = $item.PackagePath
                Source                         = $item.Source
                PackageSizeBytes               = $item.PackageSizeBytes
                Sha256                         = $item.Sha256
                Status                         = $item.Status
                Detail                         = $item.Detail
                SolutionId                     = $item.SolutionId
                SharePointProductVersion       = $item.SharePointProductVersion
                DeploymentServerType           = $item.DeploymentServerType
                ResetWebServer                 = $item.ResetWebServer
                IsCustom                       = $item.IsCustom
                IsCustomSource                 = $item.IsCustomSource
                IsFullTrustCode                = $item.IsFullTrustCode
                ContainsGlobalAssembly         = $item.ContainsGlobalAssembly
                ContainsWebApplicationAssembly = $item.ContainsWebApplicationAssembly
                ContainsCasPolicy              = $item.ContainsCasPolicy
                ContainsWebApplicationResource = $item.ContainsWebApplicationResource
                AssemblyCount                  = $item.AssemblyCount
                CustomAssemblyCount            = $item.CustomAssemblyCount
                UnsignedAssemblyCount          = $item.UnsignedAssemblyCount
                LegacyFrameworkAssemblyCount   = $item.LegacyFrameworkAssemblyCount
                TargetFrameworks               = & $join $item.TargetFrameworks
                FeatureCount                   = $item.FeatureCount
                FeatureScopes                  = & $join $item.FeatureScopes
                FeatureIds                     = & $join $item.FeatureIds
                FeatureReceiverCount           = $item.FeatureReceiverCount
                SafeControlCount               = $item.SafeControlCount
                TemplateFileCount              = $item.TemplateFileCount
                RootFileCount                  = $item.RootFileCount
                DwpFileCount                   = $item.DwpFileCount
                SiteDefinitionCount            = $item.SiteDefinitionCount
                ElementSummary                 = $item.ElementSummary
                FileCount                      = $item.FileCount
                ExpandedSizeBytes              = $item.ExpandedSizeBytes
                InFarm                         = $item.InFarm
                FarmMatch                      = $item.FarmMatch
                FarmSolutionName               = $item.FarmSolutionName
                FarmDeployed                   = $item.FarmDeployed
                FarmDeploymentState            = $item.FarmDeploymentState
                FarmFeatureCount               = $item.FarmFeatureCount
                Difference                     = & $join $item.Difference
            }
        }

        $assemblyRow = foreach ($item in $record) {
            foreach ($assembly in @($item.Assemblies)) {
                [PSCustomObject]@{
                    PackageName             = $item.PackageName
                    SolutionId              = $item.SolutionId
                    Location                = $assembly.Location
                    DeploymentTarget        = $assembly.DeploymentTarget
                    Status                  = $assembly.Status
                    Detail                  = $assembly.Detail
                    Name                    = $assembly.Name
                    Version                 = $assembly.Version
                    Culture                 = $assembly.Culture
                    PublicKeyToken          = $assembly.PublicKeyToken
                    IsSigned                = $assembly.IsSigned
                    IsManaged               = $assembly.IsManaged
                    IsMicrosoft             = $assembly.IsMicrosoft
                    IsSatellite             = $assembly.IsSatellite
                    IsCustom                = $assembly.IsCustom
                    RuntimeVersion          = $assembly.RuntimeVersion
                    TargetFramework         = $assembly.TargetFramework
                    Architecture            = $assembly.Architecture
                    BuiltForLegacyFramework = $assembly.BuiltForLegacyFramework
                    SafeControlCount        = $assembly.SafeControlCount
                }
            }
        }

        @($packageRow) | ConvertTo-SPSCsvSafeRecord | Export-Csv -Path $packageCsvPath -NoTypeInformation -Encoding UTF8
        @($assemblyRow) | ConvertTo-SPSCsvSafeRecord | Export-Csv -Path $assemblyCsvPath -NoTypeInformation -Encoding UTF8
        $json = ConvertTo-Json -InputObject @($record.ToArray()) -Depth 6
        Set-Content -Path $jsonPath -Value $json -Encoding UTF8

        return [PSCustomObject]@{
            PackageCsvPath  = $packageCsvPath
            AssemblyCsvPath = $assemblyCsvPath
            JsonPath        = $jsonPath
        }
    }
}
