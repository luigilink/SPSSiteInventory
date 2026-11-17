# Behavior tests for Get-SPSLowerBoundSignalName (pure, no farm needed).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function Get-Name {
        param ([object]$Record)
        @(& $script:Module { param ($Item) Get-SPSLowerBoundSignalName -Record $Item } $Record)
    }
}

Describe 'Get-SPSLowerBoundSignalName' {
    It 'gives the names of the column, in order' {
        $name = Get-Name -Record ([PSCustomObject]@{ LowerBoundSignals = 'HtmlFileCount; FileVersionCount;SiteNotebookCount' })

        $name | Should -Be @('HtmlFileCount', 'FileVersionCount', 'SiteNotebookCount')
    }

    It 'trims the names and leaves out an empty one and a name that is repeated' {
        $name = Get-Name -Record ([PSCustomObject]@{ LowerBoundSignals = ' FileVersionCount ;; ; HtmlFileCount;FileVersionCount; ' })

        $name | Should -Be @('FileVersionCount', 'HtmlFileCount')
    }

    It 'gives nothing for <Case>' -ForEach @(
        @{ Case = 'an empty column'; Record = [PSCustomObject]@{ LowerBoundSignals = '' } }
        @{ Case = 'a column that holds only separators'; Record = [PSCustomObject]@{ LowerBoundSignals = ' ; ;' } }
        @{ Case = 'a null column'; Record = [PSCustomObject]@{ LowerBoundSignals = $null } }
        @{ Case = 'a record without the column'; Record = [PSCustomObject]@{ Url = 'https://intranet/sites/old' } }
        @{ Case = 'no record'; Record = $null }
    ) {
        Get-Name -Record $Record | Should -HaveCount 0 -Because $Case
    }
}
