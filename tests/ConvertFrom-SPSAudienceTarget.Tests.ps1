# Behavior tests for ConvertFrom-SPSAudienceTarget: the value of the Target Audiences column (pure, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    # ConvertFrom-SPSAudienceTarget is private; reach it inside the module scope.
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function Convert-Target {
        param ([AllowNull()] [AllowEmptyString()] [string]$Value)
        & $script:Module { param ($Text) ConvertFrom-SPSAudienceTarget -Value $Text } $Value
    }

    $script:IdA = 'a88b9dcb-0000-0000-0000-000000000001'
    $script:IdB = 'b88b9dcb-0000-0000-0000-000000000002'
}

Describe 'ConvertFrom-SPSAudienceTarget' {
    It 'reads the global audiences, and ignores the comma that ends them' {
        $target = Convert-Target -Value "$($script:IdA),$($script:IdB),;;;;"

        $target.AudienceId | Should -Be @($script:IdA, $script:IdB)
        $target.DistributionList | Should -HaveCount 0
        $target.SharePointGroup | Should -HaveCount 0
        $target.Unrecognized | Should -HaveCount 0
        $target.IsEmpty | Should -BeFalse
    }

    It 'reads a SharePoint group alone, as ;;;;Name' {
        $target = Convert-Target -Value ';;;;Owners'

        $target.SharePointGroup | Should -Be @('Owners')
        $target.AudienceId | Should -HaveCount 0
        $target.DistributionList | Should -HaveCount 0
        $target.IsEmpty | Should -BeFalse
    }

    It 'reads the three parts: audiences, distribution lists on separate lines, SharePoint groups' {
        $value = "$($script:IdA);;cn=all developers,ou=distribution lists,dc=contoso`r`ncn=all testers,ou=distribution lists,dc=contoso;;1,12,Site Owners"

        $target = Convert-Target -Value $value

        $target.AudienceId | Should -Be @($script:IdA)
        $target.DistributionList | Should -Be @('cn=all developers,ou=distribution lists,dc=contoso', 'cn=all testers,ou=distribution lists,dc=contoso')
        $target.SharePointGroup | Should -Be @('1', '12', 'Site Owners')
    }

    It 'splits the distribution lists on a line feed alone too' {
        (Convert-Target -Value ";;cn=a,dc=x`ncn=b,dc=x;;").DistributionList | Should -Be @('cn=a,dc=x', 'cn=b,dc=x')
    }

    It 'trims what it reads' {
        $target = Convert-Target -Value " $($script:IdA) , $($script:IdB) ;; cn=a,dc=x ;; Owners , Members "

        $target.AudienceId | Should -Be @($script:IdA, $script:IdB)
        $target.DistributionList | Should -Be @('cn=a,dc=x')
        $target.SharePointGroup | Should -Be @('Owners', 'Members')
    }

    It 'gives the IDs in lower case, in the same form whatever they were written like, and once' {
        $target = Convert-Target -Value "{$($script:IdA.ToUpperInvariant())},$($script:IdA),$($script:IdB.ToUpperInvariant());;;;"

        $target.AudienceId | Should -Be @($script:IdA, $script:IdB)
    }

    It 'lists a value once, whatever its case, in the order of the value' {
        $target = Convert-Target -Value ';;cn=A,dc=x;;Owners,owners,Members,OWNERS'

        $target.SharePointGroup | Should -Be @('Owners', 'Members')
    }

    It 'keeps what the audience part holds and is not a GUID, so that nothing is lost' {
        $target = Convert-Target -Value "not-a-guid,$($script:IdA),Sales;;;;"

        $target.AudienceId | Should -Be @($script:IdA)
        $target.Unrecognized | Should -Be @('not-a-guid', 'Sales')
        $target.IsEmpty | Should -BeFalse
    }

    It 'says that a value targets nothing when it is empty, null, blank or only separators' -ForEach @(
        @{ Text = $null }
        @{ Text = '' }
        @{ Text = '   ' }
        @{ Text = ';;' }
        @{ Text = ';;;;' }
        @{ Text = ' , ;; ;; , ' }
    ) {
        $target = Convert-Target -Value $Text

        $target.IsEmpty | Should -BeTrue
        $target.AudienceId | Should -HaveCount 0
        $target.DistributionList | Should -HaveCount 0
        $target.SharePointGroup | Should -HaveCount 0
        $target.Unrecognized | Should -HaveCount 0
    }

    It 'keeps a separator that comes after the third part in that part' {
        (Convert-Target -Value 'a;;b;;c;;d').SharePointGroup | Should -Be @('c;;d')
    }

    It 'returns arrays, also for one value or none' {
        $target = Convert-Target -Value ";;;;Owners"

        $target.AudienceId.GetType().IsArray | Should -BeTrue
        $target.SharePointGroup.GetType().IsArray | Should -BeTrue
        $target.DistributionList.GetType().IsArray | Should -BeTrue
        $target.Unrecognized.GetType().IsArray | Should -BeTrue
    }
}
