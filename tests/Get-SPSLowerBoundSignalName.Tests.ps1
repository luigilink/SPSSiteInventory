# Behavior tests for Get-SPSLowerBoundSignalName (pure, no farm needed).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function Get-Name {
        param ([object]$Value)
        @(& $script:Module { param ($Item) Get-SPSLowerBoundSignalName -Value $Item } $Value)
    }
}

Describe 'Get-SPSLowerBoundSignalName' {
    It 'gives the names of the column, in order' {
        $name = Get-Name -Value 'HtmlFileCount; FileVersionCount;SiteNotebookCount'

        $name | Should -Be @('HtmlFileCount', 'FileVersionCount', 'SiteNotebookCount')
    }

    It 'trims the names and leaves out an empty one and a name that is repeated' {
        $name = Get-Name -Value ' FileVersionCount ;; ; HtmlFileCount;FileVersionCount; '

        $name | Should -Be @('FileVersionCount', 'HtmlFileCount')
    }

    It 'gives nothing for <Case>' -ForEach @(
        @{ Case = 'an empty text'; Value = '' }
        @{ Case = 'a text that holds only separators'; Value = ' ; ;' }
        @{ Case = 'a null'; Value = $null }
    ) {
        Get-Name -Value $Value | Should -HaveCount 0 -Because $Case
    }

    It 'gives nothing for a record that has no such column, which the caller reads as a null' {
        $record = [PSCustomObject]@{ Url = 'https://intranet/sites/old' }

        Get-Name -Value $record.LowerBoundSignals | Should -HaveCount 0
    }

    It 'reads a number as its text' {
        Get-Name -Value 5 | Should -Be @('5')
    }
}
