# Behavior tests for Get-SPSOnlineProfilePropertyName: the profile properties that SharePoint Online fills in (pure).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common
    $script:Name = @(& $script:Module { Get-SPSOnlineProfilePropertyName })
}

Describe 'Get-SPSOnlineProfilePropertyName' {
    It 'returns strings, each once' {
        $script:Name.Count | Should -BeGreaterThan 20
        foreach ($name in $script:Name) {
            $name | Should -BeOfType ([string])
            [string]::IsNullOrWhiteSpace($name) | Should -BeFalse
        }
        @($script:Name | Sort-Object -Unique).Count | Should -Be $script:Name.Count
    }

    It 'has the internal name or the display name of the property of every row of the table that Microsoft documents' -ForEach @(
        @{ Attribute = 'UserPrincipalName'; Expected = @('AccountName', 'UserName', 'SPS-UserPrincipalName') }
        @{ Attribute = 'DisplayName'; Expected = @('PreferredName') }
        @{ Attribute = 'GivenName'; Expected = @('FirstName') }
        @{ Attribute = 'sn'; Expected = @('LastName') }
        @{ Attribute = 'telephoneNumber'; Expected = @('WorkPhone') }
        @{ Attribute = 'proxyAddresses'; Expected = @('WorkEmail', 'SPS-SipAddress') }
        @{ Attribute = 'PhysicalDeliveryOfficeName'; Expected = @('Office') }
        @{ Attribute = 'Title'; Expected = @('Title', 'SPS-JobTitle') }
        @{ Attribute = 'Department'; Expected = @('Department', 'SPS-Department') }
        @{ Attribute = 'WWWHomePage'; Expected = @('PublicSiteRedirect') }
        @{ Attribute = 'PreferredLanguage'; Expected = @('SPS-MUILanguages') }
        @{ Attribute = 'msExchHideFromAddressList'; Expected = @('SPS-HideFromAddressLists') }
        @{ Attribute = 'Manager'; Expected = @('Manager') }
    ) {
        foreach ($name in $Expected) {
            $script:Name | Should -Contain $name -Because "the property of $Attribute is $name"
        }
    }

    It 'has the display names that the page of Microsoft uses' {
        foreach ($name in @('Work phone', 'Work Email', 'SIP Address', 'Public site redirect', 'Language Preferences', 'Job Title')) {
            $script:Name | Should -Contain $name
        }
    }

    It 'does not have the Phonetic Search properties, nor the properties that only the User Profile service fills in' {
        foreach ($name in @('PhoneticFirstName', 'PhoneticLastName', 'PhoneticDisplayName', 'SID', 'ADGuid', 'SPS-DistinguishedName', 'AboutMe', 'SPS-Skills')) {
            $script:Name | Should -Not -Contain $name
        }
    }
}
