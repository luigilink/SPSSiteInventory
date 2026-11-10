# Behavior tests for Get-SPSEventReceiverExample (the examples of the EventReceivers signal).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function New-Row {
        param (
            [string]$AssemblyName = 'Contoso.Intranet', [string]$Class = 'Contoso.Intranet.ItemReceiver', [int]$Receivers = 600, [int]$Lists = 100,
            [string]$FirstListUrl = '/sites/team/Lists/Tasks', [string]$FarmSolutionName = '', [string]$PackageName = '', [string]$Assembly = ''
        )
        [PSCustomObject]@{
            Assembly = $Assembly; AssemblyName = $AssemblyName; Class = $Class; ReceiverCount = $Receivers; ListCount = $Lists
            FirstListUrl = $FirstListUrl; FarmSolutionName = $FarmSolutionName; PackageName = $PackageName
        }
    }

    function Get-Example {
        param ([object[]]$Row, [int]$Maximum = 0)
        & $script:Module {
            param ($Row, $Maximum)
            if ($Maximum -gt 0) { Get-SPSEventReceiverExample -Row $Row -Maximum $Maximum } else { Get-SPSEventReceiverExample -Row $Row }
        } $Row $Maximum
    }
}

Describe 'Get-SPSEventReceiverExample' {
    It 'writes the assembly and the class, how many receivers and lists there are, and the first list' {
        Get-Example @((New-Row)) | Should -Be 'Contoso.Intranet / Contoso.Intranet.ItemReceiver: 600 receiver(s) on 100 list(s), first /sites/team/Lists/Tasks'
    }

    It 'names the farm solution that ships the assembly, or else the package' {
        Get-Example @((New-Row -FarmSolutionName 'contoso.intranet.wsp' -PackageName 'Contoso.Intranet.wsp')) | Should -Match ' \(solution contoso\.intranet\.wsp\)$'
        Get-Example @((New-Row -PackageName 'Contoso.Intranet.wsp')) | Should -Match ' \(package Contoso\.Intranet\.wsp\)$'
    }

    It 'leaves out the class, the list and the solution that it does not have' {
        Get-Example @((New-Row -Class '' -FirstListUrl '')) | Should -Be 'Contoso.Intranet: 600 receiver(s) on 100 list(s)'
    }

    It 'falls back on the assembly as it is registered when its name could not be read' {
        Get-Example @((New-Row -AssemblyName '' -Assembly ', Version=1.0.0.0' -Class '')) | Should -Match '^, Version=1\.0\.0\.0: 600 receiver'
    }

    It 'separates the rows with a semicolon, in the order that they are given' {
        $text = Get-Example @((New-Row -Class 'A' -Receivers 3), (New-Row -Class 'B' -Receivers 2))

        $text | Should -Be 'Contoso.Intranet / A: 3 receiver(s) on 100 list(s), first /sites/team/Lists/Tasks; Contoso.Intranet / B: 2 receiver(s) on 100 list(s), first /sites/team/Lists/Tasks'
    }

    It 'gives five rows at most, and as many as asked for' {
        $row = 1..8 | ForEach-Object { New-Row -Class ('C{0}' -f $_) }

        @((Get-Example $row) -split '; ') | Should -HaveCount 5
        @((Get-Example $row -Maximum 2) -split '; ') | Should -HaveCount 2
        (Get-Example $row) | Should -Not -Match 'C6'
    }

    It 'gives an empty text for no row' -ForEach @(
        @{ Row = @() }
        @{ Row = $null }
        @{ Row = @($null) }
    ) {
        Get-Example $Row | Should -Be ''
    }
}
