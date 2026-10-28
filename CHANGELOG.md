# Change log for SPSSiteInventory

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2026-10-28

### Added

- Site scans now retain web-application enumeration failures and collector warning
  details in exported reports, preserve authentication metadata for inaccessible
  applications, keep progress messages in the transcript, and mark unknown storage
  values as partial rather than zero. The warnings of a site collection that differ
  only by the names between quotes (list titles, web URLs) are grouped into one entry
  with the number of similar warnings, in `AssessmentWarnings` and `Reasons`. (#28, #86)
- Pull request template now aligns with contribution guidelines by making
  validation expectations explicit (Pester, ScriptAnalyzer, docs/wiki updates,
  changelog, and Windows PowerShell 5.1 compatibility). (#30)
- The readiness check (`Test-SPSSiteInventoryReadiness.ps1`) now shows one line per check with a
  clear status, grouped by section like the readiness check of SPSUpdate: `[ OK ]`, `[WARN]`,
  `[ERR ]` and `[SKIP]`, then a summary and a verdict that tells the operator whether the scan can
  run (an error blocks it, a warning does not). It also checks that the session is elevated, that
  the settings file loads and that its output folder is usable, that the farm can be reached and
  that the web applications to scan exist, and it compares the settings with the example
  configuration to list the blocking signals and weights that an older settings file does not have.
  The script exits with code 1 when there is an error, accepts `-SkipSharePoint` to check a host
  that is not a farm server, and returns a summary object only with `-PassThru` (it used to return
  a small object of its own by default). The checks are the new public functions
  `Get-SPSReadinessCheck` and `Write-SPSReadinessReport`. When the example configuration
  file is not found, the check now shows a skipped `Comparison with the example` result
  instead of silently leaving the comparison out; the verdict and the exit code do not
  change. (#32, #89)
- Site scans now report IRM-enabled lists (`IrmEnabledListCount`) and site lock
  state (`SiteLockState` / `IsLockedSite`) in CSV/JSON/HTML outputs. The example
  scoring configuration treats both as migration blockers; for locks this was later
  narrowed to `NoAccess` (#65). A `ReadOnly` lock, which SharePoint also reports as
  write-locked, is reported as `ReadOnly` and not as `NoAdditions`. (#38, #82)
- Only a `NoAccess` site lock is a migration blocker in the example configuration now. A
  `NoAccess` lock makes the site unreadable, so the migration tools skip it, while `NoAdditions`
  and `ReadOnly` restrict changes only and are often a deliberate migration freeze. The new
  `HasNoAccessLock` signal replaces `IsLockedSite` in `Scoring.BlockingSignals`; `IsLockedSite` and
  `SiteLockState` still report every lock, and a settings file that lists `IsLockedSite` keeps its
  behavior. The alert follows the state: `NoAccessSite` (`High`) for `NoAccess`, and `LockedSite`
  (`Medium`) for `NoAdditions` and `ReadOnly`. The HTML report gains a card and shows the lock in the details of a site
  collection, and the orchestrator warns when `NoAccess` sites exist and neither signal is listed. (#65)
- Reporting now emits a modular JSON report pack (`-sites-`, `-auth-`,
  `-workflows-`, `-irm-locks-`, `-alerts-`) with a `-manifest-` file while
  preserving the existing CSV/JSON/HTML outputs. The HTML report now includes
  navigation shortcuts and risk indicator cards for key migration blockers. `SizeGB`
  keeps four decimals instead of two, so a farm of small site collections no longer
  reports 0 GB of content. (#51, #84)
- Added SMAT-parity large-content signals with configurable thresholds:
  large sites, large lists, large-list views, checked-out files, and files with
  high version counts. CSV/JSON/HTML outputs now surface these fields and
  examples; report-pack adds `-large-content-*.json`; alerts include dedicated
  large-content entries. The queries that read the checked-out files, the file
  versions, the publishing pages and the HTML files are built with the `SPQuery`
  type of the loaded SharePoint assemblies: a name without a public key token is
  not resolved on a farm server. (#36, #80)
- Added SMAT workflow running-instance parity signals:
  `Workflow2010RunningInstanceCount` and `Workflow2013RunningInstanceCount`,
  including CSV/JSON/HTML/report-pack fields and dedicated alerts, with
  best-effort behavior when Workflow Manager instance APIs are unavailable. (#37)
- Added SMAT P0 site-template parity depth signals:
  explicit template compatibility mapping (`Compatible` / `Unsupported` /
  `Review`), unsupported-template blocker flag (`IsUnsupportedSiteTemplate`),
  and template-language review metadata (`TemplateLanguage*`). These fields are
  now propagated to CSV/JSON/HTML/report-pack and alert outputs, with
  configurable rules under `TemplateParity`. (#39)
- The five classic customization signals, scored since 1.0.0, are now columns of the inventory:
  `EventReceivers` (custom receivers only), `CustomMasterPage`, `SandboxSolutions`,
  `UniquePermissionsCount` and `UsesCustomFarmFeature`. They were only visible in the `Reasons`
  text, and not at all when their weight was 0 or missing, so the CSV could not be filtered on
  them and the HTML report had nothing for them. They are in the CSV and JSON, and in the
  details of a site collection in the HTML report, with a summary card for four of them, and the
  failure rows carry them empty like the other signals.
  Tests keep every signal that the example configuration weights or blocks on a field of the
  record. Their scores and categories are unchanged. (#77)
- Added SMAT apps parity signals: `AppInstanceCount`, `AppWebCount`, and
  `AppInstanceExamples`. These fields are now propagated to scoring, CSV/JSON/HTML
  outputs, report-pack `-apps-*.json`, and dedicated app alerts. (#40)
- Added SMAT page and publishing parity signals: `PublishingInfrastructureEnabled`,
  `PublishingWebCount`, `PublishingPageCount`, `PublishingPageLayoutCount` /
  `PublishingPageLayoutExamples` (Publishing Sites and Publishing Pages scans) and
  `CustomizedPageCount` / `CustomizedPageExamples` (Customized Pages scan: web-root
  pages, System Account edits ignored). They are propagated to scoring, CSV/JSON/HTML
  outputs, report-pack `-publishing-*.json`, and dedicated alerts. Publishing signals
  are weighted but not blocking by default, and the page-layout scan is capped by the
  new `LargeContentThresholds.MaxItemsForPublishingPageScanPerLibrary`. (#42)
- Added SMAT permission and policy parity signals: `CustomPermissionLevelCount` /
  `CustomPermissionLevelExamples` (Custom Permission Level), `EmailEnabledListCount` /
  `EmailEnabledListExamples` (Email Enabled Lists), `HtmlFileCount` / `HtmlFileExamples`
  (Browser File Handling, collected only in Permissive web applications) and, per web
  application, `BrowserFileHandling`, `WebAppPolicyCount` and `WebAppPolicyExamples`
  (Web Application Policies, read by the new `Get-SPSWebApplicationPolicy`). They flow to
  scoring, CSV/JSON/HTML (including a web application policies section), a new
  `-permissions-*.json` report-pack dataset and dedicated alerts. A new `PermissionLevels`
  setting adds localized names of the permission levels SharePoint provisions, and
  `LargeContentThresholds.MaxItemsForHtmlFileScanPerLibrary` caps the HTML file count.
  `Restricted Read`, which the publishing features provision without a base type, is one of
  the built-in names, so a publishing site is not reported as having a custom permission
  level. A failed policy read marks the site records partial instead of reporting no policies.
  (#43, #98)
- Added the subsite readiness analysis. Subsites are supported in SharePoint Online, but modern
  SharePoint favors one site collection per unit of work, connected by hub sites, so a large or
  deep hierarchy is a restructuring topic to plan, never a blocker. Each site gets
  `SubsiteCount` (the webs below the root web, app webs left out), `MaxSubsiteDepth` (the deepest
  level, 1 = directly below the root web) and `SubsiteExamples` (up to five of the deepest
  subsites), in the CSV/JSON/HTML outputs, with a summary card in the HTML report. They are
  weighted lightly in the example configuration (`SubsiteCount = 0.05`, `MaxSubsiteDepth = 0.25`)
  and are not blocking, and a new `Low` alert, `Subsites`, carries the restructuring guidance
  with its Microsoft Learn reference. A web that cannot be placed below its site collection marks
  the site partial. The HTML report calls the number of webs of the site collection, the root web
  included, `Webs` (it was `Sub-webs`). (#33)
- Added SMAT managed metadata parity: `ManagedMetadataListCount`,
  `ManagedMetadataColumnCount`, `ManagedMetadataTermSetCount` and `ManagedMetadataExamples`
  (Managed Metadata Columns). A managed metadata column is a visible `TaxonomyFieldType`
  or `TaxonomyFieldTypeMulti` field, Enterprise Keywords included; term sets are counted
  by ID from the field definitions, without calling the term store service. They flow to
  scoring (weighted, not blocking), CSV/JSON/HTML, a per-list `-managedmetadata-*` CSV/JSON
  report with a matching HTML section, and a dedicated alert, with guidance to migrate
  these lists close to the term store. A column or list property that cannot be read
  marks the site partial instead of reporting no managed metadata or an empty value.
  Hidden lists are skipped, so the newsfeed list that every site has (`MicroFeed`, with its
  hashtags column) is not reported as a use of the term store. (#44, #81)
- Added SMAT BCS and external list parity: `ExternalListCount` / `ExternalListExamples`
  (External List scan: lists backed by a Business Connectivity Services external content
  type, detected through SharePoint's external data source flag) with a per-list
  `-externallists-*` CSV/JSON report that records the LOB system instance, entity namespace
  and entity of each list, and the new `Get-SPSBcsApplication`, which reads the Business
  Data Connectivity metadata store (BCS scan) through the BDC proxy of each web
  application's service application proxy group, without needing a site collection, into a
  `-bcs-*` CSV/JSON report with the LOB system type, instances and entities. Stores are
  identified by their BDC service application ID, not by catalog ID. They flow to scoring, CSV/JSON/HTML (external list and BCS sections), the
  manifest and dedicated alerts (`ExternalLists`, `BcsApplication`, `BcsInventoryPartial`),
  with guidance that BCS is retired in SharePoint Online and that these scenarios need a
  replacement such as Power Apps. The example configuration weights `ExternalListCount` and
  treats it as a migration blocker like InfoPath; the run warns when external lists are
  found and an existing configuration does not list it in `Scoring.BlockingSignals`. Nothing is read from the external
  systems and no connection setting or credential is collected. A list, LOB system, web
  application or metadata store that cannot be read marks the site or the BCS report
  partial, and an external list whose binding cannot be read is still counted. (#41)
- Added an alert remediation catalog. Every risk alert now carries a remediation hint and
  a Microsoft Learn reference taken from one catalog (`Get-SPSAlertCatalog`), so the same
  signal always gives the same severity, explanation and advice. The alerts are written to
  a new `-alerts-*.csv` next to the JSON, listed in the manifest, and the HTML report gains
  an "Alerts and remediation" section that groups them by type with the number of sites or
  web applications concerned. The alert logic moves out of `Export-SPSInventoryReport`
  into `Get-SPSInventoryAlert` with tests that every alert type is cataloged and documented
  in the new [Alerts and remediation](wiki/Alerts.md) wiki page. (#45)
- Added the `SharePointAlerts.IncludeUserLogin` setting (default `$true`) to leave the login
  name of the alert owners out of the SharePoint alerts report. The owners are then not looked
  up at all and `UserLoginName` stays empty. While the names are collected, the scan logs a
  notice saying that the alert files contain personal data. A value that is not `$true` or
  `$false` is rejected when the settings file is loaded, because the string `'false'` would
  otherwise collect the names the operator meant to leave out. (#63)
- Added the SMAT Alerts parity: the SharePoint alerts ("Alert Me" subscriptions) that users
  set up are now inventoried. Each site gets `SharePointAlertCount` (exact, every user, every
  web; informational, not scored by default) and a new `-sharepointalerts-*.csv/json` report
  lists one row per alert: where it applies (web, list or item), its event type, frequency,
  time, status, delivery channel, CAML filter and owner. Migration tools do not migrate
  alerts and SharePoint Online retired SharePoint Alerts from July 2026, so a new `Medium`
  alert, `AlertSubscriptions`, tells the administrator to plan a replacement with SharePoint
  rules or Power Automate. The rows are capped per site by
  `LargeContentThresholds.MaxAlertRowsPerSite` (5000 by default); an unreadable alert or a
  reached cap marks the site partial. The files hold
  the login names of the alert owners, so they stay out of the HTML report. (#45)
- Added the `Workflow2013` alert. SharePoint 2013 workflows were fully retired in SharePoint
  Online on 2 April 2026, so a site that still has some now raises a `High` alert with a
  remediation (rebuild them, for example with Power Automate), like `Workflow2010` does for the
  2010 engine. `Workflow2013Running` moves from `Medium` to `High`, because a running instance
  cannot be restarted in SharePoint Online any more. (#66)
- Added the lab scripts (`tools/lab`, not part of the release package) to test a release on a lab
  SharePoint farm. `Invoke-SPSLabTest.ps1` creates small, labeled site collections that trigger
  known signals (subsites, locks, large content, permissions, alerts, publishing, InfoPath, event
  receivers, custom master page, a blog template and, best effort, workflows, IRM and incoming
  e-mail), writes lab settings from the example configuration of the toolkit being tested with the
  large-content thresholds lowered, runs the inventory, checks the reports against what each
  scenario must produce (PASS, FAIL, INFO or SKIP, with the actual values and the assessment of
  every lab site), and removes the lab, and only the lab, on request. Tests keep the expectations
  in line with the inventory record and the alert catalog. The wiki page "Lab testing" documents
  the scenarios and what stays manual. (#75) The `event-receiver` scenario is skipped when SharePoint
  cannot load the assembly of the receiver (it needs a deployed assembly), the `event-receiver` and
  `custom-master` scenarios read the `EventReceivers` and `CustomMasterPage` columns, the script
  prints a line per site collection while it creates or removes the lab, and it prints the settings
  file and the report folder before the inventory. (#87)
- Zone-aware web application authentication inventory, including mixed Windows/FBA,
  membership/role provider names and explicit identity-review flags. The example
  configuration treats `HasFbaZone` as a SharePoint Online migration blocker.
  Existing configurations remain unchanged and receive a warning when FBA is found
  without that blocking rule.
- Content-type web definitions and list bindings collected during the existing site
  walk, with IDs, parent IDs, field types, document-template references and collection
  completeness. Dedicated `-contenttypes-` CSV/JSON files and authentication/content-type
  HTML sections complement the per-site summary; standard types are not automatically
  classified as custom or blocking. (#26)
- Personal sites (My Sites, template `SPSPERS`) and site masters (hidden site collections
  whose host name is `sitemaster-` followed by a GUID) are now left out of the inventory by
  default: they are not sites to migrate and they buried the other site collections. A new
  optional `Scope` section of the settings, with `IncludePersonalSites` and
  `IncludeSiteMasters` (both `$false` by default, also when the section is missing), brings
  them back; setting both to `$true` restores the scope of 1.x. A site master is skipped
  before it is opened, a personal site as soon as the template of its root web is read, and the
  My Site host (`SPSMSITEHOST`) stays in the scan. The HTML summary, the log and the manifest
  (`Summary.ExcludedPersonalSites` and `Summary.ExcludedSiteMasters`) say how many were left
  out. (#85)

### Changed

- Workflow counts now exclude historical "previous version" workflow associations
  when SharePoint metadata flags them (with a marker-based fallback for English
  and French previous-version names when metadata is unavailable), so migration
  complexity is based on active workflows and does not misclassify qualifiers such
  as `SLA: 48`. The counts can be lower than the ones of 1.1.0. (#31)
- The example configuration weights the new signals and lists more of them in
  `Scoring.BlockingSignals`: `HasFbaZone`, `IrmEnabledListCount`,
  `IsUnsupportedSiteTemplate`, `HasNoAccessLock` and `ExternalListCount`. A configuration
  copied from this release classifies more sites as Blocking than 1.1.0 did. Settings files
  are not rewritten: a file written for 1.x keeps working, the new sections
  (`LargeContentThresholds`, `TemplateParity`, `PermissionLevels`, `SharePointAlerts`, `Scope`)
  fall back to their defaults, and the run warns when it finds one of these blockers and the
  file does not list the signal.
- Personal sites and site masters are no longer inventoried by default, so a run reports fewer
  site collections than 1.x. Set `Scope.IncludePersonalSites` and `Scope.IncludeSiteMasters` to
  `$true` to restore the scope of 1.x. (#85)
- The CSV and JSON exports gain a column for every new signal and for five classic signals that
  were scored since 1.0.0 but never exported (`EventReceivers`, `CustomMasterPage`,
  `SandboxSolutions`, `UniquePermissionsCount` and `UsesCustomFarmFeature`), and the run writes
  more files next to them. Read the files by column name, not by position. The CSV files also put
  a quote in front of text that starts with a formula character (see Security below).
- The readiness check (`Test-SPSSiteInventoryReadiness.ps1`) exits with code 1 when a check
  fails, and returns a summary object only with `-PassThru`: it used to return a small object of
  its own by default, so a script that reads its result must pass `-PassThru`. (#32)
- The HTML report calls the number of webs of a site collection, the root web included, `Webs`
  (it was `Sub-webs`). The new `SubsiteCount` counts the webs below the root web. (#33)
- The HTML report is made to be read, and stays small on a large farm. On the lab farm it was
  1.5 MB for 27 site collections and 242,000 px tall, and about 150 MB would be expected for
  3,000 site collections, because 93 % of it was the content type table and the inventory table
  had 78 columns, which a reader had to scroll across. The inventory table is now right after
  the wave plan (it was the last element of the page) and has one compact row per site
  collection: title and URL, category, score, wave, size, template, last modification, status
  and reasons, worst first. Opening a row shows the context of the site collection, the signals
  it raises with their count and examples (a signal at zero is not listed), its assessment
  warnings and its full reasons, and a search box and a count of the site collections shown sit
  next to the category filters. The content types are summarized (definitions, list bindings,
  site collections) instead of listed, and the managed metadata, external list, BCS, farm
  solution and full-trust site tables show at most 200 rows (`-MaxDetailRow` of
  `ConvertTo-SPSInventoryHtml`), with a line that says where the other rows are. The CSV and JSON
  files are not changed: they keep every column and every row. (#101)

### Security

- The CSV reports now neutralize spreadsheet formulas (CSV injection, CWE-1236). Titles of
  sites, lists, content types and alerts, CAML filters and other text typed by the users of the
  farm reach the CSV files, and a spreadsheet reads a cell that starts with `=`, `+`, `-` or `@`
  (or a tab, a carriage return, a line feed, or the full-width form of `=`, `+`, `-` and `@`) as
  a formula, which could run on the machine of the administrator who opens the file. Every CSV the toolkit writes (the inventory, alerts,
  content types, managed metadata, external lists, SharePoint alerts, BCS and farm solutions
  files) now puts a single quote in front of such a text cell, as OWASP recommends, through one
  shared helper. Numbers, including negative ones, booleans and dates are not touched. The JSON
  files and the HTML report keep the original text. A script that parses a CSV must remove the
  leading quote. (#64)

### Fixed

- The scoring no longer depends on the culture of the server. A signal that is not a whole number,
  above all the size of a site collection (`SizeGB`), was read as 1 on a server whose culture has a
  decimal comma (French, Spanish and others) and as a hundred times more or less on a German one,
  so the size counted for nothing in the score and the category: a 400 GB site collection was
  Simple on a French server and Complex on an English one. A number is now used as it is and a
  text is read with the invariant culture. The reasons (`SizeGB=25.5 (+0.51)`) are also written
  with the invariant culture, so the CSV, JSON and HTML reports read the same on every server.
  Re-run the inventory, or re-score it, on a server whose culture has a decimal comma to get the
  right categories. (#102)

## [1.1.0] - 2026-09-21

### Added

- The self-contained HTML report now includes a **Farm solutions (WSP)** section: a summary box (total solutions, custom, full-trust code, web-app resource) and a table with each solution's Deployed / Custom / full-trust / CAS policy / web-app resource / feature count / scopes, so the WSP analysis (the tool's main differentiator) is visible in the shareable report and not only in the `-solutions-` CSV/JSON. `ConvertTo-SPSInventoryHtml` and `Export-SPSInventoryReport` gain a `-SolutionMap` parameter, wired by the orchestrator.

### Changed

- Custom farm solutions are now **auto-detected**: `Get-SPSFarmSolutionMap` treats a solution as custom unless its name matches a known Microsoft / out-of-the-box marker, so `CustomSolutionPrefix` is no longer required — a typical run needs no per-client configuration. `CustomSolutionPrefix` becomes an optional override, and new `AutoDetectCustom` / `KnownMicrosoftPrefix` parameters (surfaced as `AutoDetectCustomSolutions` / `KnownMicrosoftSolutionPrefix` in the settings) let you tune or disable the behaviour.

### Fixed

- `Get-SPSFarmSolutionMap` now reports `FeatureCount` for solutions that are added but not deployed. Reading each feature's id/scope can throw until a solution is deployed; the count is now captured separately and each feature is read best-effort, so a non-deployed custom WSP still reports how many features it ships (ids/scopes may stay empty until deployment).
- The `EventReceivers` signal now counts only **custom** event receivers (those registered from a non-Microsoft assembly). Out-of-the-box receivers on native lists (Search Center, App Catalog, MySite host, ...) are no longer counted, so stock sites are no longer wrongly promoted to a higher complexity category.

## [1.0.0] - 2026-09-21

### Added

- Migration wave plan: new `Group-SPSMigrationWave` assigns each scored site a `Wave` number and `WaveName` from a configurable `MigrationWaves` category-to-wave mapping (default one wave per category; an organization can instead group several categories into a single wave). The site CSV/JSON gains `Wave`/`WaveName` columns and the HTML report gains a "migration wave plan" section (sites and total content size per wave).
- Deep farm-solution (WSP) analysis: `Get-SPSFarmSolutionMap` now characterizes each solution's migration risk directly from `SPSolution` (no package cracking) — `ContainsGlobalAssembly` (full-trust code), `ContainsCasPolicy`, `ContainsWebApplicationResource`, `DeploymentState`, deployed web-application and server counts, feature count and scopes, plus an `IsFullTrustCode` flag. A new per-site signal `UsesFullTrustCode` flags sites activating a feature from a custom full-trust WSP and is treated as blocking in the example configuration.
- `Export-SPSSolutionReport` — exports the enriched farm-solution map as its own CSV (array columns flattened) and JSON (arrays intact), so the WSP estate is a first-class deliverable next to the site inventory.
- InfoPath detection: `Get-SPSSiteCustomization` now reports `InfoPathFormCount` (InfoPath form libraries and lists whose forms were customized with InfoPath). InfoPath Forms Services is retired and has no SharePoint Online equivalent, so the signal is weighted heavily and treated as blocking in the example configuration; the count is surfaced as a column in the CSV/JSON output.
- Workflow signal split: `Get-SPSSiteCustomization` now reports `Workflow2010Count` (legacy SharePoint 2010 engine, retired in SharePoint Online) and `Workflow2013Count` (Workflow Manager) instead of a single `WorkflowAssociationCount`, and both counts are surfaced as columns in the CSV/JSON output. The example scoring weights 2010 workflows more heavily than 2013.
- `ConvertTo-SPSInventoryHtml` — renders the scored inventory as a single self-contained HTML report (Aptos style, blue `rgb(31, 56, 100)` headings, per-category summary box, sortable/filterable site table). No external resource, no farm call.
- Initial scaffold of the **SPSSiteInventory** toolkit (read-only SharePoint Server site inventory and migration-complexity categorization).
- `SPSSiteInventory.Common` module with the V1 building blocks:
  - `Measure-SPSSiteComplexity` — configurable scoring engine mapping customization signals to a category from 1 (Simple) to 4 (Blocking).
  - `Get-SPSInventorySetting` — loads and validates the `.psd1` settings file.
  - `Get-SPSSiteInventory` — enumerates site collections with identity and volumetry.
  - `Get-SPSSiteCustomization` — collects per-site customization signals.
  - `Get-SPSFarmSolutionMap` — correlates farm solutions (WSP) with the features they deploy.
  - `Export-SPSInventoryReport` — writes the scored inventory to CSV, JSON and a self-contained HTML report.
  - `Import-SPSSharePointCommand`, `Get-SPSInstalledProductVersion`, `Initialize-SPSScript`, `Add-SPSInventoryEvent` — session and logging helpers.
- `Invoke-SPSSiteInventory.ps1` orchestrator and `Test-SPSSiteInventoryReadiness.ps1` prerequisite check.
- `inventory-settings.example.psd1` neutral configuration example (scoring weights, thresholds, blocking signals, custom-solution prefixes).
- Pester tests for the pure scoring, settings, HTML-rendering, solution-report and migration-wave functions, PSScriptAnalyzer settings, and CI workflows (Pester, Release, Wiki).
