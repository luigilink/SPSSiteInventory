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
            IrmEnabled = $false
            ItemCount = 0
            Views = @()
            CheckedOutFiles = @()
            EnableVersioning = $false
            Items = @()
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

    It 'counts IRM-enabled lists and keeps unlocked sites non-blocking' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists[0].IrmEnabled = $true
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
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
    }

    It 'flags locked site collections as NoAccess when read access is locked' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Solutions = @()
            ReadLocked = $true
            WriteLocked = $true
            ReadOnly = $true
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.SiteLockState | Should -Be 'NoAccess'
        $signals.IsLockedSite | Should -BeTrue
    }

    It 'flags locked site collections as NoAdditions when write access is locked' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Solutions = @()
            ReadLocked = $false
            WriteLocked = $true
            ReadOnly = $false
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.SiteLockState | Should -Be 'NoAdditions'
        $signals.IsLockedSite | Should -BeTrue
    }

    It 'flags locked site collections as ReadOnly when only read-only mode is set' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Solutions = @()
            ReadLocked = $false
            WriteLocked = $false
            ReadOnly = $true
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.SiteLockState | Should -Be 'ReadOnly'
        $signals.IsLockedSite | Should -BeTrue
    }

    It 'does not count lists when IRM is disabled' {
        $web = Get-TestWeb -Definitions @() -Bindings @()
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
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

    It 'uses name fallback for previous-version names with AM or PM timestamps' {
        $historical = Get-TestWorkflowAssociation -Name 'WF for Statistics (Previous Version: 08/07/2016 02:50:34 PM)'
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

    It 'uses name fallback for French previous-version markers' {
        $historical = Get-TestWorkflowAssociation -Name 'WF pour les Statistiques (version précédente : 08/07/2016 14:50:34)'
        $active = Get-TestWorkflowAssociation -Name 'WF pour les Statistiques'

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

    It 'does not treat non version qualifiers as historical associations' {
        $qualified = Get-TestWorkflowAssociation -Name 'WF for Statistics (SLA: 48)'
        $active = Get-TestWorkflowAssociation -Name 'WF for Statistics'

        $web = Get-TestWeb -Definitions @() -Bindings @()
        $web.Lists[0].WorkflowAssociations = @($qualified, $active)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
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
