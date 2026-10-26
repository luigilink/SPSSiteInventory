# Behavior tests for ConvertTo-SPSManagedMetadataListRecord (no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    # ConvertTo-SPSManagedMetadataListRecord is private; reach it inside the module scope.
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    # A real .NET type is required: PowerShell turns a failing getter into $null, and also swallows
    # exceptions from script properties, so only a compiled getter reproduces a failed property read.
    if (-not ('SPSTestTaxonomyField' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
public class SPSTestTaxonomyField
{
    public string Title { get; set; }
    public string InternalName { get; set; }
    public string TypeAsString { get; set; }
    public bool FailHidden { get; set; }
    public bool FailTermSet { get; set; }
    public bool Hidden { get { if (FailHidden) { throw new InvalidOperationException("hidden state unavailable"); } return false; } }
    public Guid TermSetId { get { if (FailTermSet) { throw new InvalidOperationException("term set unavailable"); } return Guid.NewGuid(); } }
}

public class SPSTestCountingList
{
    public object Fields { get; set; }
    public string Title { get; set; }
    public object RootFolder { get; set; }
    public object BaseTemplate { get; set; }
    public object BaseType { get; set; }
    public int ItemCount { get { throw new InvalidOperationException("item count unavailable"); } }
}
'@
    }

    function Get-TestField {
        param (
            [string]$Title = 'Department',
            [string]$Type = 'TaxonomyFieldType',
            $TermSetId = '11111111-1111-1111-1111-111111111111',
            [bool]$Hidden = $false
        )
        [PSCustomObject]@{
            Title = $Title
            InternalName = ($Title -replace '\s', '_x0020_')
            TypeAsString = $Type
            Hidden = $Hidden
            TermSetId = $TermSetId
        }
    }

    function Get-TestList {
        param ([object[]]$Fields = @())
        [PSCustomObject]@{
            Title = 'Contracts'
            RootFolder = [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/Contracts' }
            Fields = $Fields
            ItemCount = 42
            BaseTemplate = 'DocumentLibrary'
            BaseType = 'DocumentLibrary'
            LastItemModifiedDate = [datetime]'2026-03-04T10:20:30'
        }
    }

    function Convert-List {
        param ($List)
        & $script:Module {
            param ($Candidate)
            ConvertTo-SPSManagedMetadataListRecord -List $Candidate -SiteUrl 'https://intranet.contoso.com/sites/team' -WebUrl 'https://intranet.contoso.com/sites/team/sub'
        } $List
    }
}

Describe 'ConvertTo-SPSManagedMetadataListRecord' {
    It 'returns null for a list without managed metadata columns' {
        $list = Get-TestList -Fields @(
            (Get-TestField -Title 'Title' -Type 'Text')
            (Get-TestField -Title 'Owner' -Type 'Lookup')
            (Get-TestField -Title 'Notes' -Type 'Note')
        )

        Convert-List -List $list | Should -BeNullOrEmpty
    }

    It 'returns null for a list without any field' {
        Convert-List -List (Get-TestList -Fields @()) | Should -BeNullOrEmpty
    }

    It 'projects single and multi-value columns with sorted names and distinct term sets' {
        $list = Get-TestList -Fields @(
            (Get-TestField -Title 'Title' -Type 'Text')
            (Get-TestField -Title 'Region' -Type 'TaxonomyFieldTypeMulti' -TermSetId '33333333-3333-3333-3333-333333333333')
            (Get-TestField -Title 'Department' -Type 'TaxonomyFieldType' -TermSetId '22222222-2222-2222-2222-222222222222')
        )

        $record = Convert-List -List $list

        $record.SiteUrl | Should -Be 'https://intranet.contoso.com/sites/team'
        $record.WebUrl | Should -Be 'https://intranet.contoso.com/sites/team/sub'
        $record.ListTitle | Should -Be 'Contracts'
        $record.ListUrl | Should -Be '/sites/team/Contracts'
        $record.ListTemplate | Should -Be 'DocumentLibrary'
        $record.ListType | Should -Be 'DocumentLibrary'
        $record.ListItemCount | Should -Be 42
        $record.ItemLastModifiedDate | Should -Be '2026-03-04 10:20:30'
        $record.ManagedMetadataColumnCount | Should -Be 2
        $record.ManagedMetadataColumns | Should -Be 'Department; Region'
        $record.TermSetIds | Should -Be '22222222-2222-2222-2222-222222222222; 33333333-3333-3333-3333-333333333333'
    }

    It 'counts the Enterprise Keywords column like any managed metadata column' {
        $list = Get-TestList -Fields @(
            (Get-TestField -Title 'Enterprise Keywords' -Type 'TaxonomyFieldTypeMulti' -TermSetId 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
        )

        $record = Convert-List -List $list

        $record.ManagedMetadataColumnCount | Should -Be 1
        $record.ManagedMetadataColumns | Should -Be 'Enterprise Keywords'
    }

    It 'ignores hidden managed metadata columns and the helper fields SharePoint adds for them' {
        $list = Get-TestList -Fields @(
            (Get-TestField -Title 'Department' -Type 'TaxonomyFieldType')
            (Get-TestField -Title 'Department_0' -Type 'Note' -Hidden $true)
            (Get-TestField -Title 'Taxonomy Catch All Column' -Type 'LookupMulti' -Hidden $true)
            (Get-TestField -Title 'Retired' -Type 'TaxonomyFieldTypeMulti' -TermSetId '44444444-4444-4444-4444-444444444444' -Hidden $true)
        )

        $record = Convert-List -List $list

        $record.ManagedMetadataColumnCount | Should -Be 1
        $record.ManagedMetadataColumns | Should -Be 'Department'
        $record.TermSetIds | Should -Be '11111111-1111-1111-1111-111111111111'
    }

    It 'returns null when every managed metadata column is hidden' {
        $list = Get-TestList -Fields @((Get-TestField -Title 'Retired' -Type 'TaxonomyFieldType' -Hidden $true))

        Convert-List -List $list | Should -BeNullOrEmpty
    }

    It 'counts a shared term set once and keeps a column whose term set ID is empty' {
        $list = Get-TestList -Fields @(
            (Get-TestField -Title 'Department' -TermSetId '11111111-1111-1111-1111-111111111111')
            (Get-TestField -Title 'Owner department' -TermSetId '11111111-1111-1111-1111-111111111111')
            (Get-TestField -Title 'Unbound' -TermSetId ([guid]::Empty))
        )

        $record = Convert-List -List $list

        $record.ManagedMetadataColumnCount | Should -Be 3
        $record.TermSetIds | Should -Be '11111111-1111-1111-1111-111111111111'
    }

    It 'normalizes term set IDs and falls back to the internal name when the title is blank' {
        $field = Get-TestField -Title '' -TermSetId '{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}'
        $field.InternalName = 'ProjectCode'

        $record = Convert-List -List (Get-TestList -Fields @($field))

        $record.ManagedMetadataColumns | Should -Be 'ProjectCode'
        $record.TermSetIds | Should -Be 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    }

    It 'leaves the last-modified date empty when SharePoint does not return a date' {
        $list = Get-TestList -Fields @((Get-TestField))
        $list.LastItemModifiedDate = $null

        (Convert-List -List $list).ItemLastModifiedDate | Should -Be ''
    }

    It 'rejects an unreadable field collection, field, type name or column name' {
        $noFields = Get-TestList
        $noFields.Fields = $null
        { Convert-List -List $noFields } | Should -Throw '*field collection is unavailable*'
        { Convert-List -List (Get-TestList -Fields @($null)) } | Should -Throw '*field could not be read*'
        { Convert-List -List (Get-TestList -Fields @((Get-TestField -Type ''))) } | Should -Throw '*no readable type name*'
        { Convert-List -List (Get-TestList -Fields @([PSCustomObject]@{ TypeAsString = 'Text' }, [PSCustomObject]@{ Title = 'Department' })) } | Should -Throw '*no readable type name*'
        $nameless = Get-TestField -Title ''
        $nameless.InternalName = ''
        { Convert-List -List (Get-TestList -Fields @($nameless)) } | Should -Throw '*no readable name*'
    }

    It 'rejects a missing hidden state or term set instead of reading them as visible or unbound' {
        $noHidden = Get-TestField -Title 'Department'
        $noHidden.PSObject.Properties.Remove('Hidden')
        { Convert-List -List (Get-TestList -Fields @($noHidden)) } | Should -Throw "*hidden state of the managed metadata column 'Department' could not be read*"
        { Convert-List -List (Get-TestList -Fields @((Get-TestField -Title 'Region' -TermSetId $null))) } | Should -Throw "*term set of the managed metadata column 'Region' could not be read*"
        { Convert-List -List (Get-TestList -Fields @((Get-TestField -TermSetId 'not-a-guid'))) } | Should -Throw
    }

    It 'lets a failing hidden-state or term-set getter propagate instead of reading it as visible or unbound' {
        $hiddenFails = [SPSTestTaxonomyField]::new()
        $hiddenFails.Title = 'Department'
        $hiddenFails.TypeAsString = 'TaxonomyFieldType'
        $hiddenFails.FailHidden = $true
        { Convert-List -List (Get-TestList -Fields @($hiddenFails)) } | Should -Throw '*hidden state unavailable*'

        $termSetFails = [SPSTestTaxonomyField]::new()
        $termSetFails.Title = 'Region'
        $termSetFails.TypeAsString = 'TaxonomyFieldTypeMulti'
        $termSetFails.FailTermSet = $true
        { Convert-List -List (Get-TestList -Fields @($termSetFails)) } | Should -Throw '*term set unavailable*'
    }

    It 'reads the term set ID of a real .NET field' {
        $field = [SPSTestTaxonomyField]::new()
        $field.Title = 'Department'
        $field.TypeAsString = 'TaxonomyFieldType'

        $record = Convert-List -List (Get-TestList -Fields @($field))

        $record.ManagedMetadataColumnCount | Should -Be 1
        $record.TermSetIds | Should -Match '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
    }

    It 'rejects a list whose title, URL or item count cannot be read' {
        $fields = @((Get-TestField))
        $noTitle = Get-TestList -Fields $fields
        $noTitle.Title = ''
        { Convert-List -List $noTitle } | Should -Throw '*list title could not be read*'
        $noUrl = Get-TestList -Fields $fields
        $noUrl.RootFolder = $null
        { Convert-List -List $noUrl } | Should -Throw "*URL of list 'Contracts' could not be read*"
        $noCount = Get-TestList -Fields $fields
        $noCount.PSObject.Properties.Remove('ItemCount')
        { Convert-List -List $noCount } | Should -Throw "*item count of list 'Contracts' could not be read*"

        $failingCount = [SPSTestCountingList]::new()
        $failingCount.Title = 'Contracts'
        $failingCount.RootFolder = [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/Contracts' }
        $failingCount.Fields = $fields
        { Convert-List -List $failingCount } | Should -Throw '*item count unavailable*'
    }

    It 'does not read the list identity when there is nothing to report' {
        $list = Get-TestList -Fields @((Get-TestField -Title 'Title' -Type 'Text'))
        $list.Title = ''
        $list.RootFolder = $null

        Convert-List -List $list | Should -BeNullOrEmpty
    }
}
