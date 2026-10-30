# Behavior tests for the modern-readiness signals of Get-SPSSiteCustomization: the alternate CSS URL of a web
# and the Script Editor and Content Editor web parts of its pages. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    # A web whose alternate CSS URL cannot be read. It is a real .NET type: PowerShell turns an exception of
    # a getter into $null, and also swallows those of script properties.
    if (-not ('SPSTestCssWeb' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Management.Automation;
public class SPSTestCssWeb
{
    public string Url { get; set; }
    public object ContentTypes { get; set; }
    public object Lists { get; set; }
    public object WorkflowAssociations { get; set; }
    public bool HasUniqueRoleAssignments { get; set; }
    public string CustomMasterUrl { get; set; }
    public object Features { get; set; }
    public object Files { get; set; }
    public bool IsRootWeb { get; set; }
    public bool HasUniqueRoleDefinitions { get; set; }
    public object RoleDefinitions { get; set; }
    public object Alerts { get; set; }
    public object RootFolder { get; set; }
    public string AlternateCssUrl { get { throw new InvalidOperationException("css unavailable"); } }
    public void Dispose() { }
}
'@
    }

    # A file whose existence cannot be told, and an item whose file cannot be read, for the same reason.
    if (-not ('SPSTestUnknownPage' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
public class SPSTestUnknownPage
{
    public string ServerRelativeUrl { get; set; }
    public bool Exists { get { throw new InvalidOperationException("existence unavailable"); } }
}

public class SPSTestItemWithoutFile
{
    public object File { get { throw new InvalidOperationException("file unavailable"); } }
}
'@
    }

    # A feature collection that gives its first feature and fails on the next one: a read that stops at the first
    # feature it looks for (the publishing one) succeeds, and one that goes on fails.
    if (-not ('SPSTestFeaturesThenFail' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections;
public sealed class SPSTestFeaturesThenFail : IEnumerable
{
    private readonly object first;
    public SPSTestFeaturesThenFail(object first) { this.first = first; }
    public IEnumerator GetEnumerator()
    {
        yield return first;
        throw new InvalidOperationException("features unavailable");
    }
}
'@
    }

    # A view whose style sheet cannot be read, for the same reason.
    if (-not ('SPSTestXsltBrokenView' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
public class SPSTestXsltBrokenView
{
    public string Title { get { return "Odd"; } }
    public bool PersonalView { get { return false; } }
    public string XslLink { get { throw new InvalidOperationException("link unavailable"); } }
    public string Xsl { get { return ""; } }
}
'@
    }

    # A view whose hidden flag cannot be read, for the same reason.
    if (-not ('SPSTestXsltHiddenBrokenView' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
public class SPSTestXsltHiddenBrokenView
{
    public string Title { get { return "Odd"; } }
    public bool PersonalView { get { return false; } }
    public bool Hidden { get { throw new InvalidOperationException("hidden unavailable"); } }
    public string XslLink { get { return "/sites/team/Style Library/odd.xsl"; } }
    public string Xsl { get { return ""; } }
}
'@
    }

    # A list whose experience setting cannot be read, for the same reason.
    if (-not ('SPSTestExperienceList' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
public class SPSTestExperienceList
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
    public bool Hidden { get; set; }
    public object ListExperienceOptions { get { throw new InvalidOperationException("experience unavailable"); } }
}
'@
    }

    function global:Get-SPAppInstance {
        param($Web)
        @()
    }

    function New-TestWebPart {
        param ([string]$TypeName, $Content = $null, $ContentLink = $null)
        $webPart = [PSCustomObject]@{ Title = 'Part'; Content = $Content; ContentLink = $ContentLink }
        $webPart.PSObject.TypeNames.Insert(0, $TypeName)
        return $webPart
    }

    function New-TestScriptEditor { New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.ScriptEditorWebPart' -Content '<script>run();</script>' }
    function New-TestContentEditor { param ($Content = '<script src="/SiteAssets/app.js"></script>') New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.ContentEditorWebPart' -Content $Content }
    function New-TestListViewPart { New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.XsltListViewWebPart' }

    # A page that records how often its web parts are read.
    function New-TestPage {
        param ([string]$Url, [object[]]$WebParts = @(), [switch]$Unreadable, [bool]$Exists = $true)
        $page = [PSCustomObject]@{ ServerRelativeUrl = $Url; Exists = $Exists; WebParts = $WebParts; Unreadable = [bool]$Unreadable; Reads = 0 }
        $page | Add-Member -MemberType ScriptMethod -Name GetLimitedWebPartManager -Value {
            param ($Scope)
            $this.Reads++
            if ($this.Unreadable) { throw 'The page could not be opened.' }
            return [PSCustomObject]@{ WebParts = $this.WebParts }
        }
        return $page
    }

    function New-TestLibrary {
        param ([string]$Title = 'Site Pages', [int]$BaseTemplate = 119, [object[]]$Batches = @(), [switch]$Throttled)
        $library = [PSCustomObject]@{
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
            BaseTemplate = $BaseTemplate
            Fields = @()
            HasExternalDataSource = $false
            Batches = $Batches
            BatchIndex = 0
            Throttled = [bool]$Throttled
            Queries = [System.Collections.Generic.List[object]]::new()
        }
        $library | Add-Member -MemberType ScriptMethod -Name GetItems -Value {
            param ($Query)
            # Only the query for the pages is answered; the other scans of a library find nothing.
            if (-not ($Query.PSObject.Properties['Query'] -and [string]$Query.Query -match 'File_x0020_Type' -and [string]$Query.Query -match 'aspx')) {
                return [PSCustomObject]@{ Items = @(); ListItemCollectionPosition = $null }
            }
            $this.Queries.Add($Query)
            if ($this.Throttled) { throw 'The query exceeds the list view threshold.' }
            $batch = $this.Batches[$this.BatchIndex]
            $this.BatchIndex++
            return [PSCustomObject]@{ Items = @($batch.Items); ListItemCollectionPosition = $batch.Position }
        }
        return $library
    }

    function New-TestView {
        param ([string]$Title = 'All Items', $XslLink = 'main.xsl', $Xsl = '', [bool]$PersonalView = $false, [bool]$Hidden = $false)
        [PSCustomObject]@{ Title = $Title; XslLink = $XslLink; Xsl = $Xsl; PersonalView = $PersonalView; Hidden = $Hidden }
    }

    # A plain list. -Experience adds the ListExperienceOptions property, which an older farm does not have.
    function New-TestList {
        param ([string]$Title = 'Tasks', [object[]]$Views = @(), [bool]$Hidden = $false, $Experience = $null, [switch]$WithExperience)
        $list = [PSCustomObject]@{
            Title = $Title
            RootFolder = [PSCustomObject]@{ ServerRelativeUrl = "/sites/team/Lists/$Title"; Properties = @{} }
            ContentTypes = @()
            WorkflowAssociations = @()
            EventReceivers = @()
            IrmEnabled = $false
            ItemCount = 0
            Views = $Views
            CheckedOutFiles = @()
            EnableVersioning = $false
            Items = @()
            BaseTemplate = 100
            Fields = @()
            HasExternalDataSource = $false
            Hidden = $Hidden
        }
        if ($WithExperience) {
            $list | Add-Member -MemberType NoteProperty -Name ListExperienceOptions -Value $Experience
        }
        return $list
    }

    function New-TestPageBatch {
        param ([object[]]$Pages, $Position = $null)
        [PSCustomObject]@{ Items = @($Pages | ForEach-Object { [PSCustomObject]@{ File = $_ } }); Position = $Position }
    }

    function New-TestWeb {
        param (
            [string]$Url = 'https://intranet.contoso.com/sites/team',
            [object[]]$Lists = @(),
            [string]$AlternateCssUrl = '',
            [string]$WelcomePage = '',
            [object[]]$Pages = @(),
            [object[]]$Features = @()
        )
        $web = [PSCustomObject]@{
            Url = $Url
            ContentTypes = @()
            Lists = $Lists
            WorkflowAssociations = @()
            HasUniqueRoleAssignments = $false
            CustomMasterUrl = ''
            Features = $Features
            Files = @()
            IsRootWeb = $true
            HasUniqueRoleDefinitions = $true
            RoleDefinitions = @()
            Alerts = @()
            AlternateCssUrl = $AlternateCssUrl
            RootFolder = [PSCustomObject]@{ WelcomePage = $WelcomePage }
            PageFiles = $Pages
        }
        $web | Add-Member -MemberType ScriptMethod -Name GetFile -Value {
            param ($Url)
            return @($this.PageFiles | Where-Object { $_.ServerRelativeUrl -like "*$Url" })[0]
        }
        $web | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        return $web
    }

    function New-TestSite {
        param ([object[]]$Webs, [object[]]$Features = @())
        [PSCustomObject]@{ Url = 'https://intranet.contoso.com/sites/team'; Features = $Features; Solutions = @(); AllWebs = $Webs }
    }

    function Get-Signal {
        param ($Site, [hashtable]$Threshold = @{})
        $warnings = @()
        $signals = Get-SPSSiteCustomization -Site $Site -LargeContentThresholds $Threshold -WarningVariable warnings -WarningAction SilentlyContinue
        [PSCustomObject]@{ Signals = $signals; Warnings = @($warnings | ForEach-Object { [string]$_ }) }
    }

    $script:PublishingWebFeature = [PSCustomObject]@{ DefinitionId = [guid]'94c94ca6-b32f-4da9-a9e3-1f3d343d7ecb' }
    # The features that opt a site collection and a web out of the modern list and library experience.
    $script:OptOutSiteFeature = [PSCustomObject]@{ DefinitionId = [guid]'E3540C7D-6BEA-403C-A224-1A12EAFEE4C4' }
    $script:OptOutWebFeature = [PSCustomObject]@{ DefinitionId = [guid]'52E14B6F-B1BB-4969-B89B-C4FAA56745EF' }
}

Describe 'Get-SPSSiteCustomization alternate CSS URL' {
    It 'counts the webs that set an alternate CSS URL and lists them' {
        $plain = New-TestWeb -Url 'https://intranet.contoso.com/sites/team'
        $branded = New-TestWeb -Url 'https://intranet.contoso.com/sites/team/news' -AlternateCssUrl '/sites/team/Style Library/brand.css'
        $also = New-TestWeb -Url 'https://intranet.contoso.com/sites/team/hr' -AlternateCssUrl '  /Style Library/hr.css  '

        $result = Get-Signal -Site (New-TestSite -Webs @($plain, $branded, $also))

        $result.Signals.AlternateCssUrlCount | Should -Be 2
        $result.Signals.AlternateCssUrlExamples | Should -Be 'https://intranet.contoso.com/sites/team/news (/sites/team/Style Library/brand.css); https://intranet.contoso.com/sites/team/hr (/Style Library/hr.css)'
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
    }

    It 'reports nothing for webs without an alternate CSS URL' {
        $web = New-TestWeb -AlternateCssUrl '   '

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.AlternateCssUrlCount | Should -Be 0
        $result.Signals.AlternateCssUrlExamples | Should -Be ''
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'lists at most five examples and still counts every web' {
        $webs = 1..7 | ForEach-Object { New-TestWeb -Url "https://intranet.contoso.com/sites/team/w$_" -AlternateCssUrl "/Style Library/w$_.css" }

        $result = Get-Signal -Site (New-TestSite -Webs $webs)

        $result.Signals.AlternateCssUrlCount | Should -Be 7
        @($result.Signals.AlternateCssUrlExamples -split '; ') | Should -HaveCount 5
    }

    It 'marks the collection partial, with a warning, when the setting cannot be read, instead of taking the web for one without' {
        $web = [SPSTestCssWeb]::new()
        $web.Url = 'https://intranet.contoso.com/sites/team'
        $web.ContentTypes = @()
        $web.Lists = @()
        $web.WorkflowAssociations = @()
        $web.CustomMasterUrl = ''
        $web.Features = @()
        $web.Files = @()
        $web.IsRootWeb = $true
        $web.HasUniqueRoleDefinitions = $true
        $web.RoleDefinitions = @()
        $web.Alerts = @()
        $web.RootFolder = [PSCustomObject]@{ WelcomePage = '' }

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.AlternateCssUrlCount | Should -Be 0
        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "Could not read the alternate CSS URL on web 'https://intranet.contoso.com/sites/team': css unavailable"
    }
}

Describe 'Get-SPSSiteCustomization script web parts' {
    It 'reads the home page of each web' {
        $homePage = New-TestPage -Url '/sites/team/SitePages/Home.aspx' -WebParts @((New-TestListViewPart), (New-TestScriptEditor))
        $web = New-TestWeb -WelcomePage 'SitePages/Home.aspx' -Pages @($homePage)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.ScriptWebPartCount | Should -Be 1
        $result.Signals.ScriptWebPartExamples | Should -Be '/sites/team/SitePages/Home.aspx (Script Editor)'
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
    }

    It 'counts a Content Editor web part only when it carries script' {
        $homePage = New-TestPage -Url '/sites/team/default.aspx' -WebParts @(
            (New-TestContentEditor)
            (New-TestContentEditor -Content '<p>Welcome</p>')
        )
        $web = New-TestWeb -WelcomePage 'default.aspx' -Pages @($homePage)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.ScriptWebPartCount | Should -Be 1
        $result.Signals.ScriptWebPartExamples | Should -Be '/sites/team/default.aspx (Content Editor)'
    }

    It 'does not read a home page that does not exist' {
        $missing = New-TestPage -Url '/sites/team/SitePages/Gone.aspx' -Exists $false -WebParts @((New-TestScriptEditor))
        $web = New-TestWeb -WelcomePage 'SitePages/Gone.aspx' -Pages @($missing)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.ScriptWebPartCount | Should -Be 0
        $missing.Reads | Should -Be 0
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'marks the collection partial, instead of leaving the home page out, when its existence cannot be told' {
        $unknown = [SPSTestUnknownPage]::new()
        $unknown.ServerRelativeUrl = '/sites/team/SitePages/Home.aspx'
        $web = New-TestWeb -WelcomePage 'SitePages/Home.aspx' -Pages @($unknown)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "Could not read the home page of web 'https://intranet.contoso.com/sites/team': .*existence unavailable"
    }

    It 'reads the pages of a Pages library of a web whose publishing feature is not active' {
        $page = New-TestPage -Url '/sites/team/Pages/Welcome.aspx' -WebParts @((New-TestScriptEditor))
        $pages = New-TestLibrary -Title 'Pages' -BaseTemplate 850 -Batches @((New-TestPageBatch -Pages @($page)))
        $web = New-TestWeb -Lists @($pages)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $pages.Queries | Should -HaveCount 1
        $result.Signals.ScriptWebPartCount | Should -Be 1
        $result.Signals.PublishingWebCount | Should -Be 0
    }

    It 'marks the collection partial, instead of leaving the page out, when the file of an item cannot be read' {
        $library = New-TestLibrary -Batches @([PSCustomObject]@{ Items = @([SPSTestItemWithoutFile]::new()); Position = $null })
        $web = New-TestWeb -Lists @($library)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "Could not list the pages of 'Site Pages' in web 'https://intranet.contoso.com/sites/team': .*file unavailable"
    }

    It 'marks the collection partial when an item has no file, or a file without an address' -ForEach @(
        @{ Name = 'no file'; File = $null; Message = 'file of a page is unavailable' }
        @{ Name = 'no address'; File = [PSCustomObject]@{ ServerRelativeUrl = ''; Name = '' }; Message = 'address of a page could not be read' }
    ) {
        $library = New-TestLibrary -Batches @([PSCustomObject]@{ Items = @([PSCustomObject]@{ File = $File }); Position = $null })
        $web = New-TestWeb -Lists @($library)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.CustomizationInventoryComplete | Should -BeFalse -Because $Name
        ($result.Warnings -join ';') | Should -Match $Message
    }

    It 'reads the pages of the Site Pages library and of a publishing Pages library' {
        $wiki = New-TestPage -Url '/sites/team/SitePages/Wiki.aspx' -WebParts @((New-TestContentEditor))
        $plain = New-TestPage -Url '/sites/team/SitePages/Plain.aspx' -WebParts @((New-TestListViewPart))
        $publishing = New-TestPage -Url '/sites/team/Pages/Welcome.aspx' -WebParts @((New-TestScriptEditor), (New-TestScriptEditor))
        $sitePages = New-TestLibrary -Title 'SitePages' -BaseTemplate 119 -Batches @((New-TestPageBatch -Pages @($wiki, $plain)))
        $pages = New-TestLibrary -Title 'Pages' -BaseTemplate 850 -Batches @((New-TestPageBatch -Pages @($publishing)))
        $web = New-TestWeb -Lists @($sitePages, $pages) -Features @($script:PublishingWebFeature)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.ScriptWebPartCount | Should -Be 3
        $result.Signals.ScriptWebPartExamples | Should -Be '/sites/team/SitePages/Wiki.aspx (Content Editor); /sites/team/Pages/Welcome.aspx (Script Editor); /sites/team/Pages/Welcome.aspx (Script Editor)'
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'reads the pages with a query for the .aspx files, in pages of 200, that passes the list view threshold' {
        $library = New-TestLibrary -Batches @((New-TestPageBatch -Pages @()))
        $web = New-TestWeb -Lists @($library)

        $null = Get-Signal -Site (New-TestSite -Webs @($web))

        $library.Queries | Should -HaveCount 1
        $library.Queries[0].RowLimit | Should -Be 200
        $library.Queries[0].Query | Should -Match 'FSObjType'
        $library.Queries[0].Query | Should -Match '<Value Type="Text">aspx</Value>'
        $library.Queries[0].ViewFields | Should -Match 'FileRef'
        $library.Queries[0].QueryThrottleMode | Should -Be 'Override'
    }

    It 'reads a page that is the home page and is in the Site Pages library once' {
        $homePage = New-TestPage -Url '/sites/team/SitePages/Home.aspx' -WebParts @((New-TestScriptEditor))
        $library = New-TestLibrary -Batches @((New-TestPageBatch -Pages @($homePage)))
        $web = New-TestWeb -Lists @($library) -WelcomePage 'SitePages/Home.aspx' -Pages @($homePage)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $homePage.Reads | Should -Be 1
        $result.Signals.ScriptWebPartCount | Should -Be 1
    }

    It 'does not read the pages of any other library' {
        $library = New-TestLibrary -Title 'Documents' -BaseTemplate 101 -Batches @((New-TestPageBatch -Pages @()))
        $web = New-TestWeb -Lists @($library)

        $null = Get-Signal -Site (New-TestSite -Webs @($web))

        $library.Queries | Should -HaveCount 0
    }

    It 'follows the pages of a library from one batch to the next' {
        $first = New-TestPage -Url '/sites/team/SitePages/A.aspx' -WebParts @((New-TestScriptEditor))
        $second = New-TestPage -Url '/sites/team/SitePages/B.aspx' -WebParts @((New-TestScriptEditor))
        $library = New-TestLibrary -Batches @(
            (New-TestPageBatch -Pages @($first) -Position 'next')
            (New-TestPageBatch -Pages @($second))
        )
        $web = New-TestWeb -Lists @($library)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $library.Queries | Should -HaveCount 2
        $result.Signals.ScriptWebPartCount | Should -Be 2
    }

    It 'stops at the cap of each library, marks the collection partial and names the setting' {
        $pages = 1..3 | ForEach-Object { New-TestPage -Url "/sites/team/SitePages/P$_.aspx" -WebParts @((New-TestScriptEditor)) }
        $library = New-TestLibrary -Batches @((New-TestPageBatch -Pages $pages))
        $web = New-TestWeb -Lists @($library)

        $result = Get-Signal -Site (New-TestSite -Webs @($web)) -Threshold @{ MaxItemsForWebPartScanPerLibrary = 2 }

        $result.Signals.ScriptWebPartCount | Should -Be 2
        $pages[2].Reads | Should -Be 0
        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match 'MaxItemsForWebPartScanPerLibrary'
    }

    It 'marks the collection partial when the cap is reached with more pages to come' {
        $pages = 1..2 | ForEach-Object { New-TestPage -Url "/sites/team/SitePages/P$_.aspx" }
        $library = New-TestLibrary -Batches @((New-TestPageBatch -Pages $pages -Position 'next'))
        $web = New-TestWeb -Lists @($library)

        $result = Get-Signal -Site (New-TestSite -Webs @($web)) -Threshold @{ MaxItemsForWebPartScanPerLibrary = 2 }

        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        $library.Queries | Should -HaveCount 1
    }

    It 'reads 200 pages of each library by default' {
        $pages = 1..201 | ForEach-Object { New-TestPage -Url "/sites/team/SitePages/P$_.aspx" }
        $library = New-TestLibrary -Batches @((New-TestPageBatch -Pages $pages))
        $web = New-TestWeb -Lists @($library)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $pages[199].Reads | Should -Be 1
        $pages[200].Reads | Should -Be 0
        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
    }

    It 'marks the collection partial, names the page and still reads the others, when a page cannot be read' {
        $broken = New-TestPage -Url '/sites/team/SitePages/Broken.aspx' -Unreadable
        $good = New-TestPage -Url '/sites/team/SitePages/Good.aspx' -WebParts @((New-TestScriptEditor))
        $library = New-TestLibrary -Batches @((New-TestPageBatch -Pages @($broken, $good)))
        $web = New-TestWeb -Lists @($library)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.ScriptWebPartCount | Should -Be 1
        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "Could not read the web parts of page '/sites/team/SitePages/Broken.aspx' in web 'https://intranet.contoso.com/sites/team': .*The page could not be opened\."
    }

    It 'warns for the first five pages that cannot be read, then once for the rest' {
        $pages = 1..8 | ForEach-Object { New-TestPage -Url "/sites/team/SitePages/P$_.aspx" -Unreadable }
        $library = New-TestLibrary -Batches @((New-TestPageBatch -Pages $pages))
        $web = New-TestWeb -Lists @($library)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        @($result.Warnings | Where-Object { $_ -like 'Could not read the web parts of page*' }) | Should -HaveCount 5
        @($result.Warnings | Where-Object { $_ -like '3 more page(s) could not be read*' }) | Should -HaveCount 1
        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
    }

    It 'marks the collection partial when the pages of a library cannot be listed' {
        $library = New-TestLibrary -Throttled
        $web = New-TestWeb -Lists @($library)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "Could not list the pages of 'Site Pages' in web 'https://intranet.contoso.com/sites/team': .*list view threshold"
    }

    It 'marks the collection partial when the home page cannot be looked up' {
        $web = New-TestWeb
        $web.RootFolder = $null

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "Could not read the home page of web 'https://intranet.contoso.com/sites/team'"
    }

    It 'adds up the web parts of every web of the site collection' {
        $homeOne = New-TestPage -Url '/sites/team/default.aspx' -WebParts @((New-TestScriptEditor))
        $homeTwo = New-TestPage -Url '/sites/team/news/default.aspx' -WebParts @((New-TestContentEditor))
        $one = New-TestWeb -Url 'https://intranet.contoso.com/sites/team' -WelcomePage 'default.aspx' -Pages @($homeOne)
        $two = New-TestWeb -Url 'https://intranet.contoso.com/sites/team/news' -WelcomePage 'default.aspx' -Pages @($homeTwo)

        $result = Get-Signal -Site (New-TestSite -Webs @($one, $two))

        $result.Signals.ScriptWebPartCount | Should -Be 2
    }

    It 'lists at most five examples and still counts every web part' {
        $homePage = New-TestPage -Url '/sites/team/default.aspx' -WebParts @(1..7 | ForEach-Object { New-TestScriptEditor })
        $web = New-TestWeb -WelcomePage 'default.aspx' -Pages @($homePage)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.ScriptWebPartCount | Should -Be 7
        @($result.Signals.ScriptWebPartExamples -split '; ') | Should -HaveCount 5
    }
}

Describe 'Get-SPSSiteCustomization XSLT list views' {
    It 'counts the views whose style sheet is not the default one and lists them' {
        $tasks = New-TestList -Title 'Tasks' -Views @(
            (New-TestView -Title 'All Tasks')
            (New-TestView -Title 'Late' -XslLink '/sites/team/Style Library/late.xsl')
        )
        $contacts = New-TestList -Title 'Contacts' -Views @((New-TestView -Title 'By company' -Xsl '<xsl:stylesheet version="1.0" />'))
        $web = New-TestWeb -Lists @($tasks, $contacts)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.XsltListViewCount | Should -Be 2
        $result.Signals.XsltListViewExamples | Should -Be 'Tasks/Late; Contacts/By company'
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
    }

    It 'does not count a view that uses the default style sheet' {
        $web = New-TestWeb -Lists @((New-TestList -Views @((New-TestView), (New-TestView -Title 'Calendar' -XslLink $null))))

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.XsltListViewCount | Should -Be 0
        $result.Signals.XsltListViewExamples | Should -Be ''
    }

    It 'does not count the personal views of a user' {
        $web = New-TestWeb -Lists @((New-TestList -Views @((New-TestView -Title 'Mine' -XslLink '/Style Library/custom.xsl' -PersonalView $true))))

        (Get-Signal -Site (New-TestSite -Webs @($web))).Signals.XsltListViewCount | Should -Be 0
    }

    It 'does not count a hidden view, in which a web part keeps its settings, and counts the visible one next to it' {
        $views = @(
            (New-TestView -Title '' -XslLink '/Style Library/web-part.xsl' -Hidden $true)
            (New-TestView -Title '' -Xsl '<xsl:stylesheet version="1.0" />' -Hidden $true)
            (New-TestView -Title 'Late' -XslLink '/Style Library/late.xsl')
        )
        $web = New-TestWeb -Lists @((New-TestList -Title 'Tasks' -Views $views))

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.XsltListViewCount | Should -Be 1
        $result.Signals.XsltListViewExamples | Should -Be 'Tasks/Late'
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
    }

    It 'does not count the views that SharePoint draws with its own style sheets, those of a blog or an asset library for example' {
        $blogViews = 1..12 | ForEach-Object { New-TestView -Title '' -XslLink 'blog.xsl' -Hidden $true }
        $posts = New-TestList -Title 'Posts' -Views $blogViews
        $images = New-TestList -Title 'Images' -Views @(
            (New-TestView -Title 'Thumbnails' -XslLink 'AssetPicker.xsl')
            (New-TestView -Title 'All Images' -XslLink '/_layouts/15/xsl/main.xsl')
        )
        $web = New-TestWeb -Lists @($posts, $images)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.XsltListViewCount | Should -Be 0
        $result.Signals.XsltListViewExamples | Should -Be ''
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'marks the collection partial, names the list and goes on with the others, when the hidden flag of a view cannot be read' {
        $broken = New-TestList -Title 'Broken' -Views @([SPSTestXsltHiddenBrokenView]::new())
        $good = New-TestList -Title 'Good' -Views @((New-TestView -XslLink '/Style Library/a.xsl'))
        $web = New-TestWeb -Lists @($broken, $good)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.XsltListViewCount | Should -Be 1
        $result.Signals.XsltListViewExamples | Should -Be 'Good/All Items'
        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "Could not read the XSLT of the views on list 'Broken' in web 'https://intranet.contoso.com/sites/team': hidden unavailable"
    }

    It 'does not look at the views of a hidden list' {
        $web = New-TestWeb -Lists @((New-TestList -Title 'Workflow History' -Hidden $true -Views @((New-TestView -XslLink '/Style Library/custom.xsl'))))

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.XsltListViewCount | Should -Be 0
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'adds up the views of every list and every web' {
        $one = New-TestWeb -Url 'https://intranet.contoso.com/sites/team' -Lists @((New-TestList -Views @((New-TestView -XslLink '/Style Library/a.xsl'))))
        $two = New-TestWeb -Url 'https://intranet.contoso.com/sites/team/news' -Lists @((New-TestList -Title 'Links' -Views @((New-TestView -XslLink '/Style Library/b.xsl'), (New-TestView -XslLink '/Style Library/c.xsl'))))

        (Get-Signal -Site (New-TestSite -Webs @($one, $two))).Signals.XsltListViewCount | Should -Be 3
    }

    It 'lists at most five examples and still counts every view' {
        $views = 1..7 | ForEach-Object { New-TestView -Title "V$_" -XslLink "/Style Library/v$_.xsl" }
        $web = New-TestWeb -Lists @((New-TestList -Views $views))

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.XsltListViewCount | Should -Be 7
        @($result.Signals.XsltListViewExamples -split '; ') | Should -HaveCount 5
    }

    It 'marks the collection partial, names the list and goes on with the others, when the XSLT of a view cannot be read' {
        $broken = New-TestList -Title 'Broken' -Views @([SPSTestXsltBrokenView]::new())
        $good = New-TestList -Title 'Good' -Views @((New-TestView -XslLink '/Style Library/a.xsl'))
        $web = New-TestWeb -Lists @($broken, $good)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.XsltListViewCount | Should -Be 1
        $result.Signals.XsltListViewExamples | Should -Be 'Good/All Items'
        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "Could not read the XSLT of the views on list 'Broken' in web 'https://intranet.contoso.com/sites/team': link unavailable"
    }

    It 'marks the collection partial when the views of a list are unavailable' {
        $list = New-TestList -Title 'NoViews'
        $list.Views = $null
        $web = New-TestWeb -Lists @($list)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "Could not read the XSLT of the views on list 'NoViews' in web 'https://intranet.contoso.com/sites/team'"
    }
}

Describe 'Get-SPSSiteCustomization lists forced to the classic experience' {
    It 'counts the lists forced to classic and lists them' -ForEach @(
        @{ Experience = 'ClassicExperience' }
        @{ Experience = 2 }
        @{ Experience = '2' }
    ) {
        $forced = New-TestList -Title 'Contracts' -WithExperience -Experience $Experience
        $auto = New-TestList -Title 'Tasks' -WithExperience -Experience 'Auto'
        $web = New-TestWeb -Lists @($forced, $auto)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.ClassicExperienceListCount | Should -Be 1
        $result.Signals.ClassicExperienceListExamples | Should -Be 'Contracts (/sites/team/Lists/Contracts)'
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'does not count a list that follows the default or is forced to the modern experience' -ForEach @(
        @{ Experience = 'Auto' }
        @{ Experience = 0 }
        @{ Experience = 'NewExperience' }
        @{ Experience = 1 }
        @{ Experience = $null }
    ) {
        $web = New-TestWeb -Lists @((New-TestList -WithExperience -Experience $Experience))

        (Get-Signal -Site (New-TestSite -Webs @($web))).Signals.ClassicExperienceListCount | Should -Be 0
    }

    It 'does not mark the collection partial on a farm whose lists have no such setting' {
        $web = New-TestWeb -Lists @((New-TestList))

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.ClassicExperienceListCount | Should -Be 0
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
    }

    It 'does not count a hidden list' {
        $web = New-TestWeb -Lists @((New-TestList -Hidden $true -WithExperience -Experience 'ClassicExperience'))

        (Get-Signal -Site (New-TestSite -Webs @($web))).Signals.ClassicExperienceListCount | Should -Be 0
    }

    It 'lists at most five examples and still counts every list' {
        $lists = 1..7 | ForEach-Object { New-TestList -Title "L$_" -WithExperience -Experience 'ClassicExperience' }
        $web = New-TestWeb -Lists $lists

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.ClassicExperienceListCount | Should -Be 7
        @($result.Signals.ClassicExperienceListExamples -split '; ') | Should -HaveCount 5
    }

    It 'marks the collection partial, with a warning, when the setting cannot be read, instead of taking the list for one that is not forced' {
        $list = [SPSTestExperienceList]::new()
        $list.Title = 'Broken'
        $list.RootFolder = [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/Lists/Broken'; Properties = @{} }
        $list.ContentTypes = @()
        $list.WorkflowAssociations = @()
        $list.EventReceivers = @()
        $list.IrmEnabled = $false
        $list.ItemCount = 0
        $list.Views = @()
        $list.CheckedOutFiles = @()
        $list.EnableVersioning = $false
        $list.Items = @()
        $list.BaseTemplate = 100
        $list.Fields = @()
        $web = New-TestWeb -Lists @($list)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.ClassicExperienceListCount | Should -Be 0
        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "Could not read the list experience on list 'Broken' in web 'https://intranet.contoso.com/sites/team': experience unavailable"
    }
}

Describe 'Get-SPSSiteCustomization opt-out of the modern list and library experience' {
    It 'counts the site collection that opted out' {
        $site = New-TestSite -Webs @((New-TestWeb)) -Features @($script:OptOutSiteFeature)

        $result = Get-Signal -Site $site

        $result.Signals.ClassicExperienceOptOutCount | Should -Be 1
        $result.Signals.ClassicExperienceOptOutExamples | Should -Be 'https://intranet.contoso.com/sites/team (site collection)'
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
    }

    It 'counts each web that opted out and lists it' {
        $one = New-TestWeb -Url 'https://intranet.contoso.com/sites/team' -Features @($script:OptOutWebFeature)
        $two = New-TestWeb -Url 'https://intranet.contoso.com/sites/team/news'
        $three = New-TestWeb -Url 'https://intranet.contoso.com/sites/team/hr' -Features @($script:OptOutWebFeature)

        $result = Get-Signal -Site (New-TestSite -Webs @($one, $two, $three))

        $result.Signals.ClassicExperienceOptOutCount | Should -Be 2
        $result.Signals.ClassicExperienceOptOutExamples | Should -Be 'https://intranet.contoso.com/sites/team (web); https://intranet.contoso.com/sites/team/hr (web)'
    }

    It 'counts the site collection and its webs together, the site collection first' {
        $web = New-TestWeb -Features @($script:OptOutWebFeature)
        $site = New-TestSite -Webs @($web) -Features @($script:OptOutSiteFeature)

        $result = Get-Signal -Site $site

        $result.Signals.ClassicExperienceOptOutCount | Should -Be 2
        $result.Signals.ClassicExperienceOptOutExamples | Should -Be 'https://intranet.contoso.com/sites/team (site collection); https://intranet.contoso.com/sites/team (web)'
    }

    It 'does not take the feature of the other scope, nor another feature, for an opt-out' {
        $web = New-TestWeb -Features @($script:OptOutSiteFeature, $script:PublishingWebFeature)
        $site = New-TestSite -Webs @($web) -Features @($script:OptOutWebFeature)

        (Get-Signal -Site $site).Signals.ClassicExperienceOptOutCount | Should -Be 0
    }

    It 'lists at most five examples and still counts every web' {
        $webs = 1..7 | ForEach-Object { New-TestWeb -Url "https://intranet.contoso.com/sites/team/w$_" -Features @($script:OptOutWebFeature) }

        $result = Get-Signal -Site (New-TestSite -Webs $webs)

        $result.Signals.ClassicExperienceOptOutCount | Should -Be 7
        @($result.Signals.ClassicExperienceOptOutExamples -split '; ') | Should -HaveCount 5
    }

    It 'marks the collection partial, with a warning, when the features of the site collection cannot be read' {
        $site = New-TestSite -Webs @((New-TestWeb))
        $site.Features = $null

        $result = Get-Signal -Site $site

        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "Could not read the modern experience opt-out feature for site collection 'https://intranet.contoso.com/sites/team'"
    }

    It 'marks the collection partial because of the opt-out alone, when the features fail after the publishing one' {
        $site = New-TestSite -Webs @((New-TestWeb))
        $site.Features = [SPSTestFeaturesThenFail]::new([PSCustomObject]@{ DefinitionId = [guid]'f6924d36-2fa8-4f0b-b16d-06b7250180fa' })

        $result = Get-Signal -Site $site

        $result.Signals.PublishingInfrastructureEnabled | Should -BeTrue
        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "Could not read the modern experience opt-out feature for site collection 'https://intranet.contoso.com/sites/team': .*features unavailable"
    }

    It 'marks the collection partial, with a warning, when the features of a web cannot be read' {
        $web = New-TestWeb
        $web.Features = $null

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "Could not read the modern experience opt-out feature on 'https://intranet.contoso.com/sites/team'"
    }

    It 'marks the collection partial because of the opt-out alone, when the features of a web fail after the publishing one' {
        $web = New-TestWeb
        $web.Features = [SPSTestFeaturesThenFail]::new($script:PublishingWebFeature)

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.PublishingWebCount | Should -Be 1
        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "Could not read the modern experience opt-out feature on 'https://intranet.contoso.com/sites/team': .*features unavailable"
    }
}

Describe 'Get-SPSSiteCustomization modern blockers' {
    It 'reports no blocker for a site collection that has none' {
        $web = New-TestWeb -Lists @((New-TestList -Views @((New-TestView))))

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.ModernBlockerCount | Should -Be 0
        $result.Signals.ModernBlockers | Should -Be ''
    }

    It 'brings together the blockers that were found' {
        $homePage = New-TestPage -Url '/sites/team/default.aspx' -WebParts @((New-TestScriptEditor))
        $tasks = New-TestList -Views @((New-TestView -XslLink '/Style Library/custom.xsl'), (New-TestView -Title 'Late' -XslLink '/Style Library/late.xsl'))
        $forced = New-TestList -Title 'Contracts' -WithExperience -Experience 'ClassicExperience'
        $web = New-TestWeb -Lists @($tasks, $forced) -AlternateCssUrl '/Style Library/brand.css' -WelcomePage 'default.aspx' -Pages @($homePage) -Features @($script:PublishingWebFeature, $script:OptOutWebFeature)
        $web.CustomMasterUrl = '/_catalogs/masterpage/brand.master'

        $result = Get-Signal -Site (New-TestSite -Webs @($web))

        $result.Signals.ModernBlockerCount | Should -Be 7
        $result.Signals.ModernBlockers | Should -Be 'Custom master page; Alternate CSS URL (1 web); Publishing features (1 web); XSLT list views (2); Script web parts (1); Opted out of modern lists (1); Lists forced to classic (1)'
    }
}
