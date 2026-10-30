# SPSSiteInventory - Release Notes

## [2.1.0] - 2026-10-30

This release adds a second question to the inventory. Besides "can this site collection move to
SharePoint Online?", it can now answer "is it ready for the modern experience on the farm where it
runs, and what does it take to modernize it?", with a target mode, the signals that keep a site
collection in the classic experience, and a report that speaks of modernization. It also brings
the last SMAT scans that were missing (Secure Store, audience targeting, site notebooks, profile
property mappings and large Excel files), an offline inspection of WSP packages that needs no farm,
a ranked list of risk indicators, an HTML report that splits itself on a very large farm, the
fixes for the known issues of 2.0.0, and reports that are written next to the script when
`OutputFolder` is empty. SPSSiteInventory is still read-only and 100% generic (no client-specific
value ships in the repository).

It is a minor release: no public function lost a parameter, and the settings file of 2.0.x keeps
working unchanged. The reports gain columns, files and manifest fields, and a few results change
because bugs were fixed: read "Upgrading from 2.0.x" below.

### Highlights

- **A target mode to modernize a farm in place.** `TargetMode = 'SharePointOnPrem'` (the default,
  also when the setting is missing, stays `SharePointOnline`) names the four categories
  *Modern-ready*, *Light remediation*, *Rebuild (SPFx)* and *Blocked*, words the HTML report and the
  waves as a modernization plan, and has an alert catalog of its own: what only matters for a
  migration to SharePoint Online is `Low` and says so, and the InfoPath forms and the SharePoint
  2010 workflows stay `High`, with the date from which SharePoint Server Subscription Edition no
  longer supports them. A new example file, `inventory-settings.onprem.example.psd1`, ships the
  scoring of that question: full-trust code still runs on the farm, so it weighs as code to rebuild
  with the SharePoint Framework and no longer blocks. A *Modern experience readiness* section of
  the HTML report counts the site collections that have a blocker, and how many have each kind.
- **What keeps a site collection in the classic experience.** In both modes the inventory counts the
  webs that set an alternate CSS URL, the list views that render with a customized XSLT (an
  `XslLink` that is not a style sheet that SharePoint ships, or an `Xsl`; the personal views and the
  hidden views, in which web parts keep their settings, are left out), the Script Editor and Content
  Editor web parts that embed a script, the site collections and webs that opted out of the modern
  list experience, and the lists forced to the classic experience. `ModernBlockerCount` and
  `ModernBlockers` bring them together, and alerts say what to do about each kind. A setting that
  cannot be read marks the site collection partial: it is never taken for a site without the signal.
- **The remaining SMAT scans.** The Secure Store target applications of the farm
  (`Get-SPSSecureStoreApplication`), the list items that target an audience, the site notebooks,
  the profile property mappings of the User Profile service (`Get-SPSProfilePropertyMapping`) with
  the customized profile page of the My Site host, and the Excel workbooks that SharePoint Online
  does not open in the browser. Each has its alerts (13 new alert types, 50 in all), its place in
  the reports and the advice of its SMAT page. The SMAT scan "Long OneDrive URLs" is not covered,
  by decision: see the `Scope` section of the
  [Configuration](https://github.com/luigilink/SPSSiteInventory/wiki/Configuration) wiki page.
- **Offline inspection of WSP packages.** `Get-SPSSolutionPackageInfo` and
  `Export-SPSSolutionPackageReport` read a WSP with no farm and no SharePoint command. They report
  the strong name of every assembly (a package is custom or Microsoft on its assemblies, not on the
  name of the solution, and a token only counts when the signature is valid), the features even
  when the solution is not deployed, the receivers, where the assemblies go, the safe controls, the
  code access security policy and the .NET framework that the DLLs were built for, and match the
  packages to the farm solutions. The package is not trusted: nothing in it is loaded. See
  [Inspecting WSP packages offline](https://github.com/luigilink/SPSSiteInventory/wiki/Solution-Packages).
- **A ranked list of risks, and an HTML report that scales.** The risk indicators are ranked bars
  grouped by severity instead of a grid of cards, a click filters the inventory, and the alerts are
  collapsible lines. Above `Report.HtmlSplitThreshold` site collections (3,000 by default) the
  report becomes an entry page, with the summary, the indicators, the alerts and the wave plan, and
  pages of at most `Report.HtmlRowsPerPage` site collections each (500): with 30,000 site
  collections, 62 files, the largest 1.3 MB. The pages are self-contained and link to each other
  with relative links, so the folder can be moved, zipped and sent.
- **The known issues of 2.0.0 are fixed.** A site collection locked with `NoAccess` is reported as
  `NoAccess` and blocks (#83); a Simple site collection whose assessment is partial waits in
  `Needs review` instead of in the quick wins (#106); the My Site host no longer reports a custom
  master page (#107); a site collection whose root web cannot be read no longer gets the template
  `#` and the language 0 (#108).
- **A lab that cleans up after itself.** The lab test script creates its site collections in a
  content database of its own and removes it at the end (#88), and has a scenario for each new
  signal.
- **Reports next to the script by default.** `OutputFolder` is empty in the example settings: the
  reports go to a `Reports` folder next to `Invoke-SPSSiteInventory.ps1`, as the logs go to a `Logs`
  folder next to it. The folder is created when the run starts, so one that cannot be created stops
  the run before the scan, not when the reports are written (#126).

### Upgrading from 2.0.x

- **Settings.** Nothing is required. The new settings are optional and fall back to their defaults:
  `TargetMode`, the caps of `LargeContentThresholds` (`MaxItemsForWebPartScanPerLibrary`,
  `LargeExcelFileSizeMB`, `MaxItemsForExcelFileScanPerLibrary`,
  `MaxItemsForAudienceTargetingScanPerList` and `MaxItemsForNotebookScanPerLibrary`) and the
  `Report` section (`HtmlSplitThreshold`, `HtmlRowsPerPage`); so is `OutputFolder`, which is not
  mandatory any more (see "Output folder" below). A signal that your file does not weigh weighs
  nothing. The readiness check compares your file with the example of its mode and lists what it
  lacks.
- **Example configuration.** `inventory-settings.example.psd1` gives a small weight to three of the
  new signals (`AlternateCssUrlCount` 0.5, `XsltListViewCount` 0.25, `ScriptWebPartCount` 0.5), so a
  file copied from it can categorize a few site collections differently. A file of 2.0.x is not
  affected.
- **Output folder.** `OutputFolder` is empty in both example files. When it is empty, or missing, the
  reports go to a `Reports` folder next to `Invoke-SPSSiteInventory.ps1`, as the logs go to a `Logs`
  folder next to it, and the run creates it when it starts. A settings file that sets `OutputFolder`,
  as every working file of 2.0.x does, is not affected: its folder is used as it is. A file that you
  copy from the new example writes next to the script until you set the folder. The readiness check
  looks at the same folder: an empty `OutputFolder` is no longer an error, and `Get-SPSReadinessCheck`
  has a new optional `-ScriptRoot` parameter for it.
- **Files and manifest.** The site CSV and JSON gain a column for each new signal, and the run
  writes more files: the `-collaboration-` JSON, and a CSV and a JSON for the Secure Store and for
  the profile property mappings, which are read once for the farm. The manifest lists them and has
  new fields (`Summary.TargetMode`, `Summary.SecureStoreInventoryComplete`,
  `Summary.ProfileInventoryComplete`, `Files.InventoryHtmlPages`, and the paths of the new files).
  They are additive: `ReportPackVersion` stays `1.0`. Read the files by column name, not by
  position.
- **HTML report.** The risk indicators are a ranked list, and a report of more than
  `Report.HtmlSplitThreshold` site collections is several files: open the entry page, whose name is
  that of the single file. `Report.HtmlSplitThreshold = 0` keeps one file, and
  `ConvertTo-SPSInventoryHtml -FileName` returns the pages as objects (the report is still a string
  without it).
- **Results that change because of the fixes.** A site collection locked with `NoAccess` used to be
  `Unknown`, partial and sometimes Simple: it is now `NoAccess`, raises the `NoAccessSite` alert
  and blocks, so a farm that has such locks reports more Blocking site collections. A Simple site
  collection whose assessment is partial leaves the quick wins for the `Needs review` bucket of
  wave 0, and the wave plan has a `Partial` column. A root web that cannot be read leaves the
  template and the language empty instead of `#` and 0. The My Site host no longer reports
  `CustomMasterPage`, and a copy of `seattle.master` in another folder, or a master page such as
  `contoso-v4.master`, is now reported. Run the inventory again to get them.
- **Alerts.** The alert catalog grows from 37 to 50 types. The five alerts of the signals of the
  modern experience (`AlternateCssUrl`, `XsltListViews`, `ScriptWebParts`, `ModernExperienceOptOut`
  and `ClassicExperienceLists`) are raised in both modes, so a site collection can show alerts for
  things that were there before and that 2.0.x did not look at.
- **Permissions.** The Secure Store and the profile property mappings are read through the service
  applications of the farm: the account that runs the inventory has to administer them (the farm
  account does). Without the permission the report is partial, and the warning of the run says why.
- **New public functions.** `Get-SPSSecureStoreApplication`, `Get-SPSProfilePropertyMapping`,
  `Get-SPSSolutionPackageInfo` and `Export-SPSSolutionPackageReport`.

### Known issues

- The Secure Store, profile property mapping, audience targeting and site notebook scans read
  members of SharePoint objects that Microsoft documents only in part (what
  `Get-SPSecureStoreApplication` returns, the connections of the User Profile service and the
  non-public method that holds the mappings of an Active Directory import connection, the audience
  manager, the file type of a notebook). They are tested with stand-ins, and the first run on a farm
  settles them. When a member differs, the run log carries a warning that names it and the report
  (the site collection, for the audience and notebook scans) is marked partial, apart from the case
  where the service itself is not found (a farm without the Secure Store or the User Profile
  service looks the same): the log then says that no proxy was found and the report is empty.
  Please report the text of such a warning.
- `JSLink`, the client-side rendering of the views and of the fields, is not collected yet: see
  "What is not collected yet" in the
  [Configuration](https://github.com/luigilink/SPSSiteInventory/wiki/Configuration) wiki page.

### Notes

- The inventory requires Windows PowerShell 5.1 (the SharePoint Server object model); do not use
  PowerShell 7. The offline inspection of WSP packages needs no farm: it runs on PowerShell 5.1 or
  later, on any machine, with `expand.exe` on Windows or `cabextract` elsewhere.
- Compatible with SharePoint Server 2016, 2019 and Subscription Edition. A SharePoint that has no
  modern list experience, such as SharePoint Server 2016, has no list experience setting: the two
  signals about it stay 0.
- To test a release on a lab farm, the `tools/lab` folder of the repository (not part of this
  ZIP) builds one test site collection per signal and checks the reports. It writes to the farm,
  so use it on a lab only; see the
  [Lab testing](https://github.com/luigilink/SPSSiteInventory/wiki/Lab-Testing) wiki page. The
  scenarios that need a deployed assembly, a SharePoint 2010 workflow template or Permissive
  browser file handling stay manual.
- See the [wiki](https://github.com/luigilink/SPSSiteInventory/wiki) for setup, configuration and usage.
