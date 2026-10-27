# Configuration

SPSSiteInventory reads a PowerShell data file (`.psd1`). Copy
`config/inventory-settings.example.psd1` to `config/inventory-settings.psd1` (gitignored)
and adjust it. No client-specific value ships in the repository.

## Top-level settings

| Setting | Type | Description |
| --- | --- | --- |
| `EnvName` | string | Free-form environment identifier (e.g. `PROD`), used in output file names and the banner. |
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
| `SharePointAlerts` | hashtable | Options of the SharePoint alerts report (`IncludeUserLogin`, default `$true`). Optional. |
| `Scoring` | hashtable | The scoring engine configuration (see below). **Mandatory.** |
| `MigrationWaves` | hashtable[] | The category-to-wave mapping (see below). Optional; a one-wave-per-category default applies when omitted. |

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
- `CustomMasterPage` — true when a web uses a master page other than the default seattle,
  oslo or v4 master.
- `EventReceivers` — the custom event receivers described above.
- `UsesCustomFarmFeature` — see [BlockingSignals](#blockingsignals).
- `UniquePermissionsCount` — the role assignments on the webs that do not inherit their
  permissions. The root web always has its own, so the value is never 0, and a subsite with
  unique permissions adds its own: it is not a count of webs.

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
  so the migration tools skip it until it is unlocked. `ReadOnly` and `NoAdditions` locks
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

Default intent:

- Personal sites (`SPSPERS#0`) are treated as compatible migration sources
  (migrate to OneDrive), not as unsupported blockers.
- Blog templates are flagged as `Review` by default because migrations usually
  require remapping to modern SharePoint Online structures.

Language behavior:

- `TemplateLanguageLcid` comes from the root web.
- If LCID is missing or not recognized by .NET culture metadata, `TemplateLanguageReviewRequired = True`.
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
the settings, the one-wave-per-category default is applied.

## Tuning

Start from the example weights and run the inventory once. Review the distribution of
categories, then adjust the weights and thresholds so the categories match your migration
reality. Because scoring is a pure function, you can re-score an exported JSON without
re-scanning the farm.
