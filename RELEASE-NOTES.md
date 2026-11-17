# SPSSiteInventory - Release Notes

## [2.2.0] - 2026-11-17

This release makes the inventory show what its numbers are made of. A first run of 2.1.0 on a real
SharePoint farm asked for more detail on three things: what the farm solutions contain (the WSP
packages could be inspected offline, but not from the scan), what the `EventReceivers` signal counts
(registrations, and not the classes behind them), and which workflows are behind the totals
`Workflow2010Count` and `Workflow2010RunningInstanceCount`. 2.2.0 lists what is behind each of them,
in the HTML report and in new CSV and JSON files. SPSSiteInventory is still read-only for the farm
and 100% generic (no client-specific value ships in the repository).

It is a minor release: no public function lost a parameter, the parameters that were added come
after the existing ones, the settings file of 2.1.x keeps working unchanged, and the values and the
weights of the signals do not change. The reports gain columns, files, sections and manifest fields:
read "Upgrading from 2.1.x" below.

### Highlights

- **The WSP packages can be inspected from the scan.** `Invoke-SPSSiteInventory.ps1` has two new
  optional parameters. `-ExportSolutionPackage` saves the package of every farm solution
  (`SolutionFile.SaveAs`) in a temporary folder of the account that runs the scan, inspects the
  packages with `Get-SPSSolutionPackageInfo`, and removes the folder as soon as they are read, also
  after an error or Ctrl+C (a killed process leaves it: the log gives its path). Nothing goes in the
  reports folder, which is the one that is zipped and sent: only what the inspection found reaches
  the reports, and the temporary paths are taken out of their text. `-SolutionPackagePath` takes the
  packages that you already have (WSP files, folders that hold some, or folders of expanded
  packages), and the two can be combined. The reports gain a *Solution packages* section (what each
  package holds: custom or Microsoft, full-trust code, assemblies, features and .NET framework; the
  farm solution that it matches and what differs; the farm solutions that no inspected package
  matches) and the `*-solution-packages-*` and `*-solution-assemblies-*` files. A package that
  cannot be saved or read is a warning, not the end of the scan. Without either parameter nothing
  changes, except that the scan ends by telling how to inspect the packages when the farm has
  solutions. See
  [Inspecting WSP packages offline](https://github.com/luigilink/SPSSiteInventory/wiki/Solution-Packages).
  (#135)
- **What the `EventReceivers` signal counts.** SharePoint registers one receiver for each event type
  and each list, so a class that listens to six events on a hundred lists counts 600. A site
  collection now has `EventReceiverExamples` (up to five assemblies and classes, the largest first,
  with the number of receivers and of lists, the first list and the solution that ships the
  assembly), the HTML detail of a site collection shows it, and the report has a *Custom event
  receivers* section by assembly. `*-eventreceivers-*` CSV and JSON files give one row for each
  assembly and class in each site collection. When the packages are inspected, each assembly is
  matched to the package and the farm solution that ship it, by its name and its public key token.
  (#132)
- **What the classic workflow signals count.** `Workflow2010Count` and
  `Workflow2010RunningInstanceCount` did not say which workflows they were, so the site owners could
  not be told which list or library to look at, and the counts could not be checked. A site
  collection now has `Workflow2010Examples` (up to five associations, the counted ones with the most
  running instances first), and the report has a *Workflow associations* section and
  `*-workflow-associations-*` CSV and JSON files, with one row for each classic workflow association
  of a web, a list or a library. `Counted` says whether the association is in `Workflow2010Count`: a
  previous version of a workflow, which SharePoint keeps as an association of its own, is not, but
  its running instances are in `Workflow2010RunningInstanceCount`. The counted rows of a site
  collection add up to the first count, and all its rows to the second. (#133)
- **The detail never changes what is counted.** The values and the weights of the signals are those
  of 2.1.0, so the categories, the waves and the alerts of a farm do not change. The detail is kept
  within limits (200 assemblies and classes for the event receivers of a site collection, and 1000
  rows for the previous versions of workflows, whose counted rows are all kept), the counts stay
  exact, and a note in the HTML report says how much of a signal its table accounts for when that is
  less than the column. A site collection whose detail cannot be built keeps its counts, its other
  signals and its status, and a warning gives the reason.

### Upgrading from 2.1.x

- **Settings.** Nothing is required: there is no new setting, and the example files are unchanged.
- **Results.** No result changes: the signals, their weights, the categories, the waves and the
  alerts (50 alert types) are those of 2.1.0.
- **Files and manifest.** The site CSV and JSON gain two columns, `EventReceiverExamples` and
  `Workflow2010Examples` (the workflow dataset of the report pack gains the second too), and the run
  writes more files: `*-eventreceivers-*` and `*-workflow-associations-*` (CSV and JSON) and, when
  packages are inspected, `*-solution-packages-*` (CSV and JSON) and `*-solution-assemblies-*`
  (CSV). The manifest lists them (`Files.EventReceiversCsv`, `Files.EventReceiversJson`,
  `Files.WorkflowAssociationsCsv`, `Files.WorkflowAssociationsJson`, `Files.SolutionPackagesCsv`,
  `Files.SolutionPackagesJson` and `Files.SolutionAssembliesCsv`) and counts the packages
  (`Summary.SolutionPackageCount` and `Summary.SolutionPackageIssueCount`, null when no package was
  inspected). They are additive: `ReportPackVersion` stays `1.0`. Read the files by column name, not
  by position.
- **HTML report.** Three new sections, each only when it has something to show: *Custom event
  receivers*, *Workflow associations* and *Solution packages* (after the farm solutions), with a
  link in the navigation. The detail of a site collection shows the two kinds of examples.
- **Inspecting the packages from the scan.** `-ExportSolutionPackage` reads the packages from the
  farm, so the account that runs the inventory has to be able to read the farm solutions, as for the
  farm solution map, and a package that it cannot save is a warning. The temporary folder is in the
  profile of that account, and it is removed when the packages have been read. Use
  `-SolutionPackagePath` instead when the packages are already on disk.
- **Public functions.** None was added or removed. The new parameters are all optional and come
  after the existing ones, so that a call of 2.1.x that gives parameters by position keeps its
  meaning: `-ExportSolutionPackage` and `-SolutionPackagePath` of the script, `-SolutionPackages`,
  `-EventReceiverClasses` and `-WorkflowAssociations` of `Export-SPSInventoryReport` and
  `ConvertTo-SPSInventoryHtml`, `-Timestamp` of `Export-SPSSolutionPackageReport` and
  `-SolutionAssemblyIndex` of `Get-SPSSiteCustomization`. (#143)

### Known issues

- **Found on a real farm, not fixed yet.** On a SharePoint 2016 farm the farm solution map reported
  one feature and no feature id for every solution, and a solution that has no feature at all was
  reported with one (#131), so `UsesCustomFarmFeature` is not raised for the site collections that
  activate a feature of a custom solution: the packages inspected with `-ExportSolutionPackage` list
  the features of each solution. `Workflow2013Count` stays at 0 when Workflow Manager is not
  connected, and the report does not say it (#134), so a 0 does not prove that a farm has no
  SharePoint 2013 workflow. Both are planned for 2.2.1. On a farm whose interface is not in English,
  the permission levels that SharePoint provisions are reported as custom, because their names are
  localized (#136): fill `PermissionLevels.BuiltInNames` with the localized names, as the warning of
  the run advises.
- **Not tested on a farm yet.** The new detail is tested with stand-ins for the SharePoint objects:
  `SolutionFile.SaveAs` and the end-to-end run of `-ExportSolutionPackage`, the registration data of
  real event receivers, and the real workflow association objects (their name, their running
  instances and the way that an association is told apart from the previous versions of its
  workflow). The first run on a farm settles them. When one differs, the run log carries a warning
  that names it and the detail of that site collection is left out, with its counts unchanged.
  Please report the text of such a warning. The time that the detail adds to a scan has not been
  measured on a farm with thousands of associations either.
- **Still open from 2.1.0.** The Secure Store, profile property mapping, audience targeting and site
  notebook scans read members of SharePoint objects that Microsoft documents only in part. They are
  tested with stand-ins, and a run on a farm settles them: when a member differs, the run log
  carries a warning that names it and the report is marked partial. `JSLink`, the client-side
  rendering of the views and of the fields, is not collected yet: see "What is not collected yet" in
  the [Configuration](https://github.com/luigilink/SPSSiteInventory/wiki/Configuration) wiki page.

### Notes

- The inventory requires Windows PowerShell 5.1 (the SharePoint Server object model); do not use
  PowerShell 7. The offline inspection of WSP packages needs no farm: it runs on PowerShell 5.1 or
  later, on any machine, with `expand.exe` on Windows or `cabextract` elsewhere.
- Compatible with SharePoint Server 2016, 2019 and Subscription Edition. A SharePoint that has no
  modern list experience, such as SharePoint Server 2016, has no list experience setting: the two
  signals about it stay 0.
- To test a release on a lab farm, the `tools/lab` folder of the repository (not part of this ZIP)
  builds one test site collection per signal and checks the reports. It writes to the farm, so use
  it on a lab only; see the
  [Lab testing](https://github.com/luigilink/SPSSiteInventory/wiki/Lab-Testing) wiki page. The
  scenarios that need a deployed assembly, a SharePoint 2010 workflow template or Permissive browser
  file handling stay manual.
- See the [wiki](https://github.com/luigilink/SPSSiteInventory/wiki) for setup, configuration and
  usage.
