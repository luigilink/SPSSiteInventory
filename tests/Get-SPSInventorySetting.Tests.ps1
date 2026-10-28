# Behavior tests for Get-SPSInventorySetting.
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
}

Describe 'Get-SPSInventorySetting' {
    It 'loads a valid settings file and returns a hashtable with a Scoring section' {
        $path = Join-Path $TestDrive 'inventory-settings.psd1'
        @'
@{
    EnvName = 'TEST'
    Scoring = @{
        Weights = @{ SandboxSolutions = 3.0 }
        Thresholds = @{ Moderate = 1.0; Complex = 6.0 }
        BlockingSignals = @('UsesCustomFarmFeature')
    }
}
'@ | Set-Content -Path $path -Encoding UTF8

        $settings = Get-SPSInventorySetting -Path $path

        $settings | Should -BeOfType [hashtable]
        $settings.EnvName | Should -Be 'TEST'
        $settings.Scoring.Thresholds.Complex | Should -Be 6.0
    }

    It 'throws when the file does not exist' {
        $missing = Join-Path $TestDrive 'does-not-exist.psd1'

        { Get-SPSInventorySetting -Path $missing } | Should -Throw
    }

    It 'accepts a SharePointAlerts section that turns the owner logins off, or no section at all' {
        $path = Join-Path $TestDrive 'alerts-off.psd1'
        @'
@{
    Scoring = @{ Weights = @{}; Thresholds = @{ Moderate = 1.0; Complex = 6.0 }; BlockingSignals = @() }
    SharePointAlerts = @{ IncludeUserLogin = $false }
}
'@ | Set-Content -Path $path -Encoding UTF8

        $settings = Get-SPSInventorySetting -Path $path

        $settings.SharePointAlerts.IncludeUserLogin | Should -BeFalse
    }

    It 'rejects a SharePointAlerts.IncludeUserLogin that is not a boolean, naming the file' {
        $path = Join-Path $TestDrive 'alerts-string.psd1'
        @'
@{
    Scoring = @{ Weights = @{}; Thresholds = @{ Moderate = 1.0; Complex = 6.0 }; BlockingSignals = @() }
    SharePointAlerts = @{ IncludeUserLogin = 'false' }
}
'@ | Set-Content -Path $path -Encoding UTF8

        { Get-SPSInventorySetting -Path $path } | Should -Throw -ExpectedMessage "*alerts-string.psd1*SharePointAlerts.IncludeUserLogin must be `$true or `$false*"
    }

    It 'rejects a SharePointAlerts section that is not a hashtable' {
        $path = Join-Path $TestDrive 'alerts-array.psd1'
        @'
@{
    Scoring = @{ Weights = @{}; Thresholds = @{ Moderate = 1.0; Complex = 6.0 }; BlockingSignals = @() }
    SharePointAlerts = @('IncludeUserLogin')
}
'@ | Set-Content -Path $path -Encoding UTF8

        { Get-SPSInventorySetting -Path $path } | Should -Throw -ExpectedMessage "*alerts-array.psd1*'SharePointAlerts' section must be a hashtable*"
    }

    It 'accepts a Scope section that keeps both kinds of site collections, or no section at all' {
        $path = Join-Path $TestDrive 'scope-on.psd1'
        @'
@{
    Scoring = @{ Weights = @{}; Thresholds = @{ Moderate = 1.0; Complex = 6.0 }; BlockingSignals = @() }
    Scope = @{ IncludePersonalSites = $true; IncludeSiteMasters = $true }
}
'@ | Set-Content -Path $path -Encoding UTF8

        $settings = Get-SPSInventorySetting -Path $path

        $settings.Scope.IncludePersonalSites | Should -BeTrue
        $settings.Scope.IncludeSiteMasters | Should -BeTrue

        $without = Join-Path $TestDrive 'scope-absent.psd1'
        @'
@{
    Scoring = @{ Weights = @{}; Thresholds = @{ Moderate = 1.0; Complex = 6.0 }; BlockingSignals = @() }
}
'@ | Set-Content -Path $without -Encoding UTF8

        (Get-SPSInventorySetting -Path $without).ContainsKey('Scope') | Should -BeFalse
    }

    It 'rejects a Scope option that is not a boolean, naming the file, before any site is read' -ForEach @(
        @{ Name = 'IncludePersonalSites'; Literal = "'false'" }
        @{ Name = 'IncludeSiteMasters'; Literal = '0' }
        @{ Name = 'IncludeSiteMasters'; Literal = "'yes'" }
    ) {
        $path = Join-Path $TestDrive 'scope-invalid.psd1'
        @"
@{
    Scoring = @{ Weights = @{}; Thresholds = @{ Moderate = 1.0; Complex = 6.0 }; BlockingSignals = @() }
    Scope = @{ $Name = $Literal }
}
"@ | Set-Content -Path $path -Encoding UTF8

        { Get-SPSInventorySetting -Path $path } | Should -Throw -ExpectedMessage "*scope-invalid.psd1*Scope.$Name must be `$true or `$false*"
    }

    It 'rejects a Scope section that is not a hashtable' {
        $path = Join-Path $TestDrive 'scope-array.psd1'
        @'
@{
    Scoring = @{ Weights = @{}; Thresholds = @{ Moderate = 1.0; Complex = 6.0 }; BlockingSignals = @() }
    Scope = @('IncludePersonalSites')
}
'@ | Set-Content -Path $path -Encoding UTF8

        { Get-SPSInventorySetting -Path $path } | Should -Throw -ExpectedMessage "*scope-array.psd1*'Scope' section must be a hashtable*"
    }

    It 'accepts a Report section, or no section at all' {
        $path = Join-Path $TestDrive 'report-valid.psd1'
        @'
@{
    Scoring = @{ Weights = @{}; Thresholds = @{ Moderate = 1.0; Complex = 6.0 }; BlockingSignals = @() }
    Report = @{ HtmlSplitThreshold = 0; HtmlRowsPerPage = 1000 }
}
'@ | Set-Content -Path $path -Encoding UTF8

        $settings = Get-SPSInventorySetting -Path $path

        $settings.Report.HtmlSplitThreshold | Should -Be 0
        $settings.Report.HtmlRowsPerPage | Should -Be 1000
        $without = Join-Path $TestDrive 'report-absent.psd1'
        @'
@{
    Scoring = @{ Weights = @{}; Thresholds = @{ Moderate = 1.0; Complex = 6.0 }; BlockingSignals = @() }
}
'@ | Set-Content -Path $without -Encoding UTF8

        (Get-SPSInventorySetting -Path $without).ContainsKey('Report') | Should -BeFalse
    }

    It 'rejects a Report option that is not a whole number in its range, naming the file' -ForEach @(
        @{ Name = 'HtmlSplitThreshold'; Literal = "'3000'" }
        @{ Name = 'HtmlSplitThreshold'; Literal = '$true' }
        @{ Name = 'HtmlSplitThreshold'; Literal = '-1' }
        @{ Name = 'HtmlRowsPerPage'; Literal = '49' }
        @{ Name = 'HtmlRowsPerPage'; Literal = '5001' }
        @{ Name = 'HtmlRowsPerPage'; Literal = '500.5' }
    ) {
        $path = Join-Path $TestDrive 'report-invalid.psd1'
        @"
@{
    Scoring = @{ Weights = @{}; Thresholds = @{ Moderate = 1.0; Complex = 6.0 }; BlockingSignals = @() }
    Report = @{ $Name = $Literal }
}
"@ | Set-Content -Path $path -Encoding UTF8

        { Get-SPSInventorySetting -Path $path } | Should -Throw -ExpectedMessage "*report-invalid.psd1*Report.$Name must be a whole number from*"
    }

    It 'rejects a Report section that is not a hashtable' {
        $path = Join-Path $TestDrive 'report-array.psd1'
        @'
@{
    Scoring = @{ Weights = @{}; Thresholds = @{ Moderate = 1.0; Complex = 6.0 }; BlockingSignals = @() }
    Report = @('HtmlSplitThreshold')
}
'@ | Set-Content -Path $path -Encoding UTF8

        { Get-SPSInventorySetting -Path $path } | Should -Throw -ExpectedMessage "*report-array.psd1*'Report' section must be a hashtable*"
    }

    It 'throws when the mandatory Scoring section is missing' {
        $path = Join-Path $TestDrive 'no-scoring.psd1'
        "@{ EnvName = 'TEST' }" | Set-Content -Path $path -Encoding UTF8

        { Get-SPSInventorySetting -Path $path } | Should -Throw '*Scoring*'
    }
}

Describe 'Example settings file' {
    BeforeAll {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:ExamplePath = Join-Path $repoRoot 'src/config/inventory-settings.example.psd1'
    }

    It 'treats external lists as a weighted migration blocker because BCS is retired in SharePoint Online' {
        $settings = Import-PowerShellDataFile -Path $script:ExamplePath

        $settings.Scoring.BlockingSignals | Should -Contain 'ExternalListCount'
        $settings.Scoring.Weights.ExternalListCount | Should -BeGreaterThan 0
    }

    It 'classifies a site with an external list as Blocking and a site without one as Simple' {
        $settings = Import-PowerShellDataFile -Path $script:ExamplePath

        $with = Measure-SPSSiteComplexity -Signals @{ ExternalListCount = 1 } -Scoring $settings.Scoring
        $without = Measure-SPSSiteComplexity -Signals @{ ExternalListCount = 0 } -Scoring $settings.Scoring

        $with.Category | Should -Be 4
        $with.Reasons | Should -Contain 'blocking: ExternalListCount'
        $without.Category | Should -Be 1
    }

    It 'blocks only the sites locked with NoAccess, not the ones that are read-only' {
        $settings = Import-PowerShellDataFile -Path $script:ExamplePath

        $settings.Scoring.BlockingSignals | Should -Contain 'HasNoAccessLock'
        $settings.Scoring.BlockingSignals | Should -Not -Contain 'IsLockedSite'
        $settings.Scoring.Weights.ContainsKey('IsLockedSite') | Should -BeFalse
    }

    It 'classifies a NoAccess site as Blocking and a ReadOnly or NoAdditions site as Simple' {
        $settings = Import-PowerShellDataFile -Path $script:ExamplePath

        $noAccess = Measure-SPSSiteComplexity -Signals @{ IsLockedSite = $true; HasNoAccessLock = $true; SiteLockState = 'NoAccess' } -Scoring $settings.Scoring
        $readOnly = Measure-SPSSiteComplexity -Signals @{ IsLockedSite = $true; HasNoAccessLock = $false; SiteLockState = 'ReadOnly' } -Scoring $settings.Scoring
        $noAdditions = Measure-SPSSiteComplexity -Signals @{ IsLockedSite = $true; HasNoAccessLock = $false; SiteLockState = 'NoAdditions' } -Scoring $settings.Scoring

        $noAccess.Category | Should -Be 4
        $noAccess.Reasons | Should -Contain 'blocking: HasNoAccessLock'
        $readOnly.Category | Should -Be 1
        $noAdditions.Category | Should -Be 1
    }

    It 'documents the alert row cap and keeps SharePoint alerts informational' {
        $settings = Import-PowerShellDataFile -Path $script:ExamplePath

        $settings.LargeContentThresholds.MaxAlertRowsPerSite | Should -Be 5000
        $settings.Scoring.BlockingSignals | Should -Not -Contain 'SharePointAlertCount'
        $settings.Scoring.Weights.ContainsKey('SharePointAlertCount') | Should -BeFalse
    }

    It 'the shipped example is a valid settings file' {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $example  = Join-Path $repoRoot 'src/config/inventory-settings.example.psd1'

        $settings = Import-PowerShellDataFile -Path $example

        $settings.ContainsKey('Scoring') | Should -BeTrue
        $settings.Scoring.ContainsKey('Weights') | Should -BeTrue
        $settings.Scoring.ContainsKey('Thresholds') | Should -BeTrue
        $settings.Scoring.ContainsKey('BlockingSignals') | Should -BeTrue
    }

    It 'collects the alert owner logins by default and the shipped example loads' {
        $settings = Get-SPSInventorySetting -Path $script:ExamplePath

        $settings.SharePointAlerts.IncludeUserLogin | Should -BeTrue
    }

    It 'has a Scope section that leaves out personal sites and site masters' {
        $settings = Get-SPSInventorySetting -Path $script:ExamplePath

        $settings.Scope | Should -BeOfType [hashtable]
        $settings.Scope.Keys | Should -Contain 'IncludePersonalSites'
        $settings.Scope.Keys | Should -Contain 'IncludeSiteMasters'
        $settings.Scope.IncludePersonalSites | Should -BeFalse
        $settings.Scope.IncludeSiteMasters | Should -BeFalse
    }
}
