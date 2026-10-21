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
'@

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
            BaseTemplate = 101
        }
        $web = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            ContentTypes = $Definitions
            Lists = @($list)
            WorkflowAssociations = @()
            HasUniqueRoleAssignments = $false
            CustomMasterUrl = ''
        }
        $web | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        return $web
    }

    function Get-TestWorkflowAssociation {
        param (
            [string]$Name,
            [bool]$HasIsCurrent = $false,
            [bool]$IsCurrent = $true
        )

        $association = [PSCustomObject]@{ Name = $Name }
        if ($HasIsCurrent) {
            $association | Add-Member -MemberType NoteProperty -Name IsCurrent -Value $IsCurrent
        }
        return $association
    }
}

Describe 'Get-SPSSiteCustomization content types' {
    It 'records web definitions and list bindings without declaring them custom' {
        $definition = Get-TestContentType -Id '0x0101' -Name 'Document & Notes'
        $binding = Get-TestContentType -Id '0x010100AAAA' -Name 'Document & Notes'
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
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
            Solutions = @()
            AllWebs = @($web)
        }
        Mock Get-SPSWorkflowSubscriptionCount -ModuleName SPSSiteInventory.Common {
            throw 'Workflow subscription access denied'
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.CustomizationInventoryComplete | Should -BeFalse
        ($warnings -join ';') | Should -Match 'Workflow Manager subscriptions could not be read'
        ($warnings -join ';') | Should -Match 'Workflow subscription access denied'
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

    It 'counts only active workflow associations when historical versions are flagged by metadata' {
        $webWorkflow = Get-TestWorkflowAssociation -Name 'WF for Statistics' -HasIsCurrent $true -IsCurrent $true
        $oldListWorkflow = Get-TestWorkflowAssociation -Name 'WF pour les Statistiques (version précédente: 08/07/2016 14:50:34)' -HasIsCurrent $true -IsCurrent $false
        $activeListWorkflow = Get-TestWorkflowAssociation -Name 'WF pour les Statistiques' -HasIsCurrent $true -IsCurrent $true

        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.WorkflowAssociations = @($webWorkflow)
        $web.Lists[0].WorkflowAssociations = @($oldListWorkflow, $activeListWorkflow)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
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
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.Workflow2010Count | Should -Be 1
    }

    It 'does not count a singleton workflow association flagged as historical by metadata' {
        $historical = Get-TestWorkflowAssociation -Name 'WF for Statistics (Previous Version: 08/07/2016 14:50:34)' -HasIsCurrent $true -IsCurrent $false

        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists[0].WorkflowAssociations = @($historical)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
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
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningAction SilentlyContinue

        $signals.CustomizationInventoryComplete | Should -BeFalse
        $signals.ContentTypeInventoryComplete | Should -BeFalse
        $signals.ContentTypeCount | Should -Be 1
        $signals.ContentTypes | Should -HaveCount 1
    }
}
