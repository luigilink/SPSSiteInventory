# Behavior tests for Get-SPSWebApplicationPolicy (no farm needed: SharePoint objects are mocked).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    function Get-TestPolicy {
        param ([string]$User, [string[]]$Roles = @('Full Control'), [string]$Display = '', [bool]$System = $false)
        [PSCustomObject]@{
            UserName = $User
            DisplayName = $Display
            IsSystemUser = $System
            PolicyRoleBindings = @($Roles | ForEach-Object { [PSCustomObject]@{ Name = $_ } })
        }
    }

    function Get-TestWebApplication {
        param ([string]$Handling = 'Strict', $AllZones = @(), [hashtable]$Zones = @{ Default = @() })
        $webApp = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com'
            BrowserFileHandling = $Handling
            Policies = $AllZones
            IisSettings = @{}
            ZoneMap = $Zones
        }
        foreach ($zone in $Zones.Keys) { $webApp.IisSettings[$zone] = [PSCustomObject]@{} }
        $webApp | Add-Member -MemberType ScriptMethod -Name ZonePolicies -Value {
            param ($Zone)
            # The comma keeps an empty collection from being unrolled into $null, like a real SPPolicyCollection.
            , $this.ZoneMap[[string]$Zone]
        }
        return $webApp
    }
}

Describe 'Get-SPSWebApplicationPolicy' {
    It 'counts the all-zone and per-zone policies and shows their permission levels' {
        $webApp = Get-TestWebApplication -AllZones @(
            Get-TestPolicy -User 'CONTOSO\farm' -Roles @('Full Control') -System $true
        ) -Zones @{
            Default = @(Get-TestPolicy -User 'CONTOSO\crawl' -Roles @('Full Read'))
            Extranet = @(Get-TestPolicy -User 'CONTOSO\partner' -Roles @('Deny Write', 'Full Read'))
        }

        $result = Get-SPSWebApplicationPolicy -WebApplication $webApp

        $result.WebAppPolicyCount | Should -Be 3
        $result.WebAppPolicyExamples | Should -Be 'CONTOSO\farm: Full Control; CONTOSO\crawl: Full Read [Default]; CONTOSO\partner: Deny Write, Full Read [Extranet]'
        $result.Policies | Should -HaveCount 3
        $result.Policies[0].Zone | Should -Be 'All zones'
        $result.Policies[0].IsSystemUser | Should -BeTrue
        $result.Policies[2].Zone | Should -Be 'Extranet'
        $result.Policies[2].Roles | Should -Be 'Deny Write, Full Read'
    }

    It 'reports the browser file handling setting as text' {
        (Get-SPSWebApplicationPolicy -WebApplication (Get-TestWebApplication -Handling 'Permissive')).BrowserFileHandling | Should -Be 'Permissive'
        (Get-SPSWebApplicationPolicy -WebApplication (Get-TestWebApplication -Handling 'Strict')).BrowserFileHandling | Should -Be 'Strict'
    }

    It 'reports an empty policy list as zero rather than unknown' {
        $result = Get-SPSWebApplicationPolicy -WebApplication (Get-TestWebApplication)

        $result.WebAppPolicyCount | Should -Be 0
        $result.WebAppPolicyExamples | Should -Be ''
        @($result.Policies).Count | Should -Be 0
    }

    It 'lists at most ten examples while counting every policy' {
        $policies = @(1..12 | ForEach-Object { Get-TestPolicy -User ('CONTOSO\user{0}' -f $_) })

        $result = Get-SPSWebApplicationPolicy -WebApplication (Get-TestWebApplication -AllZones $policies)

        $result.WebAppPolicyCount | Should -Be 12
        @($result.WebAppPolicyExamples -split '; ').Count | Should -Be 10
    }

    It 'rejects an unreadable setting instead of reporting no policies' {
        $noHandling = Get-TestWebApplication
        $noHandling.BrowserFileHandling = $null
        { Get-SPSWebApplicationPolicy -WebApplication $noHandling } | Should -Throw '*browser file handling*'

        $noPolicies = Get-TestWebApplication
        $noPolicies.Policies = $null
        { Get-SPSWebApplicationPolicy -WebApplication $noPolicies } | Should -Throw '*policies are unavailable*'

        $noZones = Get-TestWebApplication
        $noZones.IisSettings = $null
        { Get-SPSWebApplicationPolicy -WebApplication $noZones } | Should -Throw '*zones could be read*'

        $noZonePolicies = Get-TestWebApplication -Zones @{ Default = $null }
        { Get-SPSWebApplicationPolicy -WebApplication $noZonePolicies } | Should -Throw "*policies of zone 'Default'*"
    }

    It 'rejects a policy whose user or permission levels cannot be read' {
        $noUser = Get-TestWebApplication -AllZones @(Get-TestPolicy -User '')
        { Get-SPSWebApplicationPolicy -WebApplication $noUser } | Should -Throw '*user name could not be read*'

        $policy = Get-TestPolicy -User 'CONTOSO\broken'
        $policy.PolicyRoleBindings = $null
        { Get-SPSWebApplicationPolicy -WebApplication (Get-TestWebApplication -AllZones @($policy)) } | Should -Throw '*permission policy levels of*broken*'
    }
}
