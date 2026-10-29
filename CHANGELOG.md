# Change log for SPSSiteInventory

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.1.0] - 2026-10-30

### Added
- SMAT profile-migration parity. The new `Get-SPSProfilePropertyMapping` reads the profile property
  mappings of the User Profile service applications once for the farm, as the SMAT Custom Profile
  Property Mappings report does: one row per mapping, with the connection and its type, the profile
  property with its display name and length, the attribute it is mapped to, the direction (import or
  export) and the number of profiles that have the property. The service is found through the service
  application proxy group of each web application and read with the configuration manager of the User
  Profile service through the service context of that group. A service context binds the default User
  Profile proxy of its group, so that proxy identifies the service: web applications that share it report
  it once, and a group with several proxies is read through its default one. The mappings of a connection are
  read from its `PropertyMapping`, and those of an Active Directory import connection, which is the default
  of SharePoint Server 2016 and later and has none, from the non-public method that SharePoint uses for
  them. Every mapping is listed, and each row says whether SharePoint Online fills the property
  (`SynchronizedInSharePointOnline`, from the fixed list that Microsoft documents, by the internal name of
  the property and never by its display name) and whether SharePoint ships it (`BuiltInProperty`, from
  `PropertyConstants`): a mapping of a property that is neither is a
  custom one, and raises the new `ProfilePropertyMapping` alert (Low, once per connection, with the
  number of its mappings). The report reaches a `-profilemappings-` CSV and JSON, the manifest
  (`Summary.ProfileInventoryComplete`, `Files.ProfileMappingsCsv` and `Files.ProfileMappingsJson`) and a
  profile property mapping section of the HTML report, which lists the custom mappings first. A web
  application, a connection or a mapping that cannot be read, which includes a missing permission on the
  User Profile service application, a User Profile proxy that is the default of no proxy group that was
  read, and the list of the properties that SharePoint ships when it cannot be read, mark the report
  partial: the new
  `ProfilePropertyMappingInventoryPartial` alert, the manifest and a note in the HTML report say so. The
  profile property names that SharePoint Online fills, the members of the objects of the service and the
  meaning of the number of profiles are checked on the first run on a farm. (#46)
- The customized profile page of a My Site host is now a signal of its own: `CustomizedProfilePageCount`
  (1 when the `Person.aspx` of the root web of a site collection of the template `SPSMSITEHOST` is
  customized, ignoring the edits of the System Account like the customized pages do) and
  `CustomizedProfilePageExamples`. It reaches the CSV, the JSON, the `-collaboration-` dataset, a risk
  indicator and the details of the HTML report, weighs nothing in either example configuration, and raises
  the new `CustomizedProfilePage` alert (Low), which is only about a migration in the `SharePointOnPrem`
  mode: SharePoint Online has a profile experience of its own that cannot be customized. The web parts
  that a browser adds or moves, and the personalization of a user, do not customize the page and are not
  seen: SMAT compares the page with a default that is not published. The lab has a scenario for it. (#46)
- SMAT parity for the collaboration features that migrate without the data that makes them work. The
  inventory counts the list items that target an audience (`AudienceTargetedItemCount`, with
  `AudienceTargetedListCount` and `AudienceTargetedExamples`): the Target Audiences column, which a
  list has once audience targeting is enabled on it and a Pages library has from the start, is not
  empty. The column is found by its ID and not by its name (it is `Audience` in a Pages library), its
  value is read as the three parts that SharePoint stores (the IDs of the audiences of the User
  Profile service, the distribution lists and the SharePoint groups), and an audience is shown by its
  name when the audience manager can give it and by its ID when it cannot, as the SMAT report does.
  The audience data does not migrate, so the items are shown to every reader afterwards. Hidden lists
  and the system catalogs are skipped, and at most
  `LargeContentThresholds.MaxItemsForAudienceTargetingScanPerList` items (2000 by default) are read in
  each list, whatever their value, because how a query behaves on the column is not documented: a list
  above the cap makes the site collection partial. The inventory also counts the site notebooks
  (`SiteNotebookCount`, `SiteNotebookExamples`): the OneNote notebooks of the Site Assets library
  whose name ends in Notebook, as the SMAT scan reads them (SMAT also leaves out an empty notebook: the
  inventory does not test that), which are migrated under another name so
  that the links to them break (at most `MaxItemsForNotebookScanPerLibrary` folders are read). Both
  signals reach the CSV, the JSON, a new `-collaboration-` dataset of the report pack
  (`Files.CollaborationJson`), a risk indicator and the details of the HTML report, weigh nothing in
  either example configuration and raise the `AudienceTargeting` (Medium) and `SiteNotebook` (Low)
  alerts, which are two of the alerts that are only about a migration in the `SharePointOnPrem` mode.
  A column, a list or a library that cannot be read marks the site collection partial instead of
  counting for nothing. The lab has two scenarios, `audience-targeting` and `site-notebook`. (#47)
- SMAT Secure Store parity: the new `Get-SPSSecureStoreApplication` reads the Secure Store target
  applications of the farm once, through the service application proxy group of each web
  application and the service context of that group, for the default partition, so a web
  application without any site collection is read too. Web applications that share a Secure Store
  proxy report its applications once. The row has the name (the target application ID), the display
  name, the contact e-mail address, the type, the credential management URL and the ticket
  time-out, like the SMAT report; the fields of the applications and the credentials are never read.
  The report reaches a `-securestore-` CSV and JSON, the manifest (`Summary.SecureStoreInventoryComplete`,
  `Files.SecureStoreCsv` and `Files.SecureStoreJson`) and a Secure Store section of the HTML report,
  which leaves the contact e-mail address out because it is personal data. A service context binds the
  default Secure Store proxy of its group, so that proxy identifies the store: a group with several
  proxies is read through its default one. A web application, a proxy or an application that cannot be
  read, a Secure Store proxy that is the default of no proxy group that was read, or a default that cannot
  be told, marks the report partial: the new
  `SecureStoreInventoryPartial` alert, the manifest and a note in the HTML report say so. The new
  `SecureStoreApplication` alert is Low, one per target application: the applications are not
  migrated to SharePoint Online, the ones that are still needed have to be created again as Group
  Restricted applications, and the credentials have to be entered again. In the `SharePointOnPrem`
  mode it is one of the alerts that are only about a migration. The member names of the object that
  `Get-SPSecureStoreApplication` returns are not documented: the first run on a farm confirms them,
  and the warning of a row that cannot be read lists the members that the object has. (#49)
- The HTML report is split in several pages for a very large farm. Up to `Report.HtmlSplitThreshold`
  site collections (default 3000, about 5 MB) it stays one file; above, the entry page, named like
  the single file, keeps the summary, the risk indicators, the alerts, the wave plan and the detail
  sections, and the table of the site collections moves to pages of at most `Report.HtmlRowsPerPage`
  of them (default 500, about 1 MB), one series per category, worst first, named after the entry page
  (`...-sites-blocking-1.html`). Every page has the same header and navigation, a search box, sortable
  columns and the details of each site collection, and is as self-contained as the single file, with
  relative links only, so the folder can be moved, zipped and sent. A risk indicator of the entry page
  is a link to the first table page that has a site collection that raises it, with the filter in the
  address (`#ind=large-lists`); that page links to the previous and the next page that have the
  indicator. With 30,000 site collections: 62 files, the largest 1.3 MB, the entry page 42 KB, and a
  filter takes a few milliseconds. The manifest lists the pages (`Files.InventoryHtmlPages`), and
  `ConvertTo-SPSInventoryHtml -FileName` returns the pages as objects (the report is still a string
  without it). (#105)
- Offline inspection of WSP packages, with no farm and no SharePoint command:
  `Get-SPSSolutionPackageInfo` expands a WSP (a cabinet) with `expand.exe` (or `cabextract` off
  Windows), or reads a package that is already expanded, and reports what the farm solution only
  shows as booleans. It reads the strong name and the public key token of every assembly, so a
  package is custom or Microsoft on its assemblies and not on the name of the solution. A token
  only counts when the strong-name signature of the assembly is valid (`SignatureStatus`): the
  token is a hash of the public key that the assembly declares, and an assembly that is
  delay-signed with the public key of Microsoft, or altered after it was signed, carries it too,
  so it is custom and the package says why. It also reads the
  feature ids and scopes even when the solution is not deployed (the farm reports no feature for
  it), the features that have a receiver, where the assemblies are deployed, the safe controls, the
  code access security policy, the kind of elements that the features provision, and the .NET
  framework that the DLLs were built for (custom assemblies built for .NET 3.5 or before are
  counted). A DLL that was not assessed (above the size limit, not a valid image, a name that
  could not be read) makes the package `Partial` and counts as custom, and a hidden DLL is
  assessed like the others. With `-FarmSolutionMap` it matches each package to the farm solution
  and lists the differences. `Export-SPSSolutionPackageReport` writes a CSV per package, a CSV per
  assembly and a JSON file. The package is not trusted: the cabinet is copied to a folder of its
  own and that copy is what is checked (a file name that goes up with `..`, too many files, too
  large a size) and expanded, so that what is checked is what is expanded whatever happens to the
  original meanwhile, and `Sha256` is that of the copy. A location in a manifest, `manifest.xml`
  and the DLLs that are found in a folder must stay in the package: the case counts except on
  Windows, and a symbolic link or a junction is never followed. The DLLs are read as bytes and
  never loaded, and the XML is read with the DTD switched off. See the wiki page "Inspecting WSP
  packages (offline)". (#21)
- A target mode, `TargetMode`, so that the same inventory can plan the modernization of a farm
  (the classic experience to the modern one, where the site collections run) and not only a
  migration to SharePoint Online. `SharePointOnline` is the default, also when the setting is
  missing, and nothing changes for a settings file of an earlier version: its reports are the same
  as before. `SharePointOnPrem` names the four categories *Modern-ready*, *Light remediation*,
  *Rebuild (SPFx)* and *Blocked* (their numbers, 1 to 4, and the scores do not change), names the
  pages of a split HTML report and the default waves after them, words the HTML report as a
  modernization report (header, wave plan, the meaning of the high-severity signals), and does not
  raise the log warnings that are about the blockers of a migration. The mode is recorded in the
  manifest (`Summary.TargetMode`). The mode is validated when the settings are loaded: a value that
  is not one of the two names stops the run with the name of the file. A new example file,
  `inventory-settings.onprem.example.psd1`, ships the scoring of that question: full-trust code and
  custom farm features, which still run on the farm, weigh as code to rebuild with SPFx and no
  longer block, `InfoPathFormCount` stays the one blocker, and what belongs to a migration (FBA,
  unsupported templates, NoAccess locks, IRM, external lists, the term store, the subsite
  structure) weighs nothing, while it is still collected and reported. The readiness check
  compares the settings with the example of their mode. See the wiki page "Configuration". (#25)
- The inventory collects what keeps a site collection in the classic experience, in both target
  modes; with the custom master page, which it already collected, and the publishing signals they
  say why a site collection is not in the modern experience. `AlternateCssUrlCount` counts the webs
  that set an alternate CSS URL, `XsltListViewCount` the list views that render with a customized
  XSLT (a `XslLink` other than `main.xsl`, or an `Xsl`), `ScriptWebPartCount` the Script Editor web
  parts and the Content Editor web parts that embed a script or link to a file, on the home page
  of each web and on the pages of its Site Pages and Pages libraries (at most
  `LargeContentThresholds.MaxItemsForWebPartScanPerLibrary` pages per library, 200 by default),
  `ClassicExperienceOptOutCount` the site collection and the webs that opted out of the modern list
  and library experience, and `ClassicExperienceListCount` the lists whose experience is set to
  classic, each with its examples. `ModernBlockerCount` and `ModernBlockers` bring them together:
  the number of kinds of blocker, out of seven, and one text for the reports. They are columns of
  the CSV and JSON reports. A setting that cannot be read marks the site collection partial, with
  a warning, and is never taken for a site without the signal; a SharePoint that has no modern
  list experience, such as SharePoint Server 2016, has no list experience setting, and the count
  stays 0 without marking the site collection partial. The two example configurations weigh the
  signals: lightly for a migration to SharePoint Online, and as the work of modernizing a farm for
  `SharePointOnPrem`. The aggregate itself weighs nothing, or each blocker would count twice. The
  lab has five scenarios for them, and the wiki pages "Usage" and "Configuration" document them. (#25)
- The report of the `SharePointOnPrem` mode speaks of the modernization of the farm, not of a
  migration. The alert catalog has five new alert types for the signals of the modern experience
  (`AlternateCssUrl`, `XsltListViews`, `ScriptWebParts`, `ModernExperienceOptOut` and
  `ClassicExperienceLists`), raised in both modes, and the mode has a catalog of its own, with the same
  types in the same order. The alerts that are only about a migration to SharePoint Online (external
  lists and BCS, incoming e-mail, forms-based authentication, IRM, unsupported templates, SharePoint
  alerts, permission levels, large sites, checked-out files and file versions, the web application
  policies and the like) are `Low` and start by saying so, with the original text after it. The
  InfoPath forms and the SharePoint 2010 workflows stay `High`, with the date from which Microsoft no
  longer supports them in SharePoint Server Subscription Edition (14 July 2026) and a link to the page
  that says so; the full-trust code, which is rebuilt with the SharePoint Framework and runs until
  then, and the SharePoint 2013 workflows, whose engine SharePoint Workflow Manager replaces, are
  `Medium`; the classic pages, the add-ins, the large lists and the subsites have the words of the
  modernization. The risk indicators of the HTML report are ranked with the severities of the mode, the
  report has a *Modern experience readiness* section (how many site collections have a blocker, how
  many have each kind of blocker, and the 100 that have the most kinds), and the details of a site
  collection list its signals of the modern experience, in both modes. The wiki page "Alerts" documents
  the new alerts and the catalog of the mode. (#25)
- The inventory counts the Excel workbooks that SharePoint Online does not open in the browser, as the
  SMAT scan "Large Excel Files" does. `LargeExcelFileCount` counts the `.xlsx` files of the document
  libraries (the system catalogs are skipped) that are at least `LargeContentThresholds.LargeExcelFileSizeMB`
  large, 10 MB by default, and `LargeExcelFileExamples` lists up to five of them with their size. At most
  `LargeContentThresholds.MaxItemsForExcelFileScanPerLibrary` workbooks (2000 by default) are checked in each
  library; a library above it, or a size that cannot be read, marks the site collection partial. The new
  `LargeExcelFiles` alert (`Low`: the workbooks are migrated, the users are told) is raised in both modes,
  and in the `SharePointOnPrem` mode it is one of the alerts that are only about a migration. The signal weighs
  nothing in either example configuration, it is a column of the `*-large-content-*` dataset and of the CSV
  and JSON files, a risk indicator of the HTML report and a line of the details of a site collection, and the
  lab has a scenario for it. The SMAT scan "Long OneDrive URLs" is not covered, by decision: it needs the file
  paths of every personal site and the user principal name of each owner in the target, which belong to the
  OneDrive migration tooling (see the `Scope` section of the wiki page "Configuration"). (#48)

### Changed

- The risk indicators of the HTML report are a ranked list instead of a grid of 33 cards, 16 of
  them at 0 and all in red. Each signal that at least one site collection raises has a bar for
  the share of site collections, with the count and the percentage, grouped by the severity of
  its alert (High, Medium, Low, as in the alert catalog; a signal with no alert has its own
  severity), and the signals that no site collection raises are named on one line. A click on an
  indicator filters the inventory table to the site collections that raise it. The alerts are
  collapsible lines (severity, name, number affected) that open to show what the alert means,
  what to do and the reference, instead of a table of long texts. Each indicator exposes whether
  its filter is on (`aria-pressed`), and below 640 px the indicators and the alert lines reflow
  instead of making the page wider than the screen. (#90)
- The lab test script creates the lab site collections in a content database of its own
  (`<prefix>_Content`, or the name given with `-ContentDatabaseName`) and removes that database at
  the end when it holds nothing but the lab (its site collections and its deleted site collections:
  one that is not of the lab would be lost for good), so that a test run leaves nothing behind in
  the content database of the web application. The lab site collections that are not in the
  database, such as one that existed before it was created, are removed one by one, with their
  marker checked. When it cannot create the database it says why and falls back to the content
  database of the web application, which `-NoContentDatabase` asks for. (#88)

### Fixed

- A site collection locked with `NoAccess` is now reported as `NoAccess`, as a blocker. SharePoint
  refuses to read anything from such a site collection, its lock flags included: they raise
  "Access to this Web site has been blocked" (0x81020071), which PowerShell turns into `$null`
  when a property is read the usual way, so the lock was reported as `Unknown`, `HasNoAccessLock`
  never fired, the `NoAccessSite` alert was never raised and the site collection landed in the
  Simple category. The flags are read in a way that keeps the error, and that error (or
  `IsReadLocked`, which still reads on such a site) is taken for the NoAccess lock. A flag that
  cannot be read for another reason leaves the state `Unknown`, marks the site collection partial
  and writes a warning. The site collection stays `Partial` because nothing else can be read in
  it. The lab scenario `lock-noaccess` now has to pass. (#83)
- `CustomMasterPage` is no longer reported for the My Site host. Its master page, `mysite15.master`,
  is the one that SharePoint provisions for the My Site templates, but only `seattle`, `oslo` and
  `v4` were recognized. The master page is now compared on its folder and file name in the master
  page gallery instead of on a part of the text, so a copy of `seattle.master` in another folder or
  a master page such as `contoso-v4.master`, which the old comparison took for the original, is
  reported. (#107)
- A Simple site collection whose assessment is partial is no longer put in the quick wins. What
  could not be read counts as 0 in its score, so a site collection that was only read in part
  could be categorized Simple and land in the first wave. It is now in a `Needs review` bucket of
  wave 0, like `Not assessed` and `Unassigned`, whatever wave the mapping gives to the category 1,
  until it is read in full. Its `Category` and `Score` are not changed, a site collection that was
  read in full is not affected, and a partial site collection of another category keeps the wave
  of its category. The wave plan of the HTML report has a `Partial` column that counts the
  partial site collections of each wave, the summary says how many Simple site collections wait
  in `Needs review`, and the `AssessmentPartial` alert says so. The lab has a `partial-simple`
  scenario (three alerts, with the cap of the alert rows lowered to 2) that must end in
  `Needs review`. (#106)
- A site collection whose root web cannot be read, such as one locked with `NoAccess`, is no
  longer reported with the template `#`, the language 0 and two alerts that mean nothing for it.
  PowerShell turns the exception of a property getter into `$null`, so `Title`, `WebTemplate`,
  `Configuration`, `Language` and `LastItemModifiedDate` of such a root web read as empty, and the
  template and the language that were made of them were `#` and 0. They are now read in a way that
  keeps the error, each on its own, so that what can be read is kept. What could not be read stays
  empty (`Template`, `TemplateLanguageLcid`), `TemplateCompatibility` is `NotCollected`,
  `TemplateLanguageReviewRequired` is empty, and one warning names the properties and the error.
  The `TemplateCompatibilityReview` and `TemplateLanguageReview` alerts, and the 0.5 of the score
  for the language, are no longer given for a value that was not read: the site collection is
  partial, and the `AssessmentPartial` alert says so. A root web that can be read is not
  affected. The lab scenario `lock-noaccess` checks it, with a new check that an alert is not
  raised. (#108)

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
