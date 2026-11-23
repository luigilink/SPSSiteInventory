# SPSSiteInventory - Release Notes

## [2.3.1] - 2026-11-23

A patch release, from the first runs of 2.3.0 on a lab farm. It fixes the farm-solution report, which
gave one feature and no feature id to every solution, so that `UsesCustomFarmFeature` and
`UsesFullTrustCode` were never raised (#131). It fixes the inspection of the WSP packages, which missed
the application resource files that the Visual Studio SharePoint tools write (#151), and it documents the
French names of the permission levels that SharePoint provisions (#136). SPSSiteInventory is still
read-only for the farm and 100% generic (no client-specific value ships in the repository).

It is a patch release: no public function, parameter, column or setting was added or removed, and
`ReportPackVersion` stays `1.0`. One result changes, on purpose, on a farm that has custom solutions:
read "Upgrading from 2.3.0" below before you compare a scan with an earlier one.

### Highlights

- **The features of a farm solution come from the farm** (#131). `Get-SPSFarmSolutionMap` read them from a
  property that a farm solution does not have, so that every solution showed one feature and no id, and a
  solution without any feature showed one too. It now reads the feature definitions of the farm
  (`Get-SPFeature -Limit All`, once for all the solutions) and gives each solution the ones that carry its
  id, counted once whatever the compatibility levels. The farm-solution CSV and JSON show the real
  `FeatureCount`, `FeatureScopes` and `FeatureIds`, and the `Difference` of an inspected package no longer
  reports a feature count that the farm had wrong. A solution that is added and not deployed has no
  feature on the farm, as SharePoint registers them when it deploys the solution: its package lists the
  ones it would register. When the farm does not give the definitions, the scan warns and the counts stay
  at 0.
- **`UsesCustomFarmFeature` and `UsesFullTrustCode` are raised** (#131). The scan matches the features that
  each site collection activates against the ids of the custom solutions. The ids were always empty, so
  the two signals were never raised in 2.2.0 and 2.3.0. A site collection that activates a feature of a
  custom solution now has `UsesCustomFarmFeature`, and `UsesFullTrustCode` (the `FullTrustCode` alert) when
  that solution deploys a global assembly.
- **The log says what the signals are matched against.** The line that ends the farm-solution map gives
  the number of solutions, of features of custom solutions and of those of full-trust code, for example
  `23 solution(s), 41 feature(s) of custom solutions, 6 of full-trust code`. A farm that has custom
  solutions and no feature shows at once.
- **The package inspection counts the application resource files under both element names** (#151).
  The solution schema allows `ApplicationResourceFile` and `App_GlobalResourceFile`, which is the one that
  Visual Studio writes, and only the first was counted, so that `ContainsWebApplicationResource` was
  `False` for a package that has such files and no assembly deployed to a web application.
- **The French names of the provisioned permission levels are documented** (#136). The Configuration wiki
  page lists the names of View Only, Approve, Manage Hierarchy, Restricted Read and Restricted
  Interfaces for Translation on a farm with a French interface, to put in `PermissionLevels.BuiltInNames`.

### Upgrading from 2.3.0

- **Settings.** Nothing is required: no setting was added, and the example files do not change.
- **Results.** On a farm that has custom solutions, the scores and the categories change, and that is the
  point of the fix. In the example settings for a migration to SharePoint Online, `UsesCustomFarmFeature`
  and `UsesFullTrustCode` are blocking signals: a site collection that activates a feature of a custom
  solution is now *Blocked*. The on-premises preset weighs them (2.0 and 4.0) and does not block on them.
  If you compare a scan with one of 2.3.0 or 2.2.x, expect these site collections to move, and read the
  farm-solution report for the solutions behind them. A farm without custom solutions, and the signals
  other than these two, do not change.
- **Files and manifest.** No column, field or file was added. The farm-solution CSV and JSON now give
  the real `FeatureCount`, `FeatureScopes` and `FeatureIds` (they gave 1, and nothing), and the `Difference`
  of a package no longer lists a false difference on the number of features of a deployed solution.
  `ContainsWebApplicationResource` of a package can change from `False` to `True`, for the packages
  described above. Read the files by column name, not by position.
- **Log.** The line that ends the farm-solution map gives the counts of features, and a warning is written
  when the feature definitions of the farm cannot be read.
- **Public functions.** None was added or removed, and no parameter changed.

### Known issues

- **Found on a real farm, not fixed yet.** `Workflow2013Count` stays at 0 when Workflow Manager is not
  connected, and the report does not say it (#134), so a 0 does not prove that a farm has no SharePoint
  2013 workflow. It is planned for a coming release, and needs a farm that has Workflow Manager to be
  confirmed. On a farm whose interface is not in English, the permission levels that SharePoint provisions
  are reported as custom, because they are recognized by their English names (#136): the French names are
  in the Configuration page, and for another language fill `PermissionLevels.BuiltInNames`, as the warning
  of the run advises. Recognizing them in any language, without a list, is not done.
- **The categories of a farm are yours to tune.** The *Score drivers* section shows what makes the
  score, and `Scoring.Caps` limits what one signal adds, but what that does to the categories depends
  on the farm (#138, still open). On the saved report of one real farm, a cap on the receivers alone
  moved at most 2 of 23 site collections out of the Complex category, because their other signals
  already put them above the threshold; capping the few signals that have the largest values brought
  the scores together, and the thresholds then decided the categories. Read the section on your first
  inventory, set caps on the signals that weigh a lot, and move the thresholds if the categories still
  do not spread.
- **Partly tested on a farm.** The fix of the features ran on a lab farm that has two custom solutions: the
  farm-solution report gives their real counts, scopes and ids, which are the ids of their packages, the
  line that ends the farm-solution map gives the counts, the `Difference` of the packages is empty, and
  nothing else in the reports changes. No site collection of that farm activates a feature of a custom
  solution, so `UsesCustomFarmFeature` and `UsesFullTrustCode` have not been seen raised on a farm yet: they
  are tested with stand-ins. Please report anything that looks wrong in the farm-solution report, in the
  line that ends the farm-solution map, or in the two signals. The timing lines of 2.3.0 ran on the same
  lab farm; the caps (`Scoring.Caps`) are still waiting for a first run on a farm.
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
