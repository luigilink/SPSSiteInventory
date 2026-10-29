# Behavior tests for Get-SPSModernReadiness (pure summary of the blockers of the modern experience, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function Get-Readiness {
        param ([object[]]$Record, [int]$MaxSite = 0)
        & $script:Module { param ($Rows, $Max) if ($Max -gt 0) { Get-SPSModernReadiness -InputObject $Rows -MaxSite $Max } else { Get-SPSModernReadiness -InputObject $Rows } } $Record $MaxSite
    }

    function New-Site {
        param ([string]$Name, [hashtable]$Signals = @{}, [string]$Status = 'Complete', [double]$Score = 0, [int]$Category = 1)
        $record = [PSCustomObject]@{
            InventoryScope = 'SiteCollection'; Url = "https://intranet/sites/$Name"; Title = $Name
            AssessmentStatus = $Status; Category = $Category; CategoryName = "Category $Category"; Score = $Score
        }
        foreach ($key in $Signals.Keys) { $record | Add-Member -NotePropertyName $key -NotePropertyValue $Signals[$key] -Force }
        return $record
    }
}

Describe 'Get-SPSModernReadiness' {
    It 'gives every kind of blocker, in a fixed order, also when no site collection has one' {
        $result = Get-Readiness -Record @((New-Site -Name 'a'))

        @($result.Kind.Name) | Should -Be @('CustomMasterPage', 'AlternateCssUrl', 'Publishing', 'XsltListView', 'ScriptWebPart', 'ClassicExperienceOptOut', 'ClassicExperienceList')
        @($result.Kind.Label) | Should -Be @('Custom master page', 'Alternate CSS URL', 'Publishing features', 'XSLT list views', 'Script web parts', 'Opted out of modern lists', 'Lists forced to classic')
        foreach ($kind in $result.Kind) {
            $kind.SiteCount | Should -Be 0
        }
        $result.WithBlocker | Should -Be 0
        $result.Assessed | Should -Be 1
        @($result.Site) | Should -HaveCount 0
        $result.SiteTotal | Should -Be 0
    }

    It 'counts the site collections that have each kind, and the items behind it' {
        $result = Get-Readiness -Record @(
            (New-Site -Name 'a' -Signals @{ CustomMasterPage = $true; XsltListViewCount = 3; ScriptWebPartCount = 1 })
            (New-Site -Name 'b' -Signals @{ XsltListViewCount = 2; PublishingInfrastructureEnabled = $true; PublishingWebCount = 4 })
            (New-Site -Name 'c' -Signals @{ AlternateCssUrlCount = 5; ClassicExperienceOptOutCount = 1; ClassicExperienceListCount = 2 })
            (New-Site -Name 'd')
        )

        $kind = @{}
        foreach ($row in $result.Kind) { $kind[$row.Name] = $row }
        $kind['CustomMasterPage'].SiteCount | Should -Be 1
        $kind['CustomMasterPage'].Items | Should -BeNullOrEmpty
        $kind['XsltListView'].SiteCount | Should -Be 2
        $kind['XsltListView'].Items | Should -Be 5
        $kind['XsltListView'].Unit | Should -Be 'view(s)'
        $kind['ScriptWebPart'].SiteCount | Should -Be 1
        $kind['Publishing'].SiteCount | Should -Be 1
        $kind['Publishing'].Items | Should -Be 4
        $kind['AlternateCssUrl'].Items | Should -Be 5
        $kind['ClassicExperienceOptOut'].SiteCount | Should -Be 1
        $kind['ClassicExperienceList'].Items | Should -Be 2
        $result.Assessed | Should -Be 4
        $result.WithBlocker | Should -Be 3
        $result.SiteTotal | Should -Be 3
    }

    It 'lists the site collections with the most kinds first, then the highest score, then by URL' {
        $result = Get-Readiness -Record @(
            (New-Site -Name 'one-kind-high' -Score 9 -Signals @{ XsltListViewCount = 9 })
            (New-Site -Name 'two-kinds-low' -Score 1 -Signals @{ XsltListViewCount = 1; ScriptWebPartCount = 1 })
            (New-Site -Name 'two-kinds-high' -Score 5 -Signals @{ XsltListViewCount = 1; ScriptWebPartCount = 1 })
            (New-Site -Name 'a-one-kind-low' -Score 1 -Signals @{ XsltListViewCount = 1 })
            (New-Site -Name 'b-one-kind-low' -Score 1 -Signals @{ XsltListViewCount = 1 })
        )

        @($result.Site.Url) | Should -Be @(
            'https://intranet/sites/two-kinds-high', 'https://intranet/sites/two-kinds-low'
            'https://intranet/sites/one-kind-high', 'https://intranet/sites/a-one-kind-low', 'https://intranet/sites/b-one-kind-low'
        )
        $result.Site[0].Count | Should -Be 2
        $result.Site[0].Text | Should -Be 'XSLT list views (1); Script web parts (1)'
    }

    It 'cuts the list at MaxSite and says how many site collections have a blocker' {
        $records = 1..5 | ForEach-Object { New-Site -Name ('s{0}' -f $_) -Signals @{ ScriptWebPartCount = $_ } }

        $result = Get-Readiness -Record $records -MaxSite 2

        @($result.Site) | Should -HaveCount 2
        $result.SiteTotal | Should -Be 5
        $result.WithBlocker | Should -Be 5
        ($result.Kind | Where-Object Name -eq 'ScriptWebPart').SiteCount | Should -Be 5
    }

    It 'lists 100 site collections by default' {
        $records = 1..120 | ForEach-Object { New-Site -Name ('s{0:000}' -f $_) -Signals @{ ScriptWebPartCount = 1 } }

        $result = Get-Readiness -Record $records

        @($result.Site) | Should -HaveCount 100
        $result.SiteTotal | Should -Be 120
    }

    It 'counts a failed assessment apart, without looking at its fields, and ignores the web application rows' {
        $failed = New-Site -Name 'failed' -Status 'Failed' -Signals @{ XsltListViewCount = $null; CustomMasterPage = $null }
        $webApp = [PSCustomObject]@{ InventoryScope = 'WebApplication'; Url = 'https://intranet'; AssessmentStatus = 'Failed' }

        $result = Get-Readiness -Record @($failed, $webApp, (New-Site -Name 'ok' -Signals @{ XsltListViewCount = 1 }))

        $result.NotAssessed | Should -Be 1
        $result.Assessed | Should -Be 1
        $result.WithBlocker | Should -Be 1
    }

    It 'reports a partial assessment with its status, so that the report can say that its counts are lower bounds' {
        $result = Get-Readiness -Record @((New-Site -Name 'partial' -Status 'Partial' -Signals @{ ScriptWebPartCount = 1 }))

        $result.Site[0].AssessmentStatus | Should -Be 'Partial'
        $result.Assessed | Should -Be 1
    }

    It 'reads a record that does not have the fields of the modern experience as one without blockers' {
        $old = [PSCustomObject]@{ InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/old'; AssessmentStatus = 'Complete'; Category = 1 }

        $result = Get-Readiness -Record @($old)

        $result.Assessed | Should -Be 1
        $result.WithBlocker | Should -Be 0
    }

    It 'handles an empty inventory' {
        $result = Get-Readiness -Record @()

        $result.Assessed | Should -Be 0
        $result.WithBlocker | Should -Be 0
        @($result.Kind) | Should -HaveCount 7
    }

    It 'rejects a list size that is not a positive number' {
        { & $script:Module { Get-SPSModernReadiness -InputObject @() -MaxSite 0 } } | Should -Throw
    }
}
