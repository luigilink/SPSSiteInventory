function ConvertTo-SPSInventoryHtml {
    <#
        .SYNOPSIS
        Renders the scored inventory as a single self-contained HTML report.

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

        The report is made to be read: the inventory table has one compact row per site
        collection, worst first, and opening a row shows the context of the site collection,
        the signals it raises and its assessment warnings. The content types and the other
        large detail tables are summarized or limited (see MaxDetailRow), because the CSV and
        JSON files hold every row and every column.

        Every field value is HTML-encoded, so URLs, titles and reasons cannot break the
        markup.

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

        .PARAMETER ExcludedPersonalSiteCount
        Number of personal sites that the scan left out. When above 0, the summary box says so.

        .PARAMETER ExcludedSiteMasterCount
        Number of site masters that the scan left out. When above 0, the summary box says so.

        .PARAMETER MaxDetailRow
        Maximum number of rows that each detail table shows (farm solutions, sites bound to
        full-trust code, managed metadata lists, external lists and BCS applications). A table
        with more rows says how many are not shown and which files hold all of them. Defaults
        to 200. The content types are never listed in the report: it shows a summary, and the
        CSV and JSON files hold every row.

        .EXAMPLE
        $html = ConvertTo-SPSInventoryHtml -InputObject $scored -EnvName 'PROD'
        Set-Content -Path report.html -Value $html -Encoding UTF8

        .EXAMPLE
        $html = ConvertTo-SPSInventoryHtml -InputObject $scored -SolutionMap $solutionMap
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
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
        [System.Int32]
        $ExcludedPersonalSiteCount = 0,

        [Parameter()]
        [System.Int32]
        $ExcludedSiteMasterCount = 0,

        [Parameter()]
        [ValidateRange(1, 100000)]
        [System.Int32]
        $MaxDetailRow = 200
    )

    # Category metadata: name and accent colour for each complexity level. A plain
    # hashtable (not [ordered]) is used on purpose: an OrderedDictionary indexed by an
    # integer key resolves by position, not by key, which would mis-map the categories.
    # Order is enforced by iterating 1..4 explicitly.
    $categoryMeta = @{
        1 = @{ Name = 'Simple'; Color = '#107C10' }
        2 = @{ Name = 'Moderate'; Color = '#C19C00' }
        3 = @{ Name = 'Complex'; Color = '#D83B01' }
        4 = @{ Name = 'Blocking'; Color = '#A4262C' }
    }

    $records = @($InputObject)
    $siteRecords = @($records | Where-Object { $_.InventoryScope -ne 'WebApplication' })
    $total = $siteRecords.Count
    $partialCount = @($siteRecords | Where-Object { $_.AssessmentStatus -eq 'Partial' }).Count
    $failedCount = @($siteRecords | Where-Object { $_.AssessmentStatus -eq 'Failed' }).Count
    $enumerationFailureCount = @($records | Where-Object { $_.InventoryScope -eq 'WebApplication' }).Count
    $assessedTotal = $total - $failedCount

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
    $riskCards = @(
        [PSCustomObject]@{ Label = 'Sites with full-trust code'; Count = @($siteRecords | Where-Object { $_.UsesFullTrustCode }).Count }
        [PSCustomObject]@{ Label = 'Sites with custom farm features'; Count = @($siteRecords | Where-Object { $_.UsesCustomFarmFeature }).Count }
        [PSCustomObject]@{ Label = 'Sites with sandbox solutions'; Count = @($siteRecords | Where-Object { [int]$_.SandboxSolutions -gt 0 }).Count }
        [PSCustomObject]@{ Label = 'Sites with a custom master page'; Count = @($siteRecords | Where-Object { $_.CustomMasterPage }).Count }
        [PSCustomObject]@{ Label = 'Sites with custom event receivers'; Count = @($siteRecords | Where-Object { [int]$_.EventReceivers -gt 0 }).Count }
        [PSCustomObject]@{ Label = 'Sites with FBA configured'; Count = @($siteRecords | Where-Object { $_.HasFbaZone }).Count }
        [PSCustomObject]@{ Label = 'Sites with unsupported templates'; Count = @($siteRecords | Where-Object { $_.IsUnsupportedSiteTemplate }).Count }
        [PSCustomObject]@{ Label = 'Sites with template compatibility review'; Count = @($siteRecords | Where-Object { -not [bool]$_.IsUnsupportedSiteTemplate -and [string]$_.TemplateCompatibility -eq 'Review' }).Count }
        [PSCustomObject]@{ Label = 'Sites with template-language review'; Count = @($siteRecords | Where-Object { $_.TemplateLanguageReviewRequired }).Count }
        [PSCustomObject]@{ Label = 'Sites with InfoPath forms'; Count = @($siteRecords | Where-Object { [int]$_.InfoPathFormCount -gt 0 }).Count }
        [PSCustomObject]@{ Label = 'Sites with IRM-enabled lists'; Count = @($siteRecords | Where-Object { [int]$_.IrmEnabledListCount -gt 0 }).Count }
        [PSCustomObject]@{ Label = 'Sites with locked state'; Count = @($siteRecords | Where-Object { $_.IsLockedSite }).Count }
        [PSCustomObject]@{ Label = 'Sites locked with NoAccess'; Count = @($siteRecords | Where-Object { $_.HasNoAccessLock }).Count }
        [PSCustomObject]@{ Label = 'Sites with Workflow 2010'; Count = @($siteRecords | Where-Object { [int]$_.Workflow2010Count -gt 0 }).Count }
        [PSCustomObject]@{ Label = 'Sites with running Workflow 2010'; Count = @($siteRecords | Where-Object { [int]$_.Workflow2010RunningInstanceCount -gt 0 }).Count }
        [PSCustomObject]@{ Label = 'Sites with running Workflow 2013'; Count = @($siteRecords | Where-Object { [int]$_.Workflow2013RunningInstanceCount -gt 0 }).Count }
        [PSCustomObject]@{ Label = 'Sites with app instances'; Count = @($siteRecords | Where-Object { [int]$_.AppInstanceCount -gt 0 }).Count }
        [PSCustomObject]@{ Label = 'Sites with app webs'; Count = @($siteRecords | Where-Object { [int]$_.AppWebCount -gt 0 }).Count }
        [PSCustomObject]@{ Label = 'Sites with publishing features'; Count = @($siteRecords | Where-Object { [bool]$_.PublishingInfrastructureEnabled -or [int]$_.PublishingWebCount -gt 0 }).Count }
        [PSCustomObject]@{ Label = 'Sites with publishing pages'; Count = @($siteRecords | Where-Object { [int]$_.PublishingPageCount -gt 0 }).Count }
        [PSCustomObject]@{ Label = 'Sites with customized pages'; Count = @($siteRecords | Where-Object { [int]$_.CustomizedPageCount -gt 0 }).Count }
        [PSCustomObject]@{ Label = 'Sites with custom permission levels'; Count = @($siteRecords | Where-Object { [int]$_.CustomPermissionLevelCount -gt 0 }).Count }
        [PSCustomObject]@{ Label = 'Sites with e-mail enabled lists'; Count = @($siteRecords | Where-Object { [int]$_.EmailEnabledListCount -gt 0 }).Count }
        [PSCustomObject]@{ Label = 'Sites with HTML files'; Count = @($siteRecords | Where-Object { [int]$_.HtmlFileCount -gt 0 }).Count }
        [PSCustomObject]@{ Label = 'Sites with managed metadata columns'; Count = @($siteRecords | Where-Object { [int]$_.ManagedMetadataListCount -gt 0 }).Count }
        [PSCustomObject]@{ Label = 'Sites with external lists'; Count = @($siteRecords | Where-Object { [int]$_.ExternalListCount -gt 0 }).Count }
        [PSCustomObject]@{ Label = 'Sites with SharePoint alerts'; Count = @($siteRecords | Where-Object { [int]$_.SharePointAlertCount -gt 0 }).Count }
        [PSCustomObject]@{ Label = 'Sites with subsites'; Count = @($siteRecords | Where-Object { [int]$_.SubsiteCount -gt 0 }).Count }
        [PSCustomObject]@{ Label = 'Sites in web applications with permissive browser file handling'; Count = @($siteRecords | Where-Object { [string]$_.BrowserFileHandling -eq 'Permissive' }).Count }
        [PSCustomObject]@{ Label = 'Sites above large-size threshold'; Count = @($siteRecords | Where-Object { $_.IsLargeSite }).Count }
        [PSCustomObject]@{ Label = 'Sites with large lists'; Count = @($siteRecords | Where-Object { [int]$_.LargeListCount -gt 0 }).Count }
        [PSCustomObject]@{ Label = 'Sites with checked-out files'; Count = @($siteRecords | Where-Object { [int]$_.CheckedOutFileCount -gt 0 }).Count }
        [PSCustomObject]@{ Label = 'Sites with high file-version counts'; Count = @($siteRecords | Where-Object { [int]$_.FileVersionCount -gt 0 }).Count }
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
            $waveAgg[$waveGroupKey] = [PSCustomObject]@{ Wave = $waveNumber; Name = $waveName; Count = 0; SizeGB = 0.0 }
        }
        $waveAgg[$waveGroupKey].Count++
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
.card.risk { border-top-color: var(--cat4); }
.card.risk .num { color: var(--cat4); }
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
@media print { tr.detail { display: table-row; } .toolbar { display: none; } }
</style>
'@

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="en">')
    [void]$sb.AppendLine('<head>')
    [void]$sb.AppendLine('<meta charset="utf-8">')
    [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
    [void]$sb.AppendLine(('<title>{0}{1}</title>' -f $encTitle, $(if ($encEnv) { ' - ' + $encEnv } else { '' })))
    [void]$sb.AppendLine($style)
    [void]$sb.AppendLine('</head>')
    [void]$sb.AppendLine('<body>')
    [void]$sb.AppendLine('<div class="wrap">')

    # Header.
    [void]$sb.AppendLine('<div class="header">')
    [void]$sb.AppendLine(('<h1>{0}</h1>' -f $encTitle))
    $envPart = if ($encEnv) { ('Environment <strong>{0}</strong> &middot; ' -f $encEnv) } else { '' }
    [void]$sb.AppendLine(('<div class="meta">{0}Generated on <strong>{1}</strong></div>' -f $envPart, $encGenerated))
    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine('<div class="nav">')
    [void]$sb.AppendLine('<a href="#summary">Summary</a>')
    [void]$sb.AppendLine('<a href="#risk-indicators">Risk indicators</a>')
    if ($hasAlertSection) {
        [void]$sb.AppendLine('<a href="#alerts">Alerts</a>')
    }
    if ($waveKeys.Count -gt 0) {
        [void]$sb.AppendLine('<a href="#wave-plan">Migration waves</a>')
    }
    [void]$sb.AppendLine('<a href="#inventory-table">Inventory table</a>')
    if ($solutions.Count -gt 0) {
        [void]$sb.AppendLine('<a href="#farm-solutions">Farm solutions</a>')
    }
    if ($authenticationRecords.Count -gt 0) {
        [void]$sb.AppendLine('<a href="#authentication">Authentication</a>')
    }
    if ($policyRecords.Count -gt 0) {
        [void]$sb.AppendLine('<a href="#web-app-policies">Web application policies</a>')
    }
    if ($hasContentTypeSection) {
        [void]$sb.AppendLine('<a href="#content-types">Content types</a>')
    }
    if ($hasManagedMetadataSection) {
        [void]$sb.AppendLine('<a href="#managed-metadata">Managed metadata</a>')
    }
    if ($hasExternalListSection) {
        [void]$sb.AppendLine('<a href="#external-lists">External lists</a>')
    }
    if ($hasBcsSection) {
        [void]$sb.AppendLine('<a href="#bcs-applications">BCS applications</a>')
    }
    [void]$sb.AppendLine('</div>')

    # Summary box.
    [void]$sb.AppendLine('<div class="summary" id="summary">')
    [void]$sb.AppendLine(('<div class="summary-total"><strong>{0}</strong> site collection(s) &middot; <strong>{1} GB</strong> total content &middot; <strong>{2}</strong> partial &middot; <strong>{3}</strong> failed</div>' -f $total, (ConvertTo-SPSHtmlText -Value $totalSizeText), $partialCount, $failedCount))
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
    [void]$sb.AppendLine('<div class="cards">')
    foreach ($risk in $riskCards) {
        [void]$sb.AppendLine(('<div class="card risk"><div class="num">{0}</div><div class="lbl">{1}</div></div>' -f $risk.Count, (ConvertTo-SPSHtmlText -Value $risk.Label)))
    }
    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine('</div>')

    # Alerts grouped by type, with what to do about each.
    if ($hasAlertSection) {
        $alertCatalog = Get-SPSAlertCatalog
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
        [void]$sb.AppendLine(('<p><strong>{0}</strong> alert(s) of <strong>{1}</strong> type(s): <strong>{2}</strong> high, <strong>{3}</strong> medium and <strong>{4}</strong> low. Each type shows how many site collections or web applications it concerns and what to do about it. The alert of each site collection, with its URL, is in the alerts CSV and JSON files.</p>' -f $alertRows.Count, $alertGroups.Count, $highAlertCount, $mediumAlertCount, $lowAlertCount))
        if ($alertGroups.Count -gt 0) {
            [void]$sb.AppendLine('<div class="table-scroll"><table class="alerts">')
            [void]$sb.AppendLine('<thead><tr><th>Severity</th><th>Alert</th><th class="num">Affected</th><th>What it means</th><th>What to do</th><th>Reference</th></tr></thead><tbody>')
            foreach ($alertGroup in $alertGroups) {
                $severityPill = switch ($alertGroup.Severity) {
                    'High' { '<span class="pill yes">High</span>' }
                    'Medium' { '<span class="pill warn">Medium</span>' }
                    default { ('<span class="pill no">{0}</span>' -f (ConvertTo-SPSHtmlText -Value $alertGroup.Severity)) }
                }
                $referenceLink = if ($alertGroup.Reference -like 'https://*') {
                    '<a href="{0}">Microsoft Learn</a>' -f (ConvertTo-SPSHtmlText -Value $alertGroup.Reference)
                }
                else {
                    ''
                }
                [void]$sb.AppendLine(('<tr><td>{0}</td><td>{1}</td><td class="num">{2}</td><td>{3}</td><td>{4}</td><td>{5}</td></tr>' -f
                    $severityPill,
                    (ConvertTo-SPSHtmlText -Value $alertGroup.AlertType),
                    $alertGroup.Count,
                    (ConvertTo-SPSHtmlText -Value $alertGroup.Message),
                    (ConvertTo-SPSHtmlText -Value $alertGroup.Remediation),
                    $referenceLink))
            }
            [void]$sb.AppendLine('</tbody></table></div>')
        }
    }

    # Migration wave plan.
    if ($waveKeys.Count -gt 0) {
        [void]$sb.AppendLine('<h2 id="wave-plan">Migration wave plan</h2>')
        [void]$sb.AppendLine('<div class="table-scroll">')
        [void]$sb.AppendLine('<table class="waves">')
        [void]$sb.AppendLine('<thead><tr><th>Wave</th><th>Name</th><th class="num">Sites</th><th class="num">Content (GB)</th></tr></thead>')
        [void]$sb.AppendLine('<tbody>')
        foreach ($key in $waveKeys) {
            $agg = $waveAgg[$key]
            $waveLabel = if ($agg.Wave -eq 0) { '-' } else { [string]$agg.Wave }
            [void]$sb.AppendLine(('<tr><td class="num">{0}</td><td>{1}</td><td class="num">{2}</td><td class="num">{3}</td></tr>' -f $waveLabel, (ConvertTo-SPSHtmlText -Value $agg.Name), $agg.Count, (ConvertTo-SPSHtmlText -Value (ConvertTo-SPSSizeText -SizeGB $agg.SizeGB))))
        }
        [void]$sb.AppendLine('</tbody>')
        [void]$sb.AppendLine('</table>')
        [void]$sb.AppendLine('</div>')
    }

    # Inventory table: one compact row per site collection, worst first. Opening a row shows the
    # context of the site collection, the signals it raises and its assessment warnings, so the page
    # stays readable on a large farm. The CSV and JSON files keep every column.
    $inventoryRecords = @($records | Sort-Object -Property `
        @{ Expression = { $sortCategory = 0; if ($null -ne $_.Category) { $sortCategory = [int]$_.Category }; if ($sortCategory -eq 0) { 5 } else { $sortCategory } }; Descending = $true },
        @{ Expression = { try { [double]$_.Score } catch { 0.0 } }; Descending = $true },
        @{ Expression = { [string]$_.Url } })
    $notAssessedCount = @($inventoryRecords | Where-Object { $null -eq $_.Category -or [int]$_.Category -eq 0 }).Count
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
    [void]$sb.AppendLine(('<span class="count" id="inv-count">{0} of {0} shown</span>' -f $inventoryRecords.Count))
    [void]$sb.AppendLine('</div>')

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
    [void]$sb.AppendLine('<div class="table-scroll">')
    [void]$sb.AppendLine('<table id="inv">')
    [void]$sb.AppendLine('<thead><tr>')
    [void]$sb.AppendLine('<th class="tgl"></th>')
    foreach ($col in $inventoryColumns) {
        $thClass = if ($col.Class -eq 'num') { ' class="num"' } else { '' }
        [void]$sb.AppendLine(('<th{0} data-type="{1}">{2} <span class="arrow"></span></th>' -f $thClass, $col.Type, (ConvertTo-SPSHtmlText -Value $col.Label)))
    }
    [void]$sb.AppendLine('</tr></thead>')

    foreach ($record in $inventoryRecords) {
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

        [void]$sb.AppendLine(('<tbody class="site" data-category="{0}">' -f $cat))
        [void]$sb.AppendLine('<tr class="main">')
        [void]$sb.AppendLine('<td class="tgl"><button type="button" class="toggle" aria-expanded="false" aria-label="Show the details of this site collection" title="Show details"></button></td>')
        [void]$sb.AppendLine(('<td class="site-cell" data-sort="{0}">{1}</td>' -f (ConvertTo-SPSHtmlText -Value $url.ToLowerInvariant()), $siteCell))
        [void]$sb.AppendLine(('<td data-sort="{0}"><span class="badge b{0}">{1}</span></td>' -f $cat, (ConvertTo-SPSHtmlText -Value $catName)))
        [void]$sb.AppendLine(('<td class="num">{0}</td>' -f (ConvertTo-SPSHtmlText -Value (& $formatInventoryNumber $record.Score))))
        [void]$sb.AppendLine(('<td class="num">{0}</td>' -f $waveText))
        [void]$sb.AppendLine(('<td class="num">{0}</td>' -f (ConvertTo-SPSHtmlText -Value (& $formatInventoryNumber $record.SizeGB))))
        [void]$sb.AppendLine(('<td class="tpl">{0}</td>' -f (ConvertTo-SPSHtmlText -Value $record.Template)))
        [void]$sb.AppendLine(('<td>{0}</td>' -f (ConvertTo-SPSHtmlText -Value $modified)))
        [void]$sb.AppendLine(('<td>{0}</td>' -f $statusCell))
        [void]$sb.AppendLine(('<td class="reasons"><div class="clamp">{0}</div></td>' -f (ConvertTo-SPSHtmlText -Value (& $orderReasons $reasonsCell))))
        [void]$sb.AppendLine('</tr>')

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
        [void]$sb.AppendLine(('<tr class="detail"><td></td><td colspan="9">{0}</td></tr>' -f $detail.ToString()))
        [void]$sb.AppendLine('</tbody>')
    }

    [void]$sb.AppendLine('</table>')
    [void]$sb.AppendLine('</div>')

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

    [void]$sb.AppendLine('<div class="footer">Generated by SPSSiteInventory &middot; read-only inventory &middot; no farm changes</div>')
    [void]$sb.AppendLine('</div>')

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
    var activeFilter = 'all';
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
    [void]$sb.AppendLine($script)
    [void]$sb.AppendLine('</body>')
    [void]$sb.AppendLine('</html>')

    return $sb.ToString()
}
