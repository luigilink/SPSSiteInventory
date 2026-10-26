# Behavior tests for Test-SPSFeatureActivated (pure feature-collection lookup, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    # Test-SPSFeatureActivated is private; reach it inside the module scope.
    $script:Module = Get-Module -Name SPSSiteInventory.Common
    $script:PublishingWeb = '94c94ca6-b32f-4da9-a9e3-1f3d343d7ecb'
}

Describe 'Test-SPSFeatureActivated' {
    It 'finds an activated feature by its definition GUID' {
        $features = @(
            [PSCustomObject]@{ DefinitionId = [guid]'00000000-0000-0000-0000-000000000001' }
            [PSCustomObject]@{ DefinitionId = [guid]$script:PublishingWeb }
        )

        $result = & $script:Module { param ($Features, $Id) Test-SPSFeatureActivated -Feature $Features -FeatureId $Id } $features $script:PublishingWeb

        $result | Should -BeTrue
    }

    It 'matches the feature ID regardless of case' {
        $features = @([PSCustomObject]@{ DefinitionId = [guid]$script:PublishingWeb })

        $result = & $script:Module { param ($Features, $Id) Test-SPSFeatureActivated -Feature $Features -FeatureId $Id } $features $script:PublishingWeb.ToUpperInvariant()

        $result | Should -BeTrue
    }

    It 'returns false when the feature is not activated' {
        $features = @([PSCustomObject]@{ DefinitionId = [guid]'00000000-0000-0000-0000-000000000001' })

        $result = & $script:Module { param ($Features, $Id) Test-SPSFeatureActivated -Feature $Features -FeatureId $Id } $features $script:PublishingWeb

        $result | Should -BeFalse
    }

    It 'returns false for an empty or null collection' {
        (& $script:Module { param ($Id) Test-SPSFeatureActivated -Feature @() -FeatureId $Id } $script:PublishingWeb) | Should -BeFalse
        (& $script:Module { param ($Id) Test-SPSFeatureActivated -Feature $null -FeatureId $Id } $script:PublishingWeb) | Should -BeFalse
    }
}
