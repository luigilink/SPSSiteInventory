# Usage

## Running a scan

```powershell
.\Invoke-SPSSiteInventory.ps1 -ConfigPath .\config\inventory-settings.psd1
```

The orchestrator:

1. starts a transcript and prints a banner;
2. loads the SharePoint commands and your settings;
3. builds the farm-solution map (custom-code detection);
4. reads configured authentication across all zones, then enumerates site collections (personal sites and site masters are left out unless the `Scope` settings keep them);
5. collects customization signals, content-type definitions and list bindings, and scores each site;
6. exports CSV, JSON and a self-contained HTML report to the configured output folder.

Progress is reported for both site-collection enumeration and per-site assessment.
Collection read failures are recorded as partial or failed assessments and do not
prevent later site collections from being processed. A web application whose site
list cannot be read, or whose lazy enumeration stops early, is represented by a
`WebApplication`-scope failure row; earlier site records are retained. Partial scores
are provisional, because what could not be read counts as 0: a Simple site collection
with a partial assessment is placed in the `Needs review` wave, not in the quick wins,
until it is read in full, and a partial site collection of another category keeps the
wave of its category. Failed site assessments have no category or score and are placed
in the `Not assessed` wave. Review collector warning details, transcript progress and
the report's status fields before planning migration waves.

## Output files

Each run writes the site inventory in three timestamped formats, a modular JSON
report pack, plus a dedicated farm-solution report, to the output folder:

| File | Purpose |
| --- | --- |
| `*.csv` | Site inventory for review in Excel; one row per site collection. |
| `*.json` | Site inventory for downstream automation (for example feeding migration wave planning). |
| `*.html` | A shareable, self-contained report to read: summary and risk indicators, alerts, migration wave plan, a compact table of the site collections (worst first, one row to open for the details) and the detail sections. A farm with more than 3000 site collections gets an entry page and table pages in the same folder, named after it (`*-sites-<category>-<n>.html`): see [Reading the HTML report](#reading-the-html-report) and the [`Report` section](Configuration#report-section). |
| `*-manifest-*.json` | Report-pack manifest with the layout version (`ReportPackVersion`), generation metadata, top-level counters and file references. |
| `*-sites-*.json` | Site inventory dataset used by the dashboard/report-pack consumers. |
| `*-auth-*.json` | Authentication-by-web-application dataset (zone/provider summary + collection counts). |
| `*-workflows-*.json` | Workflow/template-focused dataset (`Workflow2010Count`, `Workflow2013Count`, running-instance counts, template-compatibility and template-language review fields, status, category). |
| `*-apps-*.json` | App-focused dataset (`AppInstanceCount`, `AppWebCount`, `AppInstanceExamples`, status, category). |
| `*-permissions-*.json` | Permissions and policy dataset (`CustomPermissionLevelCount`/`Examples`, `EmailEnabledListCount`/`Examples`, `HtmlFileCount`/`Examples`, plus the web application values `BrowserFileHandling`, `WebAppPolicyCount`/`Examples` repeated per site collection, status, category). Web application failure rows (`InventoryScope` = `WebApplication`) are included so the policy values read for an application whose site collections could not be enumerated are kept. |
| `*-publishing-*.json` | Publishing and customized-page dataset (`PublishingInfrastructureEnabled`, `PublishingWebCount`, `PublishingPageCount`, `PublishingPageLayoutCount`/`PublishingPageLayoutExamples`, `CustomizedPageCount`/`CustomizedPageExamples`, status, category). |
| `*-irm-locks-*.json` | Security/lock dataset (`IrmEnabledListCount`, `SiteLockState`, `IsLockedSite`, `HasNoAccessLock`). |
| `*-large-content-*.json` | Large-content risk dataset (`IsLargeSite`, large lists/views, checked-out files, high file-version counts, large Excel files, plus examples). |
| `*-collaboration-*.json` | Collaboration dataset (`AudienceTargetedListCount`, `AudienceTargetedItemCount`, `AudienceTargetedExamples`, `SiteNotebookCount`, `SiteNotebookExamples`, status, category). |
| `*-alerts-*.csv` / `*-alerts-*.json` | Normalized risk alerts extracted from the site signals, each with its severity, an explanation and a remediation hint (and the Microsoft Learn page behind it). The `SharePointOnPrem` mode has its own severity and words for them. One alert per site collection and signal; web application and BCS alerts are written once per web application and per LOB system. The CSV is for Excel, the JSON for automation. The alert types and their advice are listed in [Alerts and remediation](Alerts). |
| `*-solutions-*.csv` | Farm-solution (WSP) inventory for Excel; one row per solution, with the feature scopes/ids flattened. |
| `*-solutions-*.json` | Farm-solution (WSP) inventory for automation, with the feature scopes/ids kept as arrays. |
| `*-contenttypes-*.csv` / `*-contenttypes-*.json` | Content-type definitions and list bindings, including standard types. One row per web definition or list binding, not per item. |
| `*-managedmetadata-*.csv` / `*-managedmetadata-*.json` | Managed metadata columns by list, following the SMAT Managed Metadata Columns report. One row per list or library with at least one visible managed metadata column. |
| `*-externallists-*.csv` / `*-externallists-*.json` | External lists by list, following the SMAT External List report. One row per list backed by a Business Connectivity Services (BCS) external content type, with its BCS binding. |
| `*-bcs-*.csv` / `*-bcs-*.json` | BCS LOB systems of the farm, following the SMAT BCS report. One row per LOB system, with its type, instances and entities. |
| `*-securestore-*.csv` / `*-securestore-*.json` | Secure Store target applications of the farm, following the SMAT Secure Store report. One row per target application, with its name, display name, contact e-mail address, type, credential management URL and ticket time-out. The contact e-mail address is personal data, so it is not part of the HTML report. |
| `*-sharepointalerts-*.csv` / `*-sharepointalerts-*.json` | SharePoint alerts ("Alert Me" subscriptions) by alert, following the SMAT Alerts report. One row per alert, with where it applies, what triggers it, how often it is sent and who owns it. Not the risk alerts of `*-alerts-*`. They contain the login names of the owners, unless `SharePointAlerts.IncludeUserLogin` is `$false`, so they are not part of the HTML report. |

### Site collections left out of the inventory

Personal sites and site masters are left out by default (see the `Scope` section of
[Configuration](Configuration#scope-section)). They get no record in any file. The inventory
says how many were left out:

- the HTML summary box shows a line such as "109 personal site(s) and 10 site master(s) were
  left out of this inventory (Scope in the settings)", only when something was left out;
- the manifest has `Summary.ExcludedPersonalSites` and `Summary.ExcludedSiteMasters`, two
  integers that are always present (0 when nothing was left out or when both kinds are
  included);
- the log of the scan has an `Information` line with the same counts and the settings to change.

`Summary.SiteCollections` counts the site collections of the report, so it does not include
the ones that were left out. The new manifest fields are additive: `ReportPackVersion` stays `1.0`.

### CSV files and spreadsheet formulas

The CSV files are meant to be opened in a spreadsheet, and text typed by the users of the farm
reaches them: titles of sites, lists, content types and alerts, CAML filters, and so on. A
spreadsheet reads a cell that starts with `=`, `+`, `-` or `@`, or with a tab, a carriage return
or a line feed, as a formula, and some locales read the full-width forms of `=`, `+`, `-` and
`@` the same way. A user could therefore craft a title, such as a `HYPERLINK` or a DDE formula,
that runs on the machine of the administrator who opens the file (CSV injection).

Every CSV the toolkit writes therefore puts a single quote in front of a text cell that starts
with one of those characters, as the [OWASP guidance](https://community.owasp.org/attacks/CSV_Injection)
recommends: the spreadsheet reads the cell as text and shows it after the quote. For example, the
title `=HYPERLINK("http://example.test","x")` is written as `'=HYPERLINK("http://example.test","x")`.

- Only text cells change. Numbers (a negative number included), booleans and dates are left alone,
  so a spreadsheet still reads a number as a number. A text cell is always checked, even when it
  looks like a number, because text typed by a user cannot be told from a number.
- The JSON files keep the original text, and so does the HTML report, which encodes it. Read the
  JSON when a script needs the exact values.
- A script that parses a CSV file must remove that leading quote.
- The header row is not changed.

OWASP states that no CSV sanitization is safe for every spreadsheet. Two things to know:

- **Do not save these files as CSV again.** Excel can drop the quote when a file is saved as CSV
  and opened again, which would turn such a cell back into a formula. Treat the CSV files as
  reports to read, and use the JSON files as the data.
- Export-Csv writes every field between double quotes and doubles the quotes inside the text, so
  a comma or a quote typed by a user stays inside its cell when the spreadsheet reads the file as
  the comma-separated CSV it is (for example with Data > From Text/CSV in Excel).

The HTML report also includes configured authentication by web application/zone,
an alerts section that groups the alerts by type with what to do about each, a content-type
summary, a managed metadata section, an external list section, a BCS application section
and a Secure Store section. Authentication errors stop the scan rather than silently
producing Windows-only results. Unrecognized/federated providers are flagged for identity
review; a missing provider identity leaves `HasFbaZone` unknown unless FBA was positively
detected in another provider or zone.

## Output fields

CSV/JSON rows describe site collections and any web-application enumeration failures:

| Field | Description |
| --- | --- |
| `Url` | Site collection URL |
| `Title` | Root web title |
| `WebApp` | Web application name |
| `WebAppUrl` | Web application URL, used to distinguish applications with the same display name |
| `AuthenticationModes` / `AuthenticationZones` | Configured modes and zone/provider summary across every IIS zone, including mixed Windows/FBA |
| `FbaMembershipProviders` / `FbaRoleProviders` | Configured FBA provider names; no credentials or membership data |
| `HasFbaZone` | FBA is configured on at least one zone of the web application; not a measurement of user activity |
| `AuthenticationReviewRequired` | A federated/custom or unidentified provider requires identity review |
| `ContentDb` | Content database name |
| `Template` | Root web template (e.g. `STS#3`, `SITEPAGEPUBLISHING#0`) |
| `TemplateCompatibility` / `TemplateCompatibilityReason` | Baseline SPO template mapping result: `Compatible`, `Unsupported`, or `Review`, with the rule that triggered it. `NotCollected` when the template could not be read (the root web raised an error, as that of a `NoAccess` lock does): `Template` is then empty and the site collection is partial |
| `IsUnsupportedSiteTemplate` | Template is explicitly mapped as unsupported for direct SPO migration |
| `TemplateLanguageLcid` / `TemplateLanguageTag` / `TemplateLanguageName` | Root-web language metadata used for template-language parity checks. Empty when the language could not be read |
| `TemplateLanguageReviewRequired` / `TemplateLanguageReason` | Language metadata is unrecognized or outside configured allow-list and needs review. Empty (not `False`) when the language could not be read: that is not a language to review, the site collection is partial and its warnings say what could not be read |
| `SizeGB` | Storage used, in GB, to four decimals (about 100 KB), so that small site collections are not all 0 |
| `SubWebCount` | Number of webs in the site collection, the root web included |
| `SubsiteCount` / `MaxSubsiteDepth` / `SubsiteExamples` | Webs below the root web (app webs left out), the deepest level of that hierarchy (1 = directly below the root web) and up to five of the deepest subsites as `path (level n)`. SharePoint Online supports subsites, but modern SharePoint favors flat site collections connected by hub sites: weighted lightly, never blocking |
| `LastModified` | Last item modified date (dormancy signal) |
| `InventoryScope` | `SiteCollection` for site rows or `WebApplication` for enumeration failure rows |
| `SiteInventoryComplete` / `SiteInventoryWarnings` | Whether identity, size and root-web metadata were collected; warning text describes missing data |
| `CustomizationInventoryComplete` | False means one or more customization signals may be missing |
| `Workflow2010Count` | Active SharePoint 2010 workflow associations (legacy engine, retired in SPO); historical "previous version" associations are excluded when detectable |
| `Workflow2013Count` | SharePoint 2013 workflow subscriptions (Workflow Manager) |
| `Workflow2010RunningInstanceCount` | Active SharePoint 2010 workflow runtime instances where counters are exposed |
| `Workflow2013RunningInstanceCount` | Active SharePoint 2013 workflow runtime instances where instance APIs are available |
| `AppInstanceCount` / `AppInstanceExamples` | SharePoint add-in instances detected across the site collection and up to five examples (name + web URL) |
| `AppWebCount` | Number of webs identified as app webs (`APP#*` / `IsAppWeb`) |
| `PublishingInfrastructureEnabled` | The SharePoint Server Publishing Infrastructure site collection feature is active |
| `PublishingWebCount` | Number of webs where the SharePoint Server Publishing feature is active |
| `PublishingPageCount` | Items in the Pages libraries of publishing webs |
| `PublishingPageLayoutCount` / `PublishingPageLayoutExamples` | Distinct page layouts, identified by path, used by the scanned pages (lower bound when the scan cap is reached) and up to five examples, shown as the path below the Master Page Gallery with their page counts |
| `CustomPermissionLevelCount` / `CustomPermissionLevelExamples` | Distinct custom permission levels in the site collection and up to five examples with the web that defines them. Provisioned levels are recognized by type and by name (`PermissionLevels.BuiltInNames`) |
| `EmailEnabledListCount` / `EmailEnabledListExamples` | Lists with incoming e-mail enabled and up to five examples (title and list URL) |
| `HtmlFileCount` / `HtmlFileExamples` | `.htm`/`.html` files in document libraries and up to five examples. Collected only when the web application is Permissive, otherwise 0 |
| `ManagedMetadataListCount` / `ManagedMetadataColumnCount` | Lists with at least one visible managed metadata column, and those columns counted once per list. Enterprise Keywords is included; hidden columns and hidden lists (the newsfeed list of every site) are not |
| `ManagedMetadataTermSetCount` / `ManagedMetadataExamples` | Distinct term sets, by ID, that those columns use in the site collection, and up to five lists with their column names |
| `ExternalListCount` / `ExternalListExamples` | Lists backed by a BCS external content type (not migrated) and up to five examples with their entity |
| `SharePointAlertCount` | SharePoint alerts ("Alert Me" subscriptions) of every user, in every web of the site collection. Migration tools do not migrate them and SharePoint Online retired them from July 2026. Exact even when the rows are capped |
| `BrowserFileHandling` | Web application setting, `Strict` or `Permissive`. SharePoint Online enforces Strict |
| `WebAppPolicyCount` / `WebAppPolicyExamples` | Web application policies (all zones and each zone), including accounts SharePoint adds itself, and the first ten as `user: permission levels`. They are not migrated |
| `CustomizedPageCount` / `CustomizedPageExamples` | Customized (unghosted) pages at the root of each web, ignoring System Account edits, and up to five server-relative URLs. List view and form pages are not scanned |
| `InfoPathFormCount` | InfoPath-driven lists/libraries (retired, no SPO equivalent) |
| `IrmEnabledListCount` | Number of lists/libraries with IRM enabled |
| `IsLargeSite` | Site is above the configured large-site threshold |
| `LargeListCount` / `LargeListExamples` | Number of large lists and up to five list examples with item counts |
| `LargeListViewCount` / `LargeListViewExamples` | Number of large-list views and up to five list/view examples with row limits |
| `CheckedOutFileCount` / `CheckedOutFileExamples` | Number of checked-out files and up to five impacted libraries |
| `FileVersionCount` / `FileVersionExamples` | Number of files above the configured file-version threshold and up to five examples |
| `LargeExcelFileCount` / `LargeExcelFileExamples` | Excel workbooks (`.xlsx`) in document libraries of at least `LargeContentThresholds.LargeExcelFileSizeMB` (10 MB by default) and up to five of them with their size. SharePoint Online does not open a workbook above 10 MB in the browser: it asks the user to open it in Excel. The workbooks are migrated, so the signal says whom to warn. System catalogs are skipped, and at most `MaxItemsForExcelFileScanPerLibrary` workbooks are checked in each library (2000 by default) |
| `AudienceTargetedListCount` / `AudienceTargetedItemCount` / `AudienceTargetedExamples` | List items that target an audience (the Target Audiences column is not empty), the lists that hold them, and up to five of those lists with the number of items and the audiences, for example `/sites/team/Lists/Announcements (3 item(s): Sales, Marketing)`. An audience of the User Profile service is shown by its name, or by its ID when it cannot be resolved. The audience data does not migrate: the items are shown to every reader afterwards. Hidden lists and the system catalogs are skipped, and at most `LargeContentThresholds.MaxItemsForAudienceTargetingScanPerList` items are read in each list |
| `SiteNotebookCount` / `SiteNotebookExamples` | Site notebooks (the OneNote notebooks of the Site Assets library whose name ends in `Notebook`) and up to five of them. The notebook is migrated under another name, so the links to it break. A notebook with no section is listed too, which SMAT leaves out. At most `LargeContentThresholds.MaxItemsForNotebookScanPerLibrary` folders of the library are read |
| `SiteLockState` / `IsLockedSite` / `HasNoAccessLock` | Site collection lock state (`Unlock`, `ReadOnly`, `NoAdditions`, `NoAccess`, `Unknown`), whether the site has any lock, and whether the lock is `NoAccess`, the only one that makes the site unreadable (and blocking in the example configuration). SharePoint refuses to read a `NoAccess` site collection at all, even its lock flags, so the lock is recognized from that error and the site collection stays `Partial`. `Unknown` means that the flags could not be read for another reason, and comes with a warning |
| `UsesFullTrustCode` | Site activates a feature from a custom full-trust WSP (GAC assembly) |
| `UsesCustomFarmFeature` | Site activates a feature from a custom farm solution (WSP), as identified by the farm-solution map |
| `SandboxSolutions` | Sandbox (user) solutions in the solution gallery of the site collection, activated or not |
| `CustomMasterPage` | At least one web of the site collection uses a master page other than the ones that SharePoint provisions in the master page gallery (`seattle.master`, `oslo.master`, `v4.master` and, for the My Site templates, `mysite15.master`) |
| `AlternateCssUrlCount` / `AlternateCssUrlExamples` | Webs that set an alternate CSS URL, and up to five as `web URL (CSS URL)`. Modern pages do not use it: the branding is redone, with a site theme for example |
| `XsltListViewCount` / `XsltListViewExamples` | List views that render with XSLT (an `XslLink` other than the default `main.xsl`, or an `Xsl` of their own; personal views and the views of hidden lists are not counted) and up to five as `list/view`. The modern list ignores XSLT, so SharePoint shows such a list in the classic experience |
| `ScriptWebPartCount` / `ScriptWebPartExamples` | Script Editor web parts, and Content Editor web parts that embed a `<script>` tag or link to a file, on the home page of each web and on the pages of its Site Pages and Pages libraries, and up to five as `page URL (Script Editor)` or `page URL (Content Editor)`. They do not exist on a modern page. At most `MaxItemsForWebPartScanPerLibrary` pages of a library are read (200 by default); the web parts of list view and form pages are not read |
| `ClassicExperienceOptOutCount` / `ClassicExperienceOptOutExamples` | The site collection and the webs that opted out of the modern list and library experience (the feature `E3540C7D-6BEA-403C-A224-1A12EAFEE4C4` of the site collection and the feature `52E14B6F-B1BB-4969-B89B-C4FAA56745EF` of a web, one each), and up to five as `URL (site collection)` or `URL (web)` |
| `ClassicExperienceListCount` / `ClassicExperienceListExamples` | Lists, hidden ones left out, whose "List experience" setting is classic (`ListExperienceOptions`), and up to five as `title (list URL)`. It is 0 on a SharePoint that has no such setting, such as SharePoint Server 2016 |
| `ModernBlockerCount` / `ModernBlockers` | The kinds of blocker of the modern experience that the site collection has, out of seven (custom master page, alternate CSS URL, publishing features, XSLT list views, script web parts, opt-out of the modern list experience, lists forced to classic), and one text that says how many webs, views, web parts or lists are behind each. Not weighed in the example configurations: each blocker weighs through its own signal |
| `EventReceivers` | Event receivers registered on lists from a custom (non-Microsoft) assembly; out-of-the-box receivers are not counted |
| `UniquePermissionsCount` | Role assignments on the webs that do not inherit their permissions. The root web always has its own, so the value is never 0: it is not a count of webs with unique permissions |
| `ContentTypeCount` | Distinct content-type IDs seen in web definition collections, deduplicated within this site collection |
| `ListContentTypeBindingCount` | Number of content-type bindings across the collection's lists, not the number of distinct designs |
| `ContentTypeInventoryComplete` | False means partial collection: review warnings before interpreting counts or missing definitions |
| `AssessmentStatus` | `Complete`, `Partial` (score may omit unreadable inputs; a Simple site collection that is partial is in the `Needs review` wave), or `Failed` (not scored) |
| `AssessmentWarnings` | Collection/assessment failures associated with this record; also shown in the HTML report. Warnings of the same kind in one site collection, which differ only by the names between quotes of their subject (list titles, web URLs), are written once: the first one in full followed by ` [+N similar]`, where N is the number of other occurrences. Warnings that differ by anything else (the reason, a number) stay separate. The same grouped text appears in `Reasons`; the assessment status does not change |
| `Category` | Complexity category 1–4 |
| `CategoryName` | Simple / Moderate / Complex / Blocking |
| `Wave` | Proposed migration wave number (from the category-to-wave mapping); 0 for a site collection that is in no wave (see `WaveName`) |
| `WaveName` | Proposed migration wave name, or `Needs review` (a Simple site collection whose assessment is partial), `Not assessed` (a failed assessment) or `Unassigned` (a category that no wave takes) |
| `Score` | Numeric complexity score |
| `Reasons` | Human-readable drivers of the score |

## Farm-solution report fields

Each row in the `*-solutions-*` CSV/JSON describes one farm solution (WSP):

| Field | Description |
| --- | --- |
| `SolutionName` | Solution (WSP) name |
| `SolutionId` | Solution GUID |
| `Deployed` / `DeploymentState` | Whether and how the solution is deployed |
| `IsCustom` | Auto-detected as custom (any solution that is not a known Microsoft / OOTB one); can be forced via `CustomSolutionPrefix` |
| `ContainsGlobalAssembly` | Deploys an assembly to the GAC (full-trust code) |
| `ContainsCasPolicy` | Ships a Code Access Security policy |
| `ContainsWebApplicationResource` | Deploys web-application-scoped resources |
| `IsFullTrustCode` | Custom **and** deploys a global assembly (SPO blocker) |
| `DeployedWebApplicationCount` / `DeployedServerCount` | Deployment reach |
| `FeatureCount` / `FeatureScopes` / `FeatureIds` | Features the solution registers |

The farm only gives booleans and, for a solution that is not deployed, no feature. To read the package itself (strong names and public key tokens of its assemblies, the features and scopes, the framework it was built for), with no farm, see [Inspecting WSP packages (offline)](Solution-Packages).

## Reading the results

### Reading the HTML report

The HTML report is made to be read. The CSV and JSON files keep every column and every row.

A farm with up to 3000 site collections (the `Report.HtmlSplitThreshold` setting) gets **one file**. A
larger one gets an **entry page**, which is the file named like the other reports, and **table pages** in
the same folder: the site collections are on pages of at most 500 of them (`Report.HtmlRowsPerPage`), one
series per category, worst first. Open the entry page: its *Site collections* section lists the pages, and a
risk indicator opens the first page that has a site collection that raises it, with the filter on (`#ind=...`
in the address). That page links to the previous and the next page that have the indicator, and its search,
sort and details work on the page. Keep the pages together: they link to each other with relative links, so the
folder can be moved, zipped and sent. The manifest lists the pages in `Files.InventoryHtmlPages`.

- **Summary, risk indicators, alerts and migration waves** come first.
  - The **risk indicators** are a ranked list: each signal that at least one site collection
    raises has a bar for the share of site collections, with the count, grouped by the severity
    of its alert (High blocks or breaks a migration, Medium needs a plan or a check, Low is
    information to pass on, like the [alerts](Alerts)). A signal that has no alert has its own
    severity. The signals that no site collection raises are named on one line. Click an
    indicator to filter the inventory table to the site collections that raise it; click it
    again, or the button that appears next to the filters, to remove the filter.
  - The **alerts** are lines with their severity, name and number of affected site collections.
    Open one to read what it means, what to do about it and the Microsoft Learn page.
  - The **modern experience readiness** section is in the report of the
    [`SharePointOnPrem` mode](Configuration#targetmode-section) only, after the alerts. It says how
    many assessed site collections have a blocker of the modern experience (a custom master page,
    an alternate CSS URL, publishing features, XSLT list views, script web parts, an opt-out of the
    modern list experience, lists forced to classic), how many site collections have each kind and how
    many items are behind it, and lists the site collections that have a blocker, the most kinds
    first, then the highest score, at most 100 of them. A site collection whose assessment is
    partial is marked, because its counts are lower bounds. The `ModernBlockerCount` and
    `ModernBlockers` columns of the CSV and JSON files hold the same for all of them.
  - The **migration wave plan** gives, for each wave, the number of site collections, their
    content and how many of them are partial. The `Needs review` wave holds the Simple site
    collections whose assessment is partial, and the summary says how many wait there.
- **Site collections** is the inventory table, right after the wave plan. Each site collection
  has one row with its title and URL, category, score, wave, size, template, last modification,
  status and reasons, **worst first** (not assessed, Blocking, Complex, Moderate, then Simple, by
  score). The reasons that block a site come first in the row. Open the row (the arrow on its
  left) to see the context of the site collection (web application, content database,
  authentication, template language, number of webs, content types), **the signals it raises**
  with their count and examples, its assessment warnings and its full reasons. A signal that is
  at zero is not listed. Click a column heading to sort, use the category buttons to filter, and
  type in the search box to find a site collection by name, URL, template or signal; the count
  next to them says how many site collections are shown.
- **Farm solutions, authentication, web application policies, content types, managed
  metadata, external lists, BCS applications and Secure Store applications** follow. The
  managed metadata, external list, BCS, Secure Store, farm solution and full-trust site tables
  show at most 200 rows and say how many are not shown and which files hold all of them. The content types are not listed in the report,
  because there are thousands of them: it shows how many definitions and list bindings there
  are, and the `*-contenttypes-*` files hold every row.

The fields of the web application sections (browser file handling, policies, authentication)
are shown once per web application in their section, not on every site collection.

### Content-type detail

The `*-contenttypes-*` files retain `SiteUrl`, `WebUrl`, `Scope` (`Web` or `List`),
`ListTitle`, `ListUrl`, `ContentTypeId`, `ParentContentTypeId`, `Name`, `Group`,
`FieldCount`, `FieldTypes`, `DocumentTemplateUrl`, `Hidden`, `ReadOnly` and `Sealed`.
List-specific IDs are kept alongside their parent IDs rather than merged into site
definitions. Field types and template URLs are review leads, not a complete schema
export or proof of a WSP dependency. Standard types are included and are not
automatically classified as custom or blocking. Collection happens during the existing
site walk; it does not add a separate full-site scan.

### Managed metadata detail

The `*-managedmetadata-*` files hold one row per list or library with at least one visible
managed metadata column, like the SMAT Managed Metadata Columns report: `SiteUrl`,
`WebUrl`, `ListTitle`, `ListUrl`, `ListTemplate`, `ListType`, `ListItemCount`,
`ItemLastModifiedDate` (as SharePoint returns it, written as `yyyy-MM-dd HH:mm:ss`),
`ManagedMetadataColumnCount`, `ManagedMetadataColumns` (column titles separated by `; `)
and `TermSetIds` (the distinct term set GUIDs the columns use, separated by `; `). The
list creator that SMAT reports is not collected. Rows are only written for lists whose
columns and properties could all be read: an unreadable list marks the site `Partial`
with a warning, so check `CustomizationInventoryComplete` before treating the files as
complete.

Managed metadata columns take their values from the term store. They usually migrate
with their list, as long as the term sets they use are migrated too:

1. Size the work with the per-site `ManagedMetadataListCount` and
   `ManagedMetadataTermSetCount`, and the `TermSetIds` column to see which sites share a
   term set.
2. Migrate these lists close to the term store migration rather than long before or
   after it.
3. After the migration, check that items in these lists can still be created and edited.

Term sets appear as IDs because the inventory never queries the term store service. To
find the name of a term set, match its ID with the **Unique Identifier** shown on the
General tab of the term set in the Term Store Management Tool.

### External lists and BCS applications

The `*-externallists-*` files hold one row per external list: `SiteUrl`, `WebUrl`,
`ListTitle`, `ListUrl` and the BCS binding SharePoint stores with the list,
`LobSystemInstance`, `EntityNamespace` and `Entity`. The binding is read from the list
definition, so neither the Business Data Connectivity (BDC) service nor the external
system is called. Item counts and dates are not collected because the items are not stored
in SharePoint, and the list creator that SMAT reports is not collected. A list whose
binding cannot be read is still counted in `ExternalListCount`, so it cannot hide a
blocking signal, but its row is left out of the files and the site is marked `Partial`
with a warning: check `CustomizationInventoryComplete`.

The `*-bcs-*` files hold one row per BCS LOB system defined in the farm, like the SMAT BCS
report: `WebApplicationUrls`, `BdcServiceApplicationId`, `LobSystemName`, `LobSystemType`
(`Database`, `WebService`, `Wcf`, `DotNetAssembly`, `Custom` or `OData`),
`LobSystemInstances`, `EntityCount` and `LobEntities` (`namespace.name`, at most 20 names).
The BDC service application of each web application is found through the service
application proxy group of the web application and read through its proxy, for the default
(non-tenant) partition, so a web application without any site collection is read too, and
a web application whose proxy group has no BDC proxy simply has no BCS. Web applications
that share a BDC service application report its LOB systems once, with every web
application that sees it; a store is identified by `BdcServiceApplicationId`, never by a
catalog ID, which only identifies an object inside one store. Connection settings,
credentials and Secure Store targets are not read, and the external systems are not
contacted. A web application or LOB system that cannot be read
is reported as a warning in the run log and marks the BCS report partial: the
`BcsInventoryPartial` alert, `Summary.BcsInventoryComplete` in the manifest and a note in
the HTML report say that BCS applications may be missing.

Microsoft retired BCS in SharePoint Online (SharePoint in Microsoft 365) on 30 September
2024: external lists, external columns, external content types and hybrid BCS solutions are
no longer available there, and there is no direct migration. See
[Business Connectivity Services (BCS) retirement in Microsoft 365](https://learn.microsoft.com/en-us/sharepoint/business-connectivity-services-retirement).
To plan the work:

1. List the BCS applications in `*-bcs-*`, then find who uses them in `*-externallists-*`
   by matching `LobSystemInstance` with `LobSystemInstances`.
2. For each external system, plan a replacement of the scenario. Microsoft recommends
   Power Apps, which reaches many data sources through connectors and on-premises data
   through the on-premises data gateway.
3. BCS is not retired in SharePoint Server Subscription Edition, so a target that stays
   on-premises can keep using it.

In the example configuration a site with external lists is classed **Blocking** (category
4), like a site with InfoPath forms, because the scenario has to be rebuilt. The site
collection itself can still be migrated without those lists. Remove `ExternalListCount`
from `BlockingSignals` to treat it as remediation instead.

### Secure Store applications

The Secure Store Service stores credentials and maps them to the identity of a user or a group.
A *target application* is one of these mappings, and the solutions refer to it by its ID: a BCS
external list, an Excel Services data connection, a PerformancePoint data source and the like.
Secure Store applications are not migrated to SharePoint Online, so the ones that are still
needed have to be created again in the target. The `*-securestore-*` files hold one row per
target application, like the SMAT Secure Store report:

| Field | Description |
| --- | --- |
| `WebApplicationUrls` | The web applications that use the Secure Store, separated by `; ` |
| `SecureStoreProxyName` / `SecureStoreProxyId` | The Secure Store proxy that those web applications use. A store is identified by its proxy, so web applications that share one report its applications once |
| `Name` | The target application ID: the unique name that the solutions use to refer to it (SMAT calls it both `ApplicationID` and `Name`) |
| `FriendlyName` | The display name |
| `ContactEmail` | The contact e-mail address of the application. It is personal data: it is in these files only, never in the HTML report |
| `ApplicationType` | `Individual`, `Group`, `IndividualWithTicketing`, `GroupWithTicketing`, `RestrictedIndividual` or `RestrictedGroup`. The target only supports the Group Restricted type, which is `RestrictedGroup` |
| `CredentialManagementUrl` | The URL where the users manage their credentials, when the application has one |
| `TicketTimeoutMinutes` | The ticket time-out in minutes: from 1 for a type with tickets, 0 for the others ([MS-SSWPS](https://learn.microsoft.com/en-us/openspecs/sharepoint_protocols/ms-sswps/bbd7588a-abb2-46ab-96f3-fe4d027b8c3d)) |

The Secure Store service application of each web application is found through the service
application proxy group of the web application, and read with `Get-SPSecureStoreApplication`
through the service context of that group, for the default (non-tenant) partition. No site
collection is needed, so a web application without any site collection is read too, and a web
application whose proxy group has no Secure Store proxy simply has no Secure Store (when no web
application has one at all, the run log says so: a farm without the Secure Store service has none,
and a proxy type that is not recognized would look the same). Web applications that share a
Secure Store proxy report its applications once, with every web application that sees it. A
service context binds the default Secure Store proxy of its group, so that proxy identifies the
store: a group that holds several is read through its default one, and groups that hold the same
proxies with other defaults are read once each. A proxy that is the default of no group that was
read cannot be read, and neither can the applications of a group whose default cannot be told:
the report is partial. The fields of the applications and the credentials are never read, and no
external system is contacted.

A web application, proxy or application that cannot be read is reported as a warning in the run
log and marks the Secure Store report partial: the `SecureStoreInventoryPartial` alert,
`Summary.SecureStoreInventoryComplete` in the manifest and a note in the HTML report say that
Secure Store applications may be missing.

**Run the inventory as an administrator of the Secure Store service application.** The service
lists the target applications that the caller administers, and all of them only for a caller with
the permission of a service administrator, so an account that does not administer the Secure
Store gets a shorter list, with no error that the inventory could see. Compare the number of rows
with the Secure Store page of Central Administration.

To plan the work:

1. List the applications in `*-securestore-*`, and ask the owners of the solutions that use them
   which ones are still needed. The `*-externallists-*` and `*-bcs-*` files tell which external
   lists and LOB systems rely on one.
2. Create the ones that are needed in the Secure Store of the target during the migration tests,
   as Group Restricted applications, and enter their credentials again: the inventory does not
   read credentials and they are not migrated.
3. After the migration, check that the solutions that use them work as expected.

The member names of the object that `Get-SPSecureStoreApplication` returns are not documented, so
the inventory reads the ones of the contract of the service and of the parameters of
`New-SPSecureStoreTargetApplication`. If a farm names them differently, the warning of the run
lists the members that the object has.

### SharePoint alerts

A SharePoint alert is an "Alert Me" subscription: a user asks to be notified when a list,
a list item or a custom object changes. Migration tools do not migrate them, and Microsoft
retired SharePoint Alerts in SharePoint Online from July 2026: new alerts cannot be created
and existing ones stop working (see
[SharePoint Alerts retirement](https://support.microsoft.com/en-us/sharepoint/admin/sharepoint-alerts-retirement)).
The notifications that users rely on have to be rebuilt with SharePoint rules or Power
Automate. The `*-sharepointalerts-*` files give you what you need to plan that, like the SMAT
Alerts report. They hold one row per alert, for every user of every web:

| Field | Description |
| --- | --- |
| `SiteUrl` / `WebUrl` | The site collection and the web that hold the alert |
| `AlertId` / `Title` / `AlertTemplateName` | The alert, its title and its template (for example the one for a document library) |
| `AlertType` | `List`, `Item` or `Custom` |
| `ListUrl` / `ListId` / `ItemId` | What the alert is on: the list URL relative to the web and its ID for a list or item alert, plus the item ID for an item alert. Empty for a custom alert, and `ListUrl` is also empty when the list no longer exists |
| `EventType` | What triggers it: for example `All`, `Add`, `Modify` or `Delete` |
| `AlertFrequency` / `AlertTime` | `Immediate`, `Daily` or `Weekly`. `AlertTime` is the time the digest is sent and is empty for an immediate alert |
| `Status` | `On`, `Off` or `Error` |
| `DeliveryChannels` / `AlwaysNotify` | How it is delivered, and whether a digest is sent even when nothing changed |
| `DynamicRecipient` / `Filter` | The dynamic recipient field and the CAML filter of the alert, when it has one |
| `UserId` / `UserLoginName` | The owner of the alert: the user ID in the site and the login name (empty when `SharePointAlerts.IncludeUserLogin` is `$false`) |

`UserLoginName` is personal data, which is why these files are not part of the HTML report:
handle them like any export that names users. It is empty when the owner is a system alert
or no longer exists in the site. The HTML report shows the number of sites with alerts, the
`SharePointAlertCount` column and the `AlertSubscriptions` alert, which has the `Medium`
severity.

To leave the login names out, set `SharePointAlerts.IncludeUserLogin` to `$false` (see
[Configuration](Configuration#sharepointalerts-section)): the column is then empty and the
owners are not looked up. While the login names are collected, the scan logs a notice saying
that the files contain them.

The rows are capped per site collection by `LargeContentThresholds.MaxAlertRowsPerSite`
(5000 by default) while `SharePointAlertCount` stays exact. When the cap is reached, or
when an alert cannot be read, the row is missing and the site is marked `Partial` with a
warning: check `CustomizationInventoryComplete`. The warnings name the first five alerts of
a site that cannot be read and count the others.

To plan the work:

1. Group the rows of `*-sharepointalerts-*` by `SiteUrl` to see which sites have the most
   alerts, and by `UserLoginName` to see which users rely on notifications.
2. Look at `Status`: an alert that is `Off` is not active today, so ask its owner whether the
   notification is still needed before replacing it. An alert without a `UserLoginName` has
   nobody to ask.
3. Rebuild each notification that is still needed with a SharePoint rule or a Power Automate
   flow. Microsoft publishes a Power Automate template for each classic alert scenario (see
   the [retirement page](https://support.microsoft.com/en-us/sharepoint/admin/sharepoint-alerts-retirement)).
   Recreating an alert only applies to a target that still supports them.
4. Tell the users before and after the migration. The
   [Migration Assessment Scan: Alerts](https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-alerts)
   page describes the SMAT report that these files follow; it predates the retirement.

### Migration categories

- **Category 1 (Simple)** — lift & shift candidates. Group them into the first migration waves.
- **Category 2 (Moderate)** — plan light remediation (workflows to Power Automate, InfoPath to Lists/Power Apps).
- **Category 3 (Complex)** — schedule a partial rebuild (SPFx / Power Platform) and information-architecture review.
- **Category 4 (Blocking)** — treat as dedicated projects: custom full-trust code, custom authentication, or legacy integrations that are not portable as-is.

Use the `Reasons` column to understand why a site scored as it did, and the
`LastModified` field to spot dormant sites you may archive rather than migrate.

## Re-scoring without re-scanning

Because `Measure-SPSSiteComplexity` is a pure function, you can adjust the scoring weights
and re-apply them to a previously exported JSON, without running another farm scan. This is
useful to tune the model quickly.
