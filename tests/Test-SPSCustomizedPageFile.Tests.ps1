# Behavior tests for Test-SPSCustomizedPageFile (pure file classification, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    # Test-SPSCustomizedPageFile is private; reach it inside the module scope.
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    # Mirrors Microsoft.SharePoint.SPCustomizedPageStatus, a flags enumeration.
    if (-not ('SPSTestCustomizedPageStatus' -as [type])) {
        Add-Type -TypeDefinition 'using System; [Flags] public enum SPSTestCustomizedPageStatus { None = 0, Uncustomized = 1, Customized = 2 }'
    }

    function Test-Page {
        param ($File)
        & $script:Module { param ($Candidate) Test-SPSCustomizedPageFile -File $Candidate } $File
    }
}

Describe 'Test-SPSCustomizedPageFile' {
    It 'flags a customized page edited by a regular user' {
        $file = [PSCustomObject]@{
            CustomizedPageStatus = [SPSTestCustomizedPageStatus]::Customized
            ModifiedBy = [PSCustomObject]@{ LoginName = 'i:0#.w|contoso\jdoe' }
        }

        Test-Page -File $file | Should -BeTrue
    }

    It 'does not flag uncustomized or non-page files' {
        Test-Page -File ([PSCustomObject]@{ CustomizedPageStatus = [SPSTestCustomizedPageStatus]::Uncustomized }) | Should -BeFalse
        Test-Page -File ([PSCustomObject]@{ CustomizedPageStatus = [SPSTestCustomizedPageStatus]::None }) | Should -BeFalse
    }

    It 'reads the Customized flag from numeric and text statuses' {
        Test-Page -File ([PSCustomObject]@{ CustomizedPageStatus = 2 }) | Should -BeTrue
        Test-Page -File ([PSCustomObject]@{ CustomizedPageStatus = 3 }) | Should -BeTrue
        Test-Page -File ([PSCustomObject]@{ CustomizedPageStatus = 1 }) | Should -BeFalse
        Test-Page -File ([PSCustomObject]@{ CustomizedPageStatus = 'Customized' }) | Should -BeTrue
        Test-Page -File ([PSCustomObject]@{ CustomizedPageStatus = 'Uncustomized, Customized' }) | Should -BeTrue
        Test-Page -File ([PSCustomObject]@{ CustomizedPageStatus = 'Uncustomized' }) | Should -BeFalse
    }

    It 'ignores customized files last modified by the System Account' {
        $file = [PSCustomObject]@{
            CustomizedPageStatus = 2
            ModifiedBy = [PSCustomObject]@{ LoginName = 'sharepoint\SYSTEM' }
        }

        Test-Page -File $file | Should -BeFalse
    }

    It 'keeps a customized file in scope when ModifiedBy cannot be read' {
        $file = [PSCustomObject]@{ CustomizedPageStatus = 2 }
        $file | Add-Member -MemberType ScriptProperty -Name ModifiedBy -Value { throw 'User not found' }

        Test-Page -File $file | Should -BeTrue
    }

    It 'keeps a customized file in scope when ModifiedBy is not exposed' {
        Test-Page -File ([PSCustomObject]@{ CustomizedPageStatus = 2 }) | Should -BeTrue
    }

    It 'rejects a null file, a missing status or a null status instead of reporting not customized' {
        { Test-Page -File $null } | Should -Throw '*could not be read*'
        { Test-Page -File ([PSCustomObject]@{ Name = 'default.aspx' }) } | Should -Throw '*could not be read*'
        { Test-Page -File ([PSCustomObject]@{ CustomizedPageStatus = $null }) } | Should -Throw '*could not be read*'
    }
}
