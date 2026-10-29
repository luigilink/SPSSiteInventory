# Behavior tests for Get-SPSModernBlocker (pure aggregation of the modern-readiness signals, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function Get-Blocker {
        param ([hashtable]$Signals)
        & $script:Module { param ($Value) Get-SPSModernBlocker -Signals $Value } $Signals
    }
}

Describe 'Get-SPSModernBlocker' {
    It 'reports nothing for a site collection without any blocker' {
        $result = Get-Blocker -Signals @{
            CustomMasterPage = $false; AlternateCssUrlCount = 0; PublishingInfrastructureEnabled = $false; PublishingWebCount = 0
            XsltListViewCount = 0; ScriptWebPartCount = 0; ClassicExperienceOptOutCount = 0; ClassicExperienceListCount = 0
        }

        $result.Count | Should -Be 0
        @($result.Names) | Should -HaveCount 0
        $result.Summary | Should -Be ''
    }

    It 'treats missing and null signals as 0' {
        (Get-Blocker -Signals @{}).Count | Should -Be 0
        (Get-Blocker -Signals @{ XsltListViewCount = $null; CustomMasterPage = $null }).Count | Should -Be 0
    }

    It 'counts the kinds of blocker, not the number of items behind each' {
        $result = Get-Blocker -Signals @{ XsltListViewCount = 40; ScriptWebPartCount = 12 }

        $result.Count | Should -Be 2
        @($result.Names) | Should -Be @('XsltListView', 'ScriptWebPart')
    }

    It 'reports each kind with what is behind it' {
        $result = Get-Blocker -Signals @{
            CustomMasterPage = $true
            AlternateCssUrlCount = 2
            PublishingInfrastructureEnabled = $true
            PublishingWebCount = 3
            XsltListViewCount = 4
            ScriptWebPartCount = 5
            ClassicExperienceOptOutCount = 2
            ClassicExperienceListCount = 1
        }

        $result.Count | Should -Be 7
        @($result.Names) | Should -Be @('CustomMasterPage', 'AlternateCssUrl', 'Publishing', 'XsltListView', 'ScriptWebPart', 'ClassicExperienceOptOut', 'ClassicExperienceList')
        $result.Summary | Should -Be 'Custom master page; Alternate CSS URL (2 webs); Publishing features (3 webs); XSLT list views (4); Script web parts (5); Opted out of modern lists (2); Lists forced to classic (1)'
    }

    It 'uses the singular for one web' {
        (Get-Blocker -Signals @{ AlternateCssUrlCount = 1 }).Summary | Should -Be 'Alternate CSS URL (1 web)'
        (Get-Blocker -Signals @{ PublishingWebCount = 1 }).Summary | Should -Be 'Publishing features (1 web)'
    }

    It 'reports the publishing feature of the site collection alone, without a count of webs' {
        $result = Get-Blocker -Signals @{ PublishingInfrastructureEnabled = $true; PublishingWebCount = 0 }

        $result.Count | Should -Be 1
        $result.Summary | Should -Be 'Publishing features'
    }

    It 'reports publishing once, whether the site collection feature, the web feature or both are active' {
        (Get-Blocker -Signals @{ PublishingWebCount = 2 }).Count | Should -Be 1
        (Get-Blocker -Signals @{ PublishingInfrastructureEnabled = $true; PublishingWebCount = 2 }).Count | Should -Be 1
    }

    It 'reads the booleans of the signals' {
        (Get-Blocker -Signals @{ CustomMasterPage = $true }).Summary | Should -Be 'Custom master page'
        (Get-Blocker -Signals @{ CustomMasterPage = $false }).Count | Should -Be 0
    }

    It 'returns a count and the names as a list, also for one kind' {
        $result = Get-Blocker -Signals @{ ScriptWebPartCount = 1 }

        $result.Count | Should -BeOfType [int]
        @($result.Names) | Should -HaveCount 1
        $result.Summary | Should -BeOfType [string]
    }

    It 'rejects a call without signals' {
        { & $script:Module { Get-SPSModernBlocker -Signals $null } } | Should -Throw
    }

    It 'gives one object per kind found, with its label, its items and its unit, and the text of the summary' {
        $result = Get-Blocker -Signals @{
            CustomMasterPage = $true; AlternateCssUrlCount = 2; PublishingWebCount = 3; XsltListViewCount = 4
            ScriptWebPartCount = 1; ClassicExperienceOptOutCount = 2; ClassicExperienceListCount = 6
        }

        @($result.Kind) | Should -HaveCount 7
        @($result.Kind.Name) | Should -Be @($result.Names)
        (@($result.Kind.Text) -join '; ') | Should -Be $result.Summary
        $master = $result.Kind | Where-Object Name -eq 'CustomMasterPage'
        $master.Label | Should -Be 'Custom master page'
        $master.Items | Should -BeNullOrEmpty
        $master.Unit | Should -Be ''
        $css = $result.Kind | Where-Object Name -eq 'AlternateCssUrl'
        $css.Label | Should -Be 'Alternate CSS URL'
        $css.Items | Should -Be 2
        $css.Unit | Should -Be 'web(s)'
        ($result.Kind | Where-Object Name -eq 'Publishing').Items | Should -Be 3
        ($result.Kind | Where-Object Name -eq 'XsltListView').Unit | Should -Be 'view(s)'
        ($result.Kind | Where-Object Name -eq 'ScriptWebPart').Unit | Should -Be 'web part(s)'
        ($result.Kind | Where-Object Name -eq 'ClassicExperienceOptOut').Items | Should -Be 2
        ($result.Kind | Where-Object Name -eq 'ClassicExperienceList').Label | Should -Be 'Lists forced to classic'
    }

    It 'gives no kind, and no items for a publishing site collection that has no webs with the feature, when nothing is found' {
        @((Get-Blocker -Signals @{}).Kind) | Should -HaveCount 0
        ((Get-Blocker -Signals @{ PublishingInfrastructureEnabled = $true }).Kind | Where-Object Name -eq 'Publishing').Items | Should -Be 0
    }
}
