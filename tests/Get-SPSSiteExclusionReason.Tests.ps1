# Behavior tests for Get-SPSSiteExclusionReason (pure, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    $script:Guid = 'f5e4136f-1537-43de-a8af-d47447211c44'

    function Get-Reason {
        param ([object]$Url = '', [object]$Template = '', [bool]$Personal = $false, [bool]$Master = $false)
        & $script:Module {
            param ($Url, $Template, $Personal, $Master)
            Get-SPSSiteExclusionReason -Url $Url -Template $Template -IncludePersonalSite $Personal -IncludeSiteMaster $Master
        } $Url $Template $Personal $Master
    }
}

Describe 'Get-SPSSiteExclusionReason' {
    Context 'site masters' {
        It 'recognizes the host name <Url>' -ForEach @(
            @{ Url = 'https://sitemaster-f5e4136f-1537-43de-a8af-d47447211c44' }
            @{ Url = 'https://sitemaster-f5e4136f-1537-43de-a8af-d47447211c44/' }
            @{ Url = 'https://sitemaster-f5e4136f-1537-43de-a8af-d47447211c44/sites/x' }
            @{ Url = 'https://SITEMASTER-F5E4136F-1537-43DE-A8AF-D47447211C44' }
            @{ Url = 'http://sitemaster-f5e4136f-1537-43de-a8af-d47447211c44:8080' }
            @{ Url = 'https://sitemaster-f5e4136f-1537-43de-a8af-d47447211c44:8443/personal/x' }
            @{ Url = 'sitemaster-f5e4136f-1537-43de-a8af-d47447211c44' }
        ) {
            Get-Reason -Url $Url -Template 'SPSPERS#10' | Should -Be 'SiteMaster'
            Get-Reason -Url $Url | Should -Be 'SiteMaster'
        }

        It 'does not recognize the look-alike <Url>' -ForEach @(
            @{ Url = 'https://sitemaster-notaguid' }
            @{ Url = 'https://sitemaster.contoso.com' }
            @{ Url = 'https://sitemaster-f5e4136f-1537-43de-a8af-d47447211c4' }
            @{ Url = 'https://sitemaster-f5e4136f-1537-43de-a8af-d47447211c44.contoso.com' }
            @{ Url = 'https://mysite.contoso.com/sites/sitemaster-f5e4136f-1537-43de-a8af-d47447211c44' }
            @{ Url = 'https://intranet.contoso.com/sitemaster-f5e4136f-1537-43de-a8af-d47447211c44' }
            @{ Url = 'https://xsitemaster-f5e4136f-1537-43de-a8af-d47447211c44' }
        ) {
            Get-Reason -Url $Url -Template 'STS#0' | Should -BeNullOrEmpty
        }

        It 'keeps a site master when IncludeSiteMaster is set' {
            Get-Reason -Url "https://sitemaster-$($script:Guid)" -Template 'SPSPERS#10' -Master $true | Should -BeNullOrEmpty
        }
    }

    Context 'personal sites' {
        It 'recognizes the template <Template>' -ForEach @(
            @{ Template = 'SPSPERS#0' }
            @{ Template = 'SPSPERS#10' }
            @{ Template = 'spspers#10' }
            @{ Template = 'SPSPERS' }
            @{ Template = ' SPSPERS#10 ' }
        ) {
            Get-Reason -Url 'https://mysite.contoso.com/personal/user' -Template $Template | Should -Be 'PersonalSite'
        }

        It 'does not recognize the template <Template>' -ForEach @(
            @{ Template = 'SPSMSITEHOST#0' }
            @{ Template = 'STS#0' }
            @{ Template = 'SITEPAGEPUBLISHING#0' }
            @{ Template = 'SPSPERSX#0' }
            @{ Template = 'XSPSPERS#0' }
            @{ Template = 'SRCHCEN#0' }
        ) {
            Get-Reason -Url 'https://mysite.contoso.com' -Template $Template | Should -BeNullOrEmpty
        }

        It 'keeps the My Site host, at the root of the web application' {
            Get-Reason -Url 'https://mysite.contoso.com' -Template 'SPSMSITEHOST#0' | Should -BeNullOrEmpty
        }

        It 'keeps a personal site when IncludePersonalSite is set' {
            Get-Reason -Url 'https://mysite.contoso.com/personal/user' -Template 'SPSPERS#10' -Personal $true | Should -BeNullOrEmpty
        }
    }

    Context 'site master and personal site rules together' {
        It 'governs a site master by IncludeSiteMaster only' {
            $url = "https://sitemaster-$($script:Guid)"

            Get-Reason -Url $url -Template 'SPSPERS#10' -Personal $false -Master $false | Should -Be 'SiteMaster'
            Get-Reason -Url $url -Template 'SPSPERS#10' -Personal $true -Master $false | Should -Be 'SiteMaster'
            Get-Reason -Url $url -Template 'SPSPERS#10' -Personal $false -Master $true | Should -BeNullOrEmpty
            Get-Reason -Url $url -Template 'SPSPERS#10' -Personal $true -Master $true | Should -BeNullOrEmpty
        }

        It 'governs a personal site that is not a site master by IncludePersonalSite only' {
            $url = 'https://mysite.contoso.com/personal/user'

            Get-Reason -Url $url -Template 'SPSPERS#10' -Personal $false -Master $false | Should -Be 'PersonalSite'
            Get-Reason -Url $url -Template 'SPSPERS#10' -Personal $false -Master $true | Should -Be 'PersonalSite'
            Get-Reason -Url $url -Template 'SPSPERS#10' -Personal $true -Master $false | Should -BeNullOrEmpty
        }

        It 'leaves out nothing when both kinds are included' {
            Get-Reason -Url "https://sitemaster-$($script:Guid)" -Template 'SPSPERS#10' -Personal $true -Master $true | Should -BeNullOrEmpty
            Get-Reason -Url 'https://mysite.contoso.com/personal/user' -Template 'SPSPERS#10' -Personal $true -Master $true | Should -BeNullOrEmpty
        }

        It 'excludes a regular site collection from neither rule' {
            Get-Reason -Url 'https://intranet.contoso.com/sites/team' -Template 'STS#0' | Should -BeNullOrEmpty
        }
    }

    Context 'empty or unknown input' {
        It 'never excludes anything when the URL and the template are <Description>' -ForEach @(
            @{ Description = 'empty'; Url = ''; Template = '' }
            @{ Description = 'null'; Url = $null; Template = $null }
            @{ Description = 'blank'; Url = '  '; Template = '  ' }
            @{ Description = 'only the separator of the template'; Url = ''; Template = '#' }
        ) {
            Get-Reason -Url $Url -Template $Template | Should -BeNullOrEmpty
        }

        It 'does not exclude a site whose root web could not be read, even when its URL is a personal one' {
            Get-Reason -Url 'https://mysite.contoso.com/personal/user' -Template '' | Should -BeNullOrEmpty
        }

        It 'runs with no parameter at all' {
            & $script:Module { Get-SPSSiteExclusionReason } | Should -BeNullOrEmpty
        }
    }
}
