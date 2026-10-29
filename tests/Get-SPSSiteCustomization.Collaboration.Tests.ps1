# Behavior tests for the audience targeting and the site notebook signals of Get-SPSSiteCustomization: the list items that
# target an audience and the notebook that the Site Notebook feature creates, which do not migrate as they are. No farm is
# needed: the lists are fakes, and the audience manager is a mock.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    # A column whose ID cannot be read. It is a real .NET type: PowerShell turns an exception of a getter into $null.
    if (-not ('SPSTestCollabFailingIdField' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
public class SPSTestCollabFailingIdField
{
    public Guid Id { get { throw new InvalidOperationException("id unavailable"); } }
    public string InternalName { get { return "Broken"; } }
}
'@
    }

    function global:Get-SPAppInstance {
        param($Web)
        @()
    }

    $script:TargetingId = [guid]'61cbb965-1e04-4273-b658-eedaa662f48d'
    $script:IdSales = 'a88b9dcb-0000-0000-0000-000000000001'
    $script:IdMarketing = 'a88b9dcb-0000-0000-0000-000000000002'

    function New-TargetingField {
        param ([string]$InternalName = 'Target_x0020_Audiences')
        [PSCustomObject]@{ InternalName = $InternalName; Id = $script:TargetingId; TypeAsString = 'TargetTo' }
    }

    function New-TestBatch {
        param ([object[]]$Item, $Position = $null)
        [PSCustomObject]@{ Items = @($Item); Position = $Position }
    }

    # An item of a list: the values of its columns, which the scans read by name.
    function New-TestItem {
        param ([hashtable]$Value)
        $Value
    }

    # A list. It answers the query of the audience targeting scan (the one that has the column in its view fields) and the one of
    # the site notebooks (the one for folders) with its batches, and finds nothing for the other scans.
    function New-TestList {
        param (
            [string]$Title = 'Announcements', [string]$Url = '/sites/team/Lists/Announcements', [int]$BaseTemplate = 104,
            [object[]]$Fields = @(), [object[]]$Batches = @(), [string]$ErrorText = '', [bool]$Hidden = $false, [string]$FieldName = 'Target_x0020_Audiences', [switch]$Folders
        )
        $list = [PSCustomObject]@{
            Title = $Title
            RootFolder = [PSCustomObject]@{ ServerRelativeUrl = $Url; Properties = @{} }
            ContentTypes = @()
            WorkflowAssociations = @()
            EventReceivers = @()
            IrmEnabled = $false
            ItemCount = 0
            Views = @()
            CheckedOutFiles = @()
            EnableVersioning = $false
            Items = @()
            BaseTemplate = $BaseTemplate
            Fields = $Fields
            Hidden = $Hidden
            HasExternalDataSource = $false
            Batches = $Batches
            BatchIndex = 0
            FieldName = $FieldName
            ErrorText = $ErrorText
            Folders = [bool]$Folders
            Calls = 0
            Queries = [System.Collections.Generic.List[object]]::new()
        }
        $list | Add-Member -MemberType ScriptMethod -Name GetItems -Value {
            param ($Query)
            $isAudienceQuery = -not $this.Folders -and $Query.PSObject.Properties['ViewFields'] -and [string]$Query.ViewFields -match [regex]::Escape($this.FieldName)
            $isFolderQuery = $this.Folders -and $Query.PSObject.Properties['Query'] -and [string]$Query.Query -match 'FSObjType'
            if (-not ($isAudienceQuery -or $isFolderQuery)) {
                return [PSCustomObject]@{ Items = @(); ListItemCollectionPosition = $null }
            }
            $this.Calls++
            $this.Queries.Add([PSCustomObject]@{
                    RowLimit = [string]$Query.RowLimit; ViewFields = [string]$Query.ViewFields; Query = [string]$Query.Query
                    ViewFieldsOnly = [string]$Query.ViewFieldsOnly; Throttle = [string]$Query.QueryThrottleMode
                    Position = [string]$Query.ListItemCollectionPosition; ViewAttributes = [string]$Query.ViewAttributes
                })
            if ($this.ErrorText) { throw $this.ErrorText }
            $batch = $this.Batches[$this.BatchIndex]
            $this.BatchIndex++
            return [PSCustomObject]@{ Items = @($batch.Items); ListItemCollectionPosition = $batch.Position }
        }
        return $list
    }

    function New-TestSiteAssets {
        param ([object[]]$Batches = @(), [string]$Url = '/sites/team/SiteAssets', [string]$ErrorText = '')
        New-TestList -Title 'Site Assets' -Url $Url -BaseTemplate 101 -Batches $Batches -ErrorText $ErrorText -Folders
    }

    function New-TestNotebook {
        param ([string]$Name = 'Team Notebook', [string]$Type = 'OneNote.Notebook')
        New-TestItem @{ FileLeafRef = $Name; FileRef = "/sites/team/SiteAssets/$Name"; HTML_x0020_File_x0020_Type = $Type }
    }

    function New-TestSite {
        param ([object[]]$List)
        $web = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            ContentTypes = @(); Lists = $List; WorkflowAssociations = @(); HasUniqueRoleAssignments = $false
            CustomMasterUrl = ''; Features = @(); Files = @(); IsRootWeb = $true; HasUniqueRoleDefinitions = $true
            RoleDefinitions = @(); Alerts = @(); AlternateCssUrl = ''; RootFolder = [PSCustomObject]@{ WelcomePage = '' }
        }
        $web | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        [PSCustomObject]@{ Url = 'https://intranet.contoso.com/sites/team'; Features = @(); Solutions = @(); AllWebs = @($web) }
    }

    function Get-Signal {
        param ($Site, [hashtable]$Threshold = @{})
        $warnings = @()
        $signals = Get-SPSSiteCustomization -Site $Site -LargeContentThresholds $Threshold -WarningVariable warnings -WarningAction SilentlyContinue
        [PSCustomObject]@{ Signals = $signals; Warnings = @($warnings | ForEach-Object { [string]$_ }) }
    }

    # The mock reads a global variable: a closure would lose the mocked command's parameters.
    function Set-AudienceNames {
        param ([hashtable]$Name = @{})
        $global:SPSTestAudienceNames = $Name
        Mock Resolve-SPSAudienceName -ModuleName SPSSiteInventory.Common -MockWith { $global:SPSTestAudienceNames }
    }
}

AfterAll {
    Remove-Variable -Name SPSTestAudienceNames -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Get-SPSSiteCustomization audience targeting' {
    BeforeEach {
        Set-AudienceNames -Name @{ $script:IdSales = 'Sales'; $script:IdMarketing = 'Marketing' }
    }

    It 'counts the items that target an audience and the lists that hold them, and says which audiences, by name' {
        $targeted = New-TestItem @{ Target_x0020_Audiences = "$($script:IdSales),$($script:IdMarketing),;;;;" }
        $other = New-TestItem @{ Target_x0020_Audiences = "$($script:IdSales);;;;" }
        $untargeted = New-TestItem @{ Target_x0020_Audiences = $null }
        $list = New-TestList -Fields @((New-TargetingField)) -Batches @((New-TestBatch -Item @($targeted, $untargeted, $other)))

        $result = Get-Signal -Site (New-TestSite -List @($list))

        $result.Signals.AudienceTargetedItemCount | Should -Be 2
        $result.Signals.AudienceTargetedListCount | Should -Be 1
        $result.Signals.AudienceTargetedExamples | Should -Be '/sites/team/Lists/Announcements (2 item(s): Sales, Marketing)'
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
    }

    It 'shows an audience that has no name by its ID, a distribution list by its common name, a SharePoint group by its name' {
        Set-AudienceNames -Name @{}
        $item = New-TestItem @{ Target_x0020_Audiences = "$($script:IdSales);;cn=All Staff,ou=lists,dc=contoso;;Owners,not-a-guid" }
        $list = New-TestList -Fields @((New-TargetingField)) -Batches @((New-TestBatch -Item @($item)))

        $result = Get-Signal -Site (New-TestSite -List @($list))

        $result.Signals.AudienceTargetedExamples | Should -Be "/sites/team/Lists/Announcements (1 item(s): $($script:IdSales), All Staff, Owners, not-a-guid)"
    }

    It 'keeps an escaped comma in the common name of a distribution list' {
        $item = New-TestItem @{ Target_x0020_Audiences = ';;cn=Smith\, Jane,ou=lists,dc=contoso;;' }
        $list = New-TestList -Fields @((New-TargetingField)) -Batches @((New-TestBatch -Item @($item)))

        (Get-Signal -Site (New-TestSite -List @($list))).Signals.AudienceTargetedExamples | Should -Be '/sites/team/Lists/Announcements (1 item(s): Smith\, Jane)'
    }

    It 'shows at most five audiences of a list and says how many more there are' {
        $item = New-TestItem @{ Target_x0020_Audiences = ';;;;G1,G2,G3,G4,G5,G6,G7' }
        $list = New-TestList -Fields @((New-TargetingField)) -Batches @((New-TestBatch -Item @($item)))

        (Get-Signal -Site (New-TestSite -List @($list))).Signals.AudienceTargetedExamples | Should -Be '/sites/team/Lists/Announcements (1 item(s): G1, G2, G3, G4, G5 (+2 more))'
    }

    It 'does not count an item whose value targets nothing' -ForEach @(
        @{ Text = '' }
        @{ Text = ' ' }
        @{ Text = ';;;;' }
        @{ Text = ' , ;; ;; ' }
    ) {
        $list = New-TestList -Fields @((New-TargetingField)) -Batches @((New-TestBatch -Item @((New-TestItem @{ Target_x0020_Audiences = $Text }))))

        $result = Get-Signal -Site (New-TestSite -List @($list))

        $result.Signals.AudienceTargetedItemCount | Should -Be 0
        $result.Signals.AudienceTargetedListCount | Should -Be 0
        $result.Signals.AudienceTargetedExamples | Should -Be ''
    }

    It 'reads the column of a Pages library, which is named Audience' {
        $item = New-TestItem @{ Audience = ';;;;Owners' }
        $pages = New-TestList -Title 'Pages' -Url '/sites/team/Pages' -BaseTemplate 850 -FieldName 'Audience' -Fields @((New-TargetingField -InternalName 'Audience')) -Batches @((New-TestBatch -Item @($item)))

        $result = Get-Signal -Site (New-TestSite -List @($pages))

        $result.Signals.AudienceTargetedItemCount | Should -Be 1
        $result.Signals.AudienceTargetedExamples | Should -Be '/sites/team/Pages (1 item(s): Owners)'
    }

    It 'asks for the pages of the column in order, without a filter on it, with the throttle override' {
        $list = New-TestList -Fields @((New-TargetingField)) -Batches @((New-TestBatch -Item @()))

        $null = Get-Signal -Site (New-TestSite -List @($list))

        $list.Queries | Should -HaveCount 1
        $list.Queries[0].RowLimit | Should -Be '200'
        $list.Queries[0].ViewFields | Should -Be '<FieldRef Name="Target_x0020_Audiences" />'
        $list.Queries[0].ViewFieldsOnly | Should -Be 'True'
        $list.Queries[0].Query | Should -BeNullOrEmpty
        $list.Queries[0].Throttle | Should -Be 'Override'
        $list.Queries[0].ViewAttributes | Should -Be "Scope='RecursiveAll'"
    }

    It 'follows the pages of a list' {
        $first = New-TestBatch -Item @((New-TestItem @{ Target_x0020_Audiences = ';;;;Owners' })) -Position 'Paged=TRUE&p_ID=1'
        $second = New-TestBatch -Item @((New-TestItem @{ Target_x0020_Audiences = ';;;;Members' }), (New-TestItem @{ Target_x0020_Audiences = '' }))
        $list = New-TestList -Fields @((New-TargetingField)) -Batches @($first, $second)

        $result = Get-Signal -Site (New-TestSite -List @($list))

        $result.Signals.AudienceTargetedItemCount | Should -Be 2
        $list.Queries | Should -HaveCount 2
        $list.Queries[1].Position | Should -Be 'Paged=TRUE&p_ID=1'
    }

    It 'does not read a list that has no audience targeting column, a hidden list or a system catalog' {
        $plain = New-TestList -Title 'Tasks' -Url '/sites/team/Lists/Tasks' -Fields @([PSCustomObject]@{ InternalName = 'Title'; Id = [guid]::NewGuid(); TypeAsString = 'Text' }) -Batches @((New-TestBatch -Item @()))
        $hidden = New-TestList -Title 'Hidden' -Hidden $true -Fields @((New-TargetingField)) -Batches @((New-TestBatch -Item @((New-TestItem @{ Target_x0020_Audiences = ';;;;Owners' }))))
        $catalog = New-TestList -Title 'Master Page Gallery' -Url '/sites/team/_catalogs/masterpage' -Fields @((New-TargetingField)) -Batches @((New-TestBatch -Item @((New-TestItem @{ Target_x0020_Audiences = ';;;;Owners' }))))

        $result = Get-Signal -Site (New-TestSite -List @($plain, $hidden, $catalog))

        $plain.Calls + $hidden.Calls + $catalog.Calls | Should -Be 0
        $result.Signals.AudienceTargetedItemCount | Should -Be 0
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
        Should -Invoke Resolve-SPSAudienceName -ModuleName SPSSiteInventory.Common -Times 0 -Exactly
    }

    It 'counts every list that holds targeted items, and lists five of them' {
        $lists = @(1..6 | ForEach-Object {
                New-TestList -Title "List$_" -Url "/sites/team/Lists/List$_" -Fields @((New-TargetingField)) -Batches @((New-TestBatch -Item @((New-TestItem @{ Target_x0020_Audiences = ';;;;Owners' }), (New-TestItem @{ Target_x0020_Audiences = ';;;;Members' }))))
            })

        $result = Get-Signal -Site (New-TestSite -List $lists)

        $result.Signals.AudienceTargetedListCount | Should -Be 6
        $result.Signals.AudienceTargetedItemCount | Should -Be 12
        @($result.Signals.AudienceTargetedExamples -split '; ') | Should -HaveCount 5
    }

    It 'looks the audiences up once for the site collection, for the IDs of the lists that it shows' {
        $one = New-TestList -Title 'One' -Url '/sites/team/Lists/One' -Fields @((New-TargetingField)) -Batches @((New-TestBatch -Item @((New-TestItem @{ Target_x0020_Audiences = "$($script:IdSales);;;;" }))))
        $two = New-TestList -Title 'Two' -Url '/sites/team/Lists/Two' -Fields @((New-TargetingField)) -Batches @((New-TestBatch -Item @((New-TestItem @{ Target_x0020_Audiences = "$($script:IdSales),$($script:IdMarketing);;;;" }))))

        $null = Get-Signal -Site (New-TestSite -List @($one, $two))

        Should -Invoke Resolve-SPSAudienceName -ModuleName SPSSiteInventory.Common -Times 1 -Exactly -ParameterFilter { @($AudienceId).Count -eq 2 -and $AudienceId -contains $script:IdSales -and $AudienceId -contains $script:IdMarketing }
    }

    It 'stops at the cap of items, marks the collection partial and names the setting' {
        $items = @(1..3 | ForEach-Object { New-TestItem @{ Target_x0020_Audiences = ';;;;Owners' } })
        $list = New-TestList -Fields @((New-TargetingField)) -Batches @((New-TestBatch -Item $items))

        $result = Get-Signal -Site (New-TestSite -List @($list)) -Threshold @{ MaxItemsForAudienceTargetingScanPerList = 2 }

        $result.Signals.AudienceTargetedItemCount | Should -Be 2
        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "Audience targeting scan stopped on 'Announcements'"
        ($result.Warnings -join ';') | Should -Match 'MaxItemsForAudienceTargetingScanPerList'
    }

    It 'is complete when the list has exactly as many items as the cap, and partial when another page follows' {
        $two = @(1..2 | ForEach-Object { New-TestItem @{ Target_x0020_Audiences = ';;;;Owners' } })
        $exact = New-TestList -Fields @((New-TargetingField)) -Batches @((New-TestBatch -Item $two))
        $paged = New-TestList -Fields @((New-TargetingField)) -Batches @((New-TestBatch -Item $two -Position 'next'), (New-TestBatch -Item @()))

        (Get-Signal -Site (New-TestSite -List @($exact)) -Threshold @{ MaxItemsForAudienceTargetingScanPerList = 2 }).Signals.CustomizationInventoryComplete | Should -BeTrue
        $pagedResult = Get-Signal -Site (New-TestSite -List @($paged)) -Threshold @{ MaxItemsForAudienceTargetingScanPerList = 2 }

        $pagedResult.Signals.CustomizationInventoryComplete | Should -BeFalse
        $paged.Queries | Should -HaveCount 1
    }

    It 'falls back to 2000 items when the cap is not a usable number' -ForEach @(
        @{ Value = 0 }
        @{ Value = 'many' }
    ) {
        $items = @(1..5 | ForEach-Object { New-TestItem @{ Target_x0020_Audiences = ';;;;Owners' } })
        $list = New-TestList -Fields @((New-TargetingField)) -Batches @((New-TestBatch -Item $items))

        $result = Get-Signal -Site (New-TestSite -List @($list)) -Threshold @{ MaxItemsForAudienceTargetingScanPerList = $Value }

        $result.Signals.AudienceTargetedItemCount | Should -Be 5
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'marks the collection partial when a list cannot be read, and keeps the other lists' {
        $broken = New-TestList -Title 'Broken' -Url '/sites/team/Lists/Broken' -Fields @((New-TargetingField)) -ErrorText 'The query exceeds the list view threshold.'
        $good = New-TestList -Title 'Good' -Url '/sites/team/Lists/Good' -Fields @((New-TargetingField)) -Batches @((New-TestBatch -Item @((New-TestItem @{ Target_x0020_Audiences = ';;;;Owners' }))))

        $result = Get-Signal -Site (New-TestSite -List @($broken, $good))

        $result.Signals.AudienceTargetedItemCount | Should -Be 1
        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "Could not scan the audience targeting on 'Broken'.*list view threshold"
    }

    It 'marks the collection partial when the columns of a list cannot be read, and does not take it for a list without targeting' {
        $list = New-TestList -Title 'Broken' -Fields @([SPSTestCollabFailingIdField]::new()) -Batches @((New-TestBatch -Item @()))

        $result = Get-Signal -Site (New-TestSite -List @($list))

        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "Could not scan the audience targeting on 'Broken'.*id unavailable"
    }

    It 'has no audience targeting, without a warning, in a site collection without such a list' {
        $result = Get-Signal -Site (New-TestSite -List @((New-TestList -Title 'Tasks' -Url '/sites/team/Lists/Tasks')))

        $result.Signals.AudienceTargetedListCount | Should -Be 0
        $result.Signals.AudienceTargetedItemCount | Should -Be 0
        $result.Signals.AudienceTargetedExamples | Should -Be ''
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
    }
}

Describe 'Get-SPSSiteCustomization site notebooks' {
    It 'counts the notebook folders of the Site Assets library whose name ends in Notebook, and lists them' {
        $assets = New-TestSiteAssets -Batches @((New-TestBatch -Item @((New-TestNotebook -Name 'Team Notebook'), (New-TestNotebook -Name 'Project notebook'))))

        $result = Get-Signal -Site (New-TestSite -List @($assets))

        $result.Signals.SiteNotebookCount | Should -Be 2
        $result.Signals.SiteNotebookExamples | Should -Be '/sites/team/SiteAssets/Team Notebook; /sites/team/SiteAssets/Project notebook'
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
    }

    It 'does not count a folder that is not a notebook, or a notebook whose name does not end in Notebook' {
        $assets = New-TestSiteAssets -Batches @((New-TestBatch -Item @(
                    (New-TestNotebook -Name 'Images' -Type '')
                    (New-TestNotebook -Name 'Reports Notebook' -Type 'Excel.Sheet')
                    (New-TestNotebook -Name 'Notebook for Project 1')
                    (New-TestNotebook -Name 'Team Notebook')
                )))

        $result = Get-Signal -Site (New-TestSite -List @($assets))

        $result.Signals.SiteNotebookCount | Should -Be 1
        $result.Signals.SiteNotebookExamples | Should -Be '/sites/team/SiteAssets/Team Notebook'
    }

    It 'only reads the Site Assets library, whatever the case of its URL' {
        $other = New-TestSiteAssets -Url '/sites/team/Shared Documents' -Batches @((New-TestBatch -Item @((New-TestNotebook))))
        $lower = New-TestSiteAssets -Url '/sites/team/siteassets' -Batches @((New-TestBatch -Item @((New-TestNotebook))))

        (Get-Signal -Site (New-TestSite -List @($other))).Signals.SiteNotebookCount | Should -Be 0
        (Get-Signal -Site (New-TestSite -List @($lower))).Signals.SiteNotebookCount | Should -Be 1
        $other.Calls | Should -Be 0
    }

    It 'asks for the folders of the library, with the throttle override' {
        $assets = New-TestSiteAssets -Batches @((New-TestBatch -Item @()))

        $null = Get-Signal -Site (New-TestSite -List @($assets))

        $assets.Queries | Should -HaveCount 1
        $assets.Queries[0].Query | Should -Match 'FSObjType'
        $assets.Queries[0].Query | Should -Match '<Value Type="Integer">1</Value>'
        $assets.Queries[0].Throttle | Should -Be 'Override'
        $assets.Queries[0].RowLimit | Should -Be '200'
        $assets.Queries[0].ViewAttributes | Should -Be "Scope='RecursiveAll'"
    }

    It 'lists at most five notebooks and counts all of them' {
        $assets = New-TestSiteAssets -Batches @((New-TestBatch -Item @(1..7 | ForEach-Object { New-TestNotebook -Name "Site $_ Notebook" })))

        $result = Get-Signal -Site (New-TestSite -List @($assets))

        $result.Signals.SiteNotebookCount | Should -Be 7
        @($result.Signals.SiteNotebookExamples -split '; ') | Should -HaveCount 5
    }

    It 'follows the pages of the library' {
        $assets = New-TestSiteAssets -Batches @((New-TestBatch -Item @((New-TestNotebook -Name 'A Notebook')) -Position 'p1'), (New-TestBatch -Item @((New-TestNotebook -Name 'B Notebook'))))

        $result = Get-Signal -Site (New-TestSite -List @($assets))

        $result.Signals.SiteNotebookCount | Should -Be 2
        $assets.Queries[1].Position | Should -Be 'p1'
    }

    It 'stops at the cap of folders, marks the collection partial and names the setting' {
        $assets = New-TestSiteAssets -Batches @((New-TestBatch -Item @(1..3 | ForEach-Object { New-TestNotebook -Name "Site $_ Notebook" })))

        $result = Get-Signal -Site (New-TestSite -List @($assets)) -Threshold @{ MaxItemsForNotebookScanPerLibrary = 2 }

        $result.Signals.SiteNotebookCount | Should -Be 2
        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match 'Site notebook scan stopped on'
        ($result.Warnings -join ';') | Should -Match 'MaxItemsForNotebookScanPerLibrary'
    }

    It 'marks the collection partial when the library cannot be listed' {
        $assets = New-TestSiteAssets -ErrorText 'Access is denied'

        $result = Get-Signal -Site (New-TestSite -List @($assets))

        $result.Signals.SiteNotebookCount | Should -Be 0
        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "Could not scan the site notebooks on 'Site Assets'.*Access is denied"
    }

    It 'marks the collection partial when the name of a notebook cannot be read, instead of leaving it out' {
        $assets = New-TestSiteAssets -Batches @((New-TestBatch -Item @((New-TestItem @{ FileLeafRef = ''; HTML_x0020_File_x0020_Type = 'OneNote.Notebook' }))))

        $result = Get-Signal -Site (New-TestSite -List @($assets))

        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match 'The name of a notebook could not be read'
    }

    It 'falls back to 2000 folders when the cap is not a usable number' {
        $assets = New-TestSiteAssets -Batches @((New-TestBatch -Item @(1..3 | ForEach-Object { New-TestNotebook -Name "Site $_ Notebook" })))

        $result = Get-Signal -Site (New-TestSite -List @($assets)) -Threshold @{ MaxItemsForNotebookScanPerLibrary = 'many' }

        $result.Signals.SiteNotebookCount | Should -Be 3
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'has no site notebook, without a warning, in a site collection without a Site Assets library' {
        $result = Get-Signal -Site (New-TestSite -List @((New-TestList -Title 'Tasks' -Url '/sites/team/Lists/Tasks')))

        $result.Signals.SiteNotebookCount | Should -Be 0
        $result.Signals.SiteNotebookExamples | Should -Be ''
        $result.Warnings | Should -HaveCount 0
    }
}
