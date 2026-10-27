BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    Add-Type -TypeDefinition @'
using System;
using System.Collections;

public sealed class SPSSiteInventoryThrowAfterOne : IEnumerable
{
    private readonly object first;

    public SPSSiteInventoryThrowAfterOne(object first)
    {
        this.first = first;
    }

    public IEnumerator GetEnumerator()
    {
        return new Enumerator(first);
    }

    private sealed class Enumerator : IEnumerator
    {
        private readonly object first;
        private int state;

        public Enumerator(object first)
        {
            this.first = first;
        }

        public object Current
        {
            get
            {
                if (state == 1) { return first; }
                throw new InvalidOperationException("Enumerator has no current item.");
            }
        }

        public bool MoveNext()
        {
            if (state == 0)
            {
                state = 1;
                return true;
            }
            throw new InvalidOperationException("Access denied while advancing the web enumerator.");
        }

        public void Reset()
        {
            state = 0;
        }
    }
}

public sealed class SPSSiteInventoryBrokenAlertCollection : IEnumerable
{
    public int Count
    {
        get { throw new InvalidOperationException("The alert data could not be loaded."); }
    }

    public IEnumerator GetEnumerator()
    {
        return new object[0].GetEnumerator();
    }
}
'@

    function global:Get-SPAppInstance {
        param($Web)
        @()
    }

    function Get-TestContentType {
        param ([string]$Id, [string]$Name)
        [PSCustomObject]@{
            Id = $Id; Name = $Name; Group = 'Contoso Types'
            Parent = [PSCustomObject]@{ Id = '0x01' }
            Fields = @(
                [PSCustomObject]@{ TypeAsString = 'Text' },
                [PSCustomObject]@{ TypeAsString = 'TaxonomyFieldType' }
            )
            DocumentTemplateUrl = '/templates/document.dotx'
            Hidden = $false; ReadOnly = $false; Sealed = $false
        }
    }

    function Get-TestWeb {
        param ([object[]]$Definitions, [object[]]$Bindings)
        $list = [PSCustomObject]@{
            Title = 'Documents'
            RootFolder = [PSCustomObject]@{
                ServerRelativeUrl = '/sites/team/Documents'
                Properties = @{}
            }
            ContentTypes = $Bindings
            WorkflowAssociations = @()
            EventReceivers = @()
            IrmEnabled = $false
            ItemCount = 0
            Views = @()
            CheckedOutFiles = @()
            EnableVersioning = $false
            Items = @()
            BaseTemplate = 101
            Fields = @()
            HasExternalDataSource = $false
        }
        $web = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            ContentTypes = $Definitions
            Lists = @($list)
            WorkflowAssociations = @()
            HasUniqueRoleAssignments = $false
            CustomMasterUrl = ''
            Features = @()
            Files = @()
            IsRootWeb = $true
            HasUniqueRoleDefinitions = $true
            RoleDefinitions = @()
            Alerts = @()
        }
        $web | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        return $web
    }

    function Get-TestAlert {
        param ([string]$Title = 'Documents: all changes', [int]$UserId = 7)
        [PSCustomObject]@{
            ID = [guid]::NewGuid()
            Title = $Title
            AlertTemplateName = 'SPAlertTemplateType.DocumentLibrary'
            AlertType = 'List'
            ListUrl = 'Shared Documents'
            ListID = [guid]::NewGuid()
            EventType = 'All'
            AlertFrequency = 'Immediate'
            Status = 'On'
            DeliveryChannels = 'Email'
            AlwaysNotify = $false
            DynamicRecipient = ''
            Filter = ''
            UserId = $UserId
            User = [PSCustomObject]@{ LoginName = "i:0#.w|contoso\user$UserId" }
        }
    }

    function Get-TestWorkflowAssociation {
        param (
            [string]$Name,
            [bool]$HasIsCurrent = $false,
            [bool]$IsCurrent = $true,
            [Nullable[int]]$RunningInstances = $null
        )

        $association = [PSCustomObject]@{ Name = $Name }
        if ($HasIsCurrent) {
            $association | Add-Member -MemberType NoteProperty -Name IsCurrent -Value $IsCurrent
        }
        if ($null -ne $RunningInstances) {
            $association | Add-Member -MemberType NoteProperty -Name RunningInstances -Value $RunningInstances
        }
        return $association
    }

    function Get-TestFeature {
        param ([string]$Id)
        [PSCustomObject]@{ DefinitionId = [guid]$Id }
    }

    function Get-TestPagesList {
        param ([int]$ItemCount, [object[]]$Batches = @())

        $list = [PSCustomObject]@{
            Title = 'Pages'
            RootFolder = [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/Pages'; Properties = @{} }
            ContentTypes = @()
            WorkflowAssociations = @()
            EventReceivers = @()
            IrmEnabled = $false
            ItemCount = $ItemCount
            Views = @()
            CheckedOutFiles = @()
            EnableVersioning = $false
            Items = @()
            BaseTemplate = 850
            Fields = @()
            HasExternalDataSource = $false
            Batches = $Batches
            BatchIndex = 0
            Queries = [System.Collections.Generic.List[object]]::new()
        }
        $list | Add-Member -MemberType ScriptMethod -Name GetItems -Value {
            param ($Query)
            $this.Queries.Add($Query)
            $batch = $this.Batches[$this.BatchIndex]
            $this.BatchIndex++
            [PSCustomObject]@{ Items = @($batch.Items); ListItemCollectionPosition = $batch.Position }
        }
        return $list
    }

    function Get-TestRole {
        param ([string]$Name, [string]$Type = 'None')
        [PSCustomObject]@{ Name = $Name; Type = $Type }
    }

    function Get-TestMailList {
        param ([string]$Title, [string]$EmailAlias = $null, [bool]$CanReceiveEmail = $true)
        [PSCustomObject]@{
            Title = $Title
            RootFolder = [PSCustomObject]@{ ServerRelativeUrl = "/sites/team/$Title"; Properties = @{} }
            ContentTypes = @()
            WorkflowAssociations = @()
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
            EmailAlias = $EmailAlias
            CanReceiveEmail = $CanReceiveEmail
        }
    }

    function Get-TestLibrary {
        param ([string]$Title = 'Docs', [string]$Url = '', [object[]]$HtmlBatches = @(), [int]$BaseTemplate = 101)

        $library = Get-TestMailList -Title $Title
        if ($Url) { $library.RootFolder.ServerRelativeUrl = $Url }
        $library.BaseTemplate = $BaseTemplate
        $library | Add-Member -MemberType NoteProperty -Name HtmlBatches -Value $HtmlBatches
        $library | Add-Member -MemberType NoteProperty -Name HtmlBatchIndex -Value 0
        $library | Add-Member -MemberType NoteProperty -Name HtmlQueries -Value ([System.Collections.Generic.List[object]]::new())
        $library | Add-Member -MemberType ScriptMethod -Name GetItems -Value {
            param ($Query)
            # Checkout and version scans share GetItems; only the HTML query returns files.
            if ($Query.PSObject.Properties['Query'] -and [string]$Query.Query -match 'File_x0020_Type') {
                $this.HtmlQueries.Add($Query)
                $batch = $this.HtmlBatches[$this.HtmlBatchIndex]
                $this.HtmlBatchIndex++
                return [PSCustomObject]@{ Items = @($batch.Items); ListItemCollectionPosition = $batch.Position }
            }
            [PSCustomObject]@{ Items = @(); ListItemCollectionPosition = $null }
        }
        return $library
    }

    function Get-TestHtmlBatch {
        param ([string[]]$Urls, $Position = $null)
        [PSCustomObject]@{
            Items = @($Urls | ForEach-Object { [PSCustomObject]@{ File = [PSCustomObject]@{ ServerRelativeUrl = $_ } } })
            Position = $Position
        }
    }

    # A real .NET type: PowerShell also swallows exceptions from script properties, so only a
    # compiled getter reproduces a failed SharePoint property read.
    if (-not ('SPSTestThrowingMailList' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
public class SPSTestThrowingMailList
{
    public string Title { get; set; }
    public object RootFolder { get; set; }
    public object ContentTypes { get; set; }
    public object WorkflowAssociations { get; set; }
    public object EventReceivers { get; set; }
    public object IrmEnabled { get; set; }
    public object ItemCount { get; set; }
    public object Views { get; set; }
    public object CheckedOutFiles { get; set; }
    public object EnableVersioning { get; set; }
    public object Items { get; set; }
    public object BaseTemplate { get; set; }
    public object Fields { get; set; }
    public bool HasExternalDataSource { get; set; }
    public bool CanReceiveEmail { get; set; }
    public string EmailAlias { get { throw new InvalidOperationException("alias store unavailable"); } }
}
'@
    }

    function Get-TestPageBatch {
        param ([string[]]$Layouts, $Position = $null)
        [PSCustomObject]@{
            Items = @($Layouts | ForEach-Object { @{ PublishingPageLayout = $_ } })
            Position = $Position
        }
    }

    function Get-TestTaxonomyField {
        param (
            [string]$Title = 'Department',
            [string]$Type = 'TaxonomyFieldType',
            [string]$TermSetId = '11111111-1111-1111-1111-111111111111',
            [bool]$Hidden = $false
        )
        [PSCustomObject]@{ Title = $Title; InternalName = $Title; TypeAsString = $Type; Hidden = $Hidden; TermSetId = [guid]$TermSetId }
    }

    function Get-TestManagedMetadataList {
        param ([string]$Title, [object[]]$Fields, [int]$ItemCount = 3)
        $list = Get-TestMailList -Title $Title
        $list.Fields = $Fields
        $list.ItemCount = $ItemCount
        $list | Add-Member -MemberType NoteProperty -Name BaseType -Value 'GenericList'
        return $list
    }

    function Get-TestExternalList {
        param (
            [string]$Title,
            [string]$EntityNamespace = 'Contoso.Crm',
            [string]$Entity = 'Customer',
            [string]$Instance = 'CrmInstance',
            [switch]$WithoutDataSource
        )
        $list = Get-TestMailList -Title $Title
        $list.HasExternalDataSource = $true
        $dataSource = $null
        if (-not $WithoutDataSource) {
            $dataSource = [PSCustomObject]@{
                Properties = @{ LobSystemInstance = $Instance; EntityNamespace = $EntityNamespace; Entity = $Entity; SpecificFinder = 'Read Item' }
            }
            $dataSource | Add-Member -MemberType ScriptMethod -Name GetProperty -Value {
                param ($Key)
                if ($this.Properties.ContainsKey($Key)) { return $this.Properties[$Key] }
                return $null
            }
        }
        $list | Add-Member -MemberType NoteProperty -Name DataSource -Value $dataSource
        return $list
    }

    # Real .NET types: a failed SharePoint property read comes back as $null in PowerShell.
    if (-not ('SPSTestCollectorTaxonomyField' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
public class SPSTestCollectorTaxonomyField
{
    public string Title { get; set; }
    public string TypeAsString { get { return "TaxonomyFieldType"; } }
    public bool Hidden { get { throw new InvalidOperationException("hidden state unavailable"); } }
    public Guid TermSetId { get { return Guid.NewGuid(); } }
}

public class SPSTestFailingFlagList
{
    public string Title { get; set; }
    public object RootFolder { get; set; }
    public object ContentTypes { get; set; }
    public object WorkflowAssociations { get; set; }
    public object EventReceivers { get; set; }
    public object IrmEnabled { get; set; }
    public object Views { get; set; }
    public object CheckedOutFiles { get; set; }
    public object EnableVersioning { get; set; }
    public object Items { get; set; }
    public object BaseTemplate { get; set; }
    public object Fields { get; set; }
    public string EmailAlias { get { return null; } }
    public bool CanReceiveEmail { get; set; }
    public int ItemCount { get { return 0; } }
    public bool HasExternalDataSource { get { throw new InvalidOperationException("external flag unavailable"); } }
}

public class SPSTestFailingCountList
{
    public string Title { get; set; }
    public object RootFolder { get; set; }
    public object ContentTypes { get; set; }
    public object WorkflowAssociations { get; set; }
    public object EventReceivers { get; set; }
    public object IrmEnabled { get; set; }
    public object Views { get; set; }
    public object CheckedOutFiles { get; set; }
    public object EnableVersioning { get; set; }
    public object Items { get; set; }
    public object BaseTemplate { get; set; }
    public object Fields { get; set; }
    public bool HasExternalDataSource { get; set; }
    public string EmailAlias { get { return null; } }
    public bool CanReceiveEmail { get; set; }
    public int ItemCount { get { throw new InvalidOperationException("item count unavailable"); } }
}
'@
    }
}

Describe 'Get-SPSSiteCustomization content types' {
    It 'records web definitions and list bindings without declaring them custom' {
        $definition = Get-TestContentType -Id '0x0101' -Name 'Document & Notes'
        $binding = Get-TestContentType -Id '0x010100AAAA' -Name 'Document & Notes'
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @(Get-TestWeb -Definitions @($definition) -Bindings @($binding))
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.ContentTypeCount | Should -Be 1
        $signals.ListContentTypeBindingCount | Should -Be 1
        $signals.ContentTypeInventoryComplete | Should -BeTrue
        $signals.CustomizationInventoryComplete | Should -BeTrue
        $signals.ContentTypes | Should -HaveCount 2
        $signals.ContentTypes[0].FieldCount | Should -Be 2
        $signals.ContentTypes[0].FieldTypes | Should -Be 'TaxonomyFieldType; Text'
        $signals.ContentTypes[0].ParentContentTypeId | Should -Be '0x01'
        $signals.ContentTypes[1].ListUrl | Should -Be '/sites/team/Documents'
        $signals.ContentTypes[1].ContentTypeId | Should -Be '0x010100AAAA'
        $signals.Keys | Should -Not -Contain 'UsesCustomContentType'
    }

    It 'marks a partial read explicitly and retains the data collected elsewhere' {
        $definition = Get-TestContentType -Id '0x0101' -Name 'Document'
        $web = Get-TestWeb -Definitions @($definition) -Bindings @()
        $badBinding = Get-TestContentType -Id '' -Name 'Unreadable'
        $web.Lists[0].ContentTypes = @($badBinding)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningAction SilentlyContinue

        $signals.ContentTypeInventoryComplete | Should -BeFalse
        $signals.CustomizationInventoryComplete | Should -BeFalse
        $signals.ContentTypeCount | Should -Be 1
        $signals.ListContentTypeBindingCount | Should -Be 0
        $signals.ContentTypes | Should -HaveCount 1
    }

    It 'marks connected Workflow Manager subscription read failures as incomplete' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }
        Mock Get-SPSWorkflowSubscriptionCount -ModuleName SPSSiteInventory.Common {
            throw 'Workflow subscription access denied'
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match 'Workflow Manager subscriptions or running instances could not be read'
        ($warnings -join ';') | Should -Match 'Workflow subscription access denied'
    }

    It 'collects running workflow instance counts for 2010 and 2013 platforms when APIs are available' {
        $webWorkflow = Get-TestWorkflowAssociation -Name 'Web workflow' -HasIsCurrent $true -IsCurrent $true -RunningInstances 2
        $listWorkflow = Get-TestWorkflowAssociation -Name 'List workflow' -HasIsCurrent $true -IsCurrent $true -RunningInstances 1
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.WorkflowAssociations = @($webWorkflow)
        $web.Lists[0].WorkflowAssociations = @($listWorkflow)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }
        Mock Get-SPSWorkflowSubscriptionCount -ModuleName SPSSiteInventory.Common { 4 }
        Mock Get-SPSWorkflowRunningInstanceCount -ModuleName SPSSiteInventory.Common { 3 }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.Workflow2010Count | Should -Be 2
        $signals.Workflow2010RunningInstanceCount | Should -Be 3
        $signals.Workflow2013Count | Should -Be 4
        $signals.Workflow2013RunningInstanceCount | Should -Be 3
    }

    It 'keeps active-association definitions but includes historical associations in running totals' {
        $webCurrent = Get-TestWorkflowAssociation -Name 'Web current' -HasIsCurrent $true -IsCurrent $true -RunningInstances 1
        $webPrevious = Get-TestWorkflowAssociation -Name 'Web previous' -HasIsCurrent $true -IsCurrent $false -RunningInstances 3
        $listCurrent = Get-TestWorkflowAssociation -Name 'List current' -HasIsCurrent $true -IsCurrent $true -RunningInstances 2
        $listPrevious = Get-TestWorkflowAssociation -Name 'List previous' -HasIsCurrent $true -IsCurrent $false -RunningInstances 4
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.WorkflowAssociations = @($webCurrent, $webPrevious)
        $web.Lists[0].WorkflowAssociations = @($listCurrent, $listPrevious)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }
        Mock Get-SPSWorkflowSubscriptionCount -ModuleName SPSSiteInventory.Common { 0 }
        Mock Get-SPSWorkflowRunningInstanceCount -ModuleName SPSSiteInventory.Common { 0 }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.Workflow2010Count | Should -Be 2
        $signals.Workflow2010RunningInstanceCount | Should -Be 10
    }

    It 'collects app instance and app web signals with examples' {
        $appWeb = Get-TestWeb -Definitions @() -Bindings @()
        $appWeb | Add-Member -MemberType NoteProperty -Name IsAppWeb -Value $true
        $regularWeb = Get-TestWeb -Definitions @() -Bindings @()
        $regularWeb.Url = 'https://intranet.contoso.com/sites/team/subweb'
        Mock Get-SPAppInstance -ModuleName SPSSiteInventory.Common {
            param($Web)
            if ($Web.Url -eq 'https://intranet.contoso.com/sites/team') {
                return @(
                    [PSCustomObject]@{ Title = 'Contoso App' }
                    [PSCustomObject]@{ AppId = '11111111-1111-1111-1111-111111111111' }
                )
            }
            if ($Web.Url -eq 'https://intranet.contoso.com/sites/team/subweb') {
                return @(
                    [PSCustomObject]@{ DisplayName = 'Legacy Provider App' }
                )
            }
            return @()
        }

        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($appWeb, $regularWeb)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.AppInstanceCount | Should -Be 3
        $signals.AppWebCount | Should -Be 1
        $signals.AppInstanceExamples | Should -Match 'Contoso App'
        $signals.AppInstanceExamples | Should -Match 'Legacy Provider App'
        Should -Invoke Get-SPAppInstance -ModuleName SPSSiteInventory.Common -Times 2 -Exactly
    }

    It 'marks app-instance read failures as partial with a warning' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        Mock Get-SPAppInstance -ModuleName SPSSiteInventory.Common {
            throw 'App catalog access denied'
        }
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.CustomizationInventoryComplete | Should -BeFalse
        $signals.AppInstanceCount | Should -Be 0
        $signals.AppWebCount | Should -Be 0
        ($warnings -join ';') | Should -Match 'Could not read app instances on'
        ($warnings -join ';') | Should -Match 'App catalog access denied'
        Should -Invoke Get-SPAppInstance -ModuleName SPSSiteInventory.Common -Times 1 -Exactly
    }

    It 'detects publishing features, Pages library items and the page layouts in use' {
        $infrastructure = Get-TestFeature -Id 'F6924D36-2FA8-4F0B-B16D-06B7250180FA'
        $publishing = Get-TestFeature -Id '94c94ca6-b32f-4da9-a9e3-1f3d343d7ecb'
        $pages = Get-TestPagesList -ItemCount 3 -Batches @(
            Get-TestPageBatch -Layouts @('/_catalogs/masterpage/ArticleLeft.aspx, Article Page', '/_catalogs/masterpage/WelcomeSplash.aspx, Welcome') -Position 'next'
            Get-TestPageBatch -Layouts @('/_catalogs/masterpage/ArticleLeft.aspx, Article Page')
        )
        $publishingWeb = Get-TestWeb -Definitions @() -Bindings @()
        $publishingWeb.Features = @($publishing)
        $publishingWeb.Lists = @($publishingWeb.Lists[0], $pages)
        $plainWeb = Get-TestWeb -Definitions @() -Bindings @()
        $plainWeb.Url = 'https://intranet.contoso.com/sites/team/plain'
        $plainWeb.Features = @()
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Solutions = @()
            Features = @($infrastructure)
            AllWebs = @($publishingWeb, $plainWeb)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.PublishingInfrastructureEnabled | Should -BeTrue
        $signals.PublishingWebCount | Should -Be 1
        $signals.PublishingPageCount | Should -Be 3
        $signals.PublishingPageLayoutCount | Should -Be 2
        $signals.PublishingPageLayoutExamples | Should -Be 'ArticleLeft.aspx (2); WelcomeSplash.aspx (1)'
        $signals.CustomizationInventoryComplete | Should -BeTrue
        $pages.Queries | Should -HaveCount 2
        $pages.Queries[0].ViewFields | Should -Match 'PublishingPageLayout'
        $pages.Queries[0].ViewFieldsOnly | Should -BeTrue
        $pages.Queries[0].Query | Should -Match 'FSObjType'
    }

    It 'reports no publishing signals and skips Pages libraries on webs without the publishing feature' {
        $pages = Get-TestPagesList -ItemCount 99
        $pages | Add-Member -MemberType ScriptMethod -Name GetItems -Value { throw 'Pages must not be read without the publishing feature.' } -Force
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Features = @((Get-TestFeature -Id '00000000-0000-0000-0000-000000000001'))
        $web.Lists = @($web.Lists[0], $pages)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Solutions = @()
            Features = @((Get-TestFeature -Id '00000000-0000-0000-0000-000000000002'))
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.PublishingInfrastructureEnabled | Should -BeFalse
        $signals.PublishingWebCount | Should -Be 0
        $signals.PublishingPageCount | Should -Be 0
        $signals.PublishingPageLayoutCount | Should -Be 0
        $signals.PublishingPageLayoutExamples | Should -Be ''
        $signals.CustomizationInventoryComplete | Should -BeTrue
        @($warnings) | Should -HaveCount 0
    }

    It 'ignores pages without a layout when counting page layouts' {
        $pages = Get-TestPagesList -ItemCount 2 -Batches @(
            Get-TestPageBatch -Layouts @('', '/_catalogs/masterpage/BlankWebPartPage.aspx, Blank')
        )
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Features = @((Get-TestFeature -Id '94C94CA6-B32F-4DA9-A9E3-1F3D343D7ECB'))
        $web.Lists = @($pages)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.PublishingPageLayoutCount | Should -Be 1
        $signals.PublishingPageLayoutExamples | Should -Be 'BlankWebPartPage.aspx (1)'
    }

    It 'marks a capped publishing page scan as partial and keeps the layouts already read' {
        $pages = Get-TestPagesList -ItemCount 3 -Batches @(
            Get-TestPageBatch -Layouts @('/_catalogs/masterpage/A.aspx, A', '/_catalogs/masterpage/B.aspx, B') -Position 'next'
            Get-TestPageBatch -Layouts @('/_catalogs/masterpage/C.aspx, C')
        )
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Features = @((Get-TestFeature -Id '94c94ca6-b32f-4da9-a9e3-1f3d343d7ecb'))
        $web.Lists = @($pages)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -LargeContentThresholds @{ MaxItemsForPublishingPageScanPerLibrary = 2 } -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.PublishingPageCount | Should -Be 3
        $signals.PublishingPageLayoutCount | Should -Be 2
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match 'Publishing page layout scan stopped'
        ($warnings -join ';') | Should -Match 'MaxItemsForPublishingPageScanPerLibrary'
        $pages.Queries | Should -HaveCount 1
    }

    It 'stops a publishing page scan in the middle of a batch when the cap is reached' {
        $pages = Get-TestPagesList -ItemCount 2 -Batches @(
            Get-TestPageBatch -Layouts @('/_catalogs/masterpage/A.aspx, A', '/_catalogs/masterpage/B.aspx, B')
        )
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Features = @((Get-TestFeature -Id '94c94ca6-b32f-4da9-a9e3-1f3d343d7ecb'))
        $web.Lists = @($pages)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -LargeContentThresholds @{ MaxItemsForPublishingPageScanPerLibrary = 1 } -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.PublishingPageLayoutCount | Should -Be 1
        $signals.PublishingPageLayoutExamples | Should -Be 'A.aspx (1)'
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match 'Publishing page layout scan stopped'
    }

    It 'does not flag a publishing page scan as partial when the cap equals the library size' {
        $pages = Get-TestPagesList -ItemCount 2 -Batches @(
            Get-TestPageBatch -Layouts @('/_catalogs/masterpage/A.aspx, A', '/_catalogs/masterpage/B.aspx, B')
        )
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Features = @((Get-TestFeature -Id '94c94ca6-b32f-4da9-a9e3-1f3d343d7ecb'))
        $web.Lists = @($pages)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -LargeContentThresholds @{ MaxItemsForPublishingPageScanPerLibrary = 2 }

        $signals.PublishingPageLayoutCount | Should -Be 2
        $signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'marks unreadable publishing pages as partial while keeping the Pages item count' {
        $pages = Get-TestPagesList -ItemCount 7
        $pages | Add-Member -MemberType ScriptMethod -Name GetItems -Value { throw 'Pages access denied' } -Force
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Features = @((Get-TestFeature -Id '94c94ca6-b32f-4da9-a9e3-1f3d343d7ecb'))
        $web.Lists = @($pages)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.PublishingWebCount | Should -Be 1
        $signals.PublishingPageCount | Should -Be 7
        $signals.PublishingPageLayoutCount | Should -Be 0
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match "Could not scan publishing pages on 'Pages'"
        ($warnings -join ';') | Should -Match 'Pages access denied'
    }

    It 'marks unreadable publishing feature state as partial' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Features = ([SPSSiteInventoryThrowAfterOne]::new((Get-TestFeature -Id '00000000-0000-0000-0000-000000000001')))
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Solutions = @()
            Features = [SPSSiteInventoryThrowAfterOne]::new((Get-TestFeature -Id '00000000-0000-0000-0000-000000000002'))
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue
        $warningText = $warnings -join ';'

        $signals.PublishingInfrastructureEnabled | Should -BeFalse
        $signals.PublishingWebCount | Should -Be 0
        $signals.CustomizationInventoryComplete | Should -BeFalse
        $warningText | Should -Match "publishing infrastructure feature for site collection 'https://intranet.contoso.com/sites/team'"
        $warningText | Should -Match "publishing feature on 'https://intranet.contoso.com/sites/team'"
        $warningText | Should -Match 'Access denied while advancing the web enumerator'
    }

    It 'counts customized pages at the web root and ignores uncustomized and System Account files' {
        $user = [PSCustomObject]@{ LoginName = 'i:0#.w|contoso\jdoe' }
        $system = [PSCustomObject]@{ LoginName = 'SHAREPOINT\system' }
        $rootWeb = Get-TestWeb -Definitions @() -Bindings @()
        $rootWeb.Files = @(
            [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/default.aspx'; CustomizedPageStatus = 2; ModifiedBy = $user }
            [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/system.aspx'; CustomizedPageStatus = 2; ModifiedBy = $system }
            [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/ghosted.aspx'; CustomizedPageStatus = 1; ModifiedBy = $user }
            [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/plain.aspx'; CustomizedPageStatus = 0; ModifiedBy = $user }
        )
        $subWeb = Get-TestWeb -Definitions @() -Bindings @()
        $subWeb.Url = 'https://intranet.contoso.com/sites/team/sub'
        $subWeb.Files = @(
            [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/sub/default.aspx'; CustomizedPageStatus = 'Customized'; ModifiedBy = $user }
        )
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($rootWeb, $subWeb)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.CustomizedPageCount | Should -Be 2
        $signals.CustomizedPageExamples | Should -Be '/sites/team/default.aspx; /sites/team/sub/default.aspx'
        $signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'reports zero customized pages when no root file is customized' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Files = @(
            [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/default.aspx'; CustomizedPageStatus = 1 }
        )
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.CustomizedPageCount | Should -Be 0
        $signals.CustomizedPageExamples | Should -Be ''
        $signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'limits customized page examples to five while counting every page' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Files = @(
            1..7 | ForEach-Object { [PSCustomObject]@{ ServerRelativeUrl = "/sites/team/page$_.aspx"; CustomizedPageStatus = 2 } }
        )
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.CustomizedPageCount | Should -Be 7
        @($signals.CustomizedPageExamples -split '; ') | Should -HaveCount 5
    }

    It 'keeps customized pages already read when the root file enumeration fails' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Files = ([SPSSiteInventoryThrowAfterOne]::new(
                [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/default.aspx'; CustomizedPageStatus = 2 }))
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.CustomizedPageCount | Should -Be 1
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match "customized pages at the root of 'https://intranet.contoso.com/sites/team'"
        ($warnings -join ';') | Should -Match 'Access denied while advancing the web enumerator'
    }

    It 'marks null feature collections as partial instead of reporting publishing as off' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Features = $null
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = $null
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue
        $warningText = $warnings -join ';'

        $signals.CustomizationInventoryComplete | Should -BeFalse
        $warningText | Should -Match "publishing infrastructure feature for site collection 'https://intranet.contoso.com/sites/team': The feature collection is unavailable"
        $warningText | Should -Match "publishing feature on 'https://intranet.contoso.com/sites/team': The feature collection is unavailable"
    }

    It 'marks a null root file collection as partial instead of reporting zero customized pages' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Files = $null
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.CustomizedPageCount | Should -Be 0
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match "root file collection is unavailable on 'https://intranet.contoso.com/sites/team'"
    }

    It 'marks a page with an unreadable customization status as partial and keeps the other pages' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Files = @(
            [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/broken.aspx'; CustomizedPageStatus = $null }
            [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/default.aspx'; CustomizedPageStatus = 2 }
        )
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.CustomizedPageCount | Should -Be 1
        $signals.CustomizedPageExamples | Should -Be '/sites/team/default.aspx'
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match "customized page status of '/sites/team/broken.aspx' at the root of 'https://intranet.contoso.com/sites/team'"
    }

    It 'marks a Pages library without a readable item count as partial while still scanning layouts' {
        $pages = Get-TestPagesList -ItemCount 2 -Batches @(
            Get-TestPageBatch -Layouts @('/_catalogs/masterpage/A.aspx, A')
        )
        $pages.ItemCount = $null
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Features = @((Get-TestFeature -Id '94c94ca6-b32f-4da9-a9e3-1f3d343d7ecb'))
        $web.Lists = @($pages)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.PublishingPageCount | Should -Be 0
        $signals.PublishingPageLayoutCount | Should -Be 1
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match "item count is unavailable on Pages library 'Pages'"
    }

    It 'marks an unreadable list template on a publishing web as partial' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Features = @((Get-TestFeature -Id '94c94ca6-b32f-4da9-a9e3-1f3d343d7ecb'))
        $web.Lists[0].BaseTemplate = $null
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match "Could not read the list template on 'Documents'"
    }

    It 'keeps page layouts distinct when two layouts share a file name in different folders' {
        $pages = Get-TestPagesList -ItemCount 3 -Batches @(
            Get-TestPageBatch -Layouts @(
                '/_catalogs/masterpage/BrandA/Article.aspx, Brand A'
                '/_catalogs/masterpage/BrandB/Article.aspx, Brand B'
                '/_catalogs/masterpage/BrandA/Article.aspx, Brand A'
            )
        )
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Features = @((Get-TestFeature -Id '94c94ca6-b32f-4da9-a9e3-1f3d343d7ecb'))
        $web.Lists = @($pages)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.PublishingPageLayoutCount | Should -Be 2
        $signals.PublishingPageLayoutExamples | Should -Be 'BrandA/Article.aspx (2); BrandB/Article.aspx (1)'
    }

    It 'merges absolute and server-relative references to the same page layout' {
        $pages = Get-TestPagesList -ItemCount 3 -Batches @(
            Get-TestPageBatch -Layouts @(
                '/sites/team/_catalogs/masterpage/ArticleLeft.aspx, Left'
                'http://intranet.contoso.com/sites/team/_catalogs/masterpage/ArticleLeft.aspx, Left'
                '/sites/team/_catalogs/masterpage/ARTICLELEFT.aspx, Left'
            )
        )
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Features = @((Get-TestFeature -Id '94c94ca6-b32f-4da9-a9e3-1f3d343d7ecb'))
        $web.Lists = @($pages)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.PublishingPageLayoutCount | Should -Be 1
        $signals.PublishingPageLayoutExamples | Should -Be 'ArticleLeft.aspx (3)'
    }

    It 'marks the scan as partial when no scanned page reports a layout' {
        $pages = Get-TestPagesList -ItemCount 2 -Batches @(
            Get-TestPageBatch -Layouts @('', '')
        )
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Features = @((Get-TestFeature -Id '94c94ca6-b32f-4da9-a9e3-1f3d343d7ecb'))
        $web.Lists = @($pages)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.PublishingPageLayoutCount | Should -Be 0
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match 'No page layout could be read from the 2 page\(s\) scanned on .Pages.'
    }

    It 'counts distinct custom permission levels from the webs that own them' {
        $rootWeb = Get-TestWeb -Definitions @() -Bindings @()
        $rootWeb.RoleDefinitions = @(
            (Get-TestRole -Name 'Full Control' -Type 'Administrator')
            (Get-TestRole -Name 'Read' -Type 'Reader')
            (Get-TestRole -Name 'View Only')
            (Get-TestRole -Name 'Approve')
            (Get-TestRole -Name 'Project Manager')
            (Get-TestRole -Name 'Auditor')
        )
        $inheritingWeb = Get-TestWeb -Definitions @() -Bindings @()
        $inheritingWeb.Url = 'https://intranet.contoso.com/sites/team/inherits'
        $inheritingWeb.IsRootWeb = $false
        $inheritingWeb.HasUniqueRoleDefinitions = $false
        $inheritingWeb | Add-Member -MemberType ScriptProperty -Name RoleDefinitions -Value { throw 'Inherited levels must not be read.' } -Force
        $ownWeb = Get-TestWeb -Definitions @() -Bindings @()
        $ownWeb.Url = 'https://intranet.contoso.com/sites/team/own'
        $ownWeb.IsRootWeb = $false
        $ownWeb.RoleDefinitions = @((Get-TestRole -Name 'auditor'), (Get-TestRole -Name 'External'))
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($rootWeb, $inheritingWeb, $ownWeb)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.CustomPermissionLevelCount | Should -Be 3
        $signals.CustomPermissionLevelExamples | Should -Be 'Project Manager (https://intranet.contoso.com/sites/team); Auditor (https://intranet.contoso.com/sites/team); External (https://intranet.contoso.com/sites/team/own)'
        $signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'adds configured localized names to the built-in permission level names' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.RoleDefinitions = @(
            (Get-TestRole -Name 'Affichage seul')
            (Get-TestRole -Name 'View Only')
            (Get-TestRole -Name 'Gestionnaire projet')
        )
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $default = Get-SPSSiteCustomization -Site $site
        $configured = Get-SPSSiteCustomization -Site $site -PermissionLevels @{ BuiltInNames = @('Affichage seul') }

        $default.CustomPermissionLevelCount | Should -Be 2
        $configured.CustomPermissionLevelCount | Should -Be 1
        $configured.CustomPermissionLevelExamples | Should -Match '^Gestionnaire projet'
    }

    It 'reports no custom permission levels when only base and provisioned levels exist' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.RoleDefinitions = @((Get-TestRole -Name 'Contribute' -Type 'Contributor'), (Get-TestRole -Name 'Manage Hierarchy'))
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.CustomPermissionLevelCount | Should -Be 0
        $signals.CustomPermissionLevelExamples | Should -Be ''
        $signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'marks unreadable permission level ownership or collections as partial instead of reporting none' {
        $unknownOwner = Get-TestWeb -Definitions @() -Bindings @()
        $unknownOwner.IsRootWeb = $null
        $noLevels = Get-TestWeb -Definitions @() -Bindings @()
        $noLevels.Url = 'https://intranet.contoso.com/sites/team/nolevels'
        $noLevels.RoleDefinitions = $null
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($unknownOwner, $noLevels)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue
        $warningText = $warnings -join ';'

        $signals.CustomizationInventoryComplete | Should -BeFalse
        $warningText | Should -Match "permission level ownership could not be read on 'https://intranet.contoso.com/sites/team'"
        $warningText | Should -Match "permission levels are unavailable on 'https://intranet.contoso.com/sites/team/nolevels'"
    }

    It 'isolates a permission level that cannot be classified and keeps the others' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.RoleDefinitions = @(
            [PSCustomObject]@{ Name = $null; Type = 'None' }
            (Get-TestRole -Name 'Project Manager')
        )
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.CustomPermissionLevelCount | Should -Be 1
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match 'Could not classify a permission level'
    }

    It 'counts lists with an incoming e-mail alias and ignores lists that can only receive e-mail' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists = @(
            (Get-TestMailList -Title 'Invoices' -EmailAlias 'invoices')
            (Get-TestMailList -Title 'Capable' -EmailAlias $null -CanReceiveEmail $true)
            (Get-TestMailList -Title 'Blank' -EmailAlias '')
            (Get-TestMailList -Title 'Requests' -EmailAlias 'requests')
        )
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.EmailEnabledListCount | Should -Be 2
        $signals.EmailEnabledListExamples | Should -Be 'Invoices (/sites/team/Invoices); Requests (/sites/team/Requests)'
        $signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'marks an unreadable incoming e-mail setting as partial instead of reporting the list as disabled' {
        $mailList = [SPSTestThrowingMailList]::new()
        $mailList.Title = 'Mailbox'
        $mailList.RootFolder = [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/Mailbox'; Properties = @{} }
        $mailList.ContentTypes = @()
        $mailList.WorkflowAssociations = @()
        $mailList.EventReceivers = @()
        $mailList.IrmEnabled = $false
        $mailList.ItemCount = 0
        $mailList.Views = @()
        $mailList.CheckedOutFiles = @()
        $mailList.EnableVersioning = $false
        $mailList.Items = @()
        $mailList.BaseTemplate = 100
        $mailList.Fields = @()
        $mailList.CanReceiveEmail = $true
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists = @($mailList, (Get-TestMailList -Title 'Requests' -EmailAlias 'requests'))
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.EmailEnabledListCount | Should -Be 1
        $signals.EmailEnabledListExamples | Should -Be 'Requests (/sites/team/Requests)'
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match "Could not read the incoming e-mail setting on list 'Mailbox'"
        ($warnings -join ';') | Should -Match 'alias store unavailable'
    }

    It 'does not scan HTML files unless asked to' {
        $library = Get-TestLibrary -HtmlBatches @(Get-TestHtmlBatch -Urls @('/sites/team/Docs/a.htm'))
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists = @($library)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.HtmlFileCount | Should -Be 0
        $signals.HtmlFileExamples | Should -Be ''
        $library.HtmlQueries | Should -HaveCount 0
        @($warnings) | Should -HaveCount 0
    }

    It 'counts .htm and .html files in document libraries when the scan is requested' {
        $library = Get-TestLibrary -HtmlBatches @(
            Get-TestHtmlBatch -Urls @('/sites/team/Docs/a.htm', '/sites/team/Docs/b.html') -Position 'next'
            Get-TestHtmlBatch -Urls @('/sites/team/Docs/sub/c.html')
        )
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists = @($library)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -ScanHtmlFile

        $signals.HtmlFileCount | Should -Be 3
        $signals.HtmlFileExamples | Should -Be '/sites/team/Docs/a.htm; /sites/team/Docs/b.html; /sites/team/Docs/sub/c.html'
        $signals.CustomizationInventoryComplete | Should -BeTrue
        $library.HtmlQueries | Should -HaveCount 2
        $library.HtmlQueries[0].Query | Should -Match '>htm<.*>html<'
        $library.HtmlQueries[0].ViewFields | Should -Match 'FileRef'
        $library.HtmlQueries[0].QueryThrottleMode | Should -Be 'Override'
    }

    It 'skips system catalogs and lists that are not document libraries when scanning HTML files' {
        $catalog = Get-TestLibrary -Title 'masterpage' -Url '/sites/team/_catalogs/masterpage' -HtmlBatches @(Get-TestHtmlBatch -Urls @('/x.html'))
        $tasks = Get-TestLibrary -Title 'Tasks' -BaseTemplate 100 -HtmlBatches @(Get-TestHtmlBatch -Urls @('/y.html'))
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists = @($catalog, $tasks)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -ScanHtmlFile

        $signals.HtmlFileCount | Should -Be 0
        $catalog.HtmlQueries | Should -HaveCount 0
        $tasks.HtmlQueries | Should -HaveCount 0
    }

    It 'caps the HTML file scan and marks it partial' {
        $library = Get-TestLibrary -HtmlBatches @(
            Get-TestHtmlBatch -Urls @('/sites/team/Docs/a.htm', '/sites/team/Docs/b.htm', '/sites/team/Docs/c.htm')
        )
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists = @($library)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -ScanHtmlFile -LargeContentThresholds @{ MaxItemsForHtmlFileScanPerLibrary = 2 } -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.HtmlFileCount | Should -Be 2
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match 'HTML file scan stopped'
        ($warnings -join ';') | Should -Match 'MaxItemsForHtmlFileScanPerLibrary'
    }

    It 'marks an unreadable HTML file query as partial and keeps the other libraries' {
        $broken = Get-TestLibrary -Title 'Broken'
        $broken | Add-Member -MemberType ScriptMethod -Name GetItems -Value { throw 'Query throttled' } -Force
        $good = Get-TestLibrary -Title 'Good' -HtmlBatches @(Get-TestHtmlBatch -Urls @('/sites/team/Good/a.htm'))
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists = @($broken, $good)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -ScanHtmlFile -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.HtmlFileCount | Should -Be 1
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match "Could not scan HTML files on 'Broken'"
        ($warnings -join ';') | Should -Match 'Query throttled'
    }

    It 'keeps running workflow counts at zero when Workflow Manager APIs are unavailable' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }
        Mock Get-SPSWorkflowSubscriptionCount -ModuleName SPSSiteInventory.Common { $null }
        Mock Get-SPSWorkflowRunningInstanceCount -ModuleName SPSSiteInventory.Common { $null }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.Workflow2013Count | Should -Be 0
        $signals.Workflow2013RunningInstanceCount | Should -Be 0
        $signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'preserves sandbox, site-feature, and InfoPath read failures as warnings' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $siteFeature = [PSCustomObject]@{ DefinitionId = 'another-feature' }
        $properties = [PSCustomObject]@{}
        $properties | Add-Member -MemberType ScriptMethod -Name ContainsKey -Value { throw 'InfoPath properties access denied' }
        $web.Lists[0].RootFolder.Properties = $properties
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Solutions = [SPSSiteInventoryThrowAfterOne]::new('Sandbox solution')
            Features = [SPSSiteInventoryThrowAfterOne]::new($siteFeature)
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -CustomFeatureId @('feature-id') -WarningVariable warnings -WarningAction SilentlyContinue
        $warningText = $warnings -join ';'

        $signals.CustomizationInventoryComplete | Should -BeFalse
        $warningText | Should -Match 'sandbox solutions for site collection'
        $warningText | Should -Match 'https://intranet.contoso.com/sites/team'
        $warningText | Should -Match 'Access denied while advancing the web enumerator'
        $warningText | Should -Match 'site-scoped features for site collection'
        $warningText | Should -Match 'Access denied while advancing the web enumerator'
        $warningText | Should -Match "InfoPath state on list 'Documents' in web 'https://intranet.contoso.com/sites/team'"
        $warningText | Should -Match 'InfoPath properties access denied'
    }

    It 'counts IRM-enabled lists and keeps unlocked sites non-blocking' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists[0].IrmEnabled = $true
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            ReadLocked = $false
            WriteLocked = $false
            ReadOnly = $false
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.IrmEnabledListCount | Should -Be 1
        $signals.SiteLockState | Should -Be 'Unlock'
        $signals.IsLockedSite | Should -BeFalse
        $signals.HasNoAccessLock | Should -BeFalse
    }

    It 'flags locked site collections as NoAccess when read access is locked' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            ReadLocked = $true
            WriteLocked = $true
            ReadOnly = $true
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.SiteLockState | Should -Be 'NoAccess'
        $signals.IsLockedSite | Should -BeTrue
        $signals.HasNoAccessLock | Should -BeTrue
    }

    It 'flags locked site collections as NoAdditions when write access is locked' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            ReadLocked = $false
            WriteLocked = $true
            ReadOnly = $false
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.SiteLockState | Should -Be 'NoAdditions'
        $signals.IsLockedSite | Should -BeTrue
        $signals.HasNoAccessLock | Should -BeFalse
    }

    It 'flags locked site collections as ReadOnly when only read-only mode is set' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            ReadLocked = $false
            WriteLocked = $false
            ReadOnly = $true
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.SiteLockState | Should -Be 'ReadOnly'
        $signals.IsLockedSite | Should -BeTrue
        $signals.HasNoAccessLock | Should -BeFalse
    }

    It 'does not flag a NoAccess lock when the lock state cannot be determined' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.SiteLockState | Should -Be 'Unknown'
        $signals.IsLockedSite | Should -BeFalse
        $signals.HasNoAccessLock | Should -BeFalse
    }

    It 'does not count lists when IRM is disabled' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            ReadLocked = $false
            WriteLocked = $false
            ReadOnly = $false
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.IrmEnabledListCount | Should -Be 0
        $signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'collects large-content signals with configurable thresholds' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists[0].Title = 'Projects'
        $web.Lists[0].ItemCount = 7200
        $web.Lists[0].Views = @(
            [PSCustomObject]@{ Title = 'All Documents'; RowLimit = 7000 },
            [PSCustomObject]@{ Title = 'Compact'; RowLimit = 100 }
        )
        $web.Lists[0].CheckedOutFiles = @('file1.docx', 'file2.docx')
        $web.Lists[0].EnableVersioning = $true
        $web.Lists[0].Items = @(
            [PSCustomObject]@{ File = [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/Projects/spec.docx'; Versions = @(1..80) } },
            [PSCustomObject]@{ File = [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/Projects/notes.docx'; Versions = @(1..5) } }
        )
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -LargeContentThresholds @{
            LargeListItemCount = 5000
            LargeListViewRowLimit = 5000
            CheckedOutFileCount = 1
            FileVersionCount = 50
            MaxItemsForVersionScanPerLibrary = 2000
        }

        $signals.LargeListCount | Should -Be 1
        $signals.LargeListExamples | Should -Match 'Projects \(7200\)'
        $signals.LargeListViewCount | Should -Be 1
        $signals.LargeListViewExamples | Should -Match 'Projects/All Documents \(7000\)'
        $signals.CheckedOutFileCount | Should -Be 2
        $signals.CheckedOutFileExamples | Should -Match 'Projects \(2\)'
        $signals.FileVersionCount | Should -Be 1
        $signals.FileVersionExamples | Should -Match '/sites/team/Projects/spec\.docx \(80\)'
    }

    It 'counts ordinary checked-out files that are not listed in CheckedOutFiles' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists[0].Title = 'Shared Documents'
        $web.Lists[0].CheckedOutFiles = @()
        $web.Lists[0].Items = @(
            [PSCustomObject]@{
                Name = 'proposal.docx'
                File = [PSCustomObject]@{
                    ServerRelativeUrl = '/sites/team/Shared%20Documents/proposal.docx'
                    CheckOutType = 'Online'
                    Versions = @()
                }
            },
            [PSCustomObject]@{
                Name = 'minutes.docx'
                File = [PSCustomObject]@{
                    ServerRelativeUrl = '/sites/team/Shared%20Documents/minutes.docx'
                    CheckOutType = 'None'
                    Versions = @()
                }
            }
        )
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -LargeContentThresholds @{
            CheckedOutFileCount = 1
        }

        $signals.CheckedOutFileCount | Should -Be 1
        $signals.CheckedOutFileExamples | Should -Match 'Shared Documents \(1\)'
    }

    It 'uses paged item retrieval for version scans and marks partial when capped' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists[0].Title = 'Architecture'
        $web.Lists[0].ItemCount = 12000
        $web.Lists[0].EnableVersioning = $true
        $web.Lists[0].Views = @()
        $web.Lists[0].CheckedOutFiles = @()
        $web.Lists[0] | Add-Member -MemberType NoteProperty -Name VersionBatchIndex -Value 0 -Force
        $web.Lists[0] | Add-Member -MemberType NoteProperty -Name VersionItemOne -Value ([PSCustomObject]@{
                Name = 'a.docx'
                File = [PSCustomObject]@{
                    ServerRelativeUrl = '/sites/team/Architecture/a.docx'
                    Versions = @(1..60)
                }
            }) -Force
        $web.Lists[0] | Add-Member -MemberType NoteProperty -Name VersionItemTwo -Value ([PSCustomObject]@{
                Name = 'b.docx'
                File = [PSCustomObject]@{
                    ServerRelativeUrl = '/sites/team/Architecture/b.docx'
                    Versions = @(1..55)
                }
            }) -Force
        $web.Lists[0] | Add-Member -MemberType NoteProperty -Name VersionItemThree -Value ([PSCustomObject]@{
                Name = 'c.docx'
                File = [PSCustomObject]@{
                    ServerRelativeUrl = '/sites/team/Architecture/c.docx'
                    Versions = @(1..80)
                }
            }) -Force
        $web.Lists[0] | Add-Member -MemberType ScriptMethod -Name GetItems -Value {
            param ($Query)
            $queryText = ''
            if ($null -ne $Query.PSObject.Properties['Query'] -and $Query.Query) {
                $queryText = [string]$Query.Query
            }
            if ($queryText -match 'CheckoutUser') {
                return [PSCustomObject]@{
                    Items = @()
                    ListItemCollectionPosition = $null
                }
            }
            if ($this.VersionBatchIndex -eq 0) {
                $this.VersionBatchIndex = 1
                return [PSCustomObject]@{
                    Items = @($this.VersionItemOne, $this.VersionItemTwo)
                    ListItemCollectionPosition = 'next'
                }
            }
            return [PSCustomObject]@{
                Items = @($this.VersionItemThree)
                ListItemCollectionPosition = $null
            }
        } -Force
        $web.Lists[0] | Add-Member -MemberType ScriptProperty -Name Items -Value { throw 'Version scan must use paged GetItems retrieval.' } -Force
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -LargeContentThresholds @{
            FileVersionCount = 50
            MaxItemsForVersionScanPerLibrary = 2
        } -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.FileVersionCount | Should -Be 2
        $signals.FileVersionExamples | Should -Match '/sites/team/Architecture/a\.docx \(60\)'
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join '; ') | Should -Match 'File-version scan stopped'
    }

    It 'keeps collected checkout keys when checkout paging fails mid-stream' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists[0].Title = 'Contracts'
        $web.Lists[0].CheckedOutFiles = @('/sites/team/Contracts/seed.docx')
        $web.Lists[0].EnableVersioning = $false
        $web.Lists[0] | Add-Member -MemberType NoteProperty -Name CheckoutBatchIndex -Value 0 -Force
        $web.Lists[0] | Add-Member -MemberType ScriptMethod -Name GetItems -Value {
            param ($Query)
            $queryText = ''
            if ($null -ne $Query.PSObject.Properties['Query'] -and $Query.Query) {
                $queryText = [string]$Query.Query
            }
            if ($queryText -match 'CheckoutUser') {
                if ($this.CheckoutBatchIndex -eq 0) {
                    $this.CheckoutBatchIndex = 1
                    return [PSCustomObject]@{
                        Items = @(
                            [PSCustomObject]@{
                                Name = 'active.docx'
                                File = [PSCustomObject]@{
                                    ServerRelativeUrl = '/sites/team/Contracts/active.docx'
                                    Versions = @()
                                }
                            }
                        )
                        ListItemCollectionPosition = 'next'
                    }
                }
                throw 'Checkout paging failure'
            }
            return [PSCustomObject]@{
                Items = @()
                ListItemCollectionPosition = $null
            }
        } -Force
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -LargeContentThresholds @{
            CheckedOutFileCount = 1
        } -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.CheckedOutFileCount | Should -Be 2
        $signals.CheckedOutFileExamples | Should -Match 'Contracts \(2\)'
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join '; ') | Should -Match 'Could not read checked-out files'
    }

    It 'counts retained file versions even when versioning is currently disabled' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists[0].Title = 'Policies'
        $web.Lists[0].EnableVersioning = $false
        $web.Lists[0].CheckedOutFiles = @()
        $web.Lists[0] | Add-Member -MemberType ScriptMethod -Name GetItems -Value {
            param ($Query)
            $queryText = ''
            if ($null -ne $Query.PSObject.Properties['Query'] -and $Query.Query) {
                $queryText = [string]$Query.Query
            }
            if ($queryText -match 'CheckoutUser') {
                return [PSCustomObject]@{
                    Items = @()
                    ListItemCollectionPosition = $null
                }
            }
            return [PSCustomObject]@{
                Items = @(
                    [PSCustomObject]@{
                        Name = 'policy.docx'
                        File = [PSCustomObject]@{
                            ServerRelativeUrl = '/sites/team/Policies/policy.docx'
                            Versions = @(1..75)
                        }
                    }
                )
                ListItemCollectionPosition = $null
            }
        } -Force
        $web.Lists[0] | Add-Member -MemberType ScriptProperty -Name Items -Value { throw 'Version scan must use paged GetItems retrieval.' } -Force
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -LargeContentThresholds @{
            FileVersionCount = 50
            MaxItemsForVersionScanPerLibrary = 2000
        }

        $signals.FileVersionCount | Should -Be 1
        $signals.FileVersionExamples | Should -Match '/sites/team/Policies/policy\.docx \(75\)'
    }

    It 'counts only active workflow associations when historical versions are flagged by metadata' {
        $webWorkflow = Get-TestWorkflowAssociation -Name 'WF for Statistics' -HasIsCurrent $true -IsCurrent $true
        $oldListWorkflow = Get-TestWorkflowAssociation -Name 'WF pour les Statistiques (version précédente: 08/07/2016 14:50:34)' -HasIsCurrent $true -IsCurrent $false
        $activeListWorkflow = Get-TestWorkflowAssociation -Name 'WF pour les Statistiques' -HasIsCurrent $true -IsCurrent $true

        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.WorkflowAssociations = @($webWorkflow)
        $web.Lists[0].WorkflowAssociations = @($oldListWorkflow, $activeListWorkflow)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.Workflow2010Count | Should -Be 2
    }

    It 'uses name fallback when metadata is unavailable to skip previous-version duplicates' {
        $historical = Get-TestWorkflowAssociation -Name 'WF for Statistics (Previous Version: 08/07/2016 14:50:34)'
        $active = Get-TestWorkflowAssociation -Name 'WF for Statistics'

        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists[0].WorkflowAssociations = @($historical, $active)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.Workflow2010Count | Should -Be 1
    }

    It 'uses name fallback for previous-version names with AM or PM timestamps' {
        $historical = Get-TestWorkflowAssociation -Name 'WF for Statistics (Previous Version: 08/07/2016 02:50:34 PM)'
        $active = Get-TestWorkflowAssociation -Name 'WF for Statistics'

        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists[0].WorkflowAssociations = @($historical, $active)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.Workflow2010Count | Should -Be 1
    }

    It 'uses name fallback for French previous-version markers' {
        $historical = Get-TestWorkflowAssociation -Name 'WF pour les Statistiques (version précédente : 08/07/2016 14:50:34)'
        $active = Get-TestWorkflowAssociation -Name 'WF pour les Statistiques'

        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists[0].WorkflowAssociations = @($historical, $active)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.Workflow2010Count | Should -Be 1
    }

    It 'does not treat non version qualifiers as historical associations' {
        $qualified = Get-TestWorkflowAssociation -Name 'WF for Statistics (SLA: 48)'
        $active = Get-TestWorkflowAssociation -Name 'WF for Statistics'

        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists[0].WorkflowAssociations = @($qualified, $active)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.Workflow2010Count | Should -Be 2
    }

    It 'does not count a singleton workflow association flagged as historical by metadata' {
        $historical = Get-TestWorkflowAssociation -Name 'WF for Statistics (Previous Version: 08/07/2016 14:50:34)' -HasIsCurrent $true -IsCurrent $false

        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists[0].WorkflowAssociations = @($historical)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.Workflow2010Count | Should -Be 0
    }

    It 'marks unreadable field metadata as partial rather than exporting zero fields' {
        $definition = Get-TestContentType -Id '0x0101' -Name 'Document'
        $definition | Add-Member -MemberType ScriptProperty -Name Fields -Value { throw 'Access denied' } -Force
        $binding = Get-TestContentType -Id '0x010100AAAA' -Name 'Document'
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @(Get-TestWeb -Definitions @($definition) -Bindings @($binding))
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.ContentTypeInventoryComplete | Should -BeFalse
        $signals.ContentTypeCount | Should -Be 0
        $signals.ListContentTypeBindingCount | Should -Be 1
        $signals.ContentTypes | Should -HaveCount 1
        $signals.ContentTypes[0].FieldCount | Should -Be 2
        ($warnings -join ';') | Should -Match 'Content-type definitions could not be fully read'
    }

    It 'marks an unreadable field type as partial rather than omitting the field' {
        $definition = Get-TestContentType -Id '0x0101' -Name 'Document'
        $definition.Fields[0] | Add-Member -MemberType ScriptProperty -Name TypeAsString -Value { throw 'Access denied' } -Force
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @(Get-TestWeb -Definitions @($definition) -Bindings @())
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningAction SilentlyContinue

        $signals.CustomizationInventoryComplete | Should -BeFalse
        $signals.ContentTypeInventoryComplete | Should -BeFalse
        $signals.ContentTypeCount | Should -Be 0
        $signals.ContentTypes | Should -HaveCount 0
    }

    It 'marks null field metadata as partial' {
        $definition = Get-TestContentType -Id '0x0101' -Name 'Document'
        $definition.Fields = $null
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @(Get-TestWeb -Definitions @($definition) -Bindings @())
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningAction SilentlyContinue

        $signals.ContentTypeInventoryComplete | Should -BeFalse
        $signals.ContentTypes | Should -HaveCount 0
    }

    It 'marks missing web definitions as partial while retaining list bindings' {
        $binding = Get-TestContentType -Id '0x010100AAAA' -Name 'Document'
        $web = Get-TestWeb -Definitions @() -Bindings @($binding)
        $web.ContentTypes = $null
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningAction SilentlyContinue

        $signals.ContentTypeInventoryComplete | Should -BeFalse
        $signals.ContentTypeCount | Should -Be 0
        $signals.ListContentTypeBindingCount | Should -Be 1
        $signals.ContentTypes | Should -HaveCount 1
    }

    It 'marks a throwing list ContentTypes getter as partial while retaining definitions' {
        $definition = Get-TestContentType -Id '0x0101' -Name 'Document'
        $web = Get-TestWeb -Definitions @($definition) -Bindings @()
        $web.Lists[0] | Add-Member -MemberType ScriptProperty -Name ContentTypes -Value { throw 'Access denied' } -Force
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningAction SilentlyContinue

        $signals.ContentTypeInventoryComplete | Should -BeFalse
        $signals.ContentTypeCount | Should -Be 1
        $signals.ListContentTypeBindingCount | Should -Be 0
        $signals.ContentTypes | Should -HaveCount 1
    }

    It 'marks a null list collection as partial while retaining definitions' {
        $definition = Get-TestContentType -Id '0x0101' -Name 'Document'
        $web = Get-TestWeb -Definitions @($definition) -Bindings @()
        $web.Lists = $null
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningAction SilentlyContinue

        $signals.CustomizationInventoryComplete | Should -BeFalse
        $signals.ContentTypeInventoryComplete | Should -BeFalse
        $signals.ContentTypeCount | Should -Be 1
        $signals.ContentTypes | Should -HaveCount 1
    }

    It 'marks an unavailable web collection as partial without throwing' {
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = $null
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningAction SilentlyContinue

        $signals.CustomizationInventoryComplete | Should -BeFalse
        $signals.ContentTypeInventoryComplete | Should -BeFalse
    }

    It 'catches a throwing web collection getter and returns partial signals' {
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @()
        }
        $site | Add-Member -MemberType ScriptProperty -Name AllWebs -Value { throw 'Access denied' } -Force

        $signals = Get-SPSSiteCustomization -Site $site -WarningAction SilentlyContinue

        $signals.CustomizationInventoryComplete | Should -BeFalse
        $signals.ContentTypeInventoryComplete | Should -BeFalse
    }

    It 'retains earlier web results when the web enumerator fails lazily' {
        $definition = Get-TestContentType -Id '0x0101' -Name 'Document'
        $web = Get-TestWeb -Definitions @($definition) -Bindings @()
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = [SPSSiteInventoryThrowAfterOne]::new($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.CustomizationInventoryComplete | Should -BeFalse
        $signals.ContentTypeInventoryComplete | Should -BeFalse
        $signals.ContentTypeCount | Should -Be 1
        $signals.ContentTypes | Should -HaveCount 1
        ($warnings -join ';') | Should -Match 'Webs could not be fully enumerated'
    }

    It 'marks an unreadable list collection as partial while retaining definitions' {
        $definition = Get-TestContentType -Id '0x0101' -Name 'Document'
        $web = Get-TestWeb -Definitions @($definition) -Bindings @()
        $web | Add-Member -MemberType ScriptProperty -Name Lists -Value { throw 'Access denied' } -Force
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningAction SilentlyContinue

        $signals.CustomizationInventoryComplete | Should -BeFalse
        $signals.ContentTypeInventoryComplete | Should -BeFalse
        $signals.ContentTypeCount | Should -Be 1
        $signals.ContentTypes | Should -HaveCount 1
    }

    It 'counts lists with managed metadata columns, their columns and the distinct term sets' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists = @(
            (Get-TestManagedMetadataList -Title 'Contracts' -ItemCount 12 -Fields @(
                (Get-TestTaxonomyField -Title 'Department' -TermSetId '11111111-1111-1111-1111-111111111111')
                (Get-TestTaxonomyField -Title 'Region' -Type 'TaxonomyFieldTypeMulti' -TermSetId '22222222-2222-2222-2222-222222222222')))
            (Get-TestManagedMetadataList -Title 'Projects' -Fields @((Get-TestTaxonomyField -Title 'Department' -TermSetId '11111111-1111-1111-1111-111111111111')))
            (Get-TestManagedMetadataList -Title 'Plain' -Fields @([PSCustomObject]@{ Title = 'Title'; TypeAsString = 'Text' }))
        )
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.ManagedMetadataListCount | Should -Be 2
        $signals.ManagedMetadataColumnCount | Should -Be 3
        $signals.ManagedMetadataTermSetCount | Should -Be 2
        $signals.ManagedMetadataExamples | Should -Be 'Contracts (Department, Region); Projects (Department)'
        $signals.ManagedMetadataLists | Should -HaveCount 2
        $signals.ManagedMetadataLists[0].SiteUrl | Should -Be 'https://intranet.contoso.com/sites/team'
        $signals.ManagedMetadataLists[0].WebUrl | Should -Be 'https://intranet.contoso.com/sites/team'
        $signals.ManagedMetadataLists[0].ListTitle | Should -Be 'Contracts'
        $signals.ManagedMetadataLists[0].ListUrl | Should -Be '/sites/team/Contracts'
        $signals.ManagedMetadataLists[0].ListItemCount | Should -Be 12
        $signals.ManagedMetadataLists[0].ManagedMetadataColumns | Should -Be 'Department; Region'
        $signals.CustomizationInventoryComplete | Should -BeTrue
        @($warnings) | Should -HaveCount 0
    }

    It 'counts a term set shared by several webs once for the site collection' {
        $first = Get-TestWeb -Definitions @() -Bindings @()
        $first.Lists = @((Get-TestManagedMetadataList -Title 'Contracts' -Fields @((Get-TestTaxonomyField))))
        $second = Get-TestWeb -Definitions @() -Bindings @()
        $second.Url = 'https://intranet.contoso.com/sites/team/sub'
        $second.Lists = @((Get-TestManagedMetadataList -Title 'Tasks' -Fields @((Get-TestTaxonomyField -Title 'Owner department'))))
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($first, $second)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.ManagedMetadataListCount | Should -Be 2
        $signals.ManagedMetadataColumnCount | Should -Be 2
        $signals.ManagedMetadataTermSetCount | Should -Be 1
        $signals.ManagedMetadataLists[1].WebUrl | Should -Be 'https://intranet.contoso.com/sites/team/sub'
    }

    It 'ignores hidden managed metadata columns and the helper fields SharePoint adds for them' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists = @(
            (Get-TestManagedMetadataList -Title 'Contracts' -Fields @(
                [PSCustomObject]@{ Title = 'Title'; TypeAsString = 'Text' }
                (Get-TestTaxonomyField -Title 'Department_0' -Type 'Note' -Hidden $true)
                (Get-TestTaxonomyField -Title 'Taxonomy Catch All Column' -Type 'LookupMulti' -Hidden $true)
                (Get-TestTaxonomyField -Title 'Retired' -Hidden $true)))
        )
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.ManagedMetadataListCount | Should -Be 0
        $signals.ManagedMetadataColumnCount | Should -Be 0
        $signals.ManagedMetadataTermSetCount | Should -Be 0
        $signals.ManagedMetadataExamples | Should -Be ''
        $signals.ManagedMetadataLists | Should -HaveCount 0
        $signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'lists at most five managed metadata examples but counts every list' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists = @(1..7 | ForEach-Object { Get-TestManagedMetadataList -Title "List$_" -Fields @((Get-TestTaxonomyField)) })
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.ManagedMetadataListCount | Should -Be 7
        $signals.ManagedMetadataLists | Should -HaveCount 7
        ($signals.ManagedMetadataExamples -split '; ') | Should -HaveCount 5
    }

    It 'marks an unreadable field collection as partial and keeps the other lists' {
        $broken = Get-TestManagedMetadataList -Title 'Broken' -Fields @()
        $broken.Fields = $null
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists = @($broken, (Get-TestManagedMetadataList -Title 'Good' -Fields @((Get-TestTaxonomyField))))
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.ManagedMetadataListCount | Should -Be 1
        $signals.ManagedMetadataLists[0].ListTitle | Should -Be 'Good'
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match "Could not read the managed metadata columns on list 'Broken' in web 'https://intranet.contoso.com/sites/team'"
        ($warnings -join ';') | Should -Match 'field collection is unavailable'
    }

    It 'marks a failing hidden-state getter as partial instead of counting or skipping the column' {
        $field = [SPSTestCollectorTaxonomyField]::new()
        $field.Title = 'Department'
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists = @(
            (Get-TestManagedMetadataList -Title 'Contracts' -Fields @($field))
            (Get-TestManagedMetadataList -Title 'Good' -Fields @((Get-TestTaxonomyField)))
        )
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.ManagedMetadataListCount | Should -Be 1
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match "Could not read the managed metadata columns on list 'Contracts'"
        ($warnings -join ';') | Should -Match 'hidden state unavailable'
    }

    It 'marks a failing item count as partial instead of exporting a zero count' {
        $list = [SPSTestFailingCountList]::new()
        $list.Title = 'Contracts'
        $list.RootFolder = [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/Contracts'; Properties = @{} }
        $list.ContentTypes = @()
        $list.WorkflowAssociations = @()
        $list.EventReceivers = @()
        $list.IrmEnabled = $false
        $list.Views = @()
        $list.CheckedOutFiles = @()
        $list.EnableVersioning = $false
        $list.Items = @()
        $list.BaseTemplate = 100
        $list.Fields = @((Get-TestTaxonomyField))
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists = @($list)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.ManagedMetadataListCount | Should -Be 0
        $signals.ManagedMetadataLists | Should -HaveCount 0
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match "Could not read the managed metadata columns on list 'Contracts'"
        ($warnings -join ';') | Should -Match 'item count unavailable'
    }

    It 'counts external lists and records the BCS binding of each' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists = @(
            (Get-TestExternalList -Title 'Customers' -EntityNamespace 'Contoso.Crm' -Entity 'Customer' -Instance 'CrmInstance')
            (Get-TestExternalList -Title 'Orders' -EntityNamespace 'Contoso.Sap' -Entity 'Order' -Instance 'SapInstance')
            (Get-TestMailList -Title 'Documents')
        )
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.ExternalListCount | Should -Be 2
        $signals.ExternalListExamples | Should -Be 'Customers (Contoso.Crm.Customer); Orders (Contoso.Sap.Order)'
        $signals.ExternalLists | Should -HaveCount 2
        $signals.ExternalLists[0].SiteUrl | Should -Be 'https://intranet.contoso.com/sites/team'
        $signals.ExternalLists[0].WebUrl | Should -Be 'https://intranet.contoso.com/sites/team'
        $signals.ExternalLists[0].ListTitle | Should -Be 'Customers'
        $signals.ExternalLists[0].ListUrl | Should -Be '/sites/team/Customers'
        $signals.ExternalLists[0].LobSystemInstance | Should -Be 'CrmInstance'
        $signals.ExternalLists[1].LobSystemInstance | Should -Be 'SapInstance'
        $signals.CustomizationInventoryComplete | Should -BeTrue
        @($warnings) | Should -HaveCount 0
    }

    It 'reports no external list on a site without any' {
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @(Get-TestWeb -Definitions @() -Bindings @())
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.ExternalListCount | Should -Be 0
        $signals.ExternalListExamples | Should -Be ''
        $signals.ExternalLists | Should -HaveCount 0
        $signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'finds external lists in every web and lists at most five examples' {
        $first = Get-TestWeb -Definitions @() -Bindings @()
        $first.Lists = @(1..4 | ForEach-Object { Get-TestExternalList -Title "First$_" })
        $second = Get-TestWeb -Definitions @() -Bindings @()
        $second.Url = 'https://intranet.contoso.com/sites/team/sub'
        $second.Lists = @(1..3 | ForEach-Object { Get-TestExternalList -Title "Second$_" })
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($first, $second)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.ExternalListCount | Should -Be 7
        $signals.ExternalLists | Should -HaveCount 7
        $signals.ExternalLists[6].WebUrl | Should -Be 'https://intranet.contoso.com/sites/team/sub'
        ($signals.ExternalListExamples -split '; ') | Should -HaveCount 5
    }

    It 'marks an unreadable external data source flag as partial instead of reading the list as not external' {
        $unknown = Get-TestMailList -Title 'Unknown'
        $unknown.PSObject.Properties.Remove('HasExternalDataSource')
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists = @($unknown, (Get-TestExternalList -Title 'Customers'))
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.ExternalListCount | Should -Be 1
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match "Could not read the external data source of list 'Unknown' in web 'https://intranet.contoso.com/sites/team'"
        ($warnings -join ';') | Should -Match 'external data source flag could not be read'
    }

    It 'marks a failing external data source flag getter as partial and keeps the other lists' {
        $list = [SPSTestFailingFlagList]::new()
        $list.Title = 'Mailbox'
        $list.RootFolder = [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/Mailbox'; Properties = @{} }
        $list.ContentTypes = @()
        $list.WorkflowAssociations = @()
        $list.EventReceivers = @()
        $list.IrmEnabled = $false
        $list.Views = @()
        $list.CheckedOutFiles = @()
        $list.EnableVersioning = $false
        $list.Items = @()
        $list.BaseTemplate = 100
        $list.Fields = @()
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists = @($list, (Get-TestExternalList -Title 'Customers'))
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.ExternalListCount | Should -Be 1
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match "Could not read the external data source of list 'Mailbox'"
        ($warnings -join ';') | Should -Match 'external flag unavailable'
    }

    It 'counts an external list whose binding cannot be read, leaves its row out and marks the site partial' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists = @(
            (Get-TestExternalList -Title 'Broken' -WithoutDataSource)
            (Get-TestExternalList -Title 'Customers')
        )
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.ExternalListCount | Should -Be 2
        $signals.ExternalLists | Should -HaveCount 1
        $signals.ExternalLists[0].ListTitle | Should -Be 'Customers'
        $signals.ExternalListExamples | Should -Be 'Broken (binding unreadable); Customers (Contoso.Crm.Customer)'
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match "Could not read the external data source of list 'Broken'"
        ($warnings -join ';') | Should -Match "external data source of list 'Broken' could not be read"
    }

    It 'still counts a site whose only external lists have unreadable bindings, so the blocking signal is not lost' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists = @((Get-TestExternalList -Title 'Broken' -WithoutDataSource))
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningAction SilentlyContinue
        $result = Measure-SPSSiteComplexity -Signals $signals -Scoring @{ Weights = @{ ExternalListCount = 1.0 }; Thresholds = @{ Moderate = 1.0; Complex = 6.0 }; BlockingSignals = @('ExternalListCount') }

        $signals.ExternalListCount | Should -Be 1
        $signals.ExternalLists | Should -HaveCount 0
        $signals.CustomizationInventoryComplete | Should -BeFalse
        $result.Category | Should -Be 4
    }

    It 'counts the SharePoint alerts of every web and records one row per alert' {
        $first = Get-TestWeb -Definitions @() -Bindings @()
        $first.Alerts = @((Get-TestAlert -Title 'First' -UserId 7), (Get-TestAlert -Title 'Second' -UserId 8))
        $second = Get-TestWeb -Definitions @() -Bindings @()
        $second.Url = 'https://intranet.contoso.com/sites/team/sub'
        $second.Alerts = @((Get-TestAlert -Title 'Third' -UserId 9))
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($first, $second)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.SharePointAlertCount | Should -Be 3
        $signals.SharePointAlerts | Should -HaveCount 3
        $signals.SharePointAlerts[0].SiteUrl | Should -Be 'https://intranet.contoso.com/sites/team'
        $signals.SharePointAlerts[0].WebUrl | Should -Be 'https://intranet.contoso.com/sites/team'
        $signals.SharePointAlerts[1].Title | Should -Be 'Second'
        $signals.SharePointAlerts[1].UserLoginName | Should -Be 'i:0#.w|contoso\user8'
        $signals.SharePointAlerts[2].WebUrl | Should -Be 'https://intranet.contoso.com/sites/team/sub'
        $signals.CustomizationInventoryComplete | Should -BeTrue
        @($warnings) | Should -HaveCount 0
    }

    It 'reports no SharePoint alert on a site without any' {
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @(Get-TestWeb -Definitions @() -Bindings @())
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.SharePointAlertCount | Should -Be 0
        $signals.SharePointAlerts | Should -HaveCount 0
        $signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'keeps the alert count exact and marks the site partial when the rows reach the per-site cap' {
        $first = Get-TestWeb -Definitions @() -Bindings @()
        $first.Alerts = @(1..2 | ForEach-Object { Get-TestAlert -Title "First$_" })
        $second = Get-TestWeb -Definitions @() -Bindings @()
        $second.Url = 'https://intranet.contoso.com/sites/team/sub'
        $second.Alerts = @(1..2 | ForEach-Object { Get-TestAlert -Title "Second$_" })
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($first, $second)
        }

        $signals = Get-SPSSiteCustomization -Site $site -LargeContentThresholds @{ MaxAlertRowsPerSite = 3 } -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.SharePointAlertCount | Should -Be 4
        $signals.SharePointAlerts | Should -HaveCount 3
        $signals.SharePointAlerts[2].Title | Should -Be 'Second1'
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match 'LargeContentThresholds\.MaxAlertRowsPerSite'
    }

    It 'warns once per site, not once per web, when the alert rows reach the cap' {
        $first = Get-TestWeb -Definitions @() -Bindings @()
        $first.Alerts = @(1..2 | ForEach-Object { Get-TestAlert -Title "First$_" })
        $second = Get-TestWeb -Definitions @() -Bindings @()
        $second.Url = 'https://intranet.contoso.com/sites/team/sub'
        $second.Alerts = @(1..2 | ForEach-Object { Get-TestAlert -Title "Second$_" })
        $third = Get-TestWeb -Definitions @() -Bindings @()
        $third.Url = 'https://intranet.contoso.com/sites/team/other'
        $third.Alerts = @(Get-TestAlert -Title 'Third')
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($first, $second, $third)
        }

        $signals = Get-SPSSiteCustomization -Site $site -LargeContentThresholds @{ MaxAlertRowsPerSite = 1 } -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.SharePointAlertCount | Should -Be 5
        $signals.SharePointAlerts | Should -HaveCount 1
        @($warnings | Where-Object { $_ -match 'MaxAlertRowsPerSite' }) | Should -HaveCount 1
    }

    It 'reports the first unreadable alerts and summarizes the others instead of warning for every alert' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Alerts = @(1..8 | ForEach-Object {
            $broken = Get-TestAlert -Title "Broken$_"
            $broken.PSObject.Properties.Remove('Status')
            $broken
        })
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.SharePointAlertCount | Should -Be 8
        $signals.SharePointAlerts | Should -HaveCount 0
        $signals.CustomizationInventoryComplete | Should -BeFalse
        @($warnings | Where-Object { $_ -match 'Could not read an alert on web' }) | Should -HaveCount 5
        @($warnings | Where-Object { $_ -match '3 more alert\(s\) could not be read on site' }) | Should -HaveCount 1
    }

    It 'leaves the alert owner logins out and never looks the owners up when the setting turns them off' {
        $global:SPSTestUserLookups = 0
        $makeAlert = {
            param ([string]$Title, [int]$UserId)
            $alert = Get-TestAlert -Title $Title -UserId $UserId
            $alert.PSObject.Properties.Remove('User')
            $alert | Add-Member -MemberType ScriptProperty -Name User -Value { $global:SPSTestUserLookups++; [PSCustomObject]@{ LoginName = "i:0#.w|contoso\user$($this.UserId)" } }
            $alert
        }
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Alerts = @((& $makeAlert 'A' 7), (& $makeAlert 'B' 8))
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -SharePointAlertSettings @{ IncludeUserLogin = $false }

        $signals.SharePointAlertCount | Should -Be 2
        $signals.SharePointAlerts | Should -HaveCount 2
        $global:SPSTestUserLookups | Should -Be 0
        $signals.SharePointAlerts[0].UserLoginName | Should -Be ''
        $signals.SharePointAlerts[1].UserLoginName | Should -Be ''
        $signals.SharePointAlerts[0].UserId | Should -Be 7
        $signals.SharePointAlerts[1].UserId | Should -Be 8
        $signals.CustomizationInventoryComplete | Should -BeTrue
        Remove-Variable -Name SPSTestUserLookups -Scope Global
    }

    It 'collects the alert owner logins when the setting is true or absent' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Alerts = @((Get-TestAlert -Title 'A' -UserId 7))
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $explicit = Get-SPSSiteCustomization -Site $site -SharePointAlertSettings @{ IncludeUserLogin = $true }
        $default = Get-SPSSiteCustomization -Site $site

        $explicit.SharePointAlerts[0].UserLoginName | Should -Be 'i:0#.w|contoso\user7'
        $default.SharePointAlerts[0].UserLoginName | Should -Be 'i:0#.w|contoso\user7'
    }

    It 'rejects a SharePoint alert setting that is not a boolean instead of collecting the logins' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Alerts = @((Get-TestAlert -Title 'A' -UserId 7))
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        { Get-SPSSiteCustomization -Site $site -SharePointAlertSettings @{ IncludeUserLogin = 'false' } } | Should -Throw -ExpectedMessage '*SharePointAlerts.IncludeUserLogin must be*'
    }

    It 'resolves each alert owner once for the whole site collection' {
        $global:SPSTestUserLookups = 0
        $makeAlert = {
            param ([string]$Title, [int]$UserId)
            $alert = Get-TestAlert -Title $Title -UserId $UserId
            $alert.PSObject.Properties.Remove('User')
            $alert | Add-Member -MemberType ScriptProperty -Name User -Value { $global:SPSTestUserLookups++; [PSCustomObject]@{ LoginName = "i:0#.w|contoso\user$($this.UserId)" } }
            $alert
        }
        $first = Get-TestWeb -Definitions @() -Bindings @()
        $first.Alerts = @((& $makeAlert 'A' 7), (& $makeAlert 'B' 7), (& $makeAlert 'C' 8))
        $second = Get-TestWeb -Definitions @() -Bindings @()
        $second.Url = 'https://intranet.contoso.com/sites/team/sub'
        $second.Alerts = @((& $makeAlert 'D' 7), (& $makeAlert 'E' 9))
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($first, $second)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.SharePointAlerts | Should -HaveCount 5
        $global:SPSTestUserLookups | Should -Be 3
        $signals.SharePointAlerts[3].UserLoginName | Should -Be 'i:0#.w|contoso\user7'
        $signals.SharePointAlerts[4].UserLoginName | Should -Be 'i:0#.w|contoso\user9'
        Remove-Variable -Name SPSTestUserLookups -Scope Global
    }

    It 'keeps the site complete when the alert rows exactly fill the cap' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Alerts = @(1..3 | ForEach-Object { Get-TestAlert -Title "Alert$_" })
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -LargeContentThresholds @{ MaxAlertRowsPerSite = 3 } -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.SharePointAlertCount | Should -Be 3
        $signals.SharePointAlerts | Should -HaveCount 3
        $signals.CustomizationInventoryComplete | Should -BeTrue
        @($warnings) | Should -HaveCount 0
    }

    It 'still counts an alert that cannot be read and marks the site partial' {
        $broken = Get-TestAlert -Title 'Broken'
        $broken.PSObject.Properties.Remove('Status')
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Alerts = @((Get-TestAlert -Title 'Fine'), $broken)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.SharePointAlertCount | Should -Be 2
        $signals.SharePointAlerts | Should -HaveCount 1
        $signals.SharePointAlerts[0].Title | Should -Be 'Fine'
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match "Could not read an alert on web 'https://intranet.contoso.com/sites/team'"
    }

    It 'marks the site partial when the alert collection of a web is unavailable' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Alerts = $null
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.SharePointAlertCount | Should -Be 0
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match "Could not read the alerts on web 'https://intranet.contoso.com/sites/team': The alert collection is unavailable"
    }

    It 'marks the site partial instead of reporting no alert when the alert count cannot be read' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Alerts = [SPSSiteInventoryBrokenAlertCollection]::new()
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Features = @()
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.SharePointAlertCount | Should -Be 0
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match 'The alert data could not be loaded'
    }
}

Describe 'Get-SPSSiteCustomization subsites' {
    BeforeAll {
        function Get-TestSubsite {
            param ([System.String] $Url, [System.Boolean] $IsRootWeb = $false)

            $subsite = Get-TestWeb -Definitions @() -Bindings @()
            $subsite.Url = $Url
            $subsite.IsRootWeb = $IsRootWeb
            return $subsite
        }

        function Get-TestSite {
            param ([System.Object[]] $Web, [System.String] $Url = 'https://intranet.contoso.com/sites/team')

            return [PSCustomObject]@{
                Url      = $Url
                Features = @()
                Solutions = @()
                AllWebs  = $Web
            }
        }
    }

    It 'counts the webs below the root web, the deepest level and the deepest subsites' {
        $site = Get-TestSite -Web @(
            Get-TestSubsite -Url 'https://intranet.contoso.com/sites/team' -IsRootWeb $true
            Get-TestSubsite -Url 'https://intranet.contoso.com/sites/team/a'
            Get-TestSubsite -Url 'https://intranet.contoso.com/sites/team/a/b'
            Get-TestSubsite -Url 'https://intranet.contoso.com/sites/team/c'
        )

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.SubsiteCount | Should -Be 3
        $signals.MaxSubsiteDepth | Should -Be 2
        $signals.SubsiteExamples | Should -Be 'a/b (level 2); a (level 1); c (level 1)'
        $signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'reports no subsite for a site collection that has only its root web' {
        $site = Get-TestSite -Web @(Get-TestSubsite -Url 'https://intranet.contoso.com/sites/team' -IsRootWeb $true)

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.SubsiteCount | Should -Be 0
        $signals.MaxSubsiteDepth | Should -Be 0
        $signals.SubsiteExamples | Should -Be ''
        $signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'counts the subsites of the root site collection of a web application' {
        $site = Get-TestSite -Url 'https://intranet.contoso.com' -Web @(
            Get-TestSubsite -Url 'https://intranet.contoso.com' -IsRootWeb $true
            Get-TestSubsite -Url 'https://intranet.contoso.com/news'
            Get-TestSubsite -Url 'https://intranet.contoso.com/news/archive'
        )

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.SubsiteCount | Should -Be 2
        $signals.MaxSubsiteDepth | Should -Be 2
    }

    It 'does not count the app webs that add-ins create' {
        $appWeb = Get-TestSubsite -Url 'https://intranet.contoso.com/sites/team/MyApp'
        $appWeb | Add-Member -MemberType NoteProperty -Name IsAppWeb -Value $true
        $site = Get-TestSite -Web @(
            Get-TestSubsite -Url 'https://intranet.contoso.com/sites/team' -IsRootWeb $true
            $appWeb
            Get-TestSubsite -Url 'https://intranet.contoso.com/sites/team/real'
        )

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.AppWebCount | Should -Be 1
        $signals.SubsiteCount | Should -Be 1
        $signals.SubsiteExamples | Should -Be 'real (level 1)'
    }

    It 'lists at most five subsites, the deepest first' {
        $webs = @(Get-TestSubsite -Url 'https://intranet.contoso.com/sites/team' -IsRootWeb $true)
        foreach ($name in @('a', 'b', 'c', 'd', 'e', 'f')) {
            $webs += Get-TestSubsite -Url "https://intranet.contoso.com/sites/team/$name"
        }
        $webs += Get-TestSubsite -Url 'https://intranet.contoso.com/sites/team/z/y/x'
        $site = Get-TestSite -Web $webs

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.SubsiteCount | Should -Be 7
        $signals.MaxSubsiteDepth | Should -Be 3
        $signals.SubsiteExamples | Should -Be 'z/y/x (level 3); a (level 1); b (level 1); c (level 1); d (level 1)'
    }

    It 'marks the collection partial, with a warning, when a web is not below the site collection' {
        $site = Get-TestSite -Web @(
            Get-TestSubsite -Url 'https://intranet.contoso.com/sites/team' -IsRootWeb $true
            Get-TestSubsite -Url 'https://elsewhere.contoso.com/other'
            Get-TestSubsite -Url 'https://intranet.contoso.com/sites/team/a'
        )

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.SubsiteCount | Should -Be 1
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match "Could not place web 'https://elsewhere.contoso.com/other' in the structure of the site collection"
    }

    It 'marks the collection partial, and counts nothing, for a web with the same path on another host' {
        $site = Get-TestSite -Web @(
            Get-TestSubsite -Url 'https://intranet.contoso.com/sites/team' -IsRootWeb $true
            Get-TestSubsite -Url 'https://elsewhere.contoso.com/sites/team/payroll'
        )

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.SubsiteCount | Should -Be 0
        $signals.MaxSubsiteDepth | Should -Be 0
        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match "Could not place web 'https://elsewhere.contoso.com/sites/team/payroll'"
    }

    It 'marks the collection partial when the URL of a web cannot be read' {
        $site = Get-TestSite -Web @(
            Get-TestSubsite -Url 'https://intranet.contoso.com/sites/team' -IsRootWeb $true
            Get-TestSubsite -Url ''
        )

        $signals = Get-SPSSiteCustomization -Site $site -WarningAction SilentlyContinue

        $signals.SubsiteCount | Should -Be 0
        $signals.CustomizationInventoryComplete | Should -BeFalse
    }
}
