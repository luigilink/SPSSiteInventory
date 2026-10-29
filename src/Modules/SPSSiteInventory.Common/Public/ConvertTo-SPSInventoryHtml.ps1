function ConvertTo-SPSInventoryHtml {
    <#
        .SYNOPSIS
        Renders the scored inventory as a self-contained HTML report: one file, or several pages
        for a very large farm.

        .DESCRIPTION
        ConvertTo-SPSInventoryHtml is a pure function (no SharePoint calls) so it can be
        unit tested without a farm. It takes the scored inventory records (as produced by
        the orchestrator: one PSCustomObject per site with identity, volumetry and the
        Category / CategoryName / Score / Reasons fields) and returns a complete HTML
        document as a single string.

        The output is entirely self-contained: all CSS and the small sort/filter script
        are inlined, so the file opens correctly from disk or a share with no external
        resource, CDN or font download. The house style uses the Aptos font family, blue
        headings (rgb(31, 56, 100)) and a summary box that breaks the estate down by
        migration-complexity category (1 Simple to 4 Blocking).

        The target mode chooses the framing. By default (SharePointOnline) the report is the
        migration report described here. With SharePointOnPrem the four categories are called
        Modern-ready, Light remediation, Rebuild (SPFx) and Blocked, the pages of a split report
        are named after these names, and the header says that the report is about the
        modernization of the farm where it runs.

        The report is made to be read: the inventory table has one compact row per site
        collection, worst first, and opening a row shows the context of the site collection,
        the signals it raises and its assessment warnings. The content types and the other
        large detail tables are summarized or limited (see MaxDetailRow), because the CSV and
        JSON files hold every row and every column.

        Every field value is HTML-encoded, so URLs, titles and reasons cannot break the
        markup.

        By default the function returns the report as one string. With -FileName it returns
        pages instead, as objects with a Name (the file name), a Kind (Entry or Sites) and the
        Html. A farm with no more than SplitThreshold site collections still gives one page, the
        entry page, which is the report above. A larger one is split: the entry page keeps the
        summary, the risk indicators, the alerts, the wave plan and the detail sections, and the
        table of the site collections moves to pages of at most RowsPerPage site collections,
        one series per category, worst first. The pages link to each other with relative links,
        and are as self-contained as the single file, so that the folder can be moved, zipped
        and sent. A risk indicator of the entry page links to the first table page that has a
        site collection raising it, with the filter in the address (#ind=large-lists), and that
        page links to the previous and the next ones.

        .PARAMETER InputObject
        The scored inventory records to render. Each record is expected to expose Url,
        Title, WebApp, ContentDb, Template, SizeGB, SubWebCount, LastModified, Category,
        CategoryName, Score and Reasons. Missing fields are rendered empty.

        .PARAMETER EnvName
        Free-form environment identifier shown in the report header (for example 'PROD').

        .PARAMETER Title
        Report title. Defaults to 'SharePoint Site Inventory'.

        .PARAMETER GeneratedOn
        Timestamp shown in the header. Defaults to the current date and time. Exposed so
        callers (and tests) can produce a deterministic document.

        .PARAMETER SolutionMap
        Optional farm-solution (WSP) records, as produced by Get-SPSFarmSolutionMap. When
        provided, the report gains a "Farm solutions (WSP)" section: a summary box (total
        solutions, custom, full-trust code, web-app resource) and a table with each
        solution's Deployed / Custom / IsFullTrustCode / ContainsCasPolicy /
        ContainsWebApplicationResource / FeatureCount / FeatureScopes. Omitted cleanly when
        no map is passed.

        .PARAMETER ContentTypes
        Optional web content-type definitions and list bindings. When supplied,
        renders their metadata without classifying standard types as custom or
        blocking. Site-level completeness flags identify partial collection.

        .PARAMETER ManagedMetadataLists
        Optional per-list managed metadata rows (one row per list with managed metadata
        columns). When supplied, renders a managed metadata section with interpretation
        guidance; the term store dependency is not a migration blocker by itself.

        .PARAMETER Alert
        Optional risk alerts, as produced for the alerts report (alert type, severity,
        remediation and reference). When supplied, renders an alerts section that groups the
        alerts by type with the number of sites or web applications affected, what each one
        means and what to do about it, most severe first. The per-site list stays in the
        alerts CSV and JSON files.

        .PARAMETER ExternalLists
        Optional per-list external list rows (lists backed by a Business Connectivity
        Services external content type). When supplied, renders an external list section
        that explains these lists are not migrated.

        .PARAMETER BcsApplications
        Optional Business Connectivity Services LOB system rows from Get-SPSBcsApplication.
        When supplied, renders a BCS section.

        .PARAMETER BcsInventoryComplete
        Whether the BCS inventory could be read in full. When false, the BCS section says
        that BCS applications may be missing.

        .PARAMETER SecureStoreApplications
        Optional Secure Store target application rows from Get-SPSSecureStoreApplication. When
        supplied, renders a Secure Store section. The contact e-mail address of each target
        application, which is personal data, is not shown: the CSV and JSON files hold it.

        .PARAMETER SecureStoreInventoryComplete
        Whether the Secure Store inventory could be read in full. When false, the Secure Store
        section says that Secure Store applications may be missing.

        .PARAMETER ProfilePropertyMappings
        Optional profile property mapping rows from Get-SPSProfilePropertyMapping. When supplied,
        renders a profile property mapping section, the mappings that SharePoint Online does not have
        first.

        .PARAMETER ProfileInventoryComplete
        Whether the profile property mappings could be read in full. When false, the section says that
        mappings may be missing.

        .PARAMETER ExcludedPersonalSiteCount
        Number of personal sites that the scan left out. When above 0, the summary box says so.

        .PARAMETER ExcludedSiteMasterCount
        Number of site masters that the scan left out. When above 0, the summary box says so.

        .PARAMETER TargetMode
        SharePointOnline (the default) or SharePointOnPrem. It chooses the names of the categories,
        the names of the table pages of a split report, the line of the header that says what
        the report is for, the severity and the words of the alerts (the catalog of the mode, see
        Get-SPSAlertCatalog) and the severity of the risk indicators. The SharePointOnPrem report also
        has a Modern experience readiness section, after the alerts: what keeps each site collection
        in the classic experience. Any other value is rejected.

        .PARAMETER FileName
        The file name of the entry page, for example SPSSiteInventory-PROD-20261028-1146.html.
        The table pages are named after it (SPSSiteInventory-PROD-20261028-1146-sites-blocking-1.html),
        and the links between the pages use these names only. Giving it makes the function return
        pages, not a string.

        .PARAMETER SplitThreshold
        The number of site collections above which the report is split in several pages. Defaults
        to 3000: a report of 3000 site collections weighs about 5 MB and stays comfortable to filter.
        0 never splits. Only with -FileName.

        .PARAMETER RowsPerPage
        The number of site collections that a table page holds at most, from 50 to 5000. Defaults
        to 500, about 1 MB a page. Only with -FileName.

        .PARAMETER MaxDetailRow
        Maximum number of rows that each detail table shows (farm solutions, sites bound to
        full-trust code, managed metadata lists, external lists, BCS applications, Secure Store
        applications and profile property mappings). A table
        with more rows says how many are not shown and which files hold all of them. Defaults
        to 200. The content types are never listed in the report: it shows a summary, and the
        CSV and JSON files hold every row.

        .EXAMPLE
        $html = ConvertTo-SPSInventoryHtml -InputObject $scored -EnvName 'PROD'
        Set-Content -Path report.html -Value $html -Encoding UTF8

        .EXAMPLE
        $html = ConvertTo-SPSInventoryHtml -InputObject $scored -SolutionMap $solutionMap

        .EXAMPLE
        $page = ConvertTo-SPSInventoryHtml -InputObject $scored -FileName 'report.html' -SplitThreshold 3000
        $page | ForEach-Object { Set-Content -Path (Join-Path $folder $_.Name) -Value $_.Html -Encoding UTF8 }
    #>
    [CmdletBinding(DefaultParameterSetName = 'Single')]
    [OutputType([System.String], ParameterSetName = 'Single')]
    [OutputType([System.Management.Automation.PSObject], ParameterSetName = 'Pages')]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Object[]]
        $InputObject,

        [Parameter()]
        [System.String]
        $EnvName = '',

        [Parameter()]
        [System.String]
        $Title = 'SharePoint Site Inventory',

        [Parameter()]
        [System.DateTime]
        $GeneratedOn = (Get-Date),

        [Parameter()]
        [AllowEmptyCollection()]
        [AllowNull()]
        [System.Object[]]
        $SolutionMap = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [System.Object[]]
        $ContentTypes = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [System.Object[]]
        $ManagedMetadataLists = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [System.Object[]]
        $Alert = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [System.Object[]]
        $ExternalLists = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [System.Object[]]
        $BcsApplications = @(),

        [Parameter()]
        [System.Boolean]
        $BcsInventoryComplete = $true,

        [Parameter()]
        [AllowEmptyCollection()]
        [System.Object[]]
        $SecureStoreApplications = @(),

        [Parameter()]
        [System.Boolean]
        $SecureStoreInventoryComplete = $true,

        [Parameter()]
        [AllowEmptyCollection()]
        [System.Object[]]
        $ProfilePropertyMappings = @(),

        [Parameter()]
        [System.Boolean]
        $ProfileInventoryComplete = $true,

        [Parameter()]
        [System.Int32]
        $ExcludedPersonalSiteCount = 0,

        [Parameter()]
        [System.Int32]
        $ExcludedSiteMasterCount = 0,

        [Parameter()]
        [ValidateRange(1, 100000)]
        [System.Int32]
        $MaxDetailRow = 200,

        [Parameter()]
        [System.String]
        $TargetMode = 'SharePointOnline',

        [Parameter(ParameterSetName = 'Pages', Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $FileName,

        [Parameter(ParameterSetName = 'Pages')]
        [ValidateRange(0, 10000000)]
        [System.Int32]
        $SplitThreshold = 3000,

        [Parameter(ParameterSetName = 'Pages')]
        [ValidateRange(50, 5000)]
        [System.Int32]
        $RowsPerPage = 500
    )

    # Category metadata: name and accent colour for each complexity level. A plain
    # hashtable (not [ordered]) is used on purpose: an OrderedDictionary indexed by an
    # integer key resolves by position, not by key, which would mis-map the categories.
    # Order is enforced by iterating 1..4 explicitly.
    $targetProfile = Get-SPSTargetProfile -TargetMode $TargetMode
    $isOnPrem = $targetProfile.TargetMode -eq 'SharePointOnPrem'
    # The words that say what a wave and a high-severity signal are for. The anchor of the wave plan stays wave-plan.
    $waveNavLabel = if ($isOnPrem) { 'Modernization waves' } else { 'Migration waves' }
    $waveHeading = if ($isOnPrem) { 'Modernization wave plan' } else { 'Migration wave plan' }
    $highSeverityMeaning = if ($isOnPrem) { 'block or break the modern experience' } else { 'block or break a migration' }
    $categoryMeta = @{
        1 = @{ Name = $targetProfile.CategoryName[1]; Slug = $targetProfile.CategorySlug[1]; Color = '#107C10' }
        2 = @{ Name = $targetProfile.CategoryName[2]; Slug = $targetProfile.CategorySlug[2]; Color = '#C19C00' }
        3 = @{ Name = $targetProfile.CategoryName[3]; Slug = $targetProfile.CategorySlug[3]; Color = '#D83B01' }
        4 = @{ Name = $targetProfile.CategoryName[4]; Slug = $targetProfile.CategorySlug[4]; Color = '#A4262C' }
    }

    $records = @($InputObject)
    $siteRecords = @($records | Where-Object { $_.InventoryScope -ne 'WebApplication' })
    $total = $siteRecords.Count
    $partialCount = @($siteRecords | Where-Object { $_.AssessmentStatus -eq 'Partial' }).Count
    $failedCount = @($siteRecords | Where-Object { $_.AssessmentStatus -eq 'Failed' }).Count
    # The wave names come from the settings, so the sites that wait in Needs review are told by the rule
    # that puts them there (partial, Simple, wave 0) and not by a name that a numbered wave could have.
    $needsReviewCount = @($siteRecords | Where-Object {
            $_.AssessmentStatus -eq 'Partial' -and
            $null -ne $_.Category -and [int]$_.Category -eq 1 -and
            $null -ne $_.Wave -and [int]$_.Wave -eq 0 -and
            $_.WaveName -eq 'Needs review'
        }).Count
    $enumerationFailureCount = @($records | Where-Object { $_.InventoryScope -eq 'WebApplication' }).Count
    $assessedTotal = $total - $failedCount

    # A report with more site collections than SplitThreshold is split: the entry page, and the table of the
    # site collections on pages of at most RowsPerPage of them, one series per category.
    $paged = $PSCmdlet.ParameterSetName -eq 'Pages'
    $splitReport = $paged -and $SplitThreshold -gt 0 -and $total -gt $SplitThreshold
    $entryName = ''
    $pageBaseName = ''
    if ($paged) {
        $entryName = [System.IO.Path]::GetFileName($FileName)
        $pageBaseName = [System.IO.Path]::GetFileNameWithoutExtension($entryName)
    }

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture

    # Per-category counts and total size.
    $counts = @{ 1 = 0; 2 = 0; 3 = 0; 4 = 0 }
    $totalSize = 0.0
    foreach ($record in $siteRecords) {
        $cat = 0
        if ($null -ne $record.Category) { $cat = [int]$record.Category }
        if ($counts.ContainsKey($cat)) { $counts[$cat]++ }

        if ($null -ne $record.SizeGB) {
            try { $totalSize += [double]$record.SizeGB }
            catch { Write-Verbose -Message "Ignoring non-numeric SizeGB '$($record.SizeGB)': $($_.Exception.Message)" }
        }
    }
    $totalSizeText = ConvertTo-SPSSizeText -SizeGB $totalSize
    # Risk indicators: one entry per signal. Test says whether a site collection raises it. It gives the
    # count and the tags of the rows of the inventory table, so that a click on an indicator filters the
    # table. The severity is the one of the alert of the signal in the alert catalog (High blocks or
    # breaks a migration, Medium needs a plan or a check, Low is information to pass on); a signal that
    # has no alert has its own.
    $alertCatalog = Get-SPSAlertCatalog -TargetMode $targetProfile.TargetMode
    $riskIndicators = @(
        @{ Key = 'full-trust'; Label = 'Sites with full-trust code'; Short = 'full-trust code'; Alert = 'FullTrustCode'; Test = { param($r) [bool]$r.UsesFullTrustCode } }
        @{ Key = 'custom-farm-feature'; Label = 'Sites with custom farm features'; Short = 'custom farm features'; Severity = $(if ($isOnPrem) { 'Medium' } else { 'High' }); Test = { param($r) [bool]$r.UsesCustomFarmFeature } }
        @{ Key = 'sandbox'; Label = 'Sites with sandbox solutions'; Short = 'sandbox solutions'; Severity = 'Medium'; Test = { param($r) [int]$r.SandboxSolutions -gt 0 } }
        @{ Key = 'custom-master-page'; Label = 'Sites with a custom master page'; Short = 'a custom master page'; Severity = 'Medium'; Test = { param($r) [bool]$r.CustomMasterPage } }
        @{ Key = 'event-receivers'; Label = 'Sites with custom event receivers'; Short = 'custom event receivers'; Severity = 'Medium'; Test = { param($r) [int]$r.EventReceivers -gt 0 } }
        @{ Key = 'fba'; Label = 'Sites with FBA configured'; Short = 'FBA configured'; Alert = 'FbaConfigured'; Test = { param($r) [bool]$r.HasFbaZone } }
        @{ Key = 'unsupported-template'; Label = 'Sites with unsupported templates'; Short = 'unsupported templates'; Alert = 'UnsupportedSiteTemplate'; Test = { param($r) [bool]$r.IsUnsupportedSiteTemplate } }
        @{ Key = 'template-review'; Label = 'Sites with template compatibility review'; Short = 'template compatibility review'; Alert = 'TemplateCompatibilityReview'; Test = { param($r) -not [bool]$r.IsUnsupportedSiteTemplate -and [string]$r.TemplateCompatibility -eq 'Review' } }
        @{ Key = 'template-language'; Label = 'Sites with template-language review'; Short = 'template-language review'; Alert = 'TemplateLanguageReview'; Test = { param($r) [bool]$r.TemplateLanguageReviewRequired } }
        @{ Key = 'infopath'; Label = 'Sites with InfoPath forms'; Short = 'InfoPath forms'; Alert = 'InfoPath'; Test = { param($r) [int]$r.InfoPathFormCount -gt 0 } }
        @{ Key = 'irm'; Label = 'Sites with IRM-enabled lists'; Short = 'IRM-enabled lists'; Alert = 'IrmEnabledLists'; Test = { param($r) [int]$r.IrmEnabledListCount -gt 0 } }
        @{ Key = 'locked'; Label = 'Sites with locked state'; Short = 'a locked state'; Alert = 'LockedSite'; Test = { param($r) [bool]$r.IsLockedSite } }
        @{ Key = 'noaccess'; Label = 'Sites locked with NoAccess'; Short = 'a NoAccess lock'; Alert = 'NoAccessSite'; Test = { param($r) [bool]$r.HasNoAccessLock } }
        @{ Key = 'workflow-2010'; Label = 'Sites with Workflow 2010'; Short = 'Workflow 2010'; Alert = 'Workflow2010'; Test = { param($r) [int]$r.Workflow2010Count -gt 0 } }
        @{ Key = 'workflow-2010-running'; Label = 'Sites with running Workflow 2010'; Short = 'running Workflow 2010'; Alert = 'Workflow2010Running'; Test = { param($r) [int]$r.Workflow2010RunningInstanceCount -gt 0 } }
        @{ Key = 'workflow-2013-running'; Label = 'Sites with running Workflow 2013'; Short = 'running Workflow 2013'; Alert = 'Workflow2013Running'; Test = { param($r) [int]$r.Workflow2013RunningInstanceCount -gt 0 } }
        @{ Key = 'app-instances'; Label = 'Sites with app instances'; Short = 'app instances'; Alert = 'AppInstances'; Test = { param($r) [int]$r.AppInstanceCount -gt 0 } }
        @{ Key = 'app-webs'; Label = 'Sites with app webs'; Short = 'app webs'; Alert = 'AppWebs'; Test = { param($r) [int]$r.AppWebCount -gt 0 } }
        @{ Key = 'publishing-features'; Label = 'Sites with publishing features'; Short = 'publishing features'; Alert = 'PublishingSite'; Test = { param($r) [bool]$r.PublishingInfrastructureEnabled -or [int]$r.PublishingWebCount -gt 0 } }
        @{ Key = 'publishing-pages'; Label = 'Sites with publishing pages'; Short = 'publishing pages'; Alert = 'PublishingPages'; Test = { param($r) [int]$r.PublishingPageCount -gt 0 } }
        @{ Key = 'customized-pages'; Label = 'Sites with customized pages'; Short = 'customized pages'; Alert = 'CustomizedPages'; Test = { param($r) [int]$r.CustomizedPageCount -gt 0 } }
        @{ Key = 'alternate-css'; Label = 'Sites with an alternate CSS URL'; Short = 'an alternate CSS URL'; Alert = 'AlternateCssUrl'; Test = { param($r) [int]$r.AlternateCssUrlCount -gt 0 } }
        @{ Key = 'xslt-views'; Label = 'Sites with XSLT list views'; Short = 'XSLT list views'; Alert = 'XsltListViews'; Test = { param($r) [int]$r.XsltListViewCount -gt 0 } }
        @{ Key = 'script-web-parts'; Label = 'Sites with script web parts'; Short = 'script web parts'; Alert = 'ScriptWebParts'; Test = { param($r) [int]$r.ScriptWebPartCount -gt 0 } }
        @{ Key = 'modern-opt-out'; Label = 'Sites that opted out of modern lists'; Short = 'an opt-out of modern lists'; Alert = 'ModernExperienceOptOut'; Test = { param($r) [int]$r.ClassicExperienceOptOutCount -gt 0 } }
        @{ Key = 'classic-lists'; Label = 'Sites with lists forced to classic'; Short = 'lists forced to classic'; Alert = 'ClassicExperienceLists'; Test = { param($r) [int]$r.ClassicExperienceListCount -gt 0 } }
        @{ Key = 'custom-permission-levels'; Label = 'Sites with custom permission levels'; Short = 'custom permission levels'; Alert = 'CustomPermissionLevels'; Test = { param($r) [int]$r.CustomPermissionLevelCount -gt 0 } }
        @{ Key = 'email-enabled-lists'; Label = 'Sites with e-mail enabled lists'; Short = 'e-mail enabled lists'; Alert = 'EmailEnabledLists'; Test = { param($r) [int]$r.EmailEnabledListCount -gt 0 } }
        @{ Key = 'html-files'; Label = 'Sites with HTML files'; Short = 'HTML files'; Alert = 'HtmlFiles'; Test = { param($r) [int]$r.HtmlFileCount -gt 0 } }
        @{ Key = 'managed-metadata'; Label = 'Sites with managed metadata columns'; Short = 'managed metadata columns'; Alert = 'ManagedMetadataColumns'; Test = { param($r) [int]$r.ManagedMetadataListCount -gt 0 } }
        @{ Key = 'external-lists'; Label = 'Sites with external lists'; Short = 'external lists'; Alert = 'ExternalLists'; Test = { param($r) [int]$r.ExternalListCount -gt 0 } }
        @{ Key = 'sharepoint-alerts'; Label = 'Sites with SharePoint alerts'; Short = 'SharePoint alerts'; Alert = 'AlertSubscriptions'; Test = { param($r) [int]$r.SharePointAlertCount -gt 0 } }
        @{ Key = 'subsites'; Label = 'Sites with subsites'; Short = 'subsites'; Alert = 'Subsites'; Test = { param($r) [int]$r.SubsiteCount -gt 0 } }
        @{ Key = 'permissive-file-handling'; Label = 'Sites in web applications with permissive browser file handling'; Short = 'permissive browser file handling'; Alert = 'PermissiveBrowserFileHandling'; Test = { param($r) [string]$r.BrowserFileHandling -eq 'Permissive' } }
        @{ Key = 'large-site'; Label = 'Sites above large-size threshold'; Short = 'a size above the large-size threshold'; Alert = 'LargeSite'; Test = { param($r) [bool]$r.IsLargeSite } }
        @{ Key = 'large-lists'; Label = 'Sites with large lists'; Short = 'large lists'; Alert = 'LargeLists'; Test = { param($r) [int]$r.LargeListCount -gt 0 } }
        @{ Key = 'checked-out-files'; Label = 'Sites with checked-out files'; Short = 'checked-out files'; Alert = 'CheckedOutFiles'; Test = { param($r) [int]$r.CheckedOutFileCount -gt 0 } }
        @{ Key = 'file-versions'; Label = 'Sites with high file-version counts'; Short = 'high file-version counts'; Alert = 'FileVersions'; Test = { param($r) [int]$r.FileVersionCount -gt 0 } }
        @{ Key = 'large-excel'; Label = 'Sites with large Excel files'; Short = 'large Excel files'; Alert = 'LargeExcelFiles'; Test = { param($r) [int]$r.LargeExcelFileCount -gt 0 } }
        @{ Key = 'audience-targeting'; Label = 'Sites with audience-targeted items'; Short = 'audience-targeted items'; Alert = 'AudienceTargeting'; Test = { param($r) [int]$r.AudienceTargetedItemCount -gt 0 } }
        @{ Key = 'site-notebook'; Label = 'Sites with a site notebook'; Short = 'a site notebook'; Alert = 'SiteNotebook'; Test = { param($r) [int]$r.SiteNotebookCount -gt 0 } }
        @{ Key = 'profile-page'; Label = 'Sites with a customized profile page'; Short = 'a customized profile page'; Alert = 'CustomizedProfilePage'; Test = { param($r) [int]$r.CustomizedProfilePageCount -gt 0 } }
    )
    $riskCounts = @{}
    foreach ($indicator in $riskIndicators) { $riskCounts[$indicator.Key] = 0 }
    $taggedRecords = [System.Collections.Generic.List[System.Object]]::new()
    foreach ($record in $records) {
        $tags = [System.Collections.Generic.List[System.String]]::new()
        if ($record.InventoryScope -ne 'WebApplication') {
            foreach ($indicator in $riskIndicators) {
                if (& $indicator.Test $record) {
                    $tags.Add($indicator.Key)
                    $riskCounts[$indicator.Key]++
                }
            }
        }
        $taggedRecords.Add([PSCustomObject]@{ Record = $record; Tags = $tags.ToArray() })
    }
    $riskRows = @(
        for ($index = 0; $index -lt $riskIndicators.Count; $index++) {
            $indicator = $riskIndicators[$index]
            $severity = if ($indicator.Alert) { [string]$alertCatalog[$indicator.Alert].Severity } else { [string]$indicator.Severity }
            [PSCustomObject]@{ Key = $indicator.Key; Label = $indicator.Label; Short = $indicator.Short; Severity = $severity; Count = $riskCounts[$indicator.Key]; Order = $index }
        }
    )

    # Per-wave aggregation for the migration wave plan. Waves are discovered from the
    # records (Wave / WaveName), so this stays self-contained. Records without a wave are
    # bucketed as 0 / 'Unassigned' and shown last.
    $waveAgg = @{}
    foreach ($record in $siteRecords) {
        $waveNumber = 0
        if ($null -ne $record.Wave) { $waveNumber = [int]$record.Wave }
        $waveName = if ($record.WaveName) { [string]$record.WaveName } elseif ($waveNumber -eq 0) { 'Unassigned' } else { ('Wave {0}' -f $waveNumber) }
        $waveGroupKey = '{0}|{1}' -f $waveNumber, $waveName

        if (-not $waveAgg.ContainsKey($waveGroupKey)) {
            $waveAgg[$waveGroupKey] = [PSCustomObject]@{ Wave = $waveNumber; Name = $waveName; Count = 0; SizeGB = 0.0; PartialCount = 0 }
        }
        $waveAgg[$waveGroupKey].Count++
        if ($record.AssessmentStatus -eq 'Partial') { $waveAgg[$waveGroupKey].PartialCount++ }
        if ($null -ne $record.SizeGB) {
            try { $waveAgg[$waveGroupKey].SizeGB += [double]$record.SizeGB } catch { Write-Verbose -Message "Ignoring non-numeric SizeGB in wave aggregation: $($_.Exception.Message)" }
        }
    }
    $waveKeys = @($waveAgg.Keys | Sort-Object `
        @{ Expression = { if ($waveAgg[$_].Wave -eq 0) { [int]::MaxValue } else { [int]$waveAgg[$_].Wave } } },
        @{ Expression = { [string]$waveAgg[$_].Name } })
    $solutions = @($SolutionMap | Where-Object { $null -ne $_ })
    $authenticationRecords = @($records | Where-Object { $_.AuthenticationZones })
    $policyRecords = @($records | Where-Object { $null -ne $_.WebAppPolicyCount -or $_.BrowserFileHandling })
    $hasContentTypeSection = $PSBoundParameters.ContainsKey('ContentTypes')
    $hasManagedMetadataSection = $PSBoundParameters.ContainsKey('ManagedMetadataLists')
    $hasAlertSection = $PSBoundParameters.ContainsKey('Alert')
    $hasExternalListSection = $PSBoundParameters.ContainsKey('ExternalLists')
    $hasBcsSection = $PSBoundParameters.ContainsKey('BcsApplications')
    $hasSecureStoreSection = $PSBoundParameters.ContainsKey('SecureStoreApplications')
    $hasProfileMappingSection = $PSBoundParameters.ContainsKey('ProfilePropertyMappings')
    $hasReadinessSection = $isOnPrem -and $total -gt 0
    $readiness = if ($hasReadinessSection) { Get-SPSModernReadiness -InputObject $siteRecords } else { $null }

    $encTitle = ConvertTo-SPSHtmlText -Value $Title
    $encEnv = ConvertTo-SPSHtmlText -Value $EnvName
    $encGenerated = ConvertTo-SPSHtmlText -Value $GeneratedOn.ToString('yyyy-MM-dd HH:mm')

    $style = @'
<style>
:root {
    --brand: rgb(31, 56, 100);
    --brand-soft: rgb(31, 56, 100, 0.08);
    --border: #d9dce1;
    --text: #1f2328;
    --muted: #59636e;
    --cat1: #107C10;
    --cat2: #C19C00;
    --cat3: #D83B01;
    --cat4: #A4262C;
}
* { box-sizing: border-box; }
body {
    margin: 0;
    padding: 24px;
    font-family: 'Aptos', 'Segoe UI', system-ui, -apple-system, 'Helvetica Neue', Arial, sans-serif;
    color: var(--text);
    background: #f5f6f8;
    font-size: 14px;
    line-height: 1.45;
}
h1, h2, h3 { color: var(--brand); font-weight: 600; }
h1 { margin: 0 0 4px; font-size: 24px; }
h2 { margin: 28px 0 12px; font-size: 18px; }
.wrap { max-width: 1400px; margin: 0 auto; }
.header { border-bottom: 3px solid var(--brand); padding-bottom: 12px; margin-bottom: 8px; }
.meta { color: var(--muted); font-size: 13px; }
.meta strong { color: var(--text); }
.nav {
    margin: 12px 0 8px;
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
}
.nav a {
    display: inline-block;
    padding: 5px 12px;
    border: 1px solid var(--border);
    border-radius: 999px;
    background: #fff;
    color: var(--brand);
    text-decoration: none;
    font-size: 13px;
}
.nav a:hover { background: var(--brand-soft); }
.nav a.current { background: var(--brand); color: #fff; border-color: var(--brand); }
.pager { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; margin: 8px 0; }
.pager a, .pager strong, .pager span { display: inline-block; padding: 3px 10px; border: 1px solid var(--border); border-radius: 999px; background: #fff; font-size: 13px; }
.pager a { color: var(--brand); text-decoration: none; }
.pager a:hover { background: var(--brand-soft); }
.pager strong { background: var(--brand); border-color: var(--brand); color: #fff; }
.pager span { border-color: transparent; background: none; color: var(--muted); }
.hop { margin-left: 8px; font-size: 13px; }
.hop a { color: var(--brand); margin-right: 10px; }
.summary {
    border: 1px solid var(--border);
    border-left: 4px solid var(--brand);
    background: #fff;
    border-radius: 6px;
    padding: 16px 18px;
    margin: 16px 0 8px;
}
.summary-total { font-size: 15px; margin-bottom: 12px; }
.summary-total strong { color: var(--brand); font-size: 18px; }
.cards { display: flex; flex-wrap: wrap; gap: 12px; }
.card {
    flex: 1 1 160px;
    border: 1px solid var(--border);
    border-top: 4px solid var(--muted);
    border-radius: 6px;
    padding: 12px 14px;
    background: #fff;
}
.card .num { font-size: 26px; font-weight: 700; line-height: 1; }
.card .lbl { font-size: 13px; color: var(--muted); margin-top: 4px; }
.card .pct { font-size: 12px; color: var(--muted); }
.card.c1 { border-top-color: var(--cat1); } .card.c1 .num { color: var(--cat1); }
.card.c2 { border-top-color: var(--cat2); } .card.c2 .num { color: var(--cat2); }
.card.c3 { border-top-color: var(--cat3); } .card.c3 .num { color: var(--cat3); }
.card.c4 { border-top-color: var(--cat4); } .card.c4 .num { color: var(--cat4); }
.filters { margin: 8px 0 12px; display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
.filters button {
    font: inherit;
    cursor: pointer;
    border: 1px solid var(--border);
    background: #fff;
    color: var(--text);
    padding: 5px 12px;
    border-radius: 999px;
}
.filters button.active { background: var(--brand); color: #fff; border-color: var(--brand); }
.table-scroll { overflow-x: auto; border: 1px solid var(--border); border-radius: 6px; background: #fff; }
table { border-collapse: collapse; width: 100%; font-size: 13px; }
thead th {
    position: sticky; top: 0;
    background: var(--brand); color: #fff;
    text-align: left; padding: 9px 10px; white-space: nowrap;
    cursor: pointer; user-select: none;
}
thead th .arrow { opacity: 0.6; font-size: 11px; }
tbody td { padding: 8px 10px; border-top: 1px solid var(--border); vertical-align: top; }
tbody tr:hover { background: var(--brand-soft); }
td.num, th.num { text-align: right; }
td.url { max-width: 320px; word-break: break-all; }
td.reasons { max-width: 340px; color: var(--muted); }
.badge {
    display: inline-block; padding: 2px 10px; border-radius: 999px;
    color: #fff; font-size: 12px; font-weight: 600; white-space: nowrap;
}
.b0 { background: var(--muted); }
.b1 { background: var(--cat1); } .b2 { background: var(--cat2); }
.b3 { background: var(--cat3); } .b4 { background: var(--cat4); }
.pill { display: inline-block; padding: 2px 9px; border-radius: 999px; color: #fff; font-size: 12px; font-weight: 600; white-space: nowrap; }
.pill.yes { background: var(--cat4); }
.pill.no { background: #8a9099; }
.pill.warn { background: var(--cat2); }
.card.wsp { border-top-color: var(--cat4); } .card.wsp .num { color: var(--cat4); }
.card.custom { border-top-color: var(--cat2); } .card.custom .num { color: var(--cat2); }
.card.plain { border-top-color: var(--brand); } .card.plain .num { color: var(--brand); }
td.muted, .muted { color: var(--muted); }
.footer { color: var(--muted); font-size: 12px; margin-top: 18px; text-align: center; }
.toolbar { margin: 8px 0 12px; display: flex; flex-wrap: wrap; gap: 8px 12px; align-items: center; }
.toolbar .filters { margin: 0; }
.toolbar input[type="search"] {
    font: inherit;
    padding: 5px 14px;
    border: 1px solid var(--border);
    border-radius: 999px;
    background: #fff;
    min-width: 260px;
}
.toolbar .count { margin-left: auto; color: var(--muted); font-size: 13px; }
#inv thead th.tgl { cursor: default; width: 30px; }
#inv td.tgl { width: 30px; padding-right: 0; }
.toggle { font: inherit; font-size: 16px; line-height: 1; border: 0; background: none; cursor: pointer; color: var(--brand); padding: 3px 8px; border-radius: 4px; }
.toggle::before { content: "\25B8"; display: inline-block; }
.toggle:hover { background: var(--brand-soft); }
tbody.open .toggle::before { transform: rotate(90deg); }
.site-cell { min-width: 240px; max-width: 380px; }
.site-title { font-weight: 600; overflow-wrap: anywhere; }
.site-url { color: var(--muted); font-size: 12px; overflow-wrap: anywhere; }
td.tpl { white-space: nowrap; }
.clamp { display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
tr.detail { display: none; }
tbody.open tr.detail { display: table-row; }
tr.detail td { background: #f8f9fb; padding: 6px 10px 14px; }
.ctx { color: var(--muted); font-size: 12.5px; margin: 0 0 8px; }
.ctx strong { color: var(--text); font-weight: 600; }
dl.signals { display: grid; grid-template-columns: max-content 1fr; gap: 3px 18px; margin: 0 0 8px; }
dl.signals dt { font-weight: 600; }
dl.signals dd { margin: 0; overflow-wrap: anywhere; }
.sig-value { font-weight: 600; color: var(--brand); }
.sig-detail { color: var(--muted); }
.note { border-left: 3px solid var(--border); padding: 2px 10px; margin: 6px 0; font-size: 12.5px; color: var(--muted); overflow-wrap: anywhere; }
.note strong { color: var(--text); }
.note.warn { border-left-color: var(--cat2); }
.summary > p.muted:first-child { margin-top: 0; }
.risk-group { margin: 0 0 14px; }
.risk-head { display: flex; align-items: center; gap: 8px; margin: 0 0 4px; color: var(--muted); font-size: 13px; }
.risk {
    display: grid;
    grid-template-columns: minmax(260px, 380px) minmax(120px, 1fr) 100px;
    align-items: center;
    gap: 14px;
    width: 100%;
    font: inherit;
    text-align: left;
    color: var(--text);
    background: none;
    border: 0;
    border-radius: 6px;
    padding: 5px 8px;
    cursor: pointer;
    text-decoration: none;
}
.risk:hover { background: var(--brand-soft); }
.risk.active { background: var(--brand-soft); box-shadow: inset 3px 0 0 var(--brand); }
.risk-bar { display: block; height: 10px; border-radius: 5px; background: #e9ecf0; overflow: hidden; }
.risk-bar > span { display: block; height: 100%; border-radius: 5px; }
.sev-high .risk-bar > span { background: var(--cat4); }
.sev-medium .risk-bar > span { background: var(--cat2); }
.sev-low .risk-bar > span { background: #8a9099; }
.risk-count { text-align: right; white-space: nowrap; }
.risk-none { margin: 8px 0 0; color: var(--muted); font-size: 13px; }
.alert-list { border: 1px solid var(--border); border-radius: 6px; background: #fff; }
.alert-item { border-top: 1px solid var(--border); }
.alert-item:first-child { border-top: 0; }
.alert-item summary {
    display: grid;
    grid-template-columns: 16px 80px minmax(200px, 1fr) auto;
    align-items: center;
    gap: 12px;
    padding: 9px 12px;
    cursor: pointer;
    list-style: none;
}
.alert-item summary::-webkit-details-marker { display: none; }
.alert-item summary::before { content: "\25B8"; color: var(--brand); }
.alert-item[open] summary::before { content: "\25BE"; }
.alert-item summary:hover { background: var(--brand-soft); }
.alert-item summary .pill { justify-self: start; }
.alert-name { font-weight: 600; }
.alert-count { color: var(--muted); font-size: 13px; }
.alert-body { padding: 2px 12px 12px 120px; font-size: 13px; }
.alert-body p { margin: 4px 0; }
.chip { font: inherit; color: #fff; background: var(--brand); border: 0; border-radius: 999px; padding: 5px 12px; cursor: pointer; }
@media (max-width: 640px) {
    .risk { grid-template-columns: minmax(0, 1fr) auto; grid-template-areas: "label label" "bar count"; row-gap: 4px; }
    .risk .risk-label { grid-area: label; overflow-wrap: anywhere; }
    .risk .risk-bar { grid-area: bar; }
    .risk .risk-count { grid-area: count; }
    .alert-item summary { grid-template-columns: 16px auto minmax(0, 1fr); grid-template-areas: "mark pill count" "name name name"; row-gap: 4px; }
    .alert-item summary::before { grid-area: mark; }
    .alert-item summary .pill { grid-area: pill; }
    .alert-item summary .alert-count { grid-area: count; justify-self: end; }
    .alert-item summary .alert-name { grid-area: name; overflow-wrap: anywhere; }
    .alert-body { padding-left: 12px; }
}
@media print { tr.detail { display: table-row; } .toolbar { display: none; } }
</style>
'@

    # The head, the header and the navigation of a page. The single report and every page of a split one
    # have the same ones, and the same end.
    $startPage = {
        param([System.String]$PageHeading, [System.String]$Navigation)
        $page = [System.Text.StringBuilder]::new()
        [void]$page.AppendLine('<!DOCTYPE html>')
        [void]$page.AppendLine('<html lang="en">')
        [void]$page.AppendLine('<head>')
        [void]$page.AppendLine('<meta charset="utf-8">')
        [void]$page.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
        [void]$page.AppendLine(('<title>{0}{1}</title>' -f $PageHeading, $(if ($encEnv) { ' - ' + $encEnv } else { '' })))
        [void]$page.AppendLine($style)
        [void]$page.AppendLine('</head>')
        [void]$page.AppendLine('<body>')
        [void]$page.AppendLine('<div class="wrap">')

        # Header.
        [void]$page.AppendLine('<div class="header">')
        [void]$page.AppendLine(('<h1>{0}</h1>' -f $encTitle))
        $envPart = if ($encEnv) { ('Environment <strong>{0}</strong> &middot; ' -f $encEnv) } else { '' }
        $modePart = if ($targetProfile.TargetMode -eq 'SharePointOnline') { '' } else { ('Target <strong>{0}</strong> &middot; ' -f (ConvertTo-SPSHtmlText -Value $targetProfile.DisplayName)) }
        [void]$page.AppendLine(('<div class="meta">{0}{1}Generated on <strong>{2}</strong></div>' -f $envPart, $modePart, $encGenerated))
        [void]$page.AppendLine('</div>')
        [void]$page.AppendLine('<div class="nav">')
        [void]$page.Append($Navigation)
        [void]$page.AppendLine('</div>')
        return $page.ToString()
    }
    $endPage = {
        param([AllowNull()][System.String]$ScriptHtml)
        $page = [System.Text.StringBuilder]::new()
        [void]$page.AppendLine('<div class="footer">Generated by SPSSiteInventory &middot; read-only inventory &middot; no farm changes</div>')
        [void]$page.AppendLine('</div>')
        if ($null -ne $ScriptHtml) {
            [void]$page.AppendLine($ScriptHtml)
        }
        [void]$page.AppendLine('</body>')
        [void]$page.AppendLine('</html>')
        return $page.ToString()
    }

    $navigation = [System.Text.StringBuilder]::new()
    [void]$navigation.AppendLine('<a href="#summary">Summary</a>')
    [void]$navigation.AppendLine('<a href="#risk-indicators">Risk indicators</a>')
    if ($hasAlertSection) {
        [void]$navigation.AppendLine('<a href="#alerts">Alerts</a>')
    }
    if ($hasReadinessSection) {
        [void]$navigation.AppendLine('<a href="#modern-readiness">Modern readiness</a>')
    }
    if ($waveKeys.Count -gt 0) {
        [void]$navigation.AppendLine(('<a href="#wave-plan">{0}</a>' -f $waveNavLabel))
    }
    [void]$navigation.AppendLine('<a href="#inventory-table">Inventory table</a>')
    if ($solutions.Count -gt 0) {
        [void]$navigation.AppendLine('<a href="#farm-solutions">Farm solutions</a>')
    }
    if ($authenticationRecords.Count -gt 0) {
        [void]$navigation.AppendLine('<a href="#authentication">Authentication</a>')
    }
    if ($policyRecords.Count -gt 0) {
        [void]$navigation.AppendLine('<a href="#web-app-policies">Web application policies</a>')
    }
    if ($hasContentTypeSection) {
        [void]$navigation.AppendLine('<a href="#content-types">Content types</a>')
    }
    if ($hasManagedMetadataSection) {
        [void]$navigation.AppendLine('<a href="#managed-metadata">Managed metadata</a>')
    }
    if ($hasExternalListSection) {
        [void]$navigation.AppendLine('<a href="#external-lists">External lists</a>')
    }
    if ($hasBcsSection) {
        [void]$navigation.AppendLine('<a href="#bcs-applications">BCS applications</a>')
    }
    if ($hasSecureStoreSection) {
        [void]$navigation.AppendLine('<a href="#secure-store-applications">Secure Store</a>')
    }
    if ($hasProfileMappingSection) {
        [void]$navigation.AppendLine('<a href="#profile-property-mappings">Profile property mappings</a>')
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append((& $startPage $encTitle $navigation.ToString()))

    # Summary box.
    [void]$sb.AppendLine('<div class="summary" id="summary">')
    [void]$sb.AppendLine(('<div class="summary-total"><strong>{0}</strong> site collection(s) &middot; <strong>{1} GB</strong> total content &middot; <strong>{2}</strong> partial &middot; <strong>{3}</strong> failed</div>' -f $total, (ConvertTo-SPSHtmlText -Value $totalSizeText), $partialCount, $failedCount))
    if ($needsReviewCount -gt 0) {
        [void]$sb.AppendLine(('<div class="summary-total"><strong>{0}</strong> {1} site collection(s) with a partial assessment wait in the <strong>Needs review</strong> wave until they are read in full.</div>' -f $needsReviewCount, (ConvertTo-SPSHtmlText -Value $categoryMeta[1].Name)))
    }
    $excludedParts = @()
    if ($ExcludedPersonalSiteCount -gt 0) {
        $excludedParts += '<strong>{0}</strong> personal site(s)' -f $ExcludedPersonalSiteCount
    }
    if ($ExcludedSiteMasterCount -gt 0) {
        $excludedParts += '<strong>{0}</strong> site master(s)' -f $ExcludedSiteMasterCount
    }
    if ($excludedParts.Count -gt 0) {
        [void]$sb.AppendLine(('<div class="summary-total">{0} were left out of this inventory (Scope in the settings)</div>' -f ($excludedParts -join ' and ')))
    }
    if ($enumerationFailureCount -gt 0) {
        [void]$sb.AppendLine(('<div class="summary-total"><strong>{0}</strong> web application enumeration failure(s)</div>' -f $enumerationFailureCount))
    }
    [void]$sb.AppendLine('<div class="cards">')
    foreach ($key in 1..4) {
        $meta = $categoryMeta[$key]
        $count = $counts[[int]$key]
        $pct = if ($assessedTotal -gt 0) { [math]::Round(($count / $assessedTotal) * 100, 1) } else { 0 }
        [void]$sb.AppendLine(('<div class="card c{0}"><div class="num">{1}</div><div class="lbl">{0}. {2}</div><div class="pct">{3}%</div></div>' -f $key, $count, $meta.Name, $pct.ToString($invariant)))
    }
    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine('</div>')

    [void]$sb.AppendLine('<h2 id="risk-indicators">Risk indicators</h2>')
    [void]$sb.AppendLine('<div class="summary">')
    if ($total -eq 0) {
        [void]$sb.AppendLine('<p class="muted">There is no site collection in this inventory.</p>')
    }
    else {
        $riskHint = if ($splitReport) { 'Click an indicator to open the first page of the inventory table that has a site collection that raises it, with the filter on.' } else { 'Click an indicator to filter the inventory table.' }
        [void]$sb.AppendLine(('<p class="muted">The share of the site collections that raise each signal, grouped by the severity of the alert of the signal. {0}</p>' -f $riskHint))
        $severityMeta = [ordered]@{
            High   = @{ Pill = 'yes'; Meaning = $highSeverityMeaning }
            Medium = @{ Pill = 'warn'; Meaning = 'need a plan or a check' }
            Low    = @{ Pill = 'no'; Meaning = 'information to pass on' }
        }
        foreach ($severityName in $severityMeta.Keys) {
            $severityRows = @($riskRows | Where-Object { $_.Severity -eq $severityName -and $_.Count -gt 0 } | Sort-Object -Property @{ Expression = { $_.Count }; Descending = $true }, @{ Expression = { $_.Order } })
            if ($severityRows.Count -eq 0) { continue }
            [void]$sb.AppendLine('<div class="risk-group">')
            [void]$sb.AppendLine(('<div class="risk-head"><span class="pill {0}">{1}</span> {2}</div>' -f $severityMeta[$severityName].Pill, $severityName, $severityMeta[$severityName].Meaning))
            foreach ($row in $severityRows) {
                $share = [math]::Round(100 * $row.Count / $total, 1)
                $barWidth = [math]::Max($share, 1)
                # The page of a split report that an indicator opens is known once the tables are built: a placeholder stands for it until then.
                $riskOpen = if ($splitReport) { '<a class="risk sev-{0}" data-ind="{1}" href="@@IND-PAGE:{1}@@#ind={1}">' } else { '<button type="button" class="risk sev-{0}" data-ind="{1}" aria-pressed="false">' }
                $riskClose = if ($splitReport) { '</a>' } else { '</button>' }
                $riskRowTemplate = $riskOpen + '<span class="risk-label">{2}</span><span class="risk-bar"><span style="width:{3}%"></span></span><span class="risk-count"><strong>{4}</strong> <span class="muted">{5}%</span></span>' + $riskClose
                [void]$sb.AppendLine(($riskRowTemplate -f
                    $severityName.ToLowerInvariant(),
                    $row.Key,
                    (ConvertTo-SPSHtmlText -Value $row.Label),
                    $barWidth.ToString('0.#', $invariant),
                    $row.Count,
                    $share.ToString('0.#', $invariant)))
            }
            [void]$sb.AppendLine('</div>')
        }
        $quietRows = @($riskRows | Where-Object { $_.Count -eq 0 })
        if ($quietRows.Count -gt 0) {
            [void]$sb.AppendLine(('<p class="risk-none">No site collection has: {0}.</p>' -f ((@($quietRows | ForEach-Object { ConvertTo-SPSHtmlText -Value $_.Short })) -join ', ')))
        }
    }
    [void]$sb.AppendLine('</div>')

    # Alerts grouped by type, with what to do about each.
    if ($hasAlertSection) {
        $alertCatalog = Get-SPSAlertCatalog -TargetMode $targetProfile.TargetMode
        $severityRank = @{ High = 0; Medium = 1; Low = 2 }
        $alertRows = @($Alert | Where-Object { $null -ne $_ })
        $alertGroups = @(
            $alertRows | Group-Object -Property AlertType | ForEach-Object {
                $first = $_.Group[0]
                [PSCustomObject]@{
                    AlertType   = [string]$_.Name
                    Severity    = [string]$first.Severity
                    Count       = $_.Count
                    Message     = if ($alertCatalog.Contains([string]$_.Name)) { $alertCatalog[[string]$_.Name].Message } else { [string]$first.Message }
                    Remediation = [string]$first.Remediation
                    Reference   = [string]$first.Reference
                }
            } | Sort-Object -Property @{ Expression = { if ($severityRank.ContainsKey($_.Severity)) { $severityRank[$_.Severity] } else { 9 } } }, @{ Expression = { $_.Count }; Descending = $true }, @{ Expression = { $_.AlertType } }
        )
        $highAlertCount = @($alertRows | Where-Object { [string]$_.Severity -eq 'High' }).Count
        $mediumAlertCount = @($alertRows | Where-Object { [string]$_.Severity -eq 'Medium' }).Count
        $lowAlertCount = @($alertRows | Where-Object { [string]$_.Severity -eq 'Low' }).Count
        [void]$sb.AppendLine('<h2 id="alerts">Alerts and remediation</h2>')
        [void]$sb.AppendLine(('<p><strong>{0}</strong> alert(s) of <strong>{1}</strong> type(s): <strong>{2}</strong> high, <strong>{3}</strong> medium and <strong>{4}</strong> low. Each type shows how many site collections or web applications it concerns; open it to read what it means and what to do about it. The alert of each site collection, with its URL, is in the alerts CSV and JSON files.</p>' -f $alertRows.Count, $alertGroups.Count, $highAlertCount, $mediumAlertCount, $lowAlertCount))
        if ($alertGroups.Count -gt 0) {
            [void]$sb.AppendLine('<div class="alert-list">')
            foreach ($alertGroup in $alertGroups) {
                $severityPill = switch ($alertGroup.Severity) {
                    'High' { '<span class="pill yes">High</span>' }
                    'Medium' { '<span class="pill warn">Medium</span>' }
                    default { ('<span class="pill no">{0}</span>' -f (ConvertTo-SPSHtmlText -Value $alertGroup.Severity)) }
                }
                $referenceLink = if ($alertGroup.Reference -like 'https://*') {
                    '<p><a href="{0}">Microsoft Learn</a></p>' -f (ConvertTo-SPSHtmlText -Value $alertGroup.Reference)
                }
                else {
                    ''
                }
                [void]$sb.AppendLine('<details class="alert-item">')
                [void]$sb.AppendLine(('<summary>{0}<span class="alert-name">{1}</span><span class="alert-count">{2} affected</span></summary>' -f
                    $severityPill,
                    (ConvertTo-SPSHtmlText -Value $alertGroup.AlertType),
                    $alertGroup.Count))
                [void]$sb.AppendLine(('<div class="alert-body"><p><strong>What it means</strong> {0}</p><p><strong>What to do</strong> {1}</p>{2}</div>' -f
                    (ConvertTo-SPSHtmlText -Value $alertGroup.Message),
                    (ConvertTo-SPSHtmlText -Value $alertGroup.Remediation),
                    $referenceLink))
                [void]$sb.AppendLine('</details>')
            }
            [void]$sb.AppendLine('</div>')
        }
    }

    # Modern experience readiness: what keeps each site collection in the classic experience. The modernization
    # of a farm is the work of removing it, so the report of that mode has a section for it.
    if ($hasReadinessSection) {
        [void]$sb.AppendLine('<h2 id="modern-readiness">Modern experience readiness</h2>')
        # What could not be read must be said where there is no blocker too: a site collection with no collected signal is not a clean one.
        $failedNote = ''
        if ($readiness.NotAssessed -gt 0) {
            $failedNote = ' <strong>{0}</strong> site collection(s) whose assessment failed are not counted.' -f $readiness.NotAssessed
        }
        if ($readiness.WithBlocker -eq 0) {
            $partialNote = ''
            if ($partialCount -gt 0) {
                $partialNote = ' The assessment of <strong>{0}</strong> site collection(s) is partial: a blocker may have been missed there.' -f $partialCount
            }
            if ($readiness.Assessed -eq 0) {
                [void]$sb.AppendLine(('<p class="muted">No site collection was assessed, so no blocker of the modern experience was detected.{0}</p>' -f $failedNote))
            }
            else {
                [void]$sb.AppendLine(('<p class="muted">No blocker of the modern experience was detected in the <strong>{0}</strong> assessed site collection(s).{1}{2}</p>' -f $readiness.Assessed, $failedNote, $partialNote))
            }
        }
        else {
            $readinessNote = $failedNote
            if ($partialCount -gt 0) {
                $readinessNote += ' The counts of a site collection whose assessment is partial are lower bounds.'
            }
            [void]$sb.AppendLine(('<p><strong>{0}</strong> of <strong>{1}</strong> assessed site collection(s) have at least one blocker of the modern experience: something that keeps a page or a list in the classic experience, and that has to be rebuilt to leave it. A blocker is counted once per kind, so a site collection with a custom master page and 40 XSLT list views has two.{2}</p>' -f $readiness.WithBlocker, $readiness.Assessed, $readinessNote))
            [void]$sb.AppendLine('<div class="table-scroll">')
            [void]$sb.AppendLine('<table class="waves">')
            [void]$sb.AppendLine('<thead><tr><th>Blocker</th><th class="num">Site collections</th><th class="num">Items</th></tr></thead>')
            [void]$sb.AppendLine('<tbody>')
            foreach ($kind in $readiness.Kind) {
                $itemsText = if ($null -eq $kind.Items) { '-' } elseif ($kind.SiteCount -eq 0) { '-' } else { '{0} {1}' -f ([double]$kind.Items).ToString('0.##', $invariant), $kind.Unit }
                [void]$sb.AppendLine(('<tr><td>{0}</td><td class="num">{1}</td><td class="num">{2}</td></tr>' -f (ConvertTo-SPSHtmlText -Value $kind.Label), $kind.SiteCount, (ConvertTo-SPSHtmlText -Value $itemsText)))
            }
            [void]$sb.AppendLine('</tbody>')
            [void]$sb.AppendLine('</table>')
            [void]$sb.AppendLine('</div>')
            $readinessListNote = 'The site collections that have a blocker, the most kinds first, then the highest score.'
            if ($readiness.SiteTotal -gt $readiness.Site.Count) {
                $readinessListNote = 'The <strong>{0}</strong> site collections with the most kinds of blocker are listed below, of <strong>{1}</strong>. The CSV and JSON files carry ModernBlockerCount and ModernBlockers for all of them.' -f $readiness.Site.Count, $readiness.SiteTotal
            }
            [void]$sb.AppendLine(('<p class="muted">{0}</p>' -f $readinessListNote))
            [void]$sb.AppendLine('<div class="table-scroll">')
            [void]$sb.AppendLine('<table class="waves">')
            [void]$sb.AppendLine('<thead><tr><th>Site collection</th><th class="num">Kinds</th><th>Blockers</th><th>Category</th></tr></thead>')
            [void]$sb.AppendLine('<tbody>')
            foreach ($readinessSite in $readiness.Site) {
                $readinessCategory = 0
                if ($null -ne $readinessSite.Category) { $readinessCategory = [int]$readinessSite.Category }
                $readinessCategoryName = if ($categoryMeta.Contains($readinessCategory)) { $categoryMeta[$readinessCategory].Name } else { [string]$readinessSite.CategoryName }
                $readinessSiteCell = if ($readinessSite.Title -and $readinessSite.Title -ne $readinessSite.Url) {
                    '<div class="site-title">{0}</div><div class="site-url">{1}</div>' -f (ConvertTo-SPSHtmlText -Value $readinessSite.Title), (ConvertTo-SPSHtmlText -Value $readinessSite.Url)
                }
                else {
                    '<div class="site-title">{0}</div>' -f (ConvertTo-SPSHtmlText -Value $readinessSite.Url)
                }
                $readinessPartial = if ($readinessSite.AssessmentStatus -eq 'Partial') { ' <span class="pill warn">Partial</span>' } else { '' }
                [void]$sb.AppendLine(('<tr><td>{0}</td><td class="num">{1}</td><td>{2}{3}</td><td><span class="badge b{4}">{5}</span></td></tr>' -f $readinessSiteCell, $readinessSite.Count, (ConvertTo-SPSHtmlText -Value $readinessSite.Text), $readinessPartial, $readinessCategory, (ConvertTo-SPSHtmlText -Value $readinessCategoryName)))
            }
            [void]$sb.AppendLine('</tbody>')
            [void]$sb.AppendLine('</table>')
            [void]$sb.AppendLine('</div>')
        }
    }

    # Migration wave plan.
    if ($waveKeys.Count -gt 0) {
        [void]$sb.AppendLine(('<h2 id="wave-plan">{0}</h2>' -f $waveHeading))
        [void]$sb.AppendLine('<div class="table-scroll">')
        [void]$sb.AppendLine('<table class="waves">')
        [void]$sb.AppendLine('<thead><tr><th>Wave</th><th>Name</th><th class="num">Sites</th><th class="num">Content (GB)</th><th class="num">Partial</th></tr></thead>')
        [void]$sb.AppendLine('<tbody>')
        foreach ($key in $waveKeys) {
            $agg = $waveAgg[$key]
            $waveLabel = if ($agg.Wave -eq 0) { '-' } else { [string]$agg.Wave }
            $partialLabel = if ($agg.PartialCount -gt 0) { [string]$agg.PartialCount } else { '-' }
            [void]$sb.AppendLine(('<tr><td class="num">{0}</td><td>{1}</td><td class="num">{2}</td><td class="num">{3}</td><td class="num">{4}</td></tr>' -f $waveLabel, (ConvertTo-SPSHtmlText -Value $agg.Name), $agg.Count, (ConvertTo-SPSHtmlText -Value (ConvertTo-SPSSizeText -SizeGB $agg.SizeGB)), $partialLabel))
        }
        [void]$sb.AppendLine('</tbody>')
        [void]$sb.AppendLine('</table>')
        [void]$sb.AppendLine('</div>')
    }

    # Inventory table: one compact row per site collection, worst first. Opening a row shows the
    # context of the site collection, the signals it raises and its assessment warnings, so the page
    # stays readable on a large farm. The CSV and JSON files keep every column.
    $inventoryRecords = @($taggedRecords | Sort-Object -Property `
        @{ Expression = { $sortCategory = 0; if ($null -ne $_.Record.Category) { $sortCategory = [int]$_.Record.Category }; if ($sortCategory -eq 0) { 5 } else { $sortCategory } }; Descending = $true },
        @{ Expression = { try { [double]$_.Record.Score } catch { 0.0 } }; Descending = $true },
        @{ Expression = { [string]$_.Record.Url } })
    $notAssessedCount = @($inventoryRecords | Where-Object { $null -eq $_.Record.Category -or [int]$_.Record.Category -eq 0 }).Count
    # The blocking reasons answer "why is this site blocking?", so the compact row shows them first.
    $orderReasons = {
        param([System.String]$Reasons)
        if ($Reasons -notmatch 'blocking: ') { return $Reasons }
        $parts = @($Reasons -split '; ')
        return ((@($parts | Where-Object { $_ -like 'blocking: *' }) + @($parts | Where-Object { $_ -notlike 'blocking: *' })) -join '; ')
    }
    $formatInventoryNumber = {
        param($Value)
        if ($null -eq $Value) { return '' }
        if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal] -or $Value -is [int] -or $Value -is [long]) {
            return ([System.IConvertible]$Value).ToString($invariant)
        }
        return [string]$Value
    }

    if (-not $splitReport) {
        [void]$sb.AppendLine('<h2 id="inventory-table">Site collections</h2>')
        [void]$sb.AppendLine('<p>Worst first. Open a row to see the context of the site collection, the signals it raises and its assessment warnings. The CSV and JSON files hold every column.</p>')
        [void]$sb.AppendLine('<div class="toolbar">')
        [void]$sb.AppendLine('<input type="search" id="inv-search" placeholder="Search site collections" aria-label="Search site collections">')
        [void]$sb.AppendLine('<div class="filters">')
        [void]$sb.AppendLine('<button data-filter="all" class="active">All</button>')
        foreach ($key in 1..4) {
            [void]$sb.AppendLine(('<button data-filter="{0}">{1}. {2}</button>' -f $key, $key, $categoryMeta[$key].Name))
        }
        if ($notAssessedCount -gt 0) {
            [void]$sb.AppendLine('<button data-filter="0">Not assessed</button>')
        }
        [void]$sb.AppendLine('</div>')
        [void]$sb.AppendLine('<button type="button" class="chip" id="inv-indicator" hidden></button>')
        [void]$sb.AppendLine(('<span class="count" id="inv-count">{0} of {0} shown</span>' -f $inventoryRecords.Count))
        [void]$sb.AppendLine('</div>')
    }

    $inventoryColumns = @(
        @{ Label = 'Site'; Type = 'text'; Class = '' }
        @{ Label = 'Category'; Type = 'num'; Class = '' }
        @{ Label = 'Score'; Type = 'num'; Class = 'num' }
        @{ Label = 'Wave'; Type = 'num'; Class = 'num' }
        @{ Label = 'Size (GB)'; Type = 'num'; Class = 'num' }
        @{ Label = 'Template'; Type = 'text'; Class = '' }
        @{ Label = 'Last modified'; Type = 'text'; Class = '' }
        @{ Label = 'Status'; Type = 'text'; Class = '' }
        @{ Label = 'Reasons'; Type = 'text'; Class = '' }
    )
    $tableOpen = [System.Text.StringBuilder]::new()
    [void]$tableOpen.AppendLine('<div class="table-scroll">')
    [void]$tableOpen.AppendLine('<table id="inv">')
    [void]$tableOpen.AppendLine('<thead><tr>')
    [void]$tableOpen.AppendLine('<th class="tgl"></th>')
    foreach ($col in $inventoryColumns) {
        $thClass = if ($col.Class -eq 'num') { ' class="num"' } else { '' }
        [void]$tableOpen.AppendLine(('<th{0} data-type="{1}">{2} <span class="arrow"></span></th>' -f $thClass, $col.Type, (ConvertTo-SPSHtmlText -Value $col.Label)))
    }
    [void]$tableOpen.AppendLine('</tr></thead>')
    $tableClose = ('</table>{0}</div>{0}' -f [System.Environment]::NewLine)

    # One entry per site collection: its category, the indicators that it raises and its rows. The single
    # report puts them all in one table, a split one distributes them to its table pages.
    $rowEntries = [System.Collections.Generic.List[System.Object]]::new()
    foreach ($item in $inventoryRecords) {
        $row = [System.Text.StringBuilder]::new()
        $rowTags = @($item.Tags)
        $record = $item.Record
        $cat = 0
        if ($null -ne $record.Category) { $cat = [int]$record.Category }
        $catName = if ($categoryMeta.Contains($cat)) { $categoryMeta[$cat].Name } elseif ($record.CategoryName) { [string]$record.CategoryName } else { '' }
        $url = [string]$record.Url
        $title = [string]$record.Title
        $statusText = [string]$record.AssessmentStatus
        $warningsText = [string]$record.AssessmentWarnings
        # The reasons end with the assessment warnings, which have their own box in the details: do not
        # show them twice. A row that has warnings only, such as a failed web application, shows them.
        $reasonsText = [string]$record.Reasons
        if ($warningsText -and $reasonsText.Contains($warningsText)) {
            $reasonsText = $reasonsText.Replace($warningsText, '').Trim().TrimEnd(';').Trim()
        }
        $reasonsCell = if ($reasonsText) { $reasonsText } else { $warningsText }

        $siteCell = if ([string]$record.InventoryScope -eq 'WebApplication') {
            '<div class="site-title"><span class="pill no">Web application</span></div><div class="site-url">{0}</div>' -f (ConvertTo-SPSHtmlText -Value $url)
        }
        elseif ($title -and $title -ne $url) {
            '<div class="site-title">{0}</div><div class="site-url">{1}</div>' -f (ConvertTo-SPSHtmlText -Value $title), (ConvertTo-SPSHtmlText -Value $url)
        }
        else {
            '<div class="site-title">{0}</div>' -f (ConvertTo-SPSHtmlText -Value $url)
        }
        $statusCell = switch ($statusText) {
            'Partial' { '<span class="pill warn">Partial</span>' }
            'Failed' { '<span class="pill yes">Failed</span>' }
            default { '<span class="muted">{0}</span>' -f (ConvertTo-SPSHtmlText -Value $statusText) }
        }
        $modified = $record.LastModified
        if ($modified -is [datetime]) { $modified = $modified.ToString('yyyy-MM-dd') }
        $waveText = if ($null -ne $record.Wave -and [int]$record.Wave -ne 0) { [string][int]$record.Wave } else { '-' }

        $indicatorAttribute = if ($item.Tags.Count -gt 0) { ' data-ind="{0}"' -f ($item.Tags -join ' ') } else { '' }
        [void]$row.AppendLine(('<tbody class="site" data-category="{0}"{1}>' -f $cat, $indicatorAttribute))
        [void]$row.AppendLine('<tr class="main">')
        [void]$row.AppendLine('<td class="tgl"><button type="button" class="toggle" aria-expanded="false" aria-label="Show the details of this site collection" title="Show details"></button></td>')
        [void]$row.AppendLine(('<td class="site-cell" data-sort="{0}">{1}</td>' -f (ConvertTo-SPSHtmlText -Value $url.ToLowerInvariant()), $siteCell))
        [void]$row.AppendLine(('<td data-sort="{0}"><span class="badge b{0}">{1}</span></td>' -f $cat, (ConvertTo-SPSHtmlText -Value $catName)))
        [void]$row.AppendLine(('<td class="num">{0}</td>' -f (ConvertTo-SPSHtmlText -Value (& $formatInventoryNumber $record.Score))))
        [void]$row.AppendLine(('<td class="num">{0}</td>' -f $waveText))
        [void]$row.AppendLine(('<td class="num">{0}</td>' -f (ConvertTo-SPSHtmlText -Value (& $formatInventoryNumber $record.SizeGB))))
        [void]$row.AppendLine(('<td class="tpl">{0}</td>' -f (ConvertTo-SPSHtmlText -Value $record.Template)))
        [void]$row.AppendLine(('<td>{0}</td>' -f (ConvertTo-SPSHtmlText -Value $modified)))
        [void]$row.AppendLine(('<td>{0}</td>' -f $statusCell))
        [void]$row.AppendLine(('<td class="reasons"><div class="clamp">{0}</div></td>' -f (ConvertTo-SPSHtmlText -Value (& $orderReasons $reasonsCell))))
        [void]$row.AppendLine('</tr>')

        $contextParts = [System.Collections.Generic.List[string]]::new()
        $webApplicationName = if ($record.WebApp) { [string]$record.WebApp } else { [string]$record.WebAppUrl }
        $templateLanguage = if ($record.TemplateLanguageTag) { [string]$record.TemplateLanguageTag } else { [string]$record.TemplateLanguageName }
        $webCount = if ($null -ne $record.SubWebCount) { [string]$record.SubWebCount } else { '' }
        foreach ($item in @(
                @{ Label = 'Web application'; Value = $webApplicationName }
                @{ Label = 'Content database'; Value = [string]$record.ContentDb }
                @{ Label = 'Authentication'; Value = [string]$record.AuthenticationModes }
                @{ Label = 'Template language'; Value = $templateLanguage }
                @{ Label = 'Webs'; Value = $webCount }
            )) {
            if (-not [string]::IsNullOrWhiteSpace($item.Value)) {
                $contextParts.Add(('{0} <strong>{1}</strong>' -f $item.Label, (ConvertTo-SPSHtmlText -Value $item.Value)))
            }
        }
        $contentTypeCount = ConvertTo-SPSSignalNumber -Value $record.ContentTypeCount
        $contentTypeBindingCount = ConvertTo-SPSSignalNumber -Value $record.ListContentTypeBindingCount
        if ($contentTypeCount -gt 0 -or $contentTypeBindingCount -gt 0) {
            $contextParts.Add(('Content types <strong>{0}</strong> definition(s), <strong>{1}</strong> list binding(s)' -f $contentTypeCount.ToString($invariant), $contentTypeBindingCount.ToString($invariant)))
        }

        $detail = [System.Text.StringBuilder]::new()
        if ($contextParts.Count -gt 0) {
            [void]$detail.Append(('<div class="ctx">{0}</div>' -f ($contextParts -join ' &middot; ')))
        }
        $signals = @(Get-SPSInventorySiteSignal -Record $record)
        if ($signals.Count -gt 0) {
            [void]$detail.Append('<dl class="signals">')
            foreach ($signal in $signals) {
                $valueHtml = if ($signal.Value) { '<span class="sig-value">{0}</span>' -f (ConvertTo-SPSHtmlText -Value $signal.Value) } else { '' }
                $detailHtml = if ($signal.Detail) { ' <span class="sig-detail">{0}</span>' -f (ConvertTo-SPSHtmlText -Value $signal.Detail) } else { '' }
                [void]$detail.Append(('<dt>{0}</dt><dd>{1}{2}</dd>' -f (ConvertTo-SPSHtmlText -Value $signal.Label), $valueHtml, $detailHtml))
            }
            [void]$detail.Append('</dl>')
        }
        elseif ($statusText -ne 'Failed') {
            [void]$detail.Append('<p class="muted">No signal raised.</p>')
        }
        if ($warningsText) {
            [void]$detail.Append(('<div class="note warn"><strong>Assessment warnings</strong> {0}</div>' -f (ConvertTo-SPSHtmlText -Value $warningsText)))
        }
        if ($reasonsText) {
            [void]$detail.Append(('<div class="note"><strong>Reasons</strong> {0}</div>' -f (ConvertTo-SPSHtmlText -Value $reasonsText)))
        }
        [void]$row.AppendLine(('<tr class="detail"><td></td><td colspan="9">{0}</td></tr>' -f $detail.ToString()))
        [void]$row.AppendLine('</tbody>')
        $rowEntries.Add([PSCustomObject]@{ Category = $cat; Tags = $rowTags; Html = $row.ToString() })
    }

    $tablePage = [System.Collections.Generic.List[System.Object]]::new()
    $bucketList = [System.Collections.Generic.List[System.Object]]::new()
    $indicatorPage = @{}
    if (-not $splitReport) {
        [void]$sb.Append($tableOpen.ToString())
        foreach ($rowEntry in $rowEntries) {
            [void]$sb.Append($rowEntry.Html)
        }
        [void]$sb.Append($tableClose)
    }
    else {
        # The site collections of a category are on consecutive pages, worst category first. The rows are already
        # in that order, so a category is a run of them.
        $bucketOrder = [System.Collections.Generic.List[System.Int32]]::new()
        $bucketRows = @{}
        foreach ($rowEntry in $rowEntries) {
            $bucketId = [System.Int32]$rowEntry.Category
            if (-not $bucketRows.ContainsKey($bucketId)) {
                $bucketOrder.Add($bucketId)
                $bucketRows[$bucketId] = [System.Collections.Generic.List[System.Object]]::new()
            }
            $bucketRows[$bucketId].Add($rowEntry)
        }
        foreach ($bucketId in $bucketOrder) {
            $rows = $bucketRows[$bucketId]
            $bucketSlug = if ($bucketId -eq 0) { 'not-assessed' } elseif ($categoryMeta.Contains($bucketId)) { $categoryMeta[$bucketId].Slug } else { 'category-{0}' -f $bucketId }
            $bucketLabel = if ($bucketId -eq 0) { 'Not assessed' } elseif ($categoryMeta.Contains($bucketId)) { '{0}. {1}' -f $bucketId, $categoryMeta[$bucketId].Name } else { 'Category {0}' -f $bucketId }
            $pageCount = [int][math]::Ceiling($rows.Count / $RowsPerPage)
            $bucketPages = [System.Collections.Generic.List[System.Object]]::new()
            for ($number = 1; $number -le $pageCount; $number++) {
                $start = ($number - 1) * $RowsPerPage
                $page = [PSCustomObject]@{
                    Bucket = $bucketId
                    BucketLabel = $bucketLabel
                    BucketCount = $rows.Count
                    Number = $number
                    Of = $pageCount
                    Name = '{0}-sites-{1}-{2}.html' -f $pageBaseName, $bucketSlug, $number
                    Entries = $rows.GetRange($start, [math]::Min($RowsPerPage, $rows.Count - $start))
                    Pages = $bucketPages
                }
                $bucketPages.Add($page)
                $tablePage.Add($page)
            }
            $bucketList.Add([PSCustomObject]@{ Id = $bucketId; Label = $bucketLabel; Count = $rows.Count; Pages = $bucketPages })
        }

        # The pages that have a site collection that raises each indicator, so that an indicator opens the first of them
        # and a page links to the previous and the next one.
        for ($index = 0; $index -lt $tablePage.Count; $index++) {
            $seen = [System.Collections.Generic.HashSet[System.String]]::new()
            foreach ($rowEntry in $tablePage[$index].Entries) {
                foreach ($tag in $rowEntry.Tags) {
                    [void]$seen.Add($tag)
                }
            }
            foreach ($tag in $seen) {
                if (-not $indicatorPage.ContainsKey($tag)) {
                    $indicatorPage[$tag] = [System.Collections.Generic.List[System.Int32]]::new()
                }
                $indicatorPage[$tag].Add($index)
            }
        }

        [void]$sb.AppendLine('<h2 id="inventory-table">Site collections</h2>')
        [void]$sb.AppendLine(('<p>This report has <strong>{0}</strong> site collections, more than the {1} that one page shows well, so the table is split in <strong>{2}</strong> pages, by category, worst first. Open a page to search it, to sort it and to open the details of its site collections. A risk indicator above opens the first page that has a site collection that raises it, with the filter on, and that page links to the next ones. The CSV and JSON files hold every column.</p>' -f $total, $SplitThreshold, $tablePage.Count))
        [void]$sb.AppendLine('<div class="table-scroll">')
        [void]$sb.AppendLine('<table class="waves">')
        [void]$sb.AppendLine('<thead><tr><th>Category</th><th class="num">Site collections</th><th>Pages</th></tr></thead>')
        [void]$sb.AppendLine('<tbody>')
        foreach ($bucket in $bucketList) {
            $pageLinks = @($bucket.Pages | ForEach-Object { '<a href="{0}">{1}</a>' -f [System.Uri]::EscapeDataString($_.Name), $_.Number })
            [void]$sb.AppendLine(('<tr><td>{0}</td><td class="num">{1}</td><td>{2}</td></tr>' -f (ConvertTo-SPSHtmlText -Value $bucket.Label), $bucket.Count, ($pageLinks -join ' ')))
        }
        [void]$sb.AppendLine('</tbody>')
        [void]$sb.AppendLine('</table>')
        [void]$sb.AppendLine('</div>')
    }

    $limitNote = {
        param([System.Int32]$Total, [System.String]$Files)
        if ($Total -le $MaxDetailRow) { return '' }
        return ('<p class="muted">Showing the first {0} of {1} rows. {2} hold all the rows.</p>' -f $MaxDetailRow, $Total, $Files)
    }

    # Farm solutions (WSP) section.
    if ($solutions.Count -gt 0) {
        $solTotal = $solutions.Count
        $solCustom = @($solutions | Where-Object { $_.IsCustom }).Count
        $solFullTrust = @($solutions | Where-Object { $_.IsFullTrustCode }).Count
        $solWebApp = @($solutions | Where-Object { $_.ContainsWebApplicationResource }).Count

        [void]$sb.AppendLine('<h2 id="farm-solutions">Farm solutions (WSP)</h2>')
        [void]$sb.AppendLine('<div class="summary">')
        [void]$sb.AppendLine(('<div class="summary-total"><strong>{0}</strong> farm solution(s) &middot; <strong>{1}</strong> custom &middot; <strong>{2}</strong> full-trust code</div>' -f $solTotal, $solCustom, $solFullTrust))
        [void]$sb.AppendLine('<div class="cards">')
        [void]$sb.AppendLine(('<div class="card plain"><div class="num">{0}</div><div class="lbl">Solutions (WSP)</div></div>' -f $solTotal))
        [void]$sb.AppendLine(('<div class="card custom"><div class="num">{0}</div><div class="lbl">Custom / in-house</div></div>' -f $solCustom))
        [void]$sb.AppendLine(('<div class="card wsp"><div class="num">{0}</div><div class="lbl">Full-trust code (GAC)</div></div>' -f $solFullTrust))
        [void]$sb.AppendLine(('<div class="card wsp"><div class="num">{0}</div><div class="lbl">Web-app resource</div></div>' -f $solWebApp))
        [void]$sb.AppendLine('</div>')
        [void]$sb.AppendLine('</div>')

        [void]$sb.AppendLine('<div class="table-scroll">')
        [void]$sb.AppendLine('<table class="solutions">')
        [void]$sb.AppendLine('<thead><tr><th>Solution (WSP)</th><th>Deployed</th><th>Custom</th><th>Full-trust code</th><th>CAS policy</th><th>Web-app resource</th><th class="num">Features</th><th>Scopes</th></tr></thead>')
        [void]$sb.AppendLine('<tbody>')
        foreach ($solution in @($solutions | Sort-Object -Property @{ E = { [bool]$_.IsFullTrustCode }; Descending = $true }, @{ E = { [bool]$_.IsCustom }; Descending = $true }, @{ E = { [string]$_.SolutionName } } | Select-Object -First $MaxDetailRow)) {
            $deployed = if ($solution.DeploymentState) { [string]$solution.DeploymentState } elseif ($solution.Deployed) { 'Deployed' } else { 'NotDeployed' }
            $scopes = (@($solution.FeatureScopes) -join '; ')
            $featureCount = if ($null -ne $solution.FeatureCount) { [int]$solution.FeatureCount } else { 0 }
            [void]$sb.AppendLine(('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td><td class="num">{6}</td><td class="muted">{7}</td></tr>' -f `
                (ConvertTo-SPSHtmlText -Value $solution.SolutionName),
                (ConvertTo-SPSHtmlText -Value $deployed),
                (Get-SPSYesNoPill -Value $solution.IsCustom),
                (Get-SPSYesNoPill -Value $solution.IsFullTrustCode),
                (Get-SPSYesNoPill -Value $solution.ContainsCasPolicy -TruePill 'warn'),
                (Get-SPSYesNoPill -Value $solution.ContainsWebApplicationResource),
                $featureCount,
                (ConvertTo-SPSHtmlText -Value $scopes)))
        }
        [void]$sb.AppendLine('</tbody>')
        [void]$sb.AppendLine('</table>')
        [void]$sb.AppendLine('</div>')
        [void]$sb.AppendLine((& $limitNote $solutions.Count 'The farm solutions CSV and JSON files'))

        # Sites bound to full-trust code: link the farm-level finding to the affected
        # sites so a reader can jump from "there is custom full-trust code" to "these are
        # the sites that use it".
        $fullTrustSites = @($records | Where-Object { $_.UsesFullTrustCode })
        if ($fullTrustSites.Count -gt 0) {
            [void]$sb.AppendLine('<h2>Sites bound to full-trust code</h2>')
            [void]$sb.AppendLine('<div class="table-scroll">')
            [void]$sb.AppendLine('<table class="fulltrust">')
            [void]$sb.AppendLine('<thead><tr><th>Site</th><th>Full-trust code</th><th>Category</th><th class="num">Wave</th><th>Reasons</th></tr></thead>')
            [void]$sb.AppendLine('<tbody>')
            foreach ($site in @($fullTrustSites | Select-Object -First $MaxDetailRow)) {
                $cat = if ($null -ne $site.Category) { [int]$site.Category } else { 0 }
                $catName = if ($categoryMeta.Contains($cat)) { $categoryMeta[$cat].Name } elseif ($site.CategoryName) { [string]$site.CategoryName } else { '' }
                $waveLabel = if ($null -ne $site.Wave) { [string]$site.Wave } else { '' }
                [void]$sb.AppendLine(('<tr><td class="url">{0}</td><td>{1}</td><td><span class="badge b{2}">{3}</span></td><td class="num">{4}</td><td class="reasons">{5}</td></tr>' -f `
                    (ConvertTo-SPSHtmlText -Value $site.Url),
                    (Get-SPSYesNoPill -Value $site.UsesFullTrustCode),
                    $cat,
                    (ConvertTo-SPSHtmlText -Value $catName),
                    (ConvertTo-SPSHtmlText -Value $waveLabel),
                    (ConvertTo-SPSHtmlText -Value $site.Reasons)))
            }
            [void]$sb.AppendLine('</tbody>')
            [void]$sb.AppendLine('</table>')
            [void]$sb.AppendLine('</div>')
            [void]$sb.AppendLine((& $limitNote $fullTrustSites.Count 'The main CSV and JSON files'))
        }
    }

    if ($authenticationRecords.Count -gt 0) {
        [void]$sb.AppendLine('<h2 id="authentication">Web application authentication</h2>')
        [void]$sb.AppendLine('<p>Configured providers across all zones, not actual user sign-in activity. FBA requires identity/authentication remediation for SharePoint Online. Categories follow your configured blocking rules.</p>')
        [void]$sb.AppendLine('<div class="table-scroll"><table class="authentication">')
        [void]$sb.AppendLine('<thead><tr><th>Web application</th><th>Zones and providers</th><th>FBA configured</th><th>Identity review</th><th class="num">Collections</th></tr></thead><tbody>')
        foreach ($group in ($authenticationRecords | Group-Object -Property WebAppUrl, AuthenticationZones)) {
            $site = $group.Group[0]
            $collectionCount = @($group.Group | Where-Object { $_.InventoryScope -ne 'WebApplication' }).Count
            $fba = if ($null -eq $site.HasFbaZone) { 'Unknown' } else { Get-SPSYesNoPill -Value $site.HasFbaZone -TruePill 'warn' }
            [void]$sb.AppendLine(('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td class="num">{4}</td></tr>' -f
                (ConvertTo-SPSHtmlText -Value $site.WebAppUrl),
                (ConvertTo-SPSHtmlText -Value $site.AuthenticationZones),
                $fba,
                (Get-SPSYesNoPill -Value $site.AuthenticationReviewRequired -TruePill 'warn'),
                $collectionCount))
        }
        [void]$sb.AppendLine('</tbody></table></div>')
    }

    if ($policyRecords.Count -gt 0) {
        [void]$sb.AppendLine('<h2 id="web-app-policies">Web application policies</h2>')
        [void]$sb.AppendLine('<p>Policies grant or deny permissions across a whole web application and override site-level permissions; they are not migrated to SharePoint Online. They include accounts SharePoint adds itself, such as the farm and search crawl accounts. SharePoint Online enforces Strict browser file handling, so .htm and .html files in a Permissive web application prompt a download after migration.</p>')
        [void]$sb.AppendLine('<div class="table-scroll"><table class="web-app-policies">')
        [void]$sb.AppendLine('<thead><tr><th>Web application</th><th>Browser file handling</th><th class="num">Policies</th><th>Policy examples</th><th class="num">Collections</th></tr></thead><tbody>')
        foreach ($group in ($policyRecords | Group-Object -Property WebAppUrl)) {
            $webAppRecord = $group.Group[0]
            $collectionCount = @($group.Group | Where-Object { $_.InventoryScope -ne 'WebApplication' }).Count
            $handling = if ([string]$webAppRecord.BrowserFileHandling -eq 'Permissive') {
                '<span class="pill warn">Permissive</span>'
            }
            else {
                ConvertTo-SPSHtmlText -Value $webAppRecord.BrowserFileHandling
            }
            [void]$sb.AppendLine(('<tr><td>{0}</td><td>{1}</td><td class="num">{2}</td><td class="reasons">{3}</td><td class="num">{4}</td></tr>' -f
                (ConvertTo-SPSHtmlText -Value $webAppRecord.WebAppUrl),
                $handling,
                (ConvertTo-SPSHtmlText -Value $webAppRecord.WebAppPolicyCount),
                (ConvertTo-SPSHtmlText -Value $webAppRecord.WebAppPolicyExamples),
                $collectionCount))
        }
        [void]$sb.AppendLine('</tbody></table></div>')
    }

    if ($hasContentTypeSection) {
        $partialSites = @($siteRecords | Where-Object { $_.ContentTypeInventoryComplete -eq $false })
        $webDefinitionCount = @($ContentTypes | Where-Object { [string]$_.Scope -eq 'Web' }).Count
        $listBindingCount = @($ContentTypes | Where-Object { [string]$_.Scope -eq 'List' }).Count
        $contentTypeSiteCount = @($ContentTypes | ForEach-Object { [string]$_.SiteUrl } | Sort-Object -Unique).Count
        [void]$sb.AppendLine('<h2 id="content-types">Content types and list bindings</h2>')
        [void]$sb.AppendLine(('<p><strong>{0}</strong> definition/binding row(s): <strong>{1}</strong> web definition(s) and <strong>{2}</strong> list binding(s), in <strong>{3}</strong> site collection(s). Standard types are included; presence alone is not a migration blocker. List bindings are not item counts or distinct business designs.</p>' -f $ContentTypes.Count, $webDefinitionCount, $listBindingCount, $contentTypeSiteCount))
        [void]$sb.AppendLine('<p class="muted">The rows are not listed here, because there are too many to read in a page: the content types CSV and JSON files hold every one of them, with the IDs, parent IDs, fields and document templates. The number of content types and bindings of each site collection is in its row of the inventory table.</p>')
        if ($enumerationFailureCount -gt 0) {
            [void]$sb.AppendLine(('<p><strong>Coverage warning:</strong> {0} web application(s) had site collection enumeration failures; content-type results do not cover those scopes.</p>' -f $enumerationFailureCount))
        }
        if ($partialSites.Count -gt 0) {
            [void]$sb.AppendLine(('<p><strong>Partial collection:</strong> {0} site collection(s). Counts are lower bounds; consult ContentTypeInventoryComplete and the run warnings.</p>' -f $partialSites.Count))
        }
    }

    if ($hasManagedMetadataSection) {
        $incompleteSites = @($siteRecords | Where-Object { $_.CustomizationInventoryComplete -eq $false })
        [void]$sb.AppendLine('<h2 id="managed-metadata">Managed metadata columns by list</h2>')
        [void]$sb.AppendLine(('<p><strong>{0}</strong> list(s) with managed metadata columns. These columns take their values from the term store: they usually migrate with the list, but the term sets they use must be migrated too. Plan the term store migration together with these lists, and verify afterwards that items can be created and edited. Hidden columns and hidden lists, such as the newsfeed list, are not listed, and term sets are shown by ID, not by name; resolve them in the Term Store Management Tool.</p>' -f $ManagedMetadataLists.Count))
        if ($enumerationFailureCount -gt 0) {
            [void]$sb.AppendLine(('<p><strong>Coverage warning:</strong> {0} web application(s) had site collection enumeration failures; managed metadata results do not cover those scopes.</p>' -f $enumerationFailureCount))
        }
        if ($incompleteSites.Count -gt 0) {
            [void]$sb.AppendLine(('<p><strong>Partial collection:</strong> {0} site collection(s) have an incomplete customization inventory. Rows are a lower bound; consult CustomizationInventoryComplete and the run warnings.</p>' -f $incompleteSites.Count))
        }
        [void]$sb.AppendLine('<div class="table-scroll"><table class="managedmetadata">')
        $managedMetadataColumns = @(
            @{ Key = 'SiteUrl'; Label = 'Site' }
            @{ Key = 'WebUrl'; Label = 'Web' }
            @{ Key = 'ListTitle'; Label = 'List' }
            @{ Key = 'ListUrl'; Label = 'List URL' }
            @{ Key = 'ListTemplate'; Label = 'Template' }
            @{ Key = 'ListType'; Label = 'Type' }
            @{ Key = 'ListItemCount'; Label = 'Items' }
            @{ Key = 'ItemLastModifiedDate'; Label = 'Last modified' }
            @{ Key = 'ManagedMetadataColumnCount'; Label = 'Columns' }
            @{ Key = 'ManagedMetadataColumns'; Label = 'Managed metadata columns' }
            @{ Key = 'TermSetIds'; Label = 'Term set IDs' }
        )
        [void]$sb.AppendLine('<thead><tr>')
        foreach ($column in $managedMetadataColumns) {
            [void]$sb.AppendLine(('<th>{0}</th>' -f $column.Label))
        }
        [void]$sb.AppendLine('</tr></thead><tbody>')
        foreach ($managedMetadataList in @($ManagedMetadataLists | Select-Object -First $MaxDetailRow)) {
            [void]$sb.AppendLine('<tr>')
            foreach ($column in $managedMetadataColumns) {
                [void]$sb.AppendLine(('<td>{0}</td>' -f (ConvertTo-SPSHtmlText -Value $managedMetadataList.($column.Key))))
            }
            [void]$sb.AppendLine('</tr>')
        }
        [void]$sb.AppendLine('</tbody></table></div>')
        [void]$sb.AppendLine((& $limitNote $ManagedMetadataLists.Count 'The managed metadata CSV and JSON files'))
    }

    if ($hasExternalListSection) {
        $incompleteSites = @($siteRecords | Where-Object { $_.CustomizationInventoryComplete -eq $false })
        [void]$sb.AppendLine('<h2 id="external-lists">External lists</h2>')
        [void]$sb.AppendLine(('<p><strong>{0}</strong> external list(s). They are backed by Business Connectivity Services (BCS) external content types, so their items stay in the external system. Microsoft retired BCS in SharePoint Online on 30 September 2024, so these lists cannot be recreated there and there is no direct migration. Plan a replacement for each scenario, for example with Power Apps and its connectors (the on-premises data gateway reaches on-premises data). BCS is not retired in SharePoint Server Subscription Edition. Item counts and dates are not collected because the items are not stored in SharePoint.</p>' -f $ExternalLists.Count))
        if ($enumerationFailureCount -gt 0) {
            [void]$sb.AppendLine(('<p><strong>Coverage warning:</strong> {0} web application(s) had site collection enumeration failures; external list results do not cover those scopes.</p>' -f $enumerationFailureCount))
        }
        if ($incompleteSites.Count -gt 0) {
            [void]$sb.AppendLine(('<p><strong>Partial collection:</strong> {0} site collection(s) have an incomplete customization inventory. Rows are a lower bound; consult CustomizationInventoryComplete and the run warnings.</p>' -f $incompleteSites.Count))
        }
        [void]$sb.AppendLine('<div class="table-scroll"><table class="externallists">')
        $externalListColumns = @(
            @{ Key = 'SiteUrl'; Label = 'Site' }
            @{ Key = 'WebUrl'; Label = 'Web' }
            @{ Key = 'ListTitle'; Label = 'List' }
            @{ Key = 'ListUrl'; Label = 'List URL' }
            @{ Key = 'LobSystemInstance'; Label = 'LOB system instance' }
            @{ Key = 'EntityNamespace'; Label = 'Entity namespace' }
            @{ Key = 'Entity'; Label = 'Entity' }
        )
        [void]$sb.AppendLine('<thead><tr>')
        foreach ($column in $externalListColumns) {
            [void]$sb.AppendLine(('<th>{0}</th>' -f $column.Label))
        }
        [void]$sb.AppendLine('</tr></thead><tbody>')
        foreach ($externalList in @($ExternalLists | Select-Object -First $MaxDetailRow)) {
            [void]$sb.AppendLine('<tr>')
            foreach ($column in $externalListColumns) {
                [void]$sb.AppendLine(('<td>{0}</td>' -f (ConvertTo-SPSHtmlText -Value $externalList.($column.Key))))
            }
            [void]$sb.AppendLine('</tr>')
        }
        [void]$sb.AppendLine('</tbody></table></div>')
        [void]$sb.AppendLine((& $limitNote $ExternalLists.Count 'The external lists CSV and JSON files'))
    }

    if ($hasBcsSection) {
        [void]$sb.AppendLine('<h2 id="bcs-applications">Business Connectivity Services applications</h2>')
        [void]$sb.AppendLine(('<p><strong>{0}</strong> BCS LOB system(s). BCS is retired in SharePoint Online (30 September 2024), so BCS applications cannot be migrated there and need a replacement for each external system, for example Power Apps and its connectors. BCS is not retired in SharePoint Server Subscription Edition. Instances are the connections external lists use; match them with the LOB system instance of the external lists. Connection settings, credentials and Secure Store targets are not read.</p>' -f $BcsApplications.Count))
        if (-not $BcsInventoryComplete) {
            [void]$sb.AppendLine('<p><strong>Partial collection:</strong> some web applications or LOB systems could not be read, so BCS applications may be missing. Consult the run warnings.</p>')
        }
        [void]$sb.AppendLine('<div class="table-scroll"><table class="bcsapplications">')
        $bcsColumns = @(
            @{ Key = 'WebApplicationUrls'; Label = 'Web application' }
            @{ Key = 'BdcServiceApplicationId'; Label = 'BDC service application' }
            @{ Key = 'LobSystemName'; Label = 'LOB system' }
            @{ Key = 'LobSystemType'; Label = 'Type' }
            @{ Key = 'LobSystemInstances'; Label = 'Instances' }
            @{ Key = 'EntityCount'; Label = 'Entities' }
            @{ Key = 'LobEntities'; Label = 'Entity names' }
        )
        [void]$sb.AppendLine('<thead><tr>')
        foreach ($column in $bcsColumns) {
            [void]$sb.AppendLine(('<th>{0}</th>' -f $column.Label))
        }
        [void]$sb.AppendLine('</tr></thead><tbody>')
        foreach ($bcsApplication in @($BcsApplications | Select-Object -First $MaxDetailRow)) {
            [void]$sb.AppendLine('<tr>')
            foreach ($column in $bcsColumns) {
                [void]$sb.AppendLine(('<td>{0}</td>' -f (ConvertTo-SPSHtmlText -Value $bcsApplication.($column.Key))))
            }
            [void]$sb.AppendLine('</tr>')
        }
        [void]$sb.AppendLine('</tbody></table></div>')
        [void]$sb.AppendLine((& $limitNote $BcsApplications.Count 'The BCS CSV and JSON files'))
    }

    if ($hasSecureStoreSection) {
        [void]$sb.AppendLine('<h2 id="secure-store-applications">Secure Store applications</h2>')
        [void]$sb.AppendLine(('<p><strong>{0}</strong> Secure Store target application(s). A target application maps the identity of a user or a group to the credentials of an external system, for example for a BCS external list or an Excel Services data connection. Secure Store applications are not migrated to SharePoint Online: decide with the owners of the solutions that use them which ones are still needed, and create those again in the target, where only the Group Restricted type is supported. Credentials are not read, and the contact e-mail address of each application, which is personal data, is in the CSV and JSON files only.</p>' -f $SecureStoreApplications.Count))
        if (-not $SecureStoreInventoryComplete) {
            [void]$sb.AppendLine('<p><strong>Partial collection:</strong> some web applications or target applications could not be read, so Secure Store applications may be missing. Consult the run warnings.</p>')
        }
        [void]$sb.AppendLine('<div class="table-scroll"><table class="securestoreapplications">')
        $secureStoreColumns = @(
            @{ Key = 'WebApplicationUrls'; Label = 'Web application' }
            @{ Key = 'SecureStoreProxyName'; Label = 'Secure Store proxy' }
            @{ Key = 'Name'; Label = 'Target application ID' }
            @{ Key = 'FriendlyName'; Label = 'Display name' }
            @{ Key = 'ApplicationType'; Label = 'Type' }
            @{ Key = 'CredentialManagementUrl'; Label = 'Credential management URL' }
            @{ Key = 'TicketTimeoutMinutes'; Label = 'Ticket time-out (minutes)' }
        )
        [void]$sb.AppendLine('<thead><tr>')
        foreach ($column in $secureStoreColumns) {
            [void]$sb.AppendLine(('<th>{0}</th>' -f $column.Label))
        }
        [void]$sb.AppendLine('</tr></thead><tbody>')
        foreach ($secureStoreApplication in @($SecureStoreApplications | Select-Object -First $MaxDetailRow)) {
            [void]$sb.AppendLine('<tr>')
            foreach ($column in $secureStoreColumns) {
                [void]$sb.AppendLine(('<td>{0}</td>' -f (ConvertTo-SPSHtmlText -Value $secureStoreApplication.($column.Key))))
            }
            [void]$sb.AppendLine('</tr>')
        }
        [void]$sb.AppendLine('</tbody></table></div>')
        [void]$sb.AppendLine((& $limitNote $SecureStoreApplications.Count 'The Secure Store CSV and JSON files'))
    }

    if ($hasProfileMappingSection) {
        $customMappingCount = @($ProfilePropertyMappings | Where-Object { $null -ne $_ -and -not [bool]$_.SynchronizedInSharePointOnline -and $_.BuiltInProperty -ne $true }).Count
        # A row with no BuiltInProperty comes from a run that could not read the properties that SharePoint ships: it is not known to be custom.
        $unknownShippedCount = @($ProfilePropertyMappings | Where-Object { $null -ne $_ -and -not [bool]$_.SynchronizedInSharePointOnline -and $null -eq $_.BuiltInProperty }).Count
        $shippedWording = if ($unknownShippedCount -gt 0) { 'that is not known to be one that SharePoint ships (the list of those could not be read)' } else { 'that SharePoint does not ship' }
        [void]$sb.AppendLine('<h2 id="profile-property-mappings">User profile property mappings</h2>')
        [void]$sb.AppendLine(('<p><strong>{0}</strong> profile property mapping(s), <strong>{1}</strong> of them for a property that SharePoint Online does not fill and {2}. A profile property mapping ties a property to an attribute of a data source, such as Active Directory, to fill it in or to export it. SharePoint Online fills a fixed set of properties from Microsoft Entra ID and cannot be given other mappings: a value that is still needed has to be pushed into the profiles by a program of your own, for example with CSOM. The mappings of the properties that SharePoint ships and SharePoint Online does not fill, such as the Phonetic Search properties, are listed too and need nothing unless something relies on them. The custom mappings come first; the number of profiles is what the User Profile service reports for the property.</p>' -f $ProfilePropertyMappings.Count, $customMappingCount, $shippedWording))
        if (-not $ProfileInventoryComplete) {
            [void]$sb.AppendLine('<p><strong>Partial collection:</strong> some web applications, connections, mappings or property lists could not be read, so mappings may be missing or called custom by mistake. Consult the run warnings.</p>')
        }
        [void]$sb.AppendLine('<div class="table-scroll"><table class="profilemappings">')
        $profileMappingColumns = @(
            @{ Key = 'ConnectionName'; Label = 'Connection' }
            @{ Key = 'ConnectionType'; Label = 'Type' }
            @{ Key = 'PropertyName'; Label = 'Property' }
            @{ Key = 'PropertyDisplayName'; Label = 'Display name' }
            @{ Key = 'PropertyMapping'; Label = 'Mapped to' }
            @{ Key = 'Direction'; Label = 'Direction' }
            @{ Key = 'PropertyLength'; Label = 'Length' }
            @{ Key = 'PropertyUsage'; Label = 'Profiles' }
            @{ Key = 'SynchronizedInSharePointOnline'; Label = 'Filled by SharePoint Online' }
            @{ Key = 'BuiltInProperty'; Label = 'Shipped by SharePoint' }
        )
        [void]$sb.AppendLine('<thead><tr>')
        foreach ($column in $profileMappingColumns) {
            [void]$sb.AppendLine(('<th>{0}</th>' -f $column.Label))
        }
        [void]$sb.AppendLine('</tr></thead><tbody>')
        # The mappings that need a decision come first, and the order of each group is the one of the files.
        $shownMappings = @($ProfilePropertyMappings | Where-Object { $null -ne $_ -and -not [bool]$_.SynchronizedInSharePointOnline -and $_.BuiltInProperty -ne $true }) +
        @($ProfilePropertyMappings | Where-Object { $null -ne $_ -and ([bool]$_.SynchronizedInSharePointOnline -or $_.BuiltInProperty -eq $true) })
        foreach ($profileMapping in @($shownMappings | Select-Object -First $MaxDetailRow)) {
            [void]$sb.AppendLine('<tr>')
            foreach ($column in $profileMappingColumns) {
                $cellValue = $profileMapping.($column.Key)
                if ($column.Key -in @('SynchronizedInSharePointOnline', 'BuiltInProperty')) {
                    $cellValue = if ($null -eq $cellValue -or [string]$cellValue -eq '') { '' } elseif ([bool]$cellValue) { 'Yes' } else { 'No' }
                }
                [void]$sb.AppendLine(('<td>{0}</td>' -f (ConvertTo-SPSHtmlText -Value $cellValue)))
            }
            [void]$sb.AppendLine('</tr>')
        }
        [void]$sb.AppendLine('</tbody></table></div>')
        [void]$sb.AppendLine((& $limitNote $ProfilePropertyMappings.Count 'The profile property mappings CSV and JSON files'))
    }

    $script = @'
<script>
(function () {
    var table = document.getElementById('inv');
    if (!table) { return; }
    var sites = Array.prototype.slice.call(table.tBodies);
    var headers = table.tHead.rows[0].cells;
    var search = document.getElementById('inv-search');
    var counter = document.getElementById('inv-count');
    var buttons = document.querySelectorAll('.filters button');
    var indicators = document.querySelectorAll('button.risk[data-ind]');
    var indicatorChip = document.getElementById('inv-indicator');
    var activeFilter = 'all';
    var activeIndicator = '';
    var texts = null;

    function cellSortValue(site, index, type) {
        var cell = site.rows[0].cells[index];
        var raw = cell.getAttribute('data-sort');
        if (raw === null) { raw = cell.textContent.trim(); }
        if (type === 'num') {
            var n = parseFloat(raw);
            return isNaN(n) ? -Infinity : n;
        }
        return raw.toLowerCase();
    }

    function applyFilters() {
        var query = search ? search.value.trim().toLowerCase() : '';
        if (query !== '' && texts === null) {
            texts = sites.map(function (site) { return site.textContent.toLowerCase(); });
        }
        var shown = 0;
        for (var i = 0; i < sites.length; i++) {
            var visible = (activeFilter === 'all' || sites[i].getAttribute('data-category') === activeFilter) &&
                (activeIndicator === '' || (' ' + (sites[i].getAttribute('data-ind') || '') + ' ').indexOf(' ' + activeIndicator + ' ') !== -1) &&
                (query === '' || texts[i].indexOf(query) !== -1);
            sites[i].hidden = !visible;
            if (visible) { shown++; }
        }
        if (counter) { counter.textContent = shown + ' of ' + sites.length + ' shown'; }
    }

    for (var i = 0; i < headers.length; i++) {
        (function (index) {
            var th = headers[index];
            var type = th.getAttribute('data-type');
            if (!type) { return; }
            th.addEventListener('click', function () {
                var asc = th.getAttribute('data-dir') !== 'asc';
                for (var h = 0; h < headers.length; h++) {
                    headers[h].removeAttribute('data-dir');
                    var a = headers[h].querySelector('.arrow');
                    if (a) { a.textContent = ''; }
                }
                th.setAttribute('data-dir', asc ? 'asc' : 'desc');
                var arrow = th.querySelector('.arrow');
                if (arrow) { arrow.textContent = asc ? '\u25B2' : '\u25BC'; }

                var ordered = sites.slice().sort(function (s1, s2) {
                    var v1 = cellSortValue(s1, index, type);
                    var v2 = cellSortValue(s2, index, type);
                    if (v1 < v2) { return asc ? -1 : 1; }
                    if (v1 > v2) { return asc ? 1 : -1; }
                    return 0;
                });
                for (var r = 0; r < ordered.length; r++) { table.appendChild(ordered[r]); }
            });
        })(i);
    }

    for (var b = 0; b < buttons.length; b++) {
        buttons[b].addEventListener('click', function () {
            activeFilter = this.getAttribute('data-filter');
            for (var k = 0; k < buttons.length; k++) { buttons[k].classList.remove('active'); }
            this.classList.add('active');
            applyFilters();
        });
    }

    function setIndicator(key, label) {
        activeIndicator = key;
        for (var n = 0; n < indicators.length; n++) {
            var on = key !== '' && indicators[n].getAttribute('data-ind') === key;
            indicators[n].classList.toggle('active', on);
            indicators[n].setAttribute('aria-pressed', on ? 'true' : 'false');
        }
        if (indicatorChip) {
            indicatorChip.hidden = key === '';
            indicatorChip.textContent = label + ' \u2715';
        }
        applyFilters();
    }

    for (var m = 0; m < indicators.length; m++) {
        indicators[m].addEventListener('click', function () {
            var key = this.getAttribute('data-ind');
            if (activeIndicator === key) {
                setIndicator('', '');
                return;
            }
            setIndicator(key, this.querySelector('.risk-label').textContent);
            var target = document.getElementById('inventory-table');
            if (target && target.scrollIntoView) { target.scrollIntoView(); }
        });
    }

    if (indicatorChip) { indicatorChip.addEventListener('click', function () { setIndicator('', ''); }); }

    if (search) { search.addEventListener('input', applyFilters); }

    table.addEventListener('click', function (event) {
        var toggle = event.target.closest ? event.target.closest('.toggle') : null;
        if (!toggle) { return; }
        var site = toggle.closest('tbody');
        var open = site.classList.toggle('open');
        toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
})();
</script>
'@

    if (-not $paged) {
        [void]$sb.Append((& $endPage $script))
        return $sb.ToString()
    }

    if (-not $splitReport) {
        [void]$sb.Append((& $endPage $script))
        return [PSCustomObject]@{ Name = $entryName; Kind = 'Entry'; Html = $sb.ToString() }
    }

    # The entry page of a split report has no table, so it has no script. Each indicator opens the first table page
    # that has a site collection that raises it.
    $entryHtml = $sb.ToString() + (& $endPage $null)
    foreach ($row in $riskRows) {
        if ($indicatorPage.ContainsKey($row.Key)) {
            $entryHtml = $entryHtml.Replace(('@@IND-PAGE:{0}@@' -f $row.Key), [System.Uri]::EscapeDataString($tablePage[$indicatorPage[$row.Key][0]].Name))
        }
    }

    # What a table page needs to follow the indicator of its address: the label of each indicator, the pages, and the
    # pages that have a site collection that raises each indicator. A JSON text in a script element that does not run.
    $jsonString = {
        param([System.String]$Value)
        return '"' + $Value.Replace('\', '\\').Replace('"', '\"').Replace('<', '\u003c') + '"'
    }
    $labelJson = '{' + ((@($riskRows | ForEach-Object { '{0}:{1}' -f (& $jsonString $_.Key), (& $jsonString $_.Label) })) -join ',') + '}'
    $pageJson = '[' + ((@($tablePage | ForEach-Object { & $jsonString ([System.Uri]::EscapeDataString($_.Name)) })) -join ',') + ']'
    $indicatorJson = '{' + ((@($indicatorPage.Keys | Sort-Object | ForEach-Object { '{0}:[{1}]' -f (& $jsonString $_), ($indicatorPage[$_] -join ',') })) -join ',') + '}'

    $splitScript = @'
    var splitData = document.getElementById('inv-split');
    if (splitData) {
        var data = JSON.parse(splitData.textContent);
        var keepLinks = document.querySelectorAll('a[data-keep]');
        var hop = document.getElementById('inv-hop');

        function indicatorOfAddress() {
            var found = /(?:^|[#&])ind=([a-z0-9-]+)/.exec(location.hash);
            return found && Object.prototype.hasOwnProperty.call(data.labels, found[1]) ? found[1] : '';
        }

        function addHop(page, text, key) {
            if (page < 0) { return; }
            var link = document.createElement('a');
            link.setAttribute('href', data.pages[page] + '#ind=' + key);
            link.textContent = text;
            hop.appendChild(link);
        }

        function followAddress() {
            var key = indicatorOfAddress();
            setIndicator(key, key === '' ? '' : data.labels[key]);
            for (var k = 0; k < keepLinks.length; k++) {
                keepLinks[k].setAttribute('href', keepLinks[k].getAttribute('data-href') + (key === '' ? '' : '#ind=' + key));
            }
            while (hop.firstChild) { hop.removeChild(hop.firstChild); }
            if (key === '') { return; }
            var pages = data.indicatorPages[key] || [];
            var before = -1;
            var after = -1;
            for (var p = 0; p < pages.length; p++) {
                if (pages[p] < data.current) { before = pages[p]; }
                else if (pages[p] > data.current && after < 0) { after = pages[p]; }
            }
            addHop(before, '\u2190 Previous page with this indicator', key);
            addHop(after, 'Next page with this indicator \u2192', key);
        }

        if (indicatorChip) {
            indicatorChip.addEventListener('click', function () {
                if (window.history && history.replaceState) { history.replaceState(null, '', location.pathname + location.search); }
                followAddress();
            });
        }
        window.addEventListener('hashchange', followAddress);
        followAddress();
    }

'@
    $tableScript = $script.Insert($script.LastIndexOf('})();'), $splitScript)

    # The names of the files are percent-encoded in the links, so that a name with a space or a # is still a link.
    $entryLink = [System.Uri]::EscapeDataString($entryName)
    $pageLink = {
        param([System.String]$Name, [System.String]$Text, [System.String]$Class)
        $href = [System.Uri]::EscapeDataString($Name)
        return ('<a href="{0}" data-href="{0}" data-keep{1}>{2}</a>' -f $href, $Class, $Text)
    }

    # The pages of a category: the previous and the next one, and the numbers around the current one.
    $pager = {
        param($Page)
        if ($Page.Of -le 1) { return '' }
        $html = [System.Text.StringBuilder]::new()
        [void]$html.AppendLine('<div class="pager">')
        if ($Page.Number -gt 1) {
            [void]$html.AppendLine((& $pageLink $Page.Pages[$Page.Number - 2].Name '&larr; Previous' ''))
        }
        $shown = @(1..$Page.Of | Where-Object { $_ -eq 1 -or $_ -eq $Page.Of -or [math]::Abs($_ - $Page.Number) -le 2 })
        $before = 0
        foreach ($number in $shown) {
            if ($before -gt 0 -and $number - $before -gt 1) {
                [void]$html.AppendLine('<span>&hellip;</span>')
            }
            if ($number -eq $Page.Number) {
                [void]$html.AppendLine(('<strong>{0}</strong>' -f $number))
            }
            else {
                [void]$html.AppendLine((& $pageLink $Page.Pages[$number - 1].Name ([string]$number) ''))
            }
            $before = $number
        }
        if ($Page.Number -lt $Page.Of) {
            [void]$html.AppendLine((& $pageLink $Page.Pages[$Page.Number].Name 'Next &rarr;' ''))
        }
        [void]$html.AppendLine('</div>')
        return $html.ToString()
    }

    $buildTablePage = {
        param($Page, [System.Int32]$Index)
        $label = ConvertTo-SPSHtmlText -Value $Page.BucketLabel
        $nav = [System.Text.StringBuilder]::new()
        [void]$nav.AppendLine(('<a href="{0}">Summary</a>' -f $entryLink))
        [void]$nav.AppendLine(('<a href="{0}#risk-indicators">Risk indicators</a>' -f $entryLink))
        if ($hasAlertSection) {
            [void]$nav.AppendLine(('<a href="{0}#alerts">Alerts</a>' -f $entryLink))
        }
        if ($hasReadinessSection) {
            [void]$nav.AppendLine(('<a href="{0}#modern-readiness">Modern readiness</a>' -f $entryLink))
        }
        if ($waveKeys.Count -gt 0) {
            [void]$nav.AppendLine(('<a href="{0}#wave-plan">{1}</a>' -f $entryLink, $waveNavLabel))
        }
        [void]$nav.AppendLine(('<a href="{0}#inventory-table">Inventory table</a>' -f $entryLink))
        foreach ($bucket in $bucketList) {
            $current = if ($bucket.Id -eq $Page.Bucket) { ' class="current"' } else { '' }
            [void]$nav.AppendLine((& $pageLink $bucket.Pages[0].Name ('{0} ({1})' -f (ConvertTo-SPSHtmlText -Value $bucket.Label), $bucket.Count) $current))
        }

        $first = ($Page.Number - 1) * $RowsPerPage + 1
        $last = $first + $Page.Entries.Count - 1
        $out = [System.Text.StringBuilder]::new()
        [void]$out.Append((& $startPage ('{0} - Site collections - {1}, page {2} of {3}' -f $encTitle, $label, $Page.Number, $Page.Of) $nav.ToString()))
        [void]$out.AppendLine('<h2 id="inventory-table">Site collections</h2>')
        [void]$out.AppendLine(('<p><strong>{0}</strong>, page {1} of {2}: site collections {3} to {4} of {5}. Worst first. Open a row to see the context of the site collection, the signals it raises and its assessment warnings. The search box and the columns work on this page. The CSV and JSON files hold every column.</p>' -f $label, $Page.Number, $Page.Of, $first, $last, $Page.BucketCount))
        [void]$out.AppendLine('<div class="toolbar">')
        [void]$out.AppendLine('<input type="search" id="inv-search" placeholder="Search this page" aria-label="Search this page">')
        [void]$out.AppendLine('<button type="button" class="chip" id="inv-indicator" hidden></button>')
        [void]$out.AppendLine('<span class="hop" id="inv-hop"></span>')
        [void]$out.AppendLine(('<span class="count" id="inv-count">{0} of {0} shown</span>' -f $Page.Entries.Count))
        [void]$out.AppendLine('</div>')
        [void]$out.Append((& $pager $Page))
        [void]$out.Append($tableOpen.ToString())
        foreach ($rowEntry in $Page.Entries) {
            [void]$out.Append($rowEntry.Html)
        }
        [void]$out.Append($tableClose)
        [void]$out.Append((& $pager $Page))
        $data = ('<script type="application/json" id="inv-split">{{"entry":{0},"current":{1},"pages":{2},"labels":{3},"indicatorPages":{4}}}</script>' -f (& $jsonString $entryLink), $Index, $pageJson, $labelJson, $indicatorJson)
        [void]$out.Append((& $endPage ($data + [System.Environment]::NewLine + $tableScript)))
        return $out.ToString()
    }

    $result = [System.Collections.Generic.List[System.Object]]::new()
    $result.Add([PSCustomObject]@{ Name = $entryName; Kind = 'Entry'; Html = $entryHtml })
    for ($index = 0; $index -lt $tablePage.Count; $index++) {
        $result.Add([PSCustomObject]@{ Name = $tablePage[$index].Name; Kind = 'Sites'; Html = (& $buildTablePage $tablePage[$index] $index) })
    }
    return $result.ToArray()
}
