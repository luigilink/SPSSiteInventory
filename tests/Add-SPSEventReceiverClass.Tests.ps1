# Behavior tests for Add-SPSEventReceiverClass (the groups of custom event receivers of a site collection).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    # A folder whose URL cannot be read. It is a real .NET type: PowerShell turns an exception of a getter into $null.
    if (-not ('SPSTestFolderWithoutUrl' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
public class SPSTestFolderWithoutUrl
{
    public string ServerRelativeUrl { get { throw new InvalidOperationException("url unavailable"); } }
}
'@
    }

    $script:Contoso = 'Contoso.Intranet, Version=1.0.0.0, Culture=neutral, PublicKeyToken=0123456789abcdef'

    function New-Table {
        [System.Collections.Generic.Dictionary[System.String, System.Object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }

    function New-List {
        param ([string]$Title = 'Tasks', [string]$Url = '/sites/team/Lists/Tasks')
        [PSCustomObject]@{ ID = [guid]::NewGuid(); Title = $Title; RootFolder = [PSCustomObject]@{ ServerRelativeUrl = $Url } }
    }

    function New-Receiver {
        param ([string]$Assembly = $script:Contoso, [string]$Class = 'Contoso.Intranet.ItemReceiver', [string]$Type = 'ItemAdded')
        [PSCustomObject]@{ Assembly = $Assembly; Class = $Class; Type = $Type }
    }

    function Add-Receiver {
        param ($Table, $Receiver, $List, [int]$Maximum = 200)
        & $script:Module { param ($T, $R, $L, $M) Add-SPSEventReceiverClass -Table $T -Receiver $R -List $L -MaximumGroup $M } $Table $Receiver $List $Maximum
    }
}

Describe 'Add-SPSEventReceiverClass' {
    It 'counts the receivers of a class, the lists that they are on and their event types' {
        $table = New-Table
        $one = New-List -Title 'One'
        $two = New-List -Title 'Two'

        $null = Add-Receiver $table (New-Receiver -Type 'ItemUpdated') $one
        $null = Add-Receiver $table (New-Receiver -Type 'ItemAdded') $one
        $null = Add-Receiver $table (New-Receiver -Type 'ItemAdded') $two

        $table.Count | Should -Be 1
        $group = @($table.Values)[0]
        $group.Assembly | Should -Be $script:Contoso
        $group.Class | Should -Be 'Contoso.Intranet.ItemReceiver'
        $group.ReceiverCount | Should -Be 3
        $group.List.Count | Should -Be 2
        @($group.EventType | Sort-Object) | Should -Be @('ItemAdded', 'ItemUpdated')
    }

    It 'returns true when it counts a receiver' {
        Add-Receiver (New-Table) (New-Receiver) (New-List) | Should -BeTrue
    }

    It 'keeps the classes of an assembly, and the assemblies of a class, apart' {
        $table = New-Table
        $list = New-List

        $null = Add-Receiver $table (New-Receiver -Class 'Contoso.Intranet.A') $list
        $null = Add-Receiver $table (New-Receiver -Class 'Contoso.Intranet.B') $list
        $null = Add-Receiver $table (New-Receiver -Assembly 'Fabrikam.Docs, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null' -Class 'Contoso.Intranet.A') $list

        $table.Count | Should -Be 3
    }

    It 'groups the receivers of an assembly and a class without looking at the case' {
        $table = New-Table
        $list = New-List

        $null = Add-Receiver $table (New-Receiver -Assembly 'CONTOSO.INTRANET, Version=1.0.0.0, Culture=neutral, PublicKeyToken=0123456789ABCDEF' -Class 'CONTOSO.intranet.ItemReceiver') $list
        $null = Add-Receiver $table (New-Receiver) $list

        $table.Count | Should -Be 1
        @($table.Values)[0].ReceiverCount | Should -Be 2
    }

    It 'remembers the first list where a class is registered, and does not change it' {
        $table = New-Table

        $null = Add-Receiver $table (New-Receiver) (New-List -Title 'First' -Url '/sites/team/Lists/First')
        $null = Add-Receiver $table (New-Receiver) (New-List -Title 'Second' -Url '/sites/team/Lists/Second')

        @($table.Values)[0].FirstListUrl | Should -Be '/sites/team/Lists/First'
    }

    It 'gives the title of the list when its URL cannot be read' -ForEach @(
        @{ Case = 'no root folder'; Kind = 'none' }
        @{ Case = 'an empty URL'; Kind = 'empty' }
        @{ Case = 'a folder that fails'; Kind = 'fails' }
    ) {
        $root = switch ($Kind) {
            'none' { $null }
            'empty' { [PSCustomObject]@{ ServerRelativeUrl = '' } }
            'fails' { [SPSTestFolderWithoutUrl]::new() }
        }
        $list = [PSCustomObject]@{ ID = [guid]::NewGuid(); Title = 'Tasks'; RootFolder = $root }
        $table = New-Table

        $null = Add-Receiver $table (New-Receiver) $list

        @($table.Values)[0].FirstListUrl | Should -Be 'Tasks' -Because $Case
    }

    It 'tells two lists apart by their ID, and by their title when they have no ID' {
        $table = New-Table
        $withId = [PSCustomObject]@{ ID = [guid]::NewGuid(); Title = 'Same'; RootFolder = $null }
        $otherWithId = [PSCustomObject]@{ ID = [guid]::NewGuid(); Title = 'Same'; RootFolder = $null }
        $noId = [PSCustomObject]@{ Title = 'Same'; RootFolder = $null }
        $otherNoId = [PSCustomObject]@{ Title = 'Other'; RootFolder = $null }

        $null = Add-Receiver $table (New-Receiver) $withId
        $null = Add-Receiver $table (New-Receiver) $withId
        $null = Add-Receiver $table (New-Receiver) $otherWithId
        $null = Add-Receiver $table (New-Receiver) $noId
        $null = Add-Receiver $table (New-Receiver) $noId
        $null = Add-Receiver $table (New-Receiver) $otherNoId

        @($table.Values)[0].List.Count | Should -Be 4
        @($table.Values)[0].ReceiverCount | Should -Be 6
    }

    It 'does not keep an event type that is empty' {
        $table = New-Table

        $null = Add-Receiver $table (New-Receiver -Type '') (New-List)
        $null = Add-Receiver $table ([PSCustomObject]@{ Assembly = $script:Contoso; Class = 'Contoso.Intranet.ItemReceiver' }) (New-List)

        @($table.Values)[0].ReceiverCount | Should -Be 2
        @($table.Values)[0].EventType.Count | Should -Be 0
    }

    It 'adds no group, and returns false, when the table is full, and goes on counting the groups that exist' {
        $table = New-Table
        $list = New-List

        $null = Add-Receiver $table (New-Receiver -Class 'A') $list -Maximum 2
        $null = Add-Receiver $table (New-Receiver -Class 'B') $list -Maximum 2
        $full = Add-Receiver $table (New-Receiver -Class 'C') $list -Maximum 2
        $existing = Add-Receiver $table (New-Receiver -Class 'A') $list -Maximum 2

        $full | Should -BeFalse
        $existing | Should -BeTrue
        $table.Count | Should -Be 2
        $table[('{0}|A' -f $script:Contoso)].ReceiverCount | Should -Be 2
    }

    It 'reads a receiver that has no class, or no assembly, as empty text' {
        $table = New-Table

        $null = Add-Receiver $table ([PSCustomObject]@{ Assembly = $script:Contoso; Class = $null; Type = 'ItemAdded' }) (New-List)

        @($table.Values)[0].Class | Should -Be ''
    }
}
