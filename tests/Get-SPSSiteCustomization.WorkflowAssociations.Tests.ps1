# Behavior tests for the workflow association detail of Get-SPSSiteCustomization: which associations the Workflow2010 signals
# count, with their web, list and running instances. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function global:Get-SPAppInstance {
        param($Web)
        @()
    }

    function New-TestAssociation {
        param ([string]$Name = 'Approval', [int]$Running = 0, $IsCurrent = $null)
        $association = [PSCustomObject]@{ Name = $Name; RunningInstances = $Running }
        if ($null -ne $IsCurrent) {
            $association | Add-Member -NotePropertyName IsCurrent -NotePropertyValue ([bool]$IsCurrent)
        }
        $association
    }

    function New-TestList {
        param ([string]$Title = 'Documents', [string]$Url = '/sites/team/Shared Documents', [object[]]$Association = @())
        [PSCustomObject]@{
            ID = [guid]::NewGuid()
            Title = $Title
            RootFolder = [PSCustomObject]@{ ServerRelativeUrl = $Url; Properties = @{} }
            ContentTypes = @()
            WorkflowAssociations = $Association
            EventReceivers = @()
            IrmEnabled = $false
            ItemCount = 0
            Views = @()
            CheckedOutFiles = @()
            EnableVersioning = $false
            Items = @()
            BaseTemplate = 100
            Fields = @()
            HasExternalDataSource = $false
        }
    }

    function New-TestWeb {
        param ([string]$Url = 'https://intranet.contoso.com/sites/team', [object[]]$List = @(), [object[]]$Association = @(), [bool]$IsRootWeb = $true)
        $web = [PSCustomObject]@{
            Url = $Url
            ContentTypes = @(); Lists = $List; WorkflowAssociations = $Association; HasUniqueRoleAssignments = $false
            CustomMasterUrl = ''; Features = @(); Files = @(); IsRootWeb = $IsRootWeb; HasUniqueRoleDefinitions = $true
            RoleDefinitions = @(); Alerts = @(); AlternateCssUrl = ''; RootFolder = [PSCustomObject]@{ WelcomePage = '' }
        }
        $web | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        $web
    }

    function New-TestSite {
        param ([object[]]$Web)
        [PSCustomObject]@{ Url = 'https://intranet.contoso.com/sites/team'; Features = @(); Solutions = @(); AllWebs = @($Web) }
    }

    function Get-Signal {
        param ($Site)
        $warnings = @()
        $signals = Get-SPSSiteCustomization -Site $Site -WarningVariable warnings -WarningAction SilentlyContinue
        [PSCustomObject]@{ Signals = $signals; Warnings = @($warnings | ForEach-Object { [string]$_ }) }
    }
}

Describe 'Get-SPSSiteCustomization workflow associations' {
    It 'gives a row for each association of the webs and of the lists, with the web, the list and the running instances' {
        $team = New-TestWeb -Association @((New-TestAssociation -Name 'Publication' -Running 1)) -List @((New-TestList -Title 'Documents' -Url '/sites/team/Shared Documents' -Association @((New-TestAssociation -Name 'Approval' -Running 3))))
        $hr = New-TestWeb -Url 'https://intranet.contoso.com/sites/team/hr' -IsRootWeb $false -List @((New-TestList -Title 'Tasks' -Url '/sites/team/hr/Lists/Tasks' -Association @((New-TestAssociation -Name 'Review'))))

        $row = @((Get-Signal -Site (New-TestSite -Web @($hr, $team))).Signals.WorkflowAssociations)

        $row | Should -HaveCount 3
        $row[0].SiteUrl | Should -BeExactly 'https://intranet.contoso.com/sites/team'
        $row[0].WebUrl | Should -BeExactly 'https://intranet.contoso.com/sites/team'
        $row[0].Scope | Should -BeExactly 'Web'
        $row[0].ListTitle | Should -BeExactly ''
        $row[0].WorkflowName | Should -BeExactly 'Publication'
        $row[0].RunningInstances | Should -Be 1
        $row[1].SiteUrl | Should -BeExactly 'https://intranet.contoso.com/sites/team'
        $row[1].WebUrl | Should -BeExactly 'https://intranet.contoso.com/sites/team'
        $row[1].Scope | Should -BeExactly 'List'
        $row[1].ListTitle | Should -BeExactly 'Documents'
        $row[1].ListUrl | Should -BeExactly '/sites/team/Shared Documents'
        $row[1].WorkflowName | Should -BeExactly 'Approval'
        $row[1].RunningInstances | Should -Be 3
        $row[2].SiteUrl | Should -BeExactly 'https://intranet.contoso.com/sites/team'
        $row[2].WebUrl | Should -BeExactly 'https://intranet.contoso.com/sites/team/hr'
        $row[2].ListTitle | Should -BeExactly 'Tasks'
        $row[2].RunningInstances | Should -Be 0
    }

    It 'adds up to the counts: the counted rows are Workflow2010Count and all the rows are the running instances' {
        $web = New-TestWeb -Association @((New-TestAssociation -Name 'Publication' -Running 1), (New-TestAssociation -Name 'Publication (Previous Version: 08/07/2016 14:50:34)' -Running 4)) -List @(
            (New-TestList -Title 'Documents' -Association @((New-TestAssociation -Name 'Approval' -Running 2), (New-TestAssociation -Name 'Old' -Running 6 -IsCurrent $false)))
            (New-TestList -Title 'Tasks' -Association @((New-TestAssociation -Name 'Review' -Running 0)))
        )

        $signals = (Get-Signal -Site (New-TestSite -Web @($web))).Signals

        $row = @($signals.WorkflowAssociations)
        $row | Should -HaveCount 5
        @($row | Where-Object { $_.Counted }) | Should -HaveCount $signals.Workflow2010Count
        $signals.Workflow2010Count | Should -Be 3
        (($row | Measure-Object -Property RunningInstances -Sum).Sum) | Should -Be $signals.Workflow2010RunningInstanceCount
        $signals.Workflow2010RunningInstanceCount | Should -Be 13
    }

    It 'says which associations are previous versions, by their name or by what SharePoint says, and does not count them' {
        $web = New-TestWeb -List @((New-TestList -Association @(
                    (New-TestAssociation -Name 'Flow')
                    (New-TestAssociation -Name 'Flow (Previous Version: 08/07/2016 14:50:34)' -Running 2)
                    (New-TestAssociation -Name 'Other' -IsCurrent $false -Running 1)
                )))

        $row = @((Get-Signal -Site (New-TestSite -Web @($web))).Signals.WorkflowAssociations)

        @($row | Where-Object { $_.Counted } | ForEach-Object { $_.WorkflowName }) | Should -BeExactly @('Flow')
        @($row | Where-Object { -not $_.Counted } | ForEach-Object { $_.WorkflowName }) | Should -BeExactly @('Flow (Previous Version: 08/07/2016 14:50:34)', 'Other')
    }

    It 'gives the examples of the associations in the signals, the counted ones with the most running instances first' {
        $web = New-TestWeb -List @((New-TestList -Title 'Documents' -Association @((New-TestAssociation -Name 'Quiet' -Running 1), (New-TestAssociation -Name 'Busy' -Running 20), (New-TestAssociation -Name 'Old' -Running 99 -IsCurrent $false))))

        $examples = (Get-Signal -Site (New-TestSite -Web @($web))).Signals.Workflow2010Examples

        $examples | Should -BeExactly 'Busy (list Documents, https://intranet.contoso.com/sites/team): 20 running instance(s); Quiet (list Documents, https://intranet.contoso.com/sites/team): 1 running instance(s); Old (list Documents, https://intranet.contoso.com/sites/team): 99 running instance(s) [previous version]'
    }

    It 'gives no row and no example for a site collection that has no association, and ignores a null association' {
        $none = (Get-Signal -Site (New-TestSite -Web @((New-TestWeb -List @((New-TestList)))))).Signals
        $withNull = (Get-Signal -Site (New-TestSite -Web @((New-TestWeb -Association @($null, (New-TestAssociation)))))).Signals

        @($none.WorkflowAssociations) | Should -HaveCount 0
        $none.Workflow2010Examples | Should -BeExactly ''
        @($withNull.WorkflowAssociations) | Should -HaveCount 1
        $withNull.Workflow2010Count | Should -Be 1
    }

    It 'stops the rows of the previous versions at 1000, keeps every counted row, warns once, and leaves the counts exact' -ForEach @(
        @{ Where = 'on a list'; OnList = $true }
        @{ Where = 'on a web'; OnList = $false }
    ) {
        $previous = 1..1005 | ForEach-Object { New-TestAssociation -Name ('Flow {0} (old)' -f $_) -Running 1 -IsCurrent $false }
        $association = @((New-TestAssociation -Name 'Flow' -Running 2), (New-TestAssociation -Name 'Other' -Running 3)) + $previous
        $web = if ($OnList) { New-TestWeb -List @((New-TestList -Association $association)) } else { New-TestWeb -Association $association }

        $result = Get-Signal -Site (New-TestSite -Web @($web))

        $row = @($result.Signals.WorkflowAssociations)
        $row | Should -HaveCount 1002
        @($row | Where-Object { $_.Counted }) | Should -HaveCount 2
        @($row | Where-Object { -not $_.Counted }) | Should -HaveCount 1000
        $result.Signals.Workflow2010Count | Should -Be 2
        $result.Signals.Workflow2010RunningInstanceCount | Should -Be 1010
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
        $result.Warnings | Should -HaveCount 1 -Because $Where
        $result.Warnings[0] | Should -BeExactly "Workflow association rows of previous versions stopped after 1000 on site 'https://intranet.contoso.com/sites/team'; Workflow2010Count and Workflow2010RunningInstanceCount stay exact."
    }

    It 'does not warn at the limit' {
        $previous = 1..1000 | ForEach-Object { New-TestAssociation -Name ('Flow {0} (old)' -f $_) -IsCurrent $false }
        $web = New-TestWeb -List @((New-TestList -Association $previous))

        $result = Get-Signal -Site (New-TestSite -Web @($web))

        @($result.Signals.WorkflowAssociations) | Should -HaveCount 1000
        $result.Warnings | Should -HaveCount 0
    }

    It 'keeps the counts and the other signals, has no row, and warns with the reason, when the rows cannot be built' -ForEach @(
        @{ Detail = 'Add-SPSWorkflowAssociationRow'; Where = 'on a web'; OnWeb = $true; OnList = $false }
        @{ Detail = 'Add-SPSWorkflowAssociationRow'; Where = 'on a list'; OnWeb = $false; OnList = $true }
        @{ Detail = 'Add-SPSWorkflowAssociationRow'; Where = 'on a web and on a list'; OnWeb = $true; OnList = $true }
        @{ Detail = 'Get-SPSWorkflowAssociationExample'; Where = 'on a web and on a list'; OnWeb = $true; OnList = $true }
    ) {
        Mock -ModuleName SPSSiteInventory.Common -CommandName $Detail -MockWith { throw 'The detail failed.' }
        $webAssociation = if ($OnWeb) { @((New-TestAssociation -Name 'Publication' -Running 1)) } else { @() }
        $listAssociation = if ($OnList) { @((New-TestAssociation -Name 'Approval' -Running 2)) } else { @() }
        $web = New-TestWeb -Association $webAssociation -List @((New-TestList -Association $listAssociation))

        $result = Get-Signal -Site (New-TestSite -Web @($web))

        $result.Signals.Workflow2010Count | Should -Be ([int]$OnWeb + [int]$OnList) -Because $Where
        $result.Signals.Workflow2010RunningInstanceCount | Should -Be ([int]$OnWeb + 2 * [int]$OnList) -Because $Where
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue -Because $Where
        $result.Signals.ContentTypeInventoryComplete | Should -BeTrue -Because $Where
        @($result.Signals.WorkflowAssociations) | Should -HaveCount 0
        $result.Signals.Workflow2010Examples | Should -BeExactly ''
        $result.Warnings | Should -HaveCount 1 -Because $Where
        $result.Warnings[0] | Should -BeExactly "The workflow associations of site 'https://intranet.contoso.com/sites/team' could not be fully listed: The detail failed.; Workflow2010Count and Workflow2010RunningInstanceCount stay exact."
    }
}
