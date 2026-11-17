# Behavior tests for Add-SPSWorkflowAssociationRow (the row of a classic workflow association, in the rows of a site collection).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    # A real .NET object, as SharePoint gives, and not a custom object: the association is told apart by the object itself.
    if (-not ('SPSTestWorkflowAssociation' -as [type])) {
        Add-Type -TypeDefinition @'
public class SPSTestWorkflowAssociation
{
    public string Name { get; set; }
    public int RunningInstances { get; set; }
}
'@
    }

    function New-Association {
        param ([string]$Name = 'Approval', [int]$Running = 0)
        [PSCustomObject]@{ Name = $Name; RunningInstances = $Running }
    }

    function New-Table {
        [PSCustomObject]@{ Current = [System.Collections.Generic.List[object]]::new(); Previous = [System.Collections.Generic.List[object]]::new() }
    }

    # The result of the function and the table that it changed.
    function Add-Row {
        param ($Table = (New-Table), $Association, [object[]]$Active = @(), [hashtable]$Extra = @{})
        $result = & $script:Module {
            param ($Table, $Association, $Active, $Extra)
            Add-SPSWorkflowAssociationRow -Table $Table -Association $Association -ActiveAssociation $Active -SiteUrl 'https://intranet/sites/team' -WebUrl 'https://intranet/sites/team/hr' @Extra
        } $Table $Association $Active $Extra
        [PSCustomObject]@{ Result = $result; Table = $Table }
    }
}

Describe 'Add-SPSWorkflowAssociationRow' {
    It 'adds the row of an association of a web, with the site collection, the web, the name and the running instances' {
        $association = New-Association -Name 'Publication' -Running 3

        $outcome = Add-Row -Association $association -Active @($association)

        $outcome.Result | Should -BeTrue
        $outcome.Table.Current | Should -HaveCount 1
        $row = $outcome.Table.Current[0]
        $row.SiteUrl | Should -BeExactly 'https://intranet/sites/team'
        $row.WebUrl | Should -BeExactly 'https://intranet/sites/team/hr'
        $row.Scope | Should -BeExactly 'Web'
        $row.ListTitle | Should -BeExactly ''
        $row.ListUrl | Should -BeExactly ''
        $row.WorkflowName | Should -BeExactly 'Publication'
        $row.Counted | Should -BeTrue
        $row.RunningInstances | Should -Be 3
    }

    It 'has the columns of the workflow association files, in their order' {
        $association = New-Association

        $outcome = Add-Row -Association $association -Active @($association)

        ($outcome.Table.Current[0].PSObject.Properties.Name -join ',') | Should -BeExactly 'SiteUrl,WebUrl,Scope,ListTitle,ListUrl,WorkflowName,Counted,RunningInstances'
    }

    It 'adds the row of an association of a list or library, with its title and its URL' {
        $association = New-Association -Name 'Approval' -Running 12

        $outcome = Add-Row -Association $association -Active @($association) -Extra @{ Scope = 'List'; ListTitle = 'Documents'; ListUrl = '/sites/team/hr/Shared Documents' }

        $row = $outcome.Table.Current[0]
        $row.Scope | Should -BeExactly 'List'
        $row.ListTitle | Should -BeExactly 'Documents'
        $row.ListUrl | Should -BeExactly '/sites/team/hr/Shared Documents'
        $row.RunningInstances | Should -Be 12
    }

    It 'counts an association when it is one of the active ones, and not one that only has the same name' {
        $current = New-Association -Name 'Approval' -Running 1
        $other = New-Association -Name 'Approval' -Running 5

        $first = Add-Row -Association $current -Active @($current)
        $second = Add-Row -Table $first.Table -Association $other -Active @($current)

        $first.Table.Current | Should -HaveCount 1
        $first.Table.Current[0].RunningInstances | Should -Be 1
        $first.Table.Previous | Should -HaveCount 1
        $first.Table.Previous[0].Counted | Should -BeFalse
        $first.Table.Previous[0].RunningInstances | Should -Be 5
        $second.Result | Should -BeTrue
    }

    It 'tells the associations apart when they are objects of SharePoint and not custom objects' {
        $current = [SPSTestWorkflowAssociation]::new()
        $current.Name = 'Approval'
        $current.RunningInstances = 2
        $previous = [SPSTestWorkflowAssociation]::new()
        $previous.Name = 'Approval (Previous Version: 08/07/2016 14:50:34)'
        $previous.RunningInstances = 7

        $active = @(& $script:Module { param ($Value) Get-SPSActiveWorkflowAssociations -WorkflowAssociations $Value } @($current, $previous))
        $table = New-Table
        $null = Add-Row -Table $table -Association $current -Active $active
        $null = Add-Row -Table $table -Association $previous -Active $active

        $active | Should -HaveCount 1
        $table.Current | Should -HaveCount 1
        $table.Current[0].WorkflowName | Should -BeExactly 'Approval'
        $table.Previous | Should -HaveCount 1
        $table.Previous[0].WorkflowName | Should -BeExactly 'Approval (Previous Version: 08/07/2016 14:50:34)'
        $table.Previous[0].Counted | Should -BeFalse
        $table.Previous[0].RunningInstances | Should -Be 7
    }

    It 'puts an association that is not active in the previous versions, with its running instances, and counts it as not counted' {
        $association = New-Association -Name 'Old (Previous Version: 1)' -Running 4

        $outcome = Add-Row -Association $association -Active @()

        $outcome.Result | Should -BeTrue
        $outcome.Table.Current | Should -HaveCount 0
        $outcome.Table.Previous | Should -HaveCount 1
        $outcome.Table.Previous[0].Counted | Should -BeFalse
        $outcome.Table.Previous[0].RunningInstances | Should -Be 4
    }

    It 'gives no running instance to an association that does not say how many there are' {
        $association = [PSCustomObject]@{ Name = 'Silent' }

        $outcome = Add-Row -Association $association -Active @($association)

        $outcome.Table.Current[0].RunningInstances | Should -Be 0
        $outcome.Table.Current[0].RunningInstances | Should -BeOfType [int]
    }

    It 'stops the rows of the previous versions at the maximum, says so, and goes on with the counted associations' {
        $table = New-Table
        $previous = 1..3 | ForEach-Object { New-Association -Name ('Old {0}' -f $_) -Running $_ }
        $current = New-Association -Name 'Current' -Running 9

        $results = foreach ($association in $previous) { (Add-Row -Table $table -Association $association -Active @() -Extra @{ MaximumPreviousVersion = 2 }).Result }
        $afterTheLimit = Add-Row -Table $table -Association $current -Active @($current) -Extra @{ MaximumPreviousVersion = 2 }

        @($results) | Should -Be @($true, $true, $false)
        $table.Previous | Should -HaveCount 2
        @($table.Previous | ForEach-Object { $_.WorkflowName }) | Should -Be @('Old 1', 'Old 2')
        $afterTheLimit.Result | Should -BeTrue
        $table.Current | Should -HaveCount 1
    }

    It 'keeps 1000 rows of previous versions by default, and not the 1001st' {
        $outcome = & $script:Module {
            param ($Association)
            $table = [PSCustomObject]@{ Current = [System.Collections.Generic.List[object]]::new(); Previous = [System.Collections.Generic.List[object]]::new() }
            $result = foreach ($index in 1..1001) {
                Add-SPSWorkflowAssociationRow -Table $table -Association $Association -ActiveAssociation @() -SiteUrl 'https://intranet/sites/team' -WebUrl 'https://intranet/sites/team'
            }
            [PSCustomObject]@{ Last = @($result)[-1]; Fitting = @($result | Where-Object { $_ }).Count; Previous = $table.Previous.Count }
        } (New-Association -Name 'Old' -Running 1)

        $outcome.Previous | Should -Be 1000
        $outcome.Fitting | Should -Be 1000
        $outcome.Last | Should -BeFalse
    }

    It 'does not limit the counted associations, which always add up to the count' {
        $table = New-Table
        $association = 1..5 | ForEach-Object { New-Association -Name ('Current {0}' -f $_) }

        foreach ($item in $association) {
            (Add-Row -Table $table -Association $item -Active @($association) -Extra @{ MaximumPreviousVersion = 1 }).Result | Should -BeTrue
        }

        $table.Current | Should -HaveCount 5
    }

    It 'ignores a null in the active associations' {
        $association = New-Association

        $outcome = Add-Row -Association $association -Active @($null, $association)

        $outcome.Table.Current | Should -HaveCount 1
    }

    It 'accepts a site collection and a web without a URL' {
        $association = New-Association
        $table = New-Table

        $result = & $script:Module {
            param ($Table, $Association)
            Add-SPSWorkflowAssociationRow -Table $Table -Association $Association -ActiveAssociation @($Association) -SiteUrl '' -WebUrl ''
        } $table $association

        $result | Should -BeTrue
        $table.Current[0].WebUrl | Should -BeExactly ''
    }

    It 'refuses a scope that is not Web or List, and a maximum that is not a positive number' {
        $association = New-Association

        { Add-Row -Association $association -Extra @{ Scope = 'Site' } } | Should -Throw
        { Add-Row -Association $association -Extra @{ MaximumPreviousVersion = 0 } } | Should -Throw
    }
}
