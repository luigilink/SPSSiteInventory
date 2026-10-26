# Behavior tests for Test-SPSCustomPermissionLevel (pure classification, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    # Test-SPSCustomPermissionLevel is private; reach it inside the module scope.
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    # Mirrors Microsoft.SharePoint.SPRoleType.
    if (-not ('SPSTestRoleType' -as [type])) {
        Add-Type -TypeDefinition 'public enum SPSTestRoleType { None = 0, Guest = 1, Reader = 2, Contributor = 3, WebDesigner = 4, Administrator = 5, Editor = 6, Reviewer = 7, RestrictedReader = 8, System = 255 }'
    }

    function Test-Level {
        param ($Role, [string[]]$BuiltInName = @('View Only', 'Approve'))
        & $script:Module { param ($Candidate, $Names) Test-SPSCustomPermissionLevel -RoleDefinition $Candidate -BuiltInName $Names } $Role $BuiltInName
    }
}

Describe 'Test-SPSCustomPermissionLevel' {
    It 'flags a None-type level that SharePoint did not provision' {
        Test-Level -Role ([PSCustomObject]@{ Name = 'Project Manager'; Type = [SPSTestRoleType]::None }) | Should -BeTrue
    }

    It 'does not flag levels with a SharePoint base type, even when renamed' {
        foreach ($type in @('Guest', 'Reader', 'Contributor', 'WebDesigner', 'Administrator', 'Editor', 'Reviewer', 'RestrictedReader', 'System')) {
            Test-Level -Role ([PSCustomObject]@{ Name = 'Renamed level'; Type = [SPSTestRoleType]$type }) | Should -BeFalse
        }
    }

    It 'does not flag provisioned levels recognized by name, regardless of case' {
        Test-Level -Role ([PSCustomObject]@{ Name = 'view only'; Type = [SPSTestRoleType]::None }) | Should -BeFalse
        Test-Level -Role ([PSCustomObject]@{ Name = 'APPROVE'; Type = [SPSTestRoleType]::None }) | Should -BeFalse
    }

    It 'treats configured localized names as provisioned' {
        $role = [PSCustomObject]@{ Name = 'Affichage seul'; Type = [SPSTestRoleType]::None }

        Test-Level -Role $role | Should -BeTrue
        Test-Level -Role $role -BuiltInName @('Affichage seul') | Should -BeFalse
    }

    It 'reads numeric and text types' {
        Test-Level -Role ([PSCustomObject]@{ Name = 'Custom'; Type = 0 }) | Should -BeTrue
        Test-Level -Role ([PSCustomObject]@{ Name = 'Custom'; Type = 3 }) | Should -BeFalse
        Test-Level -Role ([PSCustomObject]@{ Name = 'Custom'; Type = 'None' }) | Should -BeTrue
        Test-Level -Role ([PSCustomObject]@{ Name = 'Custom'; Type = 'Contributor' }) | Should -BeFalse
    }

    It 'rejects a null definition, a missing or null type and a blank name instead of reporting not custom' {
        { Test-Level -Role $null } | Should -Throw '*could not be read*'
        { Test-Level -Role ([PSCustomObject]@{ Name = 'Level' }) } | Should -Throw '*could not be read*'
        { Test-Level -Role ([PSCustomObject]@{ Name = 'Level'; Type = $null }) } | Should -Throw '*could not be read*'
        { Test-Level -Role ([PSCustomObject]@{ Name = ''; Type = [SPSTestRoleType]::None }) } | Should -Throw '*could not be read*'
        { Test-Level -Role ([PSCustomObject]@{ Type = [SPSTestRoleType]::None }) } | Should -Throw '*could not be read*'
    }
}
