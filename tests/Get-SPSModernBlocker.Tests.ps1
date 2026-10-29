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
}
