# Behavior tests for Get-SPSWebDepth (pure, no farm needed).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    # Get-SPSWebDepth is private; reach it inside the module scope.
    function Get-Depth {
        param ([System.String] $SiteUrl, [System.String] $WebUrl)

        return & $script:Module { param($s, $w) Get-SPSWebDepth -SiteUrl $s -WebUrl $w } $SiteUrl $WebUrl
    }
}

Describe 'Get-SPSWebDepth' {
    It 'is 0 for the root web, with no relative URL' {
        $place = Get-Depth -SiteUrl 'https://intranet/sites/hr' -WebUrl 'https://intranet/sites/hr'

        $place.Depth | Should -Be 0
        $place.RelativeUrl | Should -Be ''
    }

    It 'is 1 for a web directly below the root web' {
        $place = Get-Depth -SiteUrl 'https://intranet/sites/hr' -WebUrl 'https://intranet/sites/hr/payroll'

        $place.Depth | Should -Be 1
        $place.RelativeUrl | Should -Be 'payroll'
    }

    It 'counts one more level for each web below that one' {
        $place = Get-Depth -SiteUrl 'https://intranet/sites/hr' -WebUrl 'https://intranet/sites/hr/payroll/2026/q1'

        $place.Depth | Should -Be 3
        $place.RelativeUrl | Should -Be 'payroll/2026/q1'
    }

    It 'works for the root site collection of a web application' {
        (Get-Depth -SiteUrl 'https://intranet' -WebUrl 'https://intranet').Depth | Should -Be 0
        (Get-Depth -SiteUrl 'https://intranet/' -WebUrl 'https://intranet/news').Depth | Should -Be 1
        (Get-Depth -SiteUrl 'https://intranet' -WebUrl 'https://intranet/news/archive').Depth | Should -Be 2
    }

    It 'ignores the case and a trailing slash' {
        $place = Get-Depth -SiteUrl 'https://Intranet/Sites/HR/' -WebUrl 'https://intranet/sites/hr/Payroll/'

        $place.Depth | Should -Be 1
        $place.RelativeUrl | Should -Be 'Payroll'
    }

    It 'decodes the URL of the web for display' {
        $place = Get-Depth -SiteUrl 'https://intranet/sites/hr' -WebUrl 'https://intranet/sites/hr/Q1%202026'

        $place.RelativeUrl | Should -Be 'Q1 2026'
    }

    It 'compares whole segments, so a site collection that starts with the same letters is not its parent' {
        Get-Depth -SiteUrl 'https://intranet/sites/hr' -WebUrl 'https://intranet/sites/hr2/payroll' | Should -BeNullOrEmpty
    }

    It 'is $null when the web is not below the site collection' {
        Get-Depth -SiteUrl 'https://intranet/sites/hr' -WebUrl 'https://intranet/sites/finance' | Should -BeNullOrEmpty
        Get-Depth -SiteUrl 'https://intranet/sites/hr/payroll' -WebUrl 'https://intranet/sites/hr' | Should -BeNullOrEmpty
    }

    It 'is $null when a URL is empty or not a URL, so that the caller can mark the inventory partial' {
        Get-Depth -SiteUrl 'https://intranet/sites/hr' -WebUrl '' | Should -BeNullOrEmpty
        Get-Depth -SiteUrl 'https://intranet/sites/hr' -WebUrl $null | Should -BeNullOrEmpty
        Get-Depth -SiteUrl '' -WebUrl 'https://intranet/sites/hr' | Should -BeNullOrEmpty
        Get-Depth -SiteUrl 'https://intranet/sites/hr' -WebUrl 'not a url' | Should -BeNullOrEmpty
    }
}
