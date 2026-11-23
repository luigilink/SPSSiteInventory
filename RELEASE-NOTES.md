# SPSSiteInventory - Release Notes

## [2.3.0] - 2026-11-23

This release helps to read a scan and to tune it. A run on a real SharePoint farm showed three
things: a scan of 34 site collections took about 19 minutes and nothing said which site collection or
which phase took the time; one signal (the event receivers) made about 90% of the score, and 23 site
collections out of 34 were in the same category; and a scan that stopped at its cap made the whole
site collection partial, so that a known limit kept a Simple site collection in the `Needs review`
wave. 2.3.0 times the scan, says what the score is made of, lets you limit what one signal adds to
it, and treats the cap of a scan as what it is, a lower bound. SPSSiteInventory is still read-only
for the farm and 100% generic (no client-specific value ships in the repository).

It is a minor release: no public function was added or removed, `Export-SPSInventoryReport` has one
new optional parameter that comes after the existing ones, the settings file of 2.2.x keeps working
unchanged (the new setting is optional, and there is no cap by default), and the values and the
weights of the signals do not change. One result does change: a site collection that was partial
only because a scan reached its cap is complete now. The reports gain a column, a manifest field, a
section and log lines: read "Upgrading from 2.2.x" below.

### Highlights

- **The scan says how long it takes.** The log gives one line for each site collection, with its
  number, its duration, its assessment status and its URL (`Site collection 5/34 done in 38 s
  (Complete): https://...`), also for one that failed, and ends the collection with the number of
  site collections, the average and the three slowest. It gives one line when each phase of the run
  ends (the settings and the SharePoint commands, the farm-solution map, the inspection of the
  packages, the enumeration of the site collections, the collection of the signals, the processing of
  the results, the three farm-wide reads and the reports), and its last line gives the total and the
  phases, so that the duration of a large farm can be estimated from a small one. The manifest has a
  new `Timing` object: `StartedAt`, `ScanSeconds` (until the first report is written, so without the
  time that the reports take, which only the log gives), `Phase` (the name and the seconds of each
  phase) and `Site` (the URL, the seconds and the assessment status of each site collection). It
  adds about 144 bytes to the manifest for each site collection. (#139)
- **The report says what the score is made of.** A signal that has a large weight and a large value
  can hold most of the score, which nothing in the report showed. The HTML report has a *Score
  drivers* section, between the migration wave plan and the table of the site collections: a table by
  category (its site collections, its lowest and highest score, the signals that weigh most in it with
  their share, and the blocking signals that set it) and a table by signal (the ten that weigh most:
  its site collections, its share of the score and the site collections where it weighs most). When
  one signal holds half of the score or more, a note says so. The numbers are read from the `Reasons`
  of the records, so the scores, the categories and the files do not change, and the section needs no
  setting. A share is a part of the whole inventory: it does not say that the signal sets the
  category of every site collection that has it, because a blocking signal sets its category whatever
  its weight. (#138)
- **A cap on what one signal adds to the score.** The optional `Scoring.Caps` setting gives, for a
  signal of `Scoring.Weights`, the most that it can add to the score of one site collection. A
  contribution above its cap is cut to it (the reasons say `EventReceivers=121 (+4, capped from
  181.5)`), so that a signal with a large value cannot, on its own, put a site collection above a
  threshold of the categories when its cap is below that threshold. There is no cap by default, and
  nothing changes without one. A cap that is not a number greater than 0, or that names a signal that
  has no weight, is refused before the scan starts, with a message that names it. The *Score drivers*
  table gets a *Capped in* column when a cap cut something, and the log of the scan lists the caps in
  force. Both example files have the block in comments. See the
  [Configuration](https://github.com/luigilink/SPSSiteInventory/wiki/Configuration) wiki page for how
  a cap and the thresholds go together. (#138)
- **A scan that stops at its cap is a lower bound, not a partial site.** The file version, page
  layout, web part, HTML file, Excel file, audience targeting and site notebook scans each read at
  most `LargeContentThresholds.MaxItemsFor...` items of a library or of a list. Reaching that cap
  marked the whole site collection partial: on a real farm, 7 site collections out of 34 were partial
  for the file version scan alone, and a Simple one waited in the `Needs review` wave for a known
  limit although all its other signals were read. The count is now a lower bound ("at least this
  many"): the site collection stays complete, keeps its category and its wave, and has the warning
  that says where the scan stopped. The new `LowerBoundSignals` column names the signals whose count
  is a lower bound, the HTML report shows these counts as "at least", and its summary and its *Modern
  experience readiness* section say how many site collections reached a cap. A scan that cannot read
  (an error, a list that cannot be opened) still makes the site collection partial. (#137)
- **The values and the weights of the signals do not change.** The score of a site collection is the
  same as in 2.2.0 unless you set a cap, and the categories follow from the score as before.

### Upgrading from 2.2.x

- **Settings.** Nothing is required: there is no new required setting, and the example files only
  gain comments (the `Scoring.Caps` block, and the way that a scan that reaches its cap is now
  treated).
- **Results.** The signals, their weights, the categories and the alerts (50 alert types) are those
  of 2.2.0, with one exception: a site collection that was partial only because a scan reached its
  cap is complete now. A farm therefore reports fewer partial site collections and fewer in the
  `Needs review` wave, and the `AssessmentPartial` alert is not raised for them. The cap of the alert
  rows (`MaxAlertRowsPerSite`) is not part of this: the rows that are cut still make the site
  collection partial.
- **Files and manifest.** The site CSV and JSON gain a column, `LowerBoundSignals` (the names of the
  signals whose count is a lower bound, separated by semicolons, empty when there is none), and so do
  the `*-publishing-*`, `*-permissions-*`, `*-large-content-*` and `*-collaboration-*` files. The
  manifest gains `Timing` (null when `Export-SPSInventoryReport` is called without `-Timing`). They
  are additive: `ReportPackVersion` stays `1.0`. Read the files by column name, not by position.
- **HTML report.** A new *Score drivers* section, with a link in the navigation. The detail of a site
  collection shows the counts whose scan reached a cap as "at least", and the summary and the *Modern
  experience readiness* section say how many site collections reached one.
- **Log.** The log gains the timing lines (one for each site collection and each phase, and the
  total) and, when a cap is set, the line that lists the caps.
- **Public functions.** None was added or removed. `Export-SPSInventoryReport` has a new optional
  parameter, `-Timing`, which comes after the existing ones, so that a call of 2.2.x that gives
  parameters by position keeps its meaning.

### Known issues

- **Found on a real farm, not fixed yet.** On a SharePoint 2016 farm the farm solution map reported
  one feature and no feature id for every solution, and a solution that has no feature at all was
  reported with one (#131), so `UsesCustomFarmFeature` is not raised for the site collections that
  activate a feature of a custom solution: the packages inspected with `-ExportSolutionPackage` list
  the features of each solution. `Workflow2013Count` stays at 0 when Workflow Manager is not
  connected, and the report does not say it (#134), so a 0 does not prove that a farm has no
  SharePoint 2013 workflow. Both are planned for a coming release. On a farm whose interface is not
  in English, the permission levels that SharePoint provisions are reported as custom, because their
  names are localized (#136): fill `PermissionLevels.BuiltInNames` with the localized names, as the
  warning of the run advises.
- **The categories of a farm are yours to tune.** The *Score drivers* section shows what makes the
  score, and `Scoring.Caps` limits what one signal adds, but what that does to the categories depends
  on the farm (#138, still open). On the saved report of one real farm, a cap on the receivers alone
  moved at most 2 of 23 site collections out of the Complex category, because their other signals
  already put them above the threshold; capping the few signals that have the largest values brought
  the scores together, and the thresholds then decided the categories. Read the section on your first
  inventory, set caps on the signals that weigh a lot, and move the thresholds if the categories still
  do not spread.
- **Not tested on a farm yet.** The timing and the caps are tested with stand-ins for the SharePoint
  objects, and the caps on one saved report, not on a live scan. The first run on a farm gives real
  durations; please report anything that looks wrong in the timing lines of the log.
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
