# The target mode changes the words of the scoring, never the arithmetic: the same signals give the same score and the
# same category number in both modes. What a signal is worth is the Scoring section, which each mode's example ships.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Online = Get-SPSInventorySetting -Path (Join-Path $repoRoot 'src/config/inventory-settings.example.psd1')
    $script:OnPrem = Get-SPSInventorySetting -Path (Join-Path $repoRoot 'src/config/inventory-settings.onprem.example.psd1')
    $script:Scoring = @{
        Weights         = @{ Workflow2010Count = 3.0; SubsiteCount = 0.5 }
        Thresholds      = @{ Moderate = 1.0; Complex = 6.0 }
        BlockingSignals = @('InfoPathFormCount')
    }

    function Measure-Mode {
        param ([hashtable]$Signals, [hashtable]$Scoring, [string]$Mode)
        if ($Mode) { Measure-SPSSiteComplexity -Signals $Signals -Scoring $Scoring -TargetMode $Mode }
        else { Measure-SPSSiteComplexity -Signals $Signals -Scoring $Scoring }
    }
}

Describe 'Measure-SPSSiteComplexity and the target mode' {
    It 'names the categories as it always did when the mode is not given' {
        (Measure-Mode -Signals @{} -Scoring $script:Scoring).CategoryName | Should -Be 'Simple'
        (Measure-Mode -Signals @{ SubsiteCount = 3 } -Scoring $script:Scoring).CategoryName | Should -Be 'Moderate'
        (Measure-Mode -Signals @{ Workflow2010Count = 2 } -Scoring $script:Scoring).CategoryName | Should -Be 'Complex'
        (Measure-Mode -Signals @{ InfoPathFormCount = 1 } -Scoring $script:Scoring).CategoryName | Should -Be 'Blocking'
    }

    It 'gives the same names with SharePointOnline as without a mode' {
        foreach ($signals in @(@{}, @{ SubsiteCount = 3 }, @{ Workflow2010Count = 2 }, @{ InfoPathFormCount = 1 })) {
            $without = Measure-Mode -Signals $signals -Scoring $script:Scoring
            $with = Measure-Mode -Signals $signals -Scoring $script:Scoring -Mode 'SharePointOnline'

            $with.CategoryName | Should -Be $without.CategoryName
        }
    }

    It 'names the categories after the modernization with SharePointOnPrem' {
        (Measure-Mode -Signals @{} -Scoring $script:Scoring -Mode 'SharePointOnPrem').CategoryName | Should -Be 'Modern-ready'
        (Measure-Mode -Signals @{ SubsiteCount = 3 } -Scoring $script:Scoring -Mode 'SharePointOnPrem').CategoryName | Should -Be 'Light remediation'
        (Measure-Mode -Signals @{ Workflow2010Count = 2 } -Scoring $script:Scoring -Mode 'SharePointOnPrem').CategoryName | Should -Be 'Rebuild (SPFx)'
        (Measure-Mode -Signals @{ InfoPathFormCount = 1 } -Scoring $script:Scoring -Mode 'SharePointOnPrem').CategoryName | Should -Be 'Blocked'
    }

    It 'gives the same score, the same category number and the same reasons in both modes' {
        foreach ($signals in @(@{}, @{ SubsiteCount = 3 }, @{ Workflow2010Count = 2 }, @{ InfoPathFormCount = 1; Workflow2010Count = 1 })) {
            $online = Measure-Mode -Signals $signals -Scoring $script:Scoring -Mode 'SharePointOnline'
            $onPrem = Measure-Mode -Signals $signals -Scoring $script:Scoring -Mode 'SharePointOnPrem'

            $onPrem.Score | Should -Be $online.Score
            $onPrem.Category | Should -Be $online.Category
            @($onPrem.Reasons) | Should -Be @($online.Reasons)
        }
    }

    It 'refuses a mode that is not one of the two, as the settings loader does' {
        { Measure-Mode -Signals @{} -Scoring $script:Scoring -Mode 'OnPrem' } | Should -Throw "TargetMode must be 'SharePointOnline' or 'SharePointOnPrem'."
    }
}

Describe 'The on-premises example scoring' {
    It 'does not block on full-trust code or on a custom farm feature, which SPFx replaces, but weighs them heavily' {
        foreach ($signal in 'UsesFullTrustCode', 'UsesCustomFarmFeature') {
            $result = Measure-Mode -Signals @{ $signal = $true } -Scoring $script:OnPrem.Scoring -Mode 'SharePointOnPrem'

            $result.Category | Should -BeLessThan 4
            $result.Score | Should -BeGreaterThan 0
        }
    }

    It 'puts a site that has full-trust code and a custom feature in Rebuild (SPFx), which the same site is Blocking in the migration example' {
        $signals = @{ UsesFullTrustCode = $true; UsesCustomFarmFeature = $true }

        (Measure-Mode -Signals $signals -Scoring $script:OnPrem.Scoring -Mode 'SharePointOnPrem').CategoryName | Should -Be 'Rebuild (SPFx)'
        (Measure-Mode -Signals $signals -Scoring $script:Online.Scoring).CategoryName | Should -Be 'Blocking'
    }

    It 'does not penalise what belongs to a migration and not to the modernization of the farm' {
        foreach ($signals in @(
                @{ HasFbaZone = $true }
                @{ ExternalListCount = 3 }
                @{ IsUnsupportedSiteTemplate = $true }
                @{ IrmEnabledListCount = 2 }
                @{ IsLockedSite = $true; HasNoAccessLock = $true; SiteLockState = 'NoAccess' }
                @{ SubsiteCount = 100; MaxSubsiteDepth = 6 }
                @{ EmailEnabledListCount = 4 }
                @{ ManagedMetadataListCount = 5; ManagedMetadataTermSetCount = 5 }
            )) {
            $result = Measure-Mode -Signals $signals -Scoring $script:OnPrem.Scoring -Mode 'SharePointOnPrem'

            $result.CategoryName | Should -Be 'Modern-ready' -Because ('{0} is not a modernization cost' -f (($signals.Keys | Sort-Object) -join ', '))
        }
    }

    It 'keeps the same signals as migration blockers in the migration example' {
        foreach ($signals in @(@{ HasFbaZone = $true }, @{ ExternalListCount = 3 }, @{ IsUnsupportedSiteTemplate = $true }, @{ UsesFullTrustCode = $true })) {
            (Measure-Mode -Signals $signals -Scoring $script:Online.Scoring).CategoryName | Should -Be 'Blocking'
        }
    }

    It 'blocks a form that has no modern editor, and rebuilds what the modern experience cannot run' {
        (Measure-Mode -Signals @{ InfoPathFormCount = 1 } -Scoring $script:OnPrem.Scoring -Mode 'SharePointOnPrem').CategoryName | Should -Be 'Blocked'
        (Measure-Mode -Signals @{ Workflow2010Count = 2 } -Scoring $script:OnPrem.Scoring -Mode 'SharePointOnPrem').CategoryName | Should -Be 'Rebuild (SPFx)'
        (Measure-Mode -Signals @{ PublishingInfrastructureEnabled = $true; PublishingWebCount = 4; CustomizedPageCount = 6 } -Scoring $script:OnPrem.Scoring -Mode 'SharePointOnPrem').CategoryName | Should -Be 'Rebuild (SPFx)'
        (Measure-Mode -Signals @{ SandboxSolutions = 1; CustomMasterPage = $true } -Scoring $script:OnPrem.Scoring -Mode 'SharePointOnPrem').CategoryName | Should -Be 'Rebuild (SPFx)'
    }

    It 'puts a site without any signal in Modern-ready' {
        (Measure-Mode -Signals @{} -Scoring $script:OnPrem.Scoring -Mode 'SharePointOnPrem').CategoryName | Should -Be 'Modern-ready'
    }

    It 'reads the thresholds of its own file, which are the ones of the migration example' {
        $script:OnPrem.Scoring.Thresholds.Moderate | Should -Be $script:Online.Scoring.Thresholds.Moderate
        $script:OnPrem.Scoring.Thresholds.Complex | Should -Be $script:Online.Scoring.Thresholds.Complex
    }
}
