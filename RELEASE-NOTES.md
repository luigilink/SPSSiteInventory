# SPSSiteInventory - Release Notes

## [2.0.0] - 2026-10-28

This release brings the scans of the SharePoint Migration Assessment Tool (SMAT, out of
support since 1 October 2026) into the inventory and says what to do about each finding: every
risk becomes an alert with a severity, a remediation hint and a Microsoft Learn reference,
and the advice follows what SharePoint Online has retired instead of repeating the older SMAT
pages. SPSSiteInventory is still read-only and 100% generic (no client-specific value ships
in the repository).

It is a major release because the reports and the example configuration change. If you parse
the files with a script, or compare them with the ones of 1.1.0, read "Upgrading from 1.x"
below first.

### Highlights

- **SMAT scans in the inventory.** The signals that matter for a move to SharePoint Online
  are collected from the SharePoint object model, per site collection: large sites, lists,
  list views, checked-out files and file versions; workflows and their running instances;
  site templates and languages; add-ins; publishing sites, page layouts and customized pages;
  custom permission levels, e-mail enabled lists, browser file handling and web application
  policies; managed metadata columns and the term sets they use; external lists and Business
  Connectivity Services applications; SharePoint alerts; IRM-enabled lists and site locks.
  Web applications also report their authentication zones (FBA), and content types are inventoried.
  The thresholds are configurable and the long scans are capped, so a run stays predictable.
- **Risk alerts with a remediation.** One catalog gives every alert its severity, an
  explanation, a remediation hint and a Microsoft Learn reference, so the same signal always
  reads the same. The guidance follows what SharePoint Online has retired, for SharePoint
  2013 workflows, add-ins, Business Connectivity Services, InfoPath Forms Services and
  SharePoint Alerts. The alerts go to a new `-alerts-` CSV and JSON and to an "Alerts and
  remediation" section of the HTML report, and the
  [Alerts and remediation](https://github.com/luigilink/SPSSiteInventory/wiki/Alerts) wiki page
  documents each of them.
- **A report pack and an HTML report made to be read.** A modular JSON report pack (sites,
  authentication, workflows, apps, publishing, permissions, IRM and locks, large content and
  alerts) comes with a manifest. Content types, managed metadata, external lists, BCS
  applications and SharePoint alerts get their own CSV and JSON files. The HTML report shows one
  compact row per site collection, worst first, that opens to list the signals the site
  collection raises, with a search box and category filters. The content types are summarized
  and the other long tables are limited to 200 rows, so the file stays small on a large farm
  (about 5 MB for 3,000 site collections).
- **Personal sites and site masters are left out.** My Sites and the hidden site masters that
  SharePoint creates buried the site collections that are worth migrating, so a scan now leaves
  them out and says how many in the log, the HTML summary and the manifest. The new `Scope`
  settings bring them back.
- **Safer files.** The CSV files neutralize spreadsheet formulas (CSV injection): text typed by
  the users of the farm is no longer read as a formula when an administrator opens a file in a
  spreadsheet. The [usage page](https://github.com/luigilink/SPSSiteInventory/wiki/Usage) explains
  the limits of this protection. The login names of the owners of SharePoint alerts are
  personal data: the scan says so, the HTML report never carries them, and
  `SharePointAlerts.IncludeUserLogin` leaves them out of the files too.
- **Scans that say what they could not read.** A web application, site, list or alert that
  cannot be read is reported and marks the record as partial, instead of showing zero or
  nothing; an unknown storage value is no longer reported as 0. The progress messages are kept
  in the transcript.
- **A readiness check that says what to fix.** `Test-SPSSiteInventoryReadiness.ps1` prints one
  line per check (`[ OK ]`, `[WARN]`, `[ERR ]`, `[SKIP]`) and a verdict, and exits with code 1
  on an error. It also checks that the session is elevated, that the settings file and its
  output folder are usable, that the farm and the web applications to scan can be reached, and
  which blocking signals and weights an older settings file lacks.
- **Subsite analysis.** Each site reports `SubsiteCount`, `MaxSubsiteDepth` and
  `SubsiteExamples`, and a `Low` alert, `Subsites`, explains why a large or deep hierarchy is a
  restructuring topic for SharePoint Online, never a blocker.
- **The classic customization signals are columns.** `EventReceivers`, `CustomMasterPage`,
  `SandboxSolutions`, `UniquePermissionsCount` and `UsesCustomFarmFeature` were scored since
  1.0.0 but only visible in the `Reasons` text, and not at all when their weight was 0. They are
  now in the CSV, the JSON and the details of each site collection in the HTML report; scores and
  categories are unchanged.

### Upgrading from 1.x

- **CSV files.** A text cell that starts with `=`, `+`, `-` or `@`, or with a tab, a carriage
  return, a line feed or the full-width form of `=`, `+`, `-` and `@`, now begins with a single
  quote, as OWASP recommends. A script that parses a CSV must remove it. The JSON files and
  the HTML report keep the original text, and numbers, booleans and dates are not touched.
- **Columns and files.** The site CSV and JSON gain a column for each new signal and for the five
  classic customization signals above, and the run writes more files next to them (the manifest
  lists them). Read the files by column name, not by position. The HTML report shows the number
  of webs of a site collection, the root web included, as `Webs` (it was `Sub-webs`); the new
  `SubsiteCount` counts the webs below the root web.
- **Scope.** Personal sites and site masters are left out by default, so a run reports fewer
  site collections than 1.x. Set `Scope.IncludePersonalSites` and `Scope.IncludeSiteMasters` to
  `$true` in the settings to get the scope of 1.x. A settings file with no `Scope` section leaves
  them out.
- **HTML report.** The layout changed: the inventory table has a few columns and a row opens to
  show the rest, the content types are summarized instead of listed (the `-contenttypes-` files
  hold every row) and the long tables show at most 200 rows (`-MaxDetailRow` of
  `ConvertTo-SPSInventoryHtml`). The CSV and JSON files are not affected.
- **Scores on a server with a decimal comma.** In 1.x a signal that is not a whole number, above
  all `SizeGB`, was read wrongly when the regional settings of the server use a decimal comma
  (French, German, Spanish and others), so the size of a site collection did not count in its
  score. Run the inventory again with 2.0.0: scores and categories can change.
- **Readiness check.** `Test-SPSSiteInventoryReadiness.ps1` exits with code 1 when a check
  fails, so it can gate an automated run, and returns an object only with `-PassThru`: it used to
  return a small object of its own by default.
- **Scoring.** The example configuration weights the new signals and blocks on more of them:
  `HasFbaZone`, `IrmEnabledListCount`, `IsUnsupportedSiteTemplate`, `HasNoAccessLock` (a
  `NoAccess` lock only: `ReadOnly` and `NoAdditions` locks are reported but not blocking) and
  `ExternalListCount`. A configuration copied from it classifies more sites as Blocking than
  1.1.0 did. Your own settings file is not rewritten and keeps working: only `Scoring` is
  mandatory, the new sections (`LargeContentThresholds`, `TemplateParity`, `PermissionLevels`,
  `SharePointAlerts`, `Scope`) fall back to their defaults, and the run warns when it finds one of these
  blockers and your `Scoring.BlockingSignals` does not list it. Compare your file with
  `inventory-settings.example.psd1` to adopt the new signals.
- **Workflow counts.** Historical "previous version" workflow associations are no longer
  counted, so the counts can be lower than with 1.1.0.

### Known issues

- A site collection locked with `NoAccess` is reported as partial, with `SiteLockState`
  `Unknown`, because SharePoint refuses to read its storage, solutions and webs ("Access to this
  Web site has been blocked"). The `NoAccessSite` alert and the `HasNoAccessLock` blocker do not
  fire for it on a real farm: look for that warning and for the `AssessmentPartial` alert. (#83)
- A site collection whose inventory is partial is scored on what could be read, so it can be
  categorized Simple and be in the first wave. Review the partial site collections (the status of
  the row, the `AssessmentPartial` alert) before you plan the waves. (#106)
- `CustomMasterPage` is reported for the My Site host. (#107)
- A ranked list of risk indicators with collapsible alerts for the HTML report (#90) and a
  report in several files for very large farms (#105) are planned for 2.1.0.

### Notes

- Requires Windows PowerShell 5.1 (the SharePoint Server object model); do not use PowerShell 7.
- Compatible with SharePoint Server 2016, 2019 and Subscription Edition.
- To test a release on a lab farm, the `tools/lab` folder of the repository (not part of this
  ZIP) builds one test site collection per signal and checks the reports. It writes to the farm,
  so use it on a lab only; see the
  [Lab testing](https://github.com/luigilink/SPSSiteInventory/wiki/Lab-Testing) wiki page. This
  release was run on a lab farm with these scripts before it was tagged; the scenarios that need
  a deployed assembly, a SharePoint 2010 workflow template or Permissive browser file handling
  stay manual.
- See the [wiki](https://github.com/luigilink/SPSSiteInventory/wiki) for setup, configuration and usage.
