function Get-SPSSolutionPackageInfo {
    <#
        .SYNOPSIS
        Inspects WSP packages on disk, with no farm, and reports what they contain.

        .DESCRIPTION
        A WSP is a cabinet (CAB) archive. Get-SPSSolutionPackageInfo expands it in a temporary folder,
        reads manifest.xml, the feature manifests and the DLLs, and removes the folder. It needs no
        farm, no SharePoint command and no Add-SPSolution, so a package can be assessed before any
        environment is touched, and it is read-only: nothing in the package is run or loaded.

        It reads what a farm solution (SPSolution) only shows as booleans:

        - the exact strong name of every assembly, with its public key token. A token that Microsoft
          signs with makes the assembly Microsoft, anything else (or no signature) makes it custom,
          so IsCustom no longer depends on the name of the solution;
        - the feature ids and scopes, even when the solution is not deployed (which is when the farm
          reports no feature), and the features that have a receiver;
        - where the assemblies are deployed (global assembly cache or web application), the safe
          controls, the code access security policy, the template files, the root files, the web part
          files and the site definitions;
        - the .NET framework the DLLs were built for: LegacyFrameworkAssemblyCount counts the custom
          assemblies built for .NET 3.5 or before (SharePoint 2010 and before), which need to be
          rebuilt for SharePoint 2016 and later.

        A package that cannot be inspected is returned with Status 'Failed' and the reason in Detail,
        so that one bad file does not stop the others. Status is 'Partial' when the package was read
        but a part of it could not be (a missing feature manifest, an assembly that is missing).

        A folder in -Path that holds manifest.xml at its root is read as a package that is already
        expanded (so a package can be inspected where no cabinet tool is available). A folder that
        does not is searched for .wsp and .cab files, and for the subfolders too with -Recurse.

        The cabinet is expanded with expand.exe on Windows, and with cabextract elsewhere. Before
        anything is written, the cabinet is refused when it lists a file name that is not safe (a name
        that goes up with '..'), too many files or too large a size.

        With -FarmSolutionMap (from Get-SPSFarmSolutionMap), each package is matched to the farm
        solution that has its solution id, or else its file name, and the differences are listed.

        .PARAMETER Path
        The WSP files, the folders that hold them, or the folders of expanded packages. Wildcards are
        accepted, and paths come from the pipeline (so Get-ChildItem *.wsp | Get-SPSSolutionPackageInfo
        works).

        .PARAMETER Recurse
        Searches the subfolders of a folder for packages.

        .PARAMETER FarmSolutionMap
        The farm solutions to compare the packages with, as returned by Get-SPSFarmSolutionMap.

        .PARAMETER KnownMicrosoftPublicKeyToken
        Extra public key tokens that count as Microsoft, in addition to the built-in ones
        (71e9bce111e9429c for SharePoint and Office Server, 31bf3856ad364e35, b77a5c561934e089 and
        b03f5f7f11d50a3a for Windows and .NET).

        .PARAMETER KnownMicrosoftPrefix
        Extra solution name prefixes that count as Microsoft, used only for a package that has no
        assembly to judge by (see Test-SPSMicrosoftSolution).

        .PARAMETER MaximumMegabyte
        The size, in MB, that a package may expand to. Defaults to 512.

        .PARAMETER TemporaryFolder
        Where the packages are expanded. Defaults to the temporary folder of the user.

        .OUTPUTS
        One object per package: PackageName, PackagePath, Source (Cabinet or Folder), PackageSizeBytes,
        Sha256, Status, Detail, SolutionId, SharePointProductVersion, DeploymentServerType,
        ResetWebServer, IsCustom, IsCustomSource (Assembly or Name), IsFullTrustCode,
        ContainsGlobalAssembly, ContainsWebApplicationAssembly, ContainsCasPolicy,
        ContainsWebApplicationResource, AssemblyCount, CustomAssemblyCount, UnsignedAssemblyCount,
        LegacyFrameworkAssemblyCount, TargetFrameworks, FeatureCount, FeatureScopes, FeatureIds,
        FeatureReceiverCount, SafeControlCount, TemplateFileCount, RootFileCount, DwpFileCount,
        SiteDefinitionCount, ElementSummary, FileCount, ExpandedSizeBytes, InFarm, FarmMatch,
        FarmSolutionName, FarmDeployed, FarmDeploymentState, FarmFeatureCount, Difference, Assemblies
        and Features.

        .EXAMPLE
        Get-SPSSolutionPackageInfo -Path D:\Packages -Recurse | Export-SPSSolutionPackageReport -OutputFolder D:\Inventory

        .EXAMPLE
        # Cross-check the packages with the solutions of the farm.
        $map = Get-SPSFarmSolutionMap
        Get-SPSSolutionPackageInfo -Path .\Contoso.Intranet.wsp -FarmSolutionMap $map
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [System.String[]]
        $Path,

        [Parameter()]
        [switch]
        $Recurse,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.Object[]]
        $FarmSolutionMap = @(),

        [Parameter()]
        [System.String[]]
        $KnownMicrosoftPublicKeyToken = @(),

        [Parameter()]
        [System.String[]]
        $KnownMicrosoftPrefix = @(),

        [Parameter()]
        [ValidateRange(1, 4096)]
        [System.Int32]
        $MaximumMegabyte = 512,

        [Parameter()]
        [System.String]
        $TemporaryFolder
    )

    begin {
        $target = [System.Collections.Generic.List[object]]::new()
        $microsoftToken = @(
            '71e9bce111e9429c'
            '31bf3856ad364e35'
            'b77a5c561934e089'
            'b03f5f7f11d50a3a'
        ) + @($KnownMicrosoftPublicKeyToken)
    }

    process {
        foreach ($entry in $Path) {
            if ([System.String]::IsNullOrWhiteSpace($entry)) {
                continue
            }
            $resolved = @(Resolve-Path -Path $entry -ErrorAction SilentlyContinue)
            if ($resolved.Count -eq 0) {
                $resolved = @(Resolve-Path -LiteralPath $entry -ErrorAction SilentlyContinue)
            }
            if ($resolved.Count -eq 0) {
                $target.Add([PSCustomObject]@{ Path = $entry; Source = 'Cabinet'; Problem = 'The path does not exist.' })
                continue
            }
            foreach ($item in $resolved) {
                $location = $item.ProviderPath
                if (Test-Path -LiteralPath $location -PathType Container) {
                    $hasManifest = @(Get-ChildItem -LiteralPath $location -File | Where-Object { $_.Name -ieq 'manifest.xml' }).Count -gt 0
                    if ($hasManifest) {
                        $target.Add([PSCustomObject]@{ Path = $location; Source = 'Folder'; Problem = '' })
                        continue
                    }
                    $found = @(Get-ChildItem -LiteralPath $location -File -Recurse:$Recurse |
                            Where-Object { $_.Extension -ieq '.wsp' -or $_.Extension -ieq '.cab' } |
                            Sort-Object -Property FullName)
                    if ($found.Count -eq 0) {
                        $target.Add([PSCustomObject]@{ Path = $location; Source = 'Folder'; Problem = 'The folder has no manifest.xml and no .wsp or .cab file.' })
                    }
                    foreach ($file in $found) {
                        $target.Add([PSCustomObject]@{ Path = $file.FullName; Source = 'Cabinet'; Problem = '' })
                    }
                }
                else {
                    $target.Add([PSCustomObject]@{ Path = $location; Source = 'Cabinet'; Problem = '' })
                }
            }
        }
    }

    end {
        $farm = @($FarmSolutionMap | Where-Object { $null -ne $_ })
        $workRoot = if ([System.String]::IsNullOrWhiteSpace($TemporaryFolder)) { [System.IO.Path]::GetTempPath() } else { $TemporaryFolder }
        $result = [System.Collections.Generic.List[object]]::new()

        foreach ($package in $target) {
            $name = [System.IO.Path]::GetFileName($package.Path.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
            if ($package.Problem) {
                $name = if ($name) { $name } else { $package.Path }
            }
            $record = [ordered]@{
                PackageName                    = $name
                PackagePath                    = $package.Path
                Source                         = $package.Source
                PackageSizeBytes               = $null
                Sha256                         = ''
                Status                         = 'Failed'
                Detail                         = ''
                SolutionId                     = ''
                SharePointProductVersion       = ''
                DeploymentServerType           = ''
                ResetWebServer                 = $null
                IsCustom                       = $null
                IsCustomSource                 = ''
                IsFullTrustCode                = $null
                ContainsGlobalAssembly         = $null
                ContainsWebApplicationAssembly = $null
                ContainsCasPolicy              = $null
                ContainsWebApplicationResource = $null
                AssemblyCount                  = 0
                CustomAssemblyCount            = 0
                UnsignedAssemblyCount          = 0
                LegacyFrameworkAssemblyCount   = 0
                TargetFrameworks               = @()
                FeatureCount                   = 0
                FeatureScopes                  = @()
                FeatureIds                     = @()
                FeatureReceiverCount           = 0
                SafeControlCount               = 0
                TemplateFileCount              = 0
                RootFileCount                  = 0
                DwpFileCount                   = 0
                SiteDefinitionCount            = 0
                ElementSummary                 = ''
                FileCount                      = 0
                ExpandedSizeBytes              = $null
                InFarm                         = $null
                FarmMatch                      = ''
                FarmSolutionName               = ''
                FarmDeployed                   = $null
                FarmDeploymentState            = ''
                FarmFeatureCount               = $null
                Difference                     = @()
                Assemblies                     = @()
                Features                       = @()
            }

            if ($package.Problem) {
                $record['Detail'] = $package.Problem
                $result.Add([PSCustomObject]$record)
                continue
            }

            $work = $null
            try {
                if ($package.Source -eq 'Cabinet') {
                    $file = Get-Item -LiteralPath $package.Path -ErrorAction Stop
                    $record['PackageSizeBytes'] = $file.Length
                    $record['Sha256'] = (Get-FileHash -LiteralPath $package.Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                    $work = Join-Path -Path $workRoot -ChildPath ('spswsp-' + [System.Guid]::NewGuid().ToString('N'))
                    $expanded = Expand-SPSSolutionPackage -Path $package.Path -WorkFolder $work -MaximumMegabyte $MaximumMegabyte
                    $root = $expanded.Path
                }
                else {
                    $root = $package.Path
                }

                $content = Get-SPSExpandedPackageInfo -Root $root -MicrosoftPublicKeyToken $microsoftToken
                if ($package.Source -eq 'Folder') {
                    $record['PackageSizeBytes'] = $content.ExpandedSizeBytes
                }

                $assembly = @($content.Assemblies)
                $judged = @($assembly | Where-Object { $_.Status -in @('Read', 'Partial', 'NotManaged') -and -not $_.IsSatellite })
                if ($judged.Count -gt 0) {
                    $isCustom = (@($judged | Where-Object { $_.IsCustom }).Count -gt 0)
                    $record['IsCustomSource'] = 'Assembly'
                }
                else {
                    $isCustom = -not (Test-SPSMicrosoftSolution -Name $name -ExtraMicrosoftPrefix $KnownMicrosoftPrefix)
                    $record['IsCustomSource'] = 'Name'
                }
                $custom = @($assembly | Where-Object { $_.IsCustom })

                $record['SolutionId'] = $content.SolutionId
                $record['SharePointProductVersion'] = $content.SharePointProductVersion
                $record['DeploymentServerType'] = $content.DeploymentServerType
                $record['ResetWebServer'] = $content.ResetWebServer
                $record['IsCustom'] = $isCustom
                $record['IsFullTrustCode'] = ($isCustom -and $content.ContainsGlobalAssembly)
                $record['ContainsGlobalAssembly'] = $content.ContainsGlobalAssembly
                $record['ContainsWebApplicationAssembly'] = $content.ContainsWebApplicationAssembly
                $record['ContainsCasPolicy'] = $content.ContainsCasPolicy
                $record['ContainsWebApplicationResource'] = $content.ContainsWebApplicationResource
                $record['AssemblyCount'] = $assembly.Count
                $record['CustomAssemblyCount'] = $custom.Count
                $record['UnsignedAssemblyCount'] = @($assembly | Where-Object { $_.IsManaged -and -not $_.IsSigned }).Count
                $record['LegacyFrameworkAssemblyCount'] = @($custom | Where-Object { $_.BuiltForLegacyFramework }).Count
                $record['TargetFrameworks'] = @($content.TargetFrameworks)
                $record['FeatureCount'] = $content.FeatureCount
                $record['FeatureScopes'] = @($content.FeatureScopes)
                $record['FeatureIds'] = @($content.FeatureIds)
                $record['FeatureReceiverCount'] = $content.FeatureReceiverCount
                $record['SafeControlCount'] = $content.SafeControlCount
                $record['TemplateFileCount'] = $content.TemplateFileCount
                $record['RootFileCount'] = $content.RootFileCount
                $record['DwpFileCount'] = $content.DwpFileCount
                $record['SiteDefinitionCount'] = $content.SiteDefinitionCount
                $record['ElementSummary'] = $content.ElementSummary
                $record['FileCount'] = $content.FileCount
                $record['ExpandedSizeBytes'] = $content.ExpandedSizeBytes
                $record['Assemblies'] = $assembly
                $record['Features'] = @($content.Features)

                $problem = @($content.Problems)
                if ($problem.Count -gt 0) {
                    $record['Status'] = 'Partial'
                    $record['Detail'] = (@($problem | Select-Object -First 5) -join ' | ') + $(if ($problem.Count -gt 5) { " | and $($problem.Count - 5) more" } else { '' })
                }
                else {
                    $record['Status'] = 'Inspected'
                }

                if ($farm.Count -gt 0) {
                    $match = $null
                    $how = ''
                    if ($record['SolutionId']) {
                        $match = $farm | Where-Object { ([System.String]$_.SolutionId).Trim().ToLowerInvariant() -eq $record['SolutionId'] } | Select-Object -First 1
                        if ($null -ne $match) { $how = 'SolutionId' }
                    }
                    if ($null -eq $match) {
                        $match = $farm | Where-Object { ([System.String]$_.SolutionName) -ieq $name } | Select-Object -First 1
                        if ($null -ne $match) { $how = 'Name' }
                    }
                    $record['InFarm'] = ($null -ne $match)
                    $record['FarmMatch'] = $how
                    if ($null -ne $match) {
                        $record['FarmSolutionName'] = [System.String]$match.SolutionName
                        $record['FarmDeployed'] = [System.Boolean]$match.Deployed
                        $record['FarmDeploymentState'] = [System.String]$match.DeploymentState
                        $record['FarmFeatureCount'] = [System.Int32]$match.FeatureCount
                        $difference = [System.Collections.Generic.List[string]]::new()
                        if ([System.Int32]$match.FeatureCount -ne $content.FeatureCount) {
                            $difference.Add("The farm lists $([System.Int32]$match.FeatureCount) feature(s), the package ships $($content.FeatureCount).")
                        }
                        if ([System.Boolean]$match.ContainsGlobalAssembly -ne [System.Boolean]$content.ContainsGlobalAssembly) {
                            $difference.Add("The farm says the solution deploys a global assembly: $([System.Boolean]$match.ContainsGlobalAssembly); the package: $([System.Boolean]$content.ContainsGlobalAssembly).")
                        }
                        if ([System.Boolean]$match.ContainsCasPolicy -ne [System.Boolean]$content.ContainsCasPolicy) {
                            $difference.Add("The farm says the solution has a code access security policy: $([System.Boolean]$match.ContainsCasPolicy); the package: $([System.Boolean]$content.ContainsCasPolicy).")
                        }
                        if ([System.Boolean]$match.IsCustom -ne $isCustom) {
                            $difference.Add("The farm classifies the solution as custom: $([System.Boolean]$match.IsCustom); the assemblies of the package: $isCustom.")
                        }
                        $record['Difference'] = $difference.ToArray()
                    }
                }
            }
            catch {
                $record['Status'] = 'Failed'
                $record['Detail'] = $_.Exception.Message
            }
            finally {
                # A scanner can hold a file for a moment: try a few times before giving up.
                for ($attempt = 1; $null -ne $work -and $attempt -le 3 -and (Test-Path -LiteralPath $work); $attempt++) {
                    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
                    if (Test-Path -LiteralPath $work) {
                        Start-Sleep -Milliseconds 250
                    }
                }
                if ($null -ne $work -and (Test-Path -LiteralPath $work)) {
                    Write-Warning -Message "The temporary folder '$work' could not be removed."
                }
            }
            $result.Add([PSCustomObject]$record)
        }

        return $result.ToArray()
    }
}
