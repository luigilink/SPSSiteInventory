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
    private string title;
    public string Title { get { if (FailTitle) { throw new InvalidOperationException("title unavailable"); } return title; } set { title = value; } }
    public bool FailTitle { get; set; }
    private string internalName;
    public string InternalName { get { if (FailInternalName) { throw new InvalidOperationException("internal name unavailable"); } return internalName; } set { internalName = value; } }
    public bool FailInternalName { get; set; }
    public string TypeAsString { get; set; }
    public bool FailHidden { get; set; }
    public bool FailTermSet { get; set; }
    public bool Hidden { get { if (FailHidden) { throw new InvalidOperationException("hidden state unavailable"); } return false; } }
    public Guid TermSetId { get { if (FailTermSet) { throw new InvalidOperationException("term set unavailable"); } return Guid.NewGuid(); } }
}

public class SPSTestDescriptiveList
{
    public object Fields { get; set; }
    public string Title { get; set; }
    public object RootFolder { get; set; }
    public bool FailTemplate { get; set; }
    public bool FailType { get; set; }
    public bool FailDate { get; set; }
    public int ItemCount { get { return 5; } }
    public string BaseTemplate { get { if (FailTemplate) { throw new InvalidOperationException("template unavailable"); } return "DocumentLibrary"; } }
    public string BaseType { get { if (FailType) { throw new InvalidOperationException("type unavailable"); } return "GenericList"; } }
    public DateTime LastItemModifiedDate { get { if (FailDate) { throw new InvalidOperationException("date unavailable"); } return new DateTime(2026, 3, 4, 10, 20, 30); } }
}

public enum SPSTestListTemplateType
{
    GenericList = 100,
    DocumentLibrary = 101,
    NamedNewsfeed = 544
}

public class SPSTestHiddenList
{
    public object Fields { get; set; }
    public string Title { get; set; }
    public object RootFolder { get; set; }
    public bool FailHidden { get; set; }
    public int ItemCount { get { return 5; } }
    public string BaseTemplate { get { return "GenericList"; } }
    public string BaseType { get { return "GenericList"; } }
    public bool Hidden { get { if (FailHidden) { throw new InvalidOperationException("hidden state of the list unavailable"); } return false; } }
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
        param ([object[]]$Fields = @(), $Hidden = $null, $BaseTemplate = 'DocumentLibrary')
        $list = [PSCustomObject]@{
            Title = 'Contracts'
            RootFolder = [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/Contracts' }
            Fields = $Fields
            ItemCount = 42
            BaseTemplate = $BaseTemplate
            BaseType = 'DocumentLibrary'
            LastItemModifiedDate = [datetime]'2026-03-04T10:20:30'
        }
        if ($null -ne $Hidden) {
            $list | Add-Member -NotePropertyName Hidden -NotePropertyValue $Hidden
        }
        $list
    }

    function Get-TestDescriptiveList {
        $list = [SPSTestDescriptiveList]::new()
        $list.Title = 'Contracts'
        $list.RootFolder = [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/Contracts' }
        $list.Fields = @((Get-TestField))
        return $list
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

    It 'returns null for a hidden list, whatever its columns' {
        $list = Get-TestList -Fields @((Get-TestField -Title 'HashTags' -Type 'TaxonomyFieldTypeMulti')) -Hidden $true

        Convert-List -List $list | Should -BeNullOrEmpty
    }

    It 'returns null for the newsfeed list (template 544) even when it is not flagged as hidden' {
        foreach ($template in @(544, '544', [SPSTestListTemplateType]::NamedNewsfeed)) {
            $list = Get-TestList -Fields @((Get-TestField -Title 'HashTags' -Type 'TaxonomyFieldTypeMulti')) -BaseTemplate $template -Hidden $false

            Convert-List -List $list | Should -BeNullOrEmpty
        }
    }

    It 'still reports a list whose template is an enum value or a name that is not the newsfeed list' {
        foreach ($template in @([SPSTestListTemplateType]::DocumentLibrary, [SPSTestListTemplateType]::GenericList, 'DocumentLibrary', 101)) {
            $list = Get-TestList -Fields @((Get-TestField)) -BaseTemplate $template -Hidden $false

            (Convert-List -List $list).ListTitle | Should -Be 'Contracts'
        }
    }

    It 'still reports a visible list, flagged or not' {
        foreach ($hidden in @($null, $false)) {
            $list = Get-TestList -Fields @((Get-TestField)) -Hidden $hidden

            (Convert-List -List $list).ListTitle | Should -Be 'Contracts'
        }
    }

    It 'lets a failing hidden-state getter of the list propagate instead of reading it as visible' {
        $list = [SPSTestHiddenList]::new()
        $list.Title = 'Contracts'
        $list.RootFolder = [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/Contracts' }
        $list.Fields = @((Get-TestField))
        $list.FailHidden = $true

        { Convert-List -List $list } | Should -Throw '*hidden state of the list unavailable*'
    }

    It 'does not read the hidden state of a list that has no managed metadata column' {
        $list = [SPSTestHiddenList]::new()
        $list.Fields = @((Get-TestField -Type 'Text'))
        $list.FailHidden = $true

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

    It 'lets a failing title getter propagate instead of falling back to the internal name' {
        $field = [SPSTestTaxonomyField]::new()
        $field.Title = 'Department'
        $field.InternalName = 'Department'
        $field.TypeAsString = 'TaxonomyFieldType'
        $field.FailTitle = $true

        { Convert-List -List (Get-TestList -Fields @($field)) } | Should -Throw '*title unavailable*'
    }

    It 'lets a failing internal-name getter propagate when the title is blank' {
        $field = [SPSTestTaxonomyField]::new()
        $field.Title = ''
        $field.TypeAsString = 'TaxonomyFieldType'
        $field.FailInternalName = $true

        { Convert-List -List (Get-TestList -Fields @($field)) } | Should -Throw '*internal name unavailable*'
    }

    It 'reads the term set ID of a real .NET field' {
        $field = [SPSTestTaxonomyField]::new()
        $field.Title = 'Department'
        $field.TypeAsString = 'TaxonomyFieldType'

        $record = Convert-List -List (Get-TestList -Fields @($field))

        $record.ManagedMetadataColumnCount | Should -Be 1
        $record.TermSetIds | Should -Match '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
    }

    It 'reads the template, type and last-modified date of a real .NET list' {
        $record = Convert-List -List (Get-TestDescriptiveList)

        $record.ListTemplate | Should -Be 'DocumentLibrary'
        $record.ListType | Should -Be 'GenericList'
        $record.ItemLastModifiedDate | Should -Be '2026-03-04 10:20:30'
    }

    It 'lets a failing template, type or last-modified getter propagate instead of exporting an empty value' {
        foreach ($case in @(
                @{ Flag = 'FailTemplate'; Message = '*template unavailable*' }
                @{ Flag = 'FailType'; Message = '*type unavailable*' }
                @{ Flag = 'FailDate'; Message = '*date unavailable*' }
            )) {
            $list = Get-TestDescriptiveList
            $list.($case.Flag) = $true

            { Convert-List -List $list } | Should -Throw -ExpectedMessage $case.Message
        }
    }

    It 'rejects a missing list template or type instead of exporting an empty value' {
        $noTemplate = Get-TestList -Fields @((Get-TestField))
        $noTemplate.BaseTemplate = $null
        { Convert-List -List $noTemplate } | Should -Throw "*template of list 'Contracts' could not be read*"
        $noType = Get-TestList -Fields @((Get-TestField))
        $noType.BaseType = $null
        { Convert-List -List $noType } | Should -Throw "*type of list 'Contracts' could not be read*"
    }

    It 'normalizes a date given as text and rejects a value that is not a date' {
        $list = Get-TestList -Fields @((Get-TestField))
        $list.LastItemModifiedDate = '2026-03-04T10:20:30'

        (Convert-List -List $list).ItemLastModifiedDate | Should -Be '2026-03-04 10:20:30'

        $list.LastItemModifiedDate = 'yesterday'
        { Convert-List -List $list } | Should -Throw
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
