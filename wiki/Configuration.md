# Configuration

SPSSiteInventory reads a PowerShell data file (`.psd1`). Copy
`config/inventory-settings.example.psd1` to `config/inventory-settings.psd1` (gitignored)
and adjust it. No client-specific value ships in the repository.

## Top-level settings

| Setting | Type | Description |
| --- | --- | --- |
| `EnvName` | string | Free-form environment identifier (e.g. `PROD`), used in output file names and the banner. |
| `TargetMode` | string | Optional. What the inventory prepares: `SharePointOnline` (the default, also when the setting is missing) for a migration to SharePoint Online, or `SharePointOnPrem` for the modernization of the farm where it runs. It names the categories and the waves and frames the report; the `Scoring` section decides what counts as a blocker (see [TargetMode](#targetmode-section)). |
| `WebApplicationUrl` | string[] | Web application URLs to scan. Leave empty to scan every content web application. |
| `CustomSolutionPrefix` | string[] | **Optional override.** Case-insensitive name prefixes that force a farm solution (WSP) to be treated as custom. Custom solutions are auto-detected by default (see below), so this is usually left empty. |
| `AutoDetectCustomSolutions` | bool | Optional (default `$true`). When true, a solution is custom unless its name matches a known Microsoft / out-of-the-box marker. Set `$false` to rely only on `CustomSolutionPrefix`. |
| `KnownMicrosoftSolutionPrefix` | string[] | Optional extra name prefixes to treat as Microsoft / out-of-the-box during auto-detection (e.g. a known vendor package). |
| `OutputFolder` | string | Folder where the CSV/JSON reports are written. |
| `LogRetentionDays` | int | Days of run logs kept under the `Logs` folder. |
| `LargeContentThresholds` | hashtable | Thresholds for large-content parity signals (large site/list/view, checked-out files, file versions). Optional; defaults apply when omitted. |
| `TemplateParity` | hashtable | Template compatibility and language rules (supported/unsupported/review mapping, optional language allow-list). Optional; built-in defaults apply when omitted. |
| `PermissionLevels` | hashtable | Permission-level names SharePoint provisions, used to tell custom permission levels apart (`BuiltInNames`, added to the built-in English names). Optional. |
| `Scope` | hashtable | Which site collections are scanned (`IncludePersonalSites` and `IncludeSiteMasters`, both default `$false`). Optional. |
| `Report` | hashtable | Options of the HTML report: `HtmlSplitThreshold` (default 3000) and `HtmlRowsPerPage` (default 500). Optional. |
| `SharePointAlerts` | hashtable | Options of the SharePoint alerts report (`IncludeUserLogin`, default `$true`). Optional. |
| `Scoring` | hashtable | The scoring engine configuration (see below). **Mandatory.** |
| `MigrationWaves` | hashtable[] | The category-to-wave mapping (see below). Optional; a one-wave-per-category default applies when omitted, with the names of the target mode. |

## TargetMode section

The same inventory answers two questions. `TargetMode` says which one is asked:

| `TargetMode` | The question | Example file |
| --- | --- | --- |
| `SharePointOnline` (default) | Can each site collection move to SharePoint Online, and what does it take? | `inventory-settings.example.psd1` |
| `SharePointOnPrem` | Is each site collection ready for the modern experience on the farm where it runs, and what does it take to modernize it? | `inventory-settings.onprem.example.psd1` |

The setting is optional: a settings file without it, such as every file of an earlier version, is
`SharePointOnline`, and its reports do not change. A value that is not one of the two names is
refused when the settings are loaded, with the name of the file, because a misspelled mode would
otherwise run as the default without anybody having chosen it. The case does not matter. The
log says which mode runs, and the manifest records it (`Summary.TargetMode`).

### What the mode changes

The score and the category **number** (1 to 4) are the same in both modes: a script, a filter or a
wave mapping that reads `Category` does not change. The mode changes the words:

| Category | `SharePointOnline` | `SharePointOnPrem` |
| --- | --- | --- |
| 1 | Simple | Modern-ready |
| 2 | Moderate | Light remediation |
| 3 | Complex | Rebuild (SPFx) |
| 4 | Blocking | Blocked |

- `CategoryName` of every record, in the CSV, the JSON and the HTML report.
- The pages of a split HTML report, which are named after the category
  (`...-sites-blocking-1.html`, or `...-sites-rebuild-spfx-1.html`).
- The default waves, when the settings have no `MigrationWaves`: *Quick wins*, *Light
  remediation*, *Rebuild* and *Projects / blockers* for a migration; *Ready*, *Light
  remediation*, *Rebuild (SPFx)* and *Blocked* for the modernization.
- The HTML report: the header says `Target SharePoint on-premises modernization`, the wave plan
  is the *Modernization wave plan*, and the summary of the sites that wait in *Needs review* is
  named after the first category of the mode.
- The alerts: the catalog of the mode has the same alert types, but what is only about a
  migration to SharePoint Online is `Low` and says so, and the alerts that matter for the
  modernization are worded for it, with another severity where the weight of the signal says so
  (the full-trust code that has to be rebuilt with SPFx is `Medium`, InfoPath and the SharePoint
  2010 workflows, which SharePoint Server Subscription Edition no longer supports, stay `High`).
  See [Alerts in the SharePointOnPrem mode](Alerts#alerts-in-the-sharepointonprem-mode). The
  ranking of the risk indicators of the HTML report follows these severities.
- The HTML report has a *Modern experience readiness* section, after the alerts: how many site
  collections have a blocker of the modern experience, how many have each kind, and the site
  collections that have the most. The report of the default mode does not have it.
- The log: the warnings that tell you to add a signal to `Scoring.BlockingSignals` because a
  migration to SharePoint Online would be blocked by it (FBA, unsupported templates, NoAccess
  locks, IRM lists, external lists) are not raised in the modernization mode.
- `Test-SPSSiteInventoryReadiness.ps1` compares your settings with the example of the mode of
  your file (`inventory-settings.onprem.example.psd1` for `SharePointOnPrem`), not with the
  migration example.

The mode does **not** change what counts as a blocker or what a signal weighs: that is the
`Scoring` section, and it is yours. Each example file ships the scoring that fits its question,
so start from the file of your mode, copy it to `inventory-settings.psd1` and adjust it. Setting
`TargetMode = 'SharePointOnPrem'` in a file that keeps the migration scoring gives the new names
to a migration scoring, which is rarely what you want.

### The on-premises preset

On the farm where the site collections run, full-trust code and custom farm features still work:
they are code to rebuild with the SharePoint Framework (SPFx) to reach the modern experience, so
the preset **weighs** them (`UsesFullTrustCode = 4.0`, `UsesCustomFarmFeature = 2.0`,
`CustomMasterPage = 3.0`, `SandboxSolutions = 3.0`) and does **not** block on them. It blocks on
`InfoPathFormCount` only: InfoPath Forms Services is deprecated in SharePoint Server
Subscription Edition and its support ended on 14 July 2026, and a form has no modern editor.
The SharePoint 2010 workflows (their support ended on 14 July 2026 too) weigh heavily, which
makes a site collection that has them *Rebuild (SPFx)*, not *Blocked*, because they still run.

What belongs to a migration and not to the modernization of a farm weighs nothing in the
preset: forms-based authentication, unsupported site templates, `NoAccess` locks, IRM-enabled
lists, external lists (BCS is not retired in SharePoint Server Subscription Edition), the term
store, incoming e-mail, `.htm` files, template-language review and the subsite structure. The
signals are still collected, and they still raise their alerts and appear in the reports, so
nothing disappears from the inventory: they just do not move a site collection to a worse
category. Subsites, in particular, are not penalised: a site collection with 100 subsites is
*Modern-ready* in the preset, and the restructuring that modern SharePoint favors (one site
collection per unit of work; hub sites, which connect them, exist in SharePoint Online but not in
SharePoint Server) is a topic of the report, not of the score.

The preset weighs the signals that only matter for the modern experience, which the toolkit
collects in both modes (see [Modern-readiness signals](#modern-readiness-signals)): an alternate
CSS URL (`AlternateCssUrlCount = 1.5` a web), a list view that renders with XSLT
(`XsltListViewCount = 1.0`), a Script Editor or Content Editor web part that holds script
(`ScriptWebPartCount = 1.5`), an opt-out of the modern list experience
(`ClassicExperienceOptOutCount = 1.0`) and a list forced to the classic experience
(`ClassicExperienceListCount = 0.5`), next to the custom master page and the publishing
features that it already weighs. They are columns of the CSV and JSON reports, they raise their
own [alerts](Alerts), and the *Modern experience readiness* section of the HTML report lists, for
each site collection, what keeps it in the classic experience.

A signal that the preset does not weigh still raises its alert, so that nothing disappears from
the inventory, but the alert is `Low` and says that it is only about a migration to SharePoint
Online. The report of this mode is therefore short on what does not matter for the modernization,
and long on what does.

## Custom solution detection

Custom farm solutions (WSP) are **auto-detected**, so you normally do not configure anything
here. On a farm the solution store only holds solutions that were explicitly added, so the
safe default is "custom unless proven Microsoft": a solution is treated as custom unless its
name matches a known Microsoft / out-of-the-box marker (`microsoft.`, language packs, ...).

- To force a solution custom when auto-detection misses it, add a prefix to
  `CustomSolutionPrefix`.
- To treat a known third-party package as out-of-the-box, add its prefix to
  `KnownMicrosoftSolutionPrefix`.
- To disable auto-detection entirely and rely only on `CustomSolutionPrefix`, set
  `AutoDetectCustomSolutions = $false`.

`IsCustom` feeds `UsesCustomFarmFeature`, and combined with a global assembly it drives
`IsFullTrustCode` / `UsesFullTrustCode` — so getting it right without manual prefixes is the
point of auto-detection.

## Scoring section

The `Scoring` hashtable drives `Measure-SPSSiteComplexity`.

```powershell
Scoring = @{
    Weights = @{
        Workflow2010Count        = 3.0
        Workflow2013Count        = 1.5
        Workflow2010RunningInstanceCount = 1.0
        Workflow2013RunningInstanceCount = 0.5
        AppInstanceCount         = 1.0
        AppWebCount              = 1.5
        PublishingInfrastructureEnabled = 2.0
        PublishingWebCount       = 0.5
        PublishingPageLayoutCount = 0.5
        PublishingPageCount      = 0.001
        CustomizedPageCount      = 1.0
        CustomPermissionLevelCount = 0.5
        EmailEnabledListCount    = 0.5
        HtmlFileCount            = 0.1
        ManagedMetadataListCount = 0.1
        ManagedMetadataTermSetCount = 0.25
        ExternalListCount        = 1.0
        IsUnsupportedSiteTemplate = 5.0
        TemplateLanguageReviewRequired = 0.5
        SubsiteCount             = 0.05
        MaxSubsiteDepth          = 0.25
        InfoPathFormCount        = 3.0
        IrmEnabledListCount      = 2.5
        IsLargeSite              = 1.5
        LargeListCount           = 0.5
        LargeListViewCount       = 0.5
        CheckedOutFileCount      = 0.05
        FileVersionCount         = 0.02
        SandboxSolutions         = 3.0
        CustomMasterPage         = 2.0
        EventReceivers           = 1.5
        UniquePermissionsCount   = 0.01
        SizeGB                   = 0.02
    }
    Thresholds = @{
        Moderate = 1.0
        Complex  = 6.0
    }
    BlockingSignals = @(
        'UsesCustomFarmFeature'
        'UsesFullTrustCode'
        'InfoPathFormCount'
        'HasNoAccessLock'
        'IrmEnabledListCount'
        'HasFbaZone'
        'IsUnsupportedSiteTemplate'
    )
}
```

### Weights

Each key is a **signal** collected by `Get-SPSSiteCustomization`. The weight is multiplied
by the signal value (booleans count as 1 when true) and summed into the site's score. Set a
weight to `0` (or omit the key) to ignore a signal.

Workflows are split by platform because their migration cost differs:

- `Workflow2010Count` — active SharePoint 2010 workflows (legacy engine,
  **retired in SharePoint Online**). Historical "previous version" associations
  are excluded when detectable so the score tracks active workflows. They always
  need a rebuild, so they are weighted heavily. Add
  `Workflow2010Count` to `BlockingSignals` if you want any legacy workflow to force
  **Blocking (4)**.
- `Workflow2010RunningInstanceCount` — active runtime instances on the 2010
  platform where per-association counters are available.
- `Workflow2013Count` — SharePoint 2013 workflows (Workflow Manager). A lighter, more
  direct remediation, so they are weighted less than their 2010 counterparts. They
  were nevertheless **retired in SharePoint Online** on 2 April 2026, so every one
  needs a rebuild, for example with Power Automate: the `Workflow2013` alert is `High`,
  like the `Workflow2010` one.
- `Workflow2013RunningInstanceCount` — active runtime instances on the 2013
  platform when Workflow Manager instance APIs are available.
- `AppInstanceCount` — SharePoint add-in instances detected across the site
  collection. This helps estimate add-in replacement effort.
- `AppWebCount` — webs identified as app webs (`APP#*` / `IsAppWeb`), which are
  typically migration redesign candidates rather than direct targets.
- `IsUnsupportedSiteTemplate` — root-web template is explicitly mapped as
  unsupported for direct SharePoint Online migration.
- `TemplateLanguageReviewRequired` — root-web language metadata needs review
  (missing, unrecognized LCID, or outside the optional allow-list).

`InfoPathFormCount` counts the InfoPath-driven lists and libraries on the site. InfoPath
Forms Services is **retired and unavailable in SharePoint Online**, so it is weighted
heavily and listed in `BlockingSignals` in the example configuration.

`IrmEnabledListCount` counts lists/libraries where IRM is enabled. IRM typically requires
records-protection and compliance remediation during migration, so the example
configuration keeps it as both weighted and blocking.

Subsites are supported in SharePoint Online, but modern SharePoint favors one site collection
per unit of work, connected by hub sites. A large or deep hierarchy is therefore a restructuring
topic to plan, not a blocker: the example configuration weights it lightly and does not list it
in `BlockingSignals`.

- `SubsiteCount` — the webs below the root web of the site collection. The root web itself
  and the app webs that add-ins create are not counted (`SubWebCount` counts every web,
  the root web included).
- `MaxSubsiteDepth` — the deepest level of the hierarchy: 1 for a web directly below the
  root web, 2 for one more level, and so on.

With the example weights, subsites alone make a site Moderate from 15 subsites directly below
the root web, or from four levels of subsites; in between, the deeper the hierarchy, the fewer
subsites it takes. The `Subsites` alert (`Low`, see
[Alerts](Alerts)) carries the restructuring guidance, and `SubsiteExamples` in the reports lists
up to five of the deepest subsites. Set both weights to `0` to ignore the structure, or raise
them to plan the restructuring first.

Large-content parity signals are threshold-driven:

- `IsLargeSite` — site storage is at or above `LargeContentThresholds.LargeSiteSizeGB`.
- `LargeListCount` — lists at or above `LargeContentThresholds.LargeListItemCount`.
- `LargeListViewCount` — views whose row limit is at or above
  `LargeContentThresholds.LargeListViewRowLimit` on large lists.
- `CheckedOutFileCount` — checked-out files detected in document libraries.
- `FileVersionCount` — files whose version count is at or above
  `LargeContentThresholds.FileVersionCount`.
- `LargeExcelFileCount` — Excel workbooks (`.xlsx`) in document libraries (the system catalogs
  under `/_catalogs/` are skipped) that are at least `LargeContentThresholds.LargeExcelFileSizeMB`
  large, 10 MB by default. SharePoint Online does not open a workbook above that size in the
  browser: it asks the user to open it in the Excel client. The workbooks are migrated, so the
  signal is reported (`LargeExcelFileExamples` lists up to five of them with their size, and the
  `LargeExcelFiles` alert says whom to warn) and weighs nothing in either example configuration. The
  source farm can open larger workbooks in the browser, which is why the size is a setting.
  At most `LargeContentThresholds.MaxItemsForExcelFileScanPerLibrary` workbooks are checked in each
  library; when it is reached, the count is a lower bound and the assessment is marked partial.

Collaboration signals describe features that migrate without the data that makes them work. They are
reported (the `AudienceTargeting` and `SiteNotebook` alerts say what to do) and weigh nothing in either
example configuration, because the content itself migrates:

- `AudienceTargetedItemCount` — list items that target an audience, that is, whose Target Audiences
  column is not empty. The column has the ID `61cbb965-1e04-4273-b658-eedaa662f48d` (its internal name is
  `Target_x0020_Audiences`, and `Audience` in a Pages library), a list has it once audience targeting is
  enabled on it, and a Pages library has it from the start. The audience data does not migrate to
  SharePoint Online, so the items are shown to every reader afterwards, until the targeting is rebuilt
  (the SMAT List Items with Audience Targeting scan says the same). `AudienceTargetedListCount` counts the
  lists that hold such items, and `AudienceTargetedExamples` lists up to five of them with the number of
  items and the audiences, for example `Announcements (/sites/team/Lists/Announcements): 3 item(s): Sales,
  Marketing`. An audience of the User Profile service is shown by its name when the account that runs the
  inventory can read the audiences, and by its ID when it cannot or when the audience was deleted; a
  distribution list is shown by its common name and a SharePoint group by its name. Hidden lists and the
  system catalogs are skipped. At most `LargeContentThresholds.MaxItemsForAudienceTargetingScanPerList`
  items are read in each list that has the column, whatever their value; when it is reached, the counts
  are lower bounds and the assessment is marked partial with a warning. The column is not filtered on,
  because how a query behaves on it is not documented: the pages of the list are read in order of ID, with
  the override of the list view threshold (run the scan as the farm account), and the value is tested by the
  inventory. The audience targeting of web parts, of navigation links and of pages is not reported, as in
  SMAT.
- `SiteNotebookCount` — the site notebooks: the OneNote notebooks of the Site Assets library (a folder that
  SharePoint marks with the HTML file type `OneNote.Notebook`) whose name ends in `Notebook`, as the SMAT
  Site Notebook scan reads them. The notebook that the Site Notebook feature creates is named after the
  site, and the name changes with the migration, so the links to it break. `SiteNotebookExamples` lists up
  to five of them. The library is found by the name of its root folder, `SiteAssets`, which is not
  translated. A notebook whose name does not end in `Notebook` is not counted, as in SMAT, so a site whose
  language gives its notebook another name is not found. At most
  `LargeContentThresholds.MaxItemsForNotebookScanPerLibrary` folders of the library are read; when it is
  reached, the count is a lower bound and the assessment is marked partial with a warning.

Publishing and customized-page signals describe classic publishing dependencies:

- `PublishingInfrastructureEnabled` — the SharePoint Server Publishing Infrastructure
  site collection feature is active.
- `PublishingWebCount` — webs where the SharePoint Server Publishing feature is active.
- `PublishingPageCount` — items in the Pages libraries of those webs.
- `PublishingPageLayoutCount` — distinct page layouts used by the pages that were
  scanned. A layout is identified by its normalized path, so two layouts that share a
  file name in different Master Page Gallery folders count separately. At most
  `LargeContentThresholds.MaxItemsForPublishingPageScanPerLibrary` pages are read per
  Pages library, so the value is a lower bound when that cap is reached (the
  assessment is then marked partial with a warning).
- `CustomizedPageCount` — customized (unghosted) pages at the root of each web, for
  example a `default.aspx` edited with SharePoint Designer. Migration reverts them to
  their default state and owners must reapply the customization. Files last modified
  by the System Account are ignored, as in the SMAT Customized Pages scan. List view
  and form pages are not scanned.

Publishing signals are weighted but **not blocking** in the example configuration:
SMAT describes publishing sites as needing extensive remediation, not as unmigratable.
Add `PublishingInfrastructureEnabled` to `BlockingSignals` to treat every publishing
site as a dedicated project.

Permission and policy signals follow the SMAT Custom Permission Level, Email Enabled
Lists, Browser File Handling and Web Application Policies scans:

- `CustomPermissionLevelCount` — distinct custom permission levels defined in the site
  collection (the root web and any web with unique permission levels). A level is custom
  when SharePoint gave it no base type and its name is not a provisioned one; see
  [PermissionLevels section](#permissionlevels-section).
- `EmailEnabledListCount` — lists with incoming e-mail enabled (an e-mail alias is set).
  A list type that merely supports e-mail is not counted. SharePoint Online has no
  incoming e-mail for lists, so messages sent to these lists stop arriving.
- `HtmlFileCount` — `.htm` and `.html` files in document libraries (system catalogs under
  `/_catalogs/` are skipped). It is collected only for site collections in a web
  application whose browser file handling is **Permissive**, because SharePoint Online
  enforces **Strict**: those files prompt a download instead of opening in the browser,
  which breaks pages and Page Viewer web parts that rely on them. In a Strict web
  application the value stays 0 without scanning. The count is capped per library by
  `LargeContentThresholds.MaxItemsForHtmlFileScanPerLibrary`.
- `BrowserFileHandling`, `WebAppPolicyCount` and `WebAppPolicyExamples` describe the
  web application (the same values repeat on each of its site collections) and are not
  scored: web application policies are not migrated to SharePoint Online, but they apply
  to the whole web application, so they are reported as an alert and in the report's
  web application section instead. The count includes accounts SharePoint adds itself,
  such as the farm and search crawl accounts, so a count above zero is expected.

None of these signals is blocking in the example configuration.

Managed metadata signals follow the SMAT Managed Metadata Columns report:

- `ManagedMetadataListCount` — lists and libraries with at least one visible managed
  metadata column, that is a field of type `TaxonomyFieldType` or
  `TaxonomyFieldTypeMulti` (the Enterprise Keywords column included). Hidden columns,
  and the hidden helper fields SharePoint adds for each column, are ignored, and so are
  the hidden lists: the newsfeed list (`MicroFeed`) of every site has a managed metadata
  column for hashtags, which says nothing about the use of the term store.
- `ManagedMetadataColumnCount` — those columns, counted once per list. It is reported
  but not scored, because it follows the list count.
- `ManagedMetadataTermSetCount` — distinct term sets, by ID, that those columns use
  across the site collection. A term set shared by several lists counts once.
- `ManagedMetadataExamples` — up to five lists with their column names.

The term set IDs come from the column definitions, so the term store service is never
called and term set names are not resolved. The per-list detail goes to the
`*-managedmetadata-*` CSV/JSON files and the HTML report (see
[Usage](Usage#managed-metadata-detail)).

These signals are weighted but **not blocking**: managed metadata columns usually migrate
with their list. What they add is a dependency on the term store, so the lists should be
migrated close to the term store migration. The weights are deliberately small because
many sites use a few such columns; raise them if your term store migration is a project
of its own.

External list signals follow the SMAT External List and BCS scans:

- `ExternalListCount` — lists backed by a Business Connectivity Services (BCS) external
  content type, which SharePoint flags as having an external data source. Their items stay
  in the external system. BCS is retired in SharePoint Online (see
  [Usage](Usage#external-lists-and-bcs-applications)), so these lists and the BCS
  applications behind them cannot be migrated there; they need a replacement such as
  Power Apps.
- `ExternalListExamples` — up to five lists with their entity.

The binding of each list (LOB system instance, entity namespace and entity name) is read
from the list definition, so neither the Business Data Connectivity service nor the
external system is called; item counts and dates are not collected because the items are
not stored in SharePoint. The BCS definitions themselves (LOB systems with their instances
and entities) are read once for the farm by `Get-SPSBcsApplication` and are reported in
their own file, not as a site signal. See [Usage](Usage#external-lists-and-bcs-applications).

`ExternalListCount` is weighted and listed in `BlockingSignals` in the example
configuration, like the other signals for features SharePoint Online no longer offers: a
site with external lists is a dedicated project because the scenario has to be rebuilt. The
site collection itself can still be migrated, without those lists. Remove
`ExternalListCount` from `BlockingSignals` to treat the replacement as remediation of a
Moderate or Complex site instead.

SharePoint alert signals follow the SMAT Alerts scan:

- `SharePointAlertCount` — the alerts ("Alert Me" subscriptions) that users set up on the
  site collection: every user's alerts, in every web. Migration tools do not migrate them,
  and SharePoint Online retired SharePoint Alerts from July 2026, so each notification has to
  be rebuilt with a SharePoint rule or a Power Automate flow. The count is exact.

The signal is reported but **not scored and not blocking** in the example configuration:
the content migrates, and each notification is replaced on its own, so it does not change
how the site is migrated. Add `SharePointAlertCount` to `Scoring.Weights` if you want sites
with many alerts to weigh more. The alert raised for it has the `Medium` severity (see
[Alerts](Alerts)). The per-alert detail goes to the `*-sharepointalerts-*` CSV/JSON files
(see [Usage](Usage#sharepoint-alerts)); they hold the login names of the alert owners, which
is personal data.

`EventReceivers` counts only **custom** event receivers (those registered from a
non-Microsoft assembly). Out-of-the-box receivers on native lists are ignored, so a stock
site is not promoted just because SharePoint's own lists carry many built-in receivers.

The classic customization signals are columns of the CSV, JSON and HTML reports under their
own name, so that you can filter and sort on them:

- `SandboxSolutions` — the sandbox (user) solutions in the solution gallery of the site
  collection, activated or not.
- `CustomMasterPage` — true when a web uses a master page other than the ones that SharePoint
  provisions in the master page gallery: `seattle.master`, `oslo.master`, `v4.master` and, for
  the My Site host and the personal sites, `mysite15.master`. A copy of one of them in another
  folder, or a master page whose name only contains one of these names, is reported.
- `EventReceivers` — the custom event receivers described above.
- `UsesCustomFarmFeature` — see [BlockingSignals](#blockingsignals).
- `UniquePermissionsCount` — the role assignments on the webs that do not inherit their
  permissions. The root web always has its own, so the value is never 0, and a subsite with
  unique permissions adds its own: it is not a count of webs.

### Modern-readiness signals

These signals say what makes a page, a list or a web fall back to the classic experience, and what
has to be rebuilt to leave it. They are collected in both target modes, and they are columns of
the CSV, JSON and `*-sites-*` reports under their own name. With `CustomMasterPage` (above) and
the publishing signals, they answer the question of the `SharePointOnPrem` mode: why is this site
collection not in the modern experience, and what does it take?

- `AlternateCssUrlCount` — the webs that set an alternate CSS URL (`SPWeb.AlternateCssUrl`).
  Modern pages do not use it, so the branding it carries is redone, with a site theme for
  example. `AlternateCssUrlExamples` lists up to five webs with their CSS file.
- `XsltListViewCount` — the list views that render with XSLT: a view whose `XslLink` is not the
  default `main.xsl`, or that keeps an `Xsl` of its own. Personal views and the views of hidden
  lists are not counted. The modern list view ignores XSLT, and SharePoint shows a list with a
  customized view in the classic experience (see
  [when SharePoint falls back to classic](https://learn.microsoft.com/en-us/sharepoint/dev/solution-guidance/modern-experience-customizations-customize-lists-and-libraries)).
  `XsltListViewExamples` lists up to five views as `list/view`.
- `ScriptWebPartCount` — the Script Editor web parts, and the Content Editor web parts that
  embed a `<script>` tag or link to a file (`ContentLink`, which is usually a script or an HTML
  page), on the home page of each web and on the pages of its Site Pages and Pages libraries.
  A Content Editor web part that holds only formatted text is not counted: a Text web part
  replaces it. Neither web part exists on a modern page, so the script is rebuilt, with the
  SharePoint Framework (SPFx). `ScriptWebPartExamples` lists up to five of them as
  `page URL (Script Editor)` or `page URL (Content Editor)`. At most
  `LargeContentThresholds.MaxItemsForWebPartScanPerLibrary` pages are read in each library (200
  by default); a library with more makes the site collection partial, with a warning that names
  the setting. The web parts of the list view and form pages are not read.
- `ClassicExperienceOptOutCount` — the site collection and the webs that opted out of the modern
  list and library experience: the site collection feature
  `E3540C7D-6BEA-403C-A224-1A12EAFEE4C4` and the web feature
  `52E14B6F-B1BB-4969-B89B-C4FAA56745EF` (see
  [Opting out of the modern list and library experience](https://learn.microsoft.com/en-us/sharepoint/dev/transform/modernize-userinterface-lists-and-libraries-optout)).
  Each active feature counts for 1, and `ClassicExperienceOptOutExamples` lists up to five as
  `URL (site collection)` or `URL (web)`.
- `ClassicExperienceListCount` — the lists whose "List experience" setting is *Classic
  experience* (`ListExperienceOptions`). That setting overrides the opt-outs above, and a list
  that is hidden is not counted. A SharePoint that has no modern list experience, such as
  SharePoint Server 2016, has no such setting: the count is 0 there and the site collection is
  not marked partial. `ClassicExperienceListExamples` lists up to five lists as `title (URL)`.
- `ModernBlockerCount` and `ModernBlockers` — the kinds of blocker that the site collection has,
  out of seven: a custom master page, an alternate CSS URL, publishing features, XSLT list views,
  script web parts, an opt-out of the modern list experience and lists forced to classic.
  `ModernBlockerCount` is the number of kinds (0 to 7), not the number of items behind them, and
  `ModernBlockers` is one text for the reports, such as `Custom master page; XSLT list views (3);
  Script web parts (1)`. It brings the other signals together and is not weighed in either example
  configuration: each blocker already weighs through its own signal, and weighing the aggregate
  would count it twice.

A signal that cannot be read is not taken for a site without it: the site collection is marked
partial, with a warning that names the web, the list or the page. The example for the default
mode weighs the first three lightly (`AlternateCssUrlCount = 0.5`, `XsltListViewCount = 0.25`,
`ScriptWebPartCount = 0.5`), because a migration redoes them, and the other two not at all; the
`SharePointOnPrem` example weighs them as the work of modernizing the farm (see
[the on-premises preset](#the-on-premises-preset)).

What is not collected yet: the `JSLink` of the views and of the fields (the client-side rendering
that the modern list also ignores), and the web parts of the list view and form pages.

### Thresholds

- `Moderate` — a score at or above this value promotes the site from **Simple (1)** to **Moderate (2)**.
- `Complex` — a score at or above this value promotes the site to **Complex (3)**.

### BlockingSignals

A list of signal names. If **any** of them is truthy for a site, the site is forced to
**Blocking (4)**, regardless of the score. Use this for signals that make a site
non-portable as-is:

- `UsesCustomFarmFeature` — the site activates a feature from a custom farm solution.
- `UsesFullTrustCode` — the site activates a feature from a custom **full-trust** solution
  (a WSP deploying a global assembly to the GAC), correlated through the farm-solution map.
- `InfoPathFormCount` — the site uses InfoPath forms.
- `HasNoAccessLock` — the site collection is locked with `NoAccess`: nobody can read it,
  so the migration tools skip it until it is unlocked. The inventory cannot read such a
  site collection either (SharePoint answers "Access to this Web site has been blocked"
  to every read, the lock flags included): it recognizes the lock from that error, and the
  site collection stays `Partial` with a warning for what could not be read. `ReadOnly` and `NoAdditions` locks
  only restrict changes, so they are not blocking: the content can still be read and
  migrated, and the lock is often a deliberate freeze. They are reported by `IsLockedSite`
  (true for any lock) and `SiteLockState`, and raise the `LockedSite` alert.
- `IrmEnabledListCount` — at least one list/library has IRM enabled.
- `ExternalListCount` — at least one external list (backed by a BCS external content
  type) exists. BCS is retired in SharePoint Online, so the scenario needs a replacement
  such as Power Apps.
- `HasFbaZone` — at least one zone of the site's web application is configured for
  forms-based authentication. This requires an identity/authentication redesign for
  SharePoint Online, not an on-premises farm repair. The signal does not prove that
  FBA is actively used by the site or its users.
- `IsUnsupportedSiteTemplate` — template compatibility mapping identified the
  root-web template as unsupported for direct migration.

Existing settings files are not rewritten. Add `HasFbaZone`, `HasNoAccessLock`,
`IrmEnabledListCount` and `IsUnsupportedSiteTemplate` to your existing
`Scoring.BlockingSignals` to apply these blocker overrides. A settings file that lists
`IsLockedSite` keeps blocking every lock state; replace it with `HasNoAccessLock` to block
only the sites that cannot be read.

## TemplateParity section

```powershell
TemplateParity = @{
    UnsupportedTemplates = @(
        'APP#0'
        'SPSMSITEHOST#0'
    )
    SupportedTemplatePrefixes = @(
        'STS#'
        'COMMUNITY#'
        'PROJECTSITE#'
        'SITEPAGEPUBLISHING#'
        'CMSPUBLISHING#'
        'BLANKINTERNET#'
        'SRCHCEN#'
        'WIKI#'
        'ENTERWIKI#'
        'BDR#'
        'OFFILE#'
        'GROUP#'
        'SPSPERS#'
        'SPSNEWS#'
        'SPSNHOME#'
    )
    ReviewTemplatePrefixes = @('BLOG#')
    SupportedLanguageLcid = @()
}
```

Detection order is explicit and deterministic:

1. Exact template key in `UnsupportedTemplates` => `TemplateCompatibility = Unsupported`.
2. Template key starts with `ReviewTemplatePrefixes` => `TemplateCompatibility = Review`.
3. Template key starts with `SupportedTemplatePrefixes` => `TemplateCompatibility = Compatible`.
4. Anything else => `TemplateCompatibility = Review`.

A template that could not be read, because the root web raised an error (the one of a site collection
locked with `NoAccess`, for example), is not mapped: `Template` is empty and
`TemplateCompatibility = NotCollected`, with no review alert. The site collection is partial, and its
warnings say that the root web could not be read.

Default intent:

- Personal sites (`SPSPERS#0`) are treated as compatible migration sources
  (migrate to OneDrive), not as unsupported blockers.
- Blog templates are flagged as `Review` by default because migrations usually
  require remapping to modern SharePoint Online structures.

Language behavior:

- `TemplateLanguageLcid` comes from the root web.
- If the LCID was read but is not recognized by .NET culture metadata, `TemplateLanguageReviewRequired = True`.
- If the LCID could not be read, `TemplateLanguageLcid` and `TemplateLanguageReviewRequired` are empty and there is
  no review alert: the site collection is partial, and its warnings say what could not be read.
- If `SupportedLanguageLcid` is non-empty, LCIDs outside that allow-list are flagged for review.

Content types are inventoried for review, including standard definitions and list
bindings. They do not contribute to the default score. Names, groups and content-type
ID prefixes alone do not reliably identify custom or non-portable definitions.

## PermissionLevels section

```powershell
PermissionLevels = @{
    # Localized names, on your farm, of the levels SharePoint provisions
    BuiltInNames = @('<name of View Only>', '<name of Approve>')
}
```

SharePoint gives Limited Access, Read, Contribute, Design, Full Control and Edit a
base type, so they are never custom, even when renamed. Other levels
have no base type: the ones a user creates, and the ones SharePoint provisions for
features and site templates. The provisioned levels are recognized by name, using these
English names: View Only, Approve, Manage Hierarchy, Restricted Read, Restricted
Interfaces for Translation, Moderate and Records Center Web Service Submitters.

Permission level names are localized, so on a farm that is not in English the
provisioned levels have other names and would be reported as custom on almost every
site collection. List those names in `BuiltInNames`; they are added to the English names.
The scan logs a warning when half or more of the site collections report custom
permission levels, which usually means the names are missing. The
`CustomPermissionLevelExamples` field shows which levels were flagged.

## Scope section

```powershell
Scope = @{
    # Keep the personal sites (My Sites) in the inventory (default $false)
    IncludePersonalSites = $false
    # Keep the site masters in the inventory (default $false)
    IncludeSiteMasters = $false
}
```

Personal sites and site masters are not sites to migrate, so the scan leaves them out by
default, also when the section is missing. On a farm with a User Profile Service they are
often most of the site collections: they bury the sites that matter and make the reports
large.

- **Personal sites** (My Sites, `/personal/<user>`) belong to the OneDrive migration. A site
  collection is a personal site when the template of its root web is `SPSPERS`, whatever
  the configuration (`SPSPERS#0`, `SPSPERS#10`, ...). The template needs no User Profile
  Service application, so personal sites whose profile is gone are found too. Set
  `IncludePersonalSites` to `$true` to keep them.
- **Site masters** are hidden site collections that SharePoint creates itself to speed up the
  creation of personal sites. Their host name is `sitemaster-` followed by a GUID, for
  example `https://sitemaster-f5e4136f-1537-43de-a8af-d47447211c44`, and they have the
  personal site template too, usually locked with `NoAdditions`. They are recognized by the
  host name, before the site is opened. Set `IncludeSiteMasters` to `$true` to keep them. A
  site master follows `IncludeSiteMasters` only, never `IncludePersonalSites`.

The My Site host (template `SPSMSITEHOST`, at the root of the My Site web application) is a
real site and always stays in the scan. A site collection whose root web cannot be read is
not recognized as a personal site and stays too.

A site collection that is left out gets no record and no warning. The scan logs how many were
left out of each kind, the HTML summary says so, and the manifest has `Summary.ExcludedPersonalSites`
and `Summary.ExcludedSiteMasters` (see [Usage](Usage#site-collections-left-out-of-the-inventory)).

Version 1.x scanned every site collection. To restore that scope, set both options to `$true`;
the scan then reports as many site collections as 1.x did. A settings file from 1.x has no
`Scope` section, so a scan with it reports fewer site collections than before.

Each option must be `$true` or `$false`. Anything else, such as the string `'false'`, is
rejected when the settings file is loaded, before any site collection is read.

### Long OneDrive URLs

The SMAT scan "Long OneDrive URLs" is **not covered**, by decision. It measures the path of every
file of every personal site against the limit of 400 characters, once the URL of the OneDrive uses the
user principal name (`personal/user_contoso_com`) instead of `personal/domain_user`. That needs what
this inventory does not do: read the files of every personal site, which `IncludePersonalSites` leaves
out by default because those sites belong to the OneDrive migration, and know the user principal name
that each owner will have in the target. The OneDrive migration tooling knows both. With
`IncludePersonalSites` set to `$true` the personal sites are inventoried like any site collection, with
the same signals, but the length of their file paths is not measured.

## Report section

```powershell
Report = @{
    # The HTML report is split in several pages above this number of site collections (default 3000, 0 never splits)
    HtmlSplitThreshold = 3000
    # The number of site collections that a table page holds at most, from 50 to 5000 (default 500)
    HtmlRowsPerPage = 500
}
```

The HTML report is one file, as long as the farm has no more site collections than
`HtmlSplitThreshold`. About 3000 site collections weigh about 5 MB, which still filters at once.
A larger farm gets an **entry page** and, in the same folder, the table of its site collections on
**pages of at most `HtmlRowsPerPage` of them**, one series of pages per category, worst first:

- The entry page is named like the single file (`SPSSiteInventory-PROD-20261028-1146.html`). It keeps the
  summary, the risk indicators, the alerts, the wave plan and the detail sections, and lists the table pages
  by category. It stays small (about 40 KB for 30,000 site collections).
- The table pages are named after it (`SPSSiteInventory-PROD-20261028-1146-sites-blocking-1.html`,
  `...-sites-simple-12.html`). Each one has the same header, the way back to the entry page, the other
  categories, a search box, sortable columns and the details of each site collection.
- A risk indicator of the entry page links to the first table page that has a site collection that raises it,
  with the filter in the address (`#ind=large-lists`). The filter applies to that page; the page links to the
  previous and to the next page that has the indicator, and its other links keep the filter.
- The pages are as self-contained as the single file and link to each other with relative links only: keep
  them together, and the folder can be moved, zipped and sent. The manifest lists them
  (`Files.InventoryHtmlPages`).

With 30,000 site collections, the HTML report is 62 files and about 50 MB, and the largest page is
about 1.3 MB. The CSV and JSON files are not split. Both options must be whole numbers
(`HtmlSplitThreshold` from 0 to 10000000, `HtmlRowsPerPage` from 50 to 5000): anything else, such as the
text `'3000'`, is rejected when the settings file is loaded.

## SharePointAlerts section

```powershell
SharePointAlerts = @{
    # Collect the login name of the owner of each alert (default $true)
    IncludeUserLogin = $true
}
```

The SharePoint alerts report (`*-sharepointalerts-*`, see
[Usage](Usage#sharepoint-alerts)) lists the "Alert Me" subscriptions of the users, with the
login name of each owner so that you can tell them which notifications to replace. A login
name is personal data. Set `IncludeUserLogin` to `$false` to leave it out: `UserLoginName`
stays empty and the owner of an alert is not looked up at all, which also saves a query per
owner. `UserId`, a number local to the site collection that does not name anybody, is kept.

The value must be `$true` or `$false`. Anything else, such as the string `'false'`, is
rejected when the settings file is loaded: it would otherwise count as `$true` and collect
the names you meant to leave out. While the login names are collected, the scan logs a notice
saying that the alert files contain them.

## LargeContentThresholds section

```powershell
LargeContentThresholds = @{
    LargeSiteSizeGB = 100
    LargeListItemCount = 5000
    LargeListViewRowLimit = 5000
    CheckedOutFileCount = 1
    FileVersionCount = 50
    MaxItemsForVersionScanPerLibrary = 2000
    MaxItemsForPublishingPageScanPerLibrary = 2000
    MaxItemsForHtmlFileScanPerLibrary = 2000
    MaxItemsForWebPartScanPerLibrary = 200
    LargeExcelFileSizeMB = 10
    MaxItemsForExcelFileScanPerLibrary = 2000
    MaxItemsForAudienceTargetingScanPerList = 2000
    MaxItemsForNotebookScanPerLibrary = 2000
    MaxAlertRowsPerSite = 5000
}
```

- `LargeSiteSizeGB` — marks `IsLargeSite` when `SizeGB` reaches this value.
- `LargeListItemCount` — minimum list size for `LargeListCount`.
- `LargeListViewRowLimit` — minimum view row limit for `LargeListViewCount`.
- `CheckedOutFileCount` — minimum checked-out files in a library before it is surfaced
  in examples (site-wide checked-out files are always counted).
- `FileVersionCount` — minimum file-version count for `FileVersionCount`.
- `MaxItemsForVersionScanPerLibrary` — cap for per-library file-version scanning.
  When the cap is reached, assessment stays usable but is marked partial with a warning.
- `MaxItemsForPublishingPageScanPerLibrary` — cap for the page-layout scan of each
  publishing Pages library. `PublishingPageCount` still uses the library item count, so
  only the layout summary is affected when the cap is reached.
- `MaxItemsForHtmlFileScanPerLibrary` — cap for the `.htm`/`.html` file count of each
  document library in Permissive web applications. When it is reached, the count is a
  lower bound and the assessment is marked partial with a warning. The query filters on
  the file type column, which is not indexed, so it asks SharePoint to override the list
  view threshold; run the scan as the farm account.
- `MaxItemsForWebPartScanPerLibrary` — cap for the pages whose web parts are read, in each Site
  Pages and Pages library, to count `ScriptWebPartCount` (the home page of each web is always
  read). Reading the web parts of a page is the costliest of the scans, so the default is 200
  pages. When a library has more, the count is a lower bound and the assessment is marked
  partial with a warning. The query filters on the file type column, which is not indexed, so it
  asks SharePoint to override the list view threshold; run the scan as the farm account.
- `LargeExcelFileSizeMB` — minimum size, in MB, of a workbook for `LargeExcelFileCount`. The default,
  10, is the size above which SharePoint Online asks the user to open a workbook in Excel instead of
  the browser. A value that is not a number above 0 is replaced by the default.
- `MaxItemsForExcelFileScanPerLibrary` — cap for the workbooks (`.xlsx`) checked in each document
  library, whatever their size. When it is reached, the count is a lower bound and the assessment is
  marked partial with a warning. The query filters on the file type column, which is not indexed, so it
  asks SharePoint to override the list view threshold; run the scan as the farm account.
- `MaxItemsForAudienceTargetingScanPerList` — cap for the items read in each list that has the audience
  targeting column, to count `AudienceTargetedItemCount`, whatever their value. When it is reached, the
  counts are lower bounds and the assessment is marked partial with a warning. The query reads the pages
  of the list in order of ID, with the override of the list view threshold; run the scan as the farm
  account.
- `MaxItemsForNotebookScanPerLibrary` — cap for the folders of the Site Assets library read to find the
  site notebooks. When it is reached, the count is a lower bound and the assessment is marked partial with
  a warning.
- `MaxAlertRowsPerSite` — cap for the SharePoint alert rows exported per site
  collection. `SharePointAlertCount` stays exact; when the cap is reached the rows are cut,
  the assessment is marked partial and a warning names the setting.

## MigrationWaves section

`MigrationWaves` maps complexity categories to ordered migration waves, consumed by
`Group-SPSMigrationWave`. In a SharePoint Server to SharePoint Online migration the
migrated unit is the **site collection**, so waves are planned per site by complexity —
content databases are an on-premises storage concern with no SharePoint Online equivalent
and are not used here.

```powershell
MigrationWaves = @(
    @{ Wave = 1; Name = 'Quick wins'; Categories = @(1) }
    @{ Wave = 2; Name = 'Light remediation'; Categories = @(2) }
    @{ Wave = 3; Name = 'Rebuild'; Categories = @(3) }
    @{ Wave = 4; Name = 'Projects / blockers'; Categories = @(4) }
)
```

Each entry lists the categories it groups. The default above is **one wave per category**.
To put every non-blocking site in the first wave instead:

```powershell
MigrationWaves = @(
    @{ Wave = 1; Name = 'Migrate now'; Categories = @(1, 2, 3) }
    @{ Wave = 2; Name = 'Projects';    Categories = @(4) }
)
```

A site whose category is not listed in any wave lands in an **Unassigned** bucket (wave 0),
surfaced in the report rather than silently dropped. When `MigrationWaves` is omitted from
the settings, the one-wave-per-category default of the [target mode](#targetmode-section) is
applied. The on-premises example ships its own waves (*Ready*, *Light remediation*, *Rebuild
(SPFx)*, *Blocked*), which are also that default.

Two other buckets of wave 0 do not come from the mapping:

- **Not assessed**: the assessment of the site collection failed, so it has no category.
- **Needs review**: the assessment is partial and the category is 1 (Simple). What could not
  be read counts as 0 in the score, so the site collection can look simple without being so:
  it waits in this bucket until it is read in full, and the mapping does not move it, whatever
  wave takes the category 1. Its `Category` and `Score` are not changed. A partial site
  collection of another category keeps the wave of its category, because what could not be
  read can only raise its score; the wave plan of the HTML report counts the partial site
  collections of each wave. To plan a site collection that is in this bucket, fix what the
  warnings of its record say (an unreadable item, or a cap such as
  `LargeContentThresholds.MaxItemsForVersionScanPerLibrary`) and run the inventory again.

## Tuning

Start from the example weights and run the inventory once. Review the distribution of
categories, then adjust the weights and thresholds so the categories match your migration
reality. Because scoring is a pure function, you can re-score an exported JSON without
re-scanning the farm.
