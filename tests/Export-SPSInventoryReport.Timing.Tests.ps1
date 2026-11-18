# The manifest of Export-SPSInventoryReport gives the durations of the scan that the orchestrator measured, as they are given. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    $script:Site = [PSCustomObject]@{
        InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/team'; Title = 'Team'; WebApp = 'Intranet'
        AssessmentStatus = 'Complete'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; Score = 0; Reasons = ''
    }

    function New-Timing {
        param ([int]$Phases = 2, [int]$Sites = 2)
        [PSCustomObject]@{
            StartedAt = '2026-11-18T09:00:00.0000000+01:00'
            ScanSeconds = 1144.3
            # 1..0 is the list 1, 0 in PowerShell, so a count of 0 is a list of nothing.
            Phase = @(if ($Phases -gt 0) { 1..$Phases | ForEach-Object { [PSCustomObject]@{ Name = "Phase $_"; Seconds = 10.5 * $_ } } })
            Site = @(if ($Sites -gt 0) { 1..$Sites | ForEach-Object { [PSCustomObject]@{ Url = "https://intranet/sites/s$_"; Seconds = 3.2 * $_; AssessmentStatus = $(if ($_ -eq 2) { 'Failed' } else { 'Complete' }) } } })
        }
    }
}

Describe 'Export-SPSInventoryReport and the durations of the scan' {
    It 'puts the new parameter after the ones that it already had, because none has a position and they are positional in the order of declaration' {
        $common = @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ProgressAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable', 'WhatIf', 'Confirm')
        $name = @((Get-Command -Name Export-SPSInventoryReport).Parameters.Keys | Where-Object { $common -notcontains $_ })
        $before = @(
            'InputObject', 'OutputFolder', 'BaseName', 'EnvName', 'SolutionMap', 'ContentTypes', 'ManagedMetadataLists', 'ExternalLists', 'SharePointAlerts',
            'BcsApplications', 'BcsInventoryComplete', 'SecureStoreApplications', 'SecureStoreInventoryComplete', 'ProfilePropertyMappings', 'ProfileInventoryComplete',
            'SolutionJsonPath', 'ExcludedPersonalSiteCount', 'ExcludedSiteMasterCount', 'HtmlSplitThreshold', 'HtmlRowsPerPage', 'TargetMode', 'SolutionPackages', 'EventReceiverClasses', 'WorkflowAssociations'
        )

        @($name[0..($before.Count - 1)]) | Should -BeExactly $before
        $name[$before.Count] | Should -BeExactly 'Timing'
    }

    It 'writes the durations in the manifest as they are given: the start, the seconds of the scan, each phase and each site collection' {
        $output = Export-SPSInventoryReport -InputObject @($script:Site) -Timing (New-Timing) -OutputFolder (Join-Path $TestDrive 'a') -BaseName 'T'

        $manifest = Get-Content -Path $output.ManifestJsonPath -Raw | ConvertFrom-Json
        $manifest.Timing.StartedAt | Should -Not -BeNullOrEmpty
        ([datetimeoffset]$manifest.Timing.StartedAt).Year | Should -Be 2026
        $manifest.Timing.ScanSeconds | Should -Be 1144.3
        @($manifest.Timing.Phase) | Should -HaveCount 2
        $manifest.Timing.Phase[0].Name | Should -BeExactly 'Phase 1'
        $manifest.Timing.Phase[1].Seconds | Should -Be 21
        @($manifest.Timing.Site) | Should -HaveCount 2
        $manifest.Timing.Site[0].Url | Should -BeExactly 'https://intranet/sites/s1'
        $manifest.Timing.Site[0].Seconds | Should -Be 3.2
        $manifest.Timing.Site[1].AssessmentStatus | Should -BeExactly 'Failed'
    }

    It 'keeps a single phase and a single site collection as lists in the JSON' {
        $output = Export-SPSInventoryReport -InputObject @($script:Site) -Timing (New-Timing -Phases 1 -Sites 1) -OutputFolder (Join-Path $TestDrive 'b') -BaseName 'One'

        $text = Get-Content -Path $output.ManifestJsonPath -Raw
        $text | Should -Match '"Phase":\s*\['
        $text | Should -Match '"Site":\s*\['
    }

    It 'writes an empty list of site collections as a list' {
        $output = Export-SPSInventoryReport -InputObject @($script:Site) -Timing (New-Timing -Phases 1 -Sites 0) -OutputFolder (Join-Path $TestDrive 'c') -BaseName 'None'

        (Get-Content -Path $output.ManifestJsonPath -Raw) | Should -Match '"Site":\s*\[\s*\]'
    }

    It 'writes Timing as null without the parameter, and changes nothing else in the manifest' {
        $without = Export-SPSInventoryReport -InputObject @($script:Site) -OutputFolder (Join-Path $TestDrive 'd') -BaseName 'W'
        $with = Export-SPSInventoryReport -InputObject @($script:Site) -Timing (New-Timing) -OutputFolder (Join-Path $TestDrive 'e') -BaseName 'W'

        $manifestWithout = Get-Content -Path $without.ManifestJsonPath -Raw | ConvertFrom-Json
        $manifestWith = Get-Content -Path $with.ManifestJsonPath -Raw | ConvertFrom-Json
        @($manifestWithout.PSObject.Properties.Name) | Should -Contain 'Timing'
        $manifestWithout.Timing | Should -BeNullOrEmpty
        @($manifestWith.PSObject.Properties.Name) | Should -Be @($manifestWithout.PSObject.Properties.Name)
        $manifestWith.ReportPackVersion | Should -Be '1.0'
        $manifestWith.Summary.SiteCollections | Should -Be 1
        $manifestWith.Files.InventoryCsv | Should -Not -BeNullOrEmpty
    }
}
