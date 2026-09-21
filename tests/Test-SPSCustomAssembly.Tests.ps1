# Behavior tests for Test-SPSCustomAssembly (pure assembly classification, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    # Test-SPSCustomAssembly is private; reach it inside the module scope.
    $script:Module = Get-Module -Name SPSSiteInventory.Common
}

Describe 'Test-SPSCustomAssembly' {
    It 'treats out-of-the-box SharePoint assemblies as non-custom' {
        $result = & $script:Module { Test-SPSCustomAssembly -Assembly 'Microsoft.SharePoint, Version=16.0.0.0, Culture=neutral, PublicKeyToken=71e9bce111e9429c' }
        $result | Should -BeFalse
    }

    It 'treats out-of-the-box Office Server assemblies as non-custom' {
        $result = & $script:Module { Test-SPSCustomAssembly -Assembly 'Microsoft.Office.Server.Search, Version=16.0.0.0, Culture=neutral, PublicKeyToken=71e9bce111e9429c' }
        $result | Should -BeFalse
    }

    It 'treats a third-party / in-house assembly as custom' {
        $result = & $script:Module { Test-SPSCustomAssembly -Assembly 'Contoso.Intranet.EventReceivers, Version=1.0.0.0, Culture=neutral, PublicKeyToken=abcdef0123456789' }
        $result | Should -BeTrue
    }

    It 'is case-insensitive on the Microsoft prefix' {
        $result = & $script:Module { Test-SPSCustomAssembly -Assembly 'microsoft.sharepoint.publishing, Version=16.0.0.0' }
        $result | Should -BeFalse
    }

    It 'treats an empty or null assembly as non-custom (conservative)' {
        (& $script:Module { Test-SPSCustomAssembly -Assembly '' }) | Should -BeFalse
        (& $script:Module { Test-SPSCustomAssembly -Assembly $null }) | Should -BeFalse
    }
}
