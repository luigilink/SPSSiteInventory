# Behavior tests for Get-SPSWorkflowAssociationExample (the examples of the Workflow2010 signals, from the rows of the report).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function New-Row {
        param ([string]$Name = 'Approval', [string]$Web = 'https://intranet/sites/team', [string]$Scope = 'List', [string]$List = 'Documents', [int]$Running = 0, [bool]$Counted = $true)
        [PSCustomObject]@{ SiteUrl = 'https://intranet/sites/team'; WebUrl = $Web; Scope = $Scope; ListTitle = $List; ListUrl = '/sites/team/Documents'; WorkflowName = $Name; Counted = $Counted; RunningInstances = $Running }
    }

    function Get-Example {
        param ([object[]]$Row, [int]$Maximum = 0)
        & $script:Module {
            param ($Row, $Maximum)
            if ($Maximum -gt 0) { Get-SPSWorkflowAssociationExample -Row $Row -Maximum $Maximum } else { Get-SPSWorkflowAssociationExample -Row $Row }
        } $Row $Maximum
    }
}

Describe 'Get-SPSWorkflowAssociationExample' {
    It 'gives an empty text when there is no row' -ForEach @(
        @{ Case = 'an empty list'; Row = @() }
        @{ Case = 'a list that has only a null'; Row = @($null) }
    ) {
        Get-Example -Row $Row | Should -BeExactly '' -Because $Case
    }

    It 'says the name of the workflow, the list and the web, and the running instances' {
        Get-Example -Row @((New-Row -Name 'Approval' -Running 12)) | Should -BeExactly 'Approval (list Documents, https://intranet/sites/team): 12 running instance(s)'
    }

    It 'says the web, and no list, for an association of a web' {
        Get-Example -Row @((New-Row -Name 'Publication' -Scope 'Web' -List '' -Web 'https://intranet/sites/team/hr')) | Should -BeExactly 'Publication (web https://intranet/sites/team/hr): 0 running instance(s)'
    }

    It 'says that a previous version is one, because it is not counted' {
        Get-Example -Row @((New-Row -Name 'Old' -Running 3 -Counted $false)) | Should -BeExactly 'Old (list Documents, https://intranet/sites/team): 3 running instance(s) [previous version]'
    }

    It 'puts the counted associations first, then the ones with the most running instances, then by name' {
        $row = @(
            (New-Row -Name 'Previous busy' -Running 50 -Counted $false)
            (New-Row -Name 'Zeta' -Running 5)
            (New-Row -Name 'Alpha' -Running 5)
            (New-Row -Name 'Busy' -Running 20)
            (New-Row -Name 'Idle' -Running 0)
        )

        $text = Get-Example -Row $row -Maximum 5

        @($text -split '; ' | ForEach-Object { ($_ -split ' \(')[0] }) | Should -BeExactly @('Busy', 'Alpha', 'Zeta', 'Idle', 'Previous busy')
    }

    It 'puts the rows that tie on the counted flag, the running instances and the name by web, then by list' {
        # Each pair is in the order that only one key gives: the other keys would put it the other way round.
        $row = @(
            (New-Row -Name 'Flow' -Web 'https://intranet/web/w2' -List 'Alpha')
            (New-Row -Name 'Flow' -Web 'https://intranet/web/w1' -List 'Zeta')
            (New-Row -Name 'Other' -Web 'https://intranet/web/w3' -List 'Tasks')
            (New-Row -Name 'Other' -Web 'https://intranet/web/w3' -List 'Documents')
        )

        $text = Get-Example -Row $row -Maximum 4

        $text | Should -BeExactly ('Flow (list Zeta, https://intranet/web/w1): 0 running instance(s); Flow (list Alpha, https://intranet/web/w2): 0 running instance(s); Other (list Documents, https://intranet/web/w3): 0 running instance(s); Other (list Tasks, https://intranet/web/w3): 0 running instance(s)')
    }

    It 'gives at most five rows, or the number that it is asked for, separated by semicolons' {
        $row = 1..8 | ForEach-Object { New-Row -Name ('Workflow {0}' -f $_) -Running (10 - $_) }

        @((Get-Example -Row $row) -split '; ') | Should -HaveCount 5
        @((Get-Example -Row $row -Maximum 2) -split '; ') | Should -HaveCount 2
        @((Get-Example -Row $row -Maximum 100) -split '; ') | Should -HaveCount 8
    }

    It 'skips a null among the rows' {
        Get-Example -Row @($null, (New-Row -Name 'Approval')) | Should -BeExactly 'Approval (list Documents, https://intranet/sites/team): 0 running instance(s)'
    }

    It 'gives the same text whatever the order of the rows' {
        $first = Get-Example -Row @((New-Row -Name 'A' -Running 1), (New-Row -Name 'B' -Running 1))
        $second = Get-Example -Row @((New-Row -Name 'B' -Running 1), (New-Row -Name 'A' -Running 1))

        $first | Should -BeExactly $second
    }
}
