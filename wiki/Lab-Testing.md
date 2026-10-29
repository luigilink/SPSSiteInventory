# Lab testing

The unit tests of SPSSiteInventory run against mocked SharePoint objects, so each new collector still has to be checked once on a real farm. The lab scripts do that for you: they build small test site collections on a **lab** farm, run the inventory and check the reports against what each test site must produce.

> **They write to the farm.** Unlike the toolkit, which is read-only, the lab scripts create and remove site collections. Use them on a lab farm only, and on a lab web application: the inventory scans the whole web application, not only the lab sites.

The scripts are in the `tools/lab` folder of the repository. They are not part of the release ZIP, which holds the read-only toolkit only: copy the folder to the farm server next to the extracted release you want to test.

## What you need

- A lab SharePoint Server farm (2016, 2019 or Subscription Edition) and a lab web application.
- The **SharePoint Management Shell**, elevated (Windows PowerShell 5.1), signed in as the farm account.
- The toolkit to test: the extracted release ZIP, or the `src` folder of the repository.
- A farm account that can create a content database (the farm account can). The lab then has a content database of its own, `<prefix>_Content`. When the script cannot create one, it says why and the lab goes in the content database of the web application, as before.

## Run it

```powershell
.\Invoke-SPSLabTest.ps1 -WebApplicationUrl https://lab.contoso.local -ToolkitPath C:\SPSSiteInventory
```

By default, the script runs these steps in order (`-Action` runs one of them):

1. **Provision**: writes the lab settings from the example configuration of the toolkit being tested (only the environment name, the web application, the report folder and the large-content thresholds change), then creates a content database for the lab and one site collection per scenario in it, `<web application>/sites/<prefix>-<scenario>`, and marks it as a lab site. A confirmation is asked before each one; `-Force` skips it and `-WhatIf` shows what would be created.
2. **Inventory**: runs `Invoke-SPSSiteInventory.ps1` of the toolkit with the lab settings.
3. **Verify**: checks the reports against the expectations of every scenario (see below) and prints the result. The exit code is 1 when a check fails.
4. **Remove**: removes the lab: its content database when it has one, the lab site collections otherwise (see Safety). It runs only with `-Cleanup`, or on its own with `-Action Remove`. With `-Cleanup` it also runs when an earlier step failed, so that a half-built lab is not left behind, and the failure of that step is still the one reported.

With `-WhatIf`, nothing is written: no settings file, no manifest and no site collection. The inventory and the verification are skipped too, because there is nothing for them to read.

| Parameter | Meaning |
| --- | --- |
| `-WebApplicationUrl` | The lab web application. There is no default: name it on purpose. |
| `-ToolkitPath` | The toolkit to test. Defaults to the `src` folder of the repository that holds the script. |
| `-Action` | `Provision`, `Inventory`, `Verify`, `Remove` or `All` (the default). |
| `-Scenario` | Builds and checks only these scenarios, for example `-Scenario subsites,infopath`. |
| `-WorkFolder` | Where the lab settings, the manifest (`lab-manifest.json`) and the reports go. Defaults to `.\SPSLab`. |
| `-Prefix` | The prefix of the site collection names (lowercase letters and digits). Defaults to `spslab`. When the lab is removed with the manifest of the work folder, it must be the prefix of that manifest. |
| `-Owner` | The owner of the site collections. Defaults to the current account. |
| `-ContentDatabaseName` | The content database of the lab. It must start with `<prefix>_`. Defaults to `<prefix>_Content`. |
| `-NoContentDatabase` | Does not create a content database: the lab goes in the content database of the web application. |
| `-Cleanup` | With `-Action All`, removes the lab at the end. |
| `-Force` | Does not ask for a confirmation before each creation or removal. |

## Read the result

```text
== subsites (https://lab.contoso.local/sites/spslab-subsites) ==
[PASS]  SubsiteCount eq 5
[PASS]  Alert Subsites
[INFO]  Assessment - actual: Partial: Customization inventory partial; some signals may be missing.
```

| Status | Meaning |
| --- | --- |
| `PASS` | The check is met. |
| `FAIL` | The check is not met. It is a problem of the toolkit, or of the lab if the scenario could not be built (`Scenario built`). |
| `INFO` | Informational: a check that depends on the farm or on the account is not met, or a site is `Partial` or `Failed`. Read it, it does not fail the run. |
| `SKIP` | The check could not run: the scenario was skipped because the farm lacks something it needs, or the alerts report of the run is missing. |

The verification reads the latest sites report of the work folder, and the alerts report that was written with it (same name and time stamp), never an older or a newer one. An alerts report that is missing makes the alert checks `SKIP`; one that is there but empty means that the run raised no alert, so they `FAIL`. `-Scenario` limits it to the scenarios you name.

Every lab site also gets an `Assessment` line. A site whose assessment is `Partial` or `Failed` is how a problem with a real farm shows up (a property that cannot be read, for example), and its warnings are listed: those are the ones to send back. The reports are in the work folder; they hold lab data only.

## The scenarios

Each scenario is a site collection built to trigger known signals, and what the inventory must report for it. A scenario that cannot be built on the farm is skipped and does not stop the others. A check marked *(info)* is reported but never fails the run.

| Scenario | What it builds | What must be reported |
| --- | --- | --- |
| `baseline` | An empty team site: nothing must be flagged, and the assessment must be complete. | `AssessmentStatus = "Complete"`; `SubsiteCount = 0`; `MaxSubsiteDepth = 0`; `SubWebCount = 1`; `SiteLockState = "Unlock"`; `IsLockedSite = false`; `InfoPathFormCount = 0`; `Workflow2010Count = 0`; `SharePointAlertCount = 0`; `UsesFullTrustCode = false`; `AlternateCssUrlCount = 0`; `XsltListViewCount = 0`; `ScriptWebPartCount = 0`; `ClassicExperienceOptOutCount = 0`; `ClassicExperienceListCount = 0`; `ModernBlockerCount = 0`; `AudienceTargetedItemCount = 0`; `CustomizedProfilePageCount = 0`; `Category = 1` |
| `subsites` | Five subsites, three levels deep: a, a/b, a/b/c, d and e. | `SubsiteCount = 5`; `MaxSubsiteDepth = 3`; `SubWebCount = 6`; `SubsiteExamples like "a/b/c (level 3)*"`; alert `Subsites` |
| `lock-readonly` | A ReadOnly lock: the site is reported as locked but not as a blocker. | `SiteLockState = "ReadOnly"`; `IsLockedSite = true`; `HasNoAccessLock = false`; alert `LockedSite` |
| `lock-noadditions` | A NoAdditions lock: the site is reported as locked but not as a blocker. | `SiteLockState = "NoAdditions"`; `IsLockedSite = true`; `HasNoAccessLock = false`; alert `LockedSite` |
| `lock-noaccess` | A NoAccess lock. The site cannot be read, so its assessment stays partial, its template and its language stay empty and raise no alert, but the lock must be recognized and reported as a blocker. | `SiteLockState = "NoAccess"`; `IsLockedSite = true`; `HasNoAccessLock = true`; `Category = 4`; `Template = ""`; `TemplateLanguageLcid = null`; `TemplateCompatibility = "NotCollected"`; `SiteInventoryWarnings` says that the root web could not be read; alert `NoAccessSite`; no alert `TemplateCompatibilityReview` and no alert `TemplateLanguageReview` |
| `large-content` | A list above the large-list threshold with a view that has a high row limit, a document with several versions and a checked-out document. | `LargeListCount >= 1`; `LargeListViewCount >= 1`; `CheckedOutFileCount >= 1`; `FileVersionCount >= 1`; alert `LargeLists`; alert `LargeListViews`; alert `CheckedOutFiles`; alert `FileVersions` |
| `large-excel` | A workbook above the large-workbook threshold and a small one in a library: only the large one must be reported. | `LargeExcelFileCount = 1`; `LargeExcelFileExamples like "*lab-large.xlsx*"`; alert `LargeExcelFiles` |
| `audience-targeting` | A list with audience targeting and three items: two target an audience and a group, one does not. Only the two must be reported. | `AudienceTargetedItemCount = 2`; `AudienceTargetedListCount = 1`; `AudienceTargetedExamples like "*LabAudience*"` and `like "*Lab Readers*"`; alert `AudienceTargeting` |
| `site-notebook` | The Site Notebook feature of a team site: the notebook that it creates in the Site Assets library must be reported. | `SiteNotebookCount >= 1`; `SiteNotebookExamples like "*Notebook*"`; alert `SiteNotebook` |
| `permissions` | A custom permission level. | `CustomPermissionLevelCount >= 1`; alert `CustomPermissionLevels` |
| `alerts` | Two SharePoint alerts ("Alert Me" subscriptions) of the owner of the site on a list. | `SharePointAlertCount >= 2`; alert `AlertSubscriptions` |
| `partial-simple` | Three SharePoint alerts, one more than the lab lets the inventory export (MaxAlertRowsPerSite): the assessment is partial and nothing else is flagged, so the site is Simple and waits in the Needs review wave, not in the quick wins. | `AssessmentStatus = "Partial"`; `SharePointAlertCount >= 3`; `Category = 1`; `Wave = 0`; `WaveName = "Needs review"`; alert `AssessmentPartial` |
| `publishing` | The SharePoint Server Publishing features, and a page when the publishing API allows it. | `PublishingInfrastructureEnabled = true`; `PublishingWebCount >= 1`; `PublishingPageCount >= 1` (info); alert `PublishingSite` |
| `template-blog` | A blog site: its template is mapped to Review. | `TemplateCompatibility = "Review"`; alert `TemplateCompatibilityReview` |
| `infopath` | An InfoPath form library: a blocker in the example configuration. | `InfoPathFormCount >= 1`; `Category = 4`; alert `InfoPath` |
| `event-receiver` | A list with an event receiver registered from the assembly Contoso.Lab.Receivers. SharePoint loads the assembly to register a receiver, so the scenario is skipped unless an assembly of that name is deployed on the farm. The receiver never fires: it is only registered. | `EventReceivers >= 1` |
| `custom-master` | A custom master page, set as the master page of the site. | `CustomMasterPage = true` |
| `customized-page` | The default page of the root web, edited. The inventory ignores edits of the System Account, which is the farm account: run the lab with another account for this one. | `CustomizedPageCount >= 1` (info); alert `CustomizedPages` (info) |
| `customized-profile-page` | A My Site host whose profile page, Person.aspx, is edited. The inventory ignores edits of the System Account, which is the farm account: run the lab with another account for this one. | `CustomizedProfilePageCount >= 1` (info); `CustomizedProfilePageExamples like "*Person.aspx*"` (info); alert `CustomizedProfilePage` (info) |
| `alternate-css` | An alternate CSS URL on the root web: a style sheet in a library, set as the alternate CSS of the site. | `AlternateCssUrlCount >= 1`; `AlternateCssUrlExamples like "*lab.css*"`; `ModernBlockerCount >= 1`; alert `AlternateCssUrl` |
| `xslt-view` | A list view that renders with a style sheet of its own (its XslLink). | `XsltListViewCount >= 1`; `XsltListViewExamples like "*LabXslView*"`; `ModernBlockerCount >= 1`; alert `XsltListViews` |
| `script-web-part` | A Script Editor web part and a Content Editor web part with a script, on the home page of the root web. | `ScriptWebPartCount >= 2`; `ScriptWebPartExamples like "*Script Editor*"` and `like "*Content Editor*"`; `ModernBlockerCount >= 1`; alert `ScriptWebParts` |
| `modern-opt-out` | The site collection and the root web opted out of the modern list and library experience, with the two features that do it. SharePoint 2016 does not have them: the scenario is skipped there. | `ClassicExperienceOptOutCount >= 2`; `ClassicExperienceOptOutExamples like "*(site collection)*"` and `like "*(web)*"`; `ModernBlockerCount >= 1`; alert `ModernExperienceOptOut` |
| `forced-classic` | A list whose "List experience" setting is the classic experience. SharePoint 2016 has no such setting: the scenario is skipped there. | `ClassicExperienceListCount >= 1`; `ClassicExperienceListExamples like "*LabClassic*"`; `ModernBlockerCount >= 1`; alert `ClassicExperienceLists` |
| `workflow-2010` | A SharePoint 2010 workflow association on a list, from an out-of-the-box template. | `Workflow2010Count >= 1`; alert `Workflow2010` |
| `email-enabled` | A list with an incoming e-mail address. Needs the incoming e-mail service of the farm. | `EmailEnabledListCount >= 1` (info); alert `EmailEnabledLists` (info) |
| `irm` | A list with Information Rights Management enabled. Needs IRM to be configured on the farm. | `IrmEnabledListCount >= 1` (info); alert `IrmEnabledLists` (info) |
| `html-files` | An .html file in a library. Only counted where the web application uses Permissive browser file handling. | `HtmlFileCount >= 1`; alert `HtmlFiles` |

Notes:

- The large-content thresholds are lowered in the lab settings (`LargeListItemCount` 200, `LargeListViewRowLimit` 100, `CheckedOutFileCount` 1, `FileVersionCount` 5, `LargeExcelFileSizeMB` 0.01) so that small fixtures trigger the signals. They are not lowered further, because the system lists of a new site (the Master Page Gallery, for example) have a hundred items. The cap of the alert rows that are exported per site collection (`MaxAlertRowsPerSite`) is lowered to 2: the `alerts` scenario stays under it, and `partial-simple` goes one alert over it, which is how a small fixture gets a partial assessment without an unreadable site.
- `audience-targeting` is skipped on a farm without the field type of the audience targeting column (SharePoint Foundation has none). The audience that it targets does not exist, so the inventory shows its ID, and a farm where the User Profile service is not reachable shows the same. `site-notebook` activates the Site Notebook feature, which may create the notebook only when somebody opens it, with the OneNote web application: when the feature is not installed, or when no notebook was created, the scenario is skipped and says so. A skipped scenario is not provisioned or verified again while its site collection exists, and removing the site collection removes the notebook: to test the notebook, open the Site Notebook link of `<web application>/sites/<prefix>-site-notebook`, run `-Action Inventory` again, and check in the report that the row of that site has a `SiteNotebookCount` of at least 1, a `SiteNotebookExamples` that names the notebook, and the `SiteNotebook` alert.
- `event-receiver` is skipped on a farm where no assembly named `Contoso.Lab.Receivers` is deployed: SharePoint loads the assembly when it registers a receiver, so a fake one cannot be registered. Only an assembly load failure is a skip; any other error from the registration is a failure. See "What stays manual".
- `EventReceivers` and `CustomMasterPage` are columns of the inventory, so the lab reads them there, not in the `Reasons` of the score. So are the signals of the modern experience, and their scenarios (`alternate-css`, `xslt-view`, `script-web-part`, `modern-opt-out` and `forced-classic`) are what check them on a real farm: the `baseline` site expects all of them at 0, which is how a default that SharePoint sets (the style sheet of a standard view, for example) would show up as a false report.
- `script-web-part` adds its web parts to the home page of the root web, which is a wiki page on SharePoint 2013 and later, with the web part manager; the scenario is skipped when the two web parts are not available on the SharePoint, and fails when they cannot be added. `modern-opt-out` is skipped only when the feature of the site collection or the one of the web is not installed: an error of the activation of an installed feature fails it. `modern-opt-out` and `forced-classic` need the modern list experience, which SharePoint Server 2019 and Subscription Edition have: on SharePoint Server 2016 they are skipped, and `ClassicExperienceOptOutCount` and `ClassicExperienceListCount` stay 0.
- While it creates the site collections, the script prints one line before each (`[3/25] Creating https://lab.contoso.local/sites/spslab-lock-readonly ...`) and one after it with the result and the seconds it took (`[3/25] Created in 41 s`, `Skipped in 3 s: <reason>` or `Failed in 3 s: <message>`). `Remove` prints the same for each site collection it removes. With `-WhatIf` they print nothing.
- Before the inventory starts, the script prints the settings file and the report folder that it uses, so that you can check that they are the lab ones and not those of another environment.
- `partial-simple` is the one scenario that is **expected to be partial and Simple**: the `Assessment` line of the report says `INFO` for it, like for `lock-noaccess`, and what must pass is the rest, above all `Wave = 0` and `WaveName = "Needs review"`. A Simple site collection with a partial assessment is not a quick win, because what could not be read counts as 0 in its score. `lock-noaccess` is partial as well, but it is a blocker, so it stays in the blocker wave.
- `lock-noaccess` is a site that cannot be read, so its **assessment stays partial** and the `Assessment` line of the report says `INFO` for it. What must pass is the lock itself: SharePoint refuses to read even its lock flags ("Access to this Web site has been blocked"), and the inventory has to recognize that error as the NoAccess lock and report the site as a blocker. The root web raises the same error, so the template and the language are not read: they stay empty (the record says `NotCollected`, not the template `#` and the language 0 that PowerShell makes of an exception), a warning says that the root web could not be read, and the site does not get the `TemplateCompatibilityReview` and `TemplateLanguageReview` alerts, which would say nothing about it. A check marked `No alert` passes when the alert is *not* raised.
- When the lab runs as the farm account, the edits of the farm account are those of the System Account, which the inventory ignores for customized pages: run it as another account to see `customized-page` pass.

## What stays manual

The lab does not build these, because they need services, packages or farm-level changes that a script should not make. Build them by hand when you want to test them:

- external lists and BCS applications (a Business Data Connectivity model and an external content type);
- profile property mappings (a User Profile service application with a synchronization connection): the report is read once for the farm, not per site collection, so check the `*-profilemappings-*` files after a run, as the farm account or an administrator of the User Profile service application, and compare them with the connections and the profile properties of Central Administration;
- Secure Store applications (a target application in the Secure Store service application, for example `New-SPSecureStoreTargetApplication`): the report is read once for the farm, not per site collection, so check the `*-securestore-*` files after a run, as the account of the inventory, and compare them with the Secure Store page of Central Administration;
- managed metadata columns (a term store and a term set);
- SharePoint 2013 workflows (Workflow Manager), and running workflow instances;
- SharePoint add-ins and app webs (an app catalog);
- Forms-based authentication zones, web application policies and the browser file handling of the web application (`html-files` needs a Permissive web application);
- farm solutions, full-trust code and sandbox solutions (a WSP);
- custom event receivers (`EventReceivers`): SharePoint loads the assembly to register a receiver, so deploy one (a WSP or the GAC) and register it on a list; the `event-receiver` scenario registers one from an assembly named `Contoso.Lab.Receivers` when it is deployed;
- a site large enough for `IsLargeSite` (the size is rounded to 0.01 GB, so a small fixture cannot reach it).

## Safety

- The web application is explicit, and every site collection of the lab has a name prefix and a marker (a property of its root web). `Remove` touches nothing that does not have both (the content database of the lab has its own conditions, below), and `-WhatIf` and `-Confirm` are supported: the script passes them to every step that can change something.
- The manifest in the work folder belongs to one web application and one prefix. `Remove` refuses a manifest that is not for the `-WebApplicationUrl` you gave (or for the `-Prefix`, when you gave one) and removes nothing, so a manifest left in a work folder cannot be used against another lab.
- Removing a site collection unlocks it first. A removed site collection stays in the deleted sites, which blocks its URL: the script purges, after a confirmation, only the deleted sites that it removed itself or that the manifest lists as already removed, so that the lab can be built again with the same URLs. A site that merely looks like a lab site is never purged.
- An existing site collection at a lab URL is never reused or changed: remove the lab first.
- The content database of the lab is removed only when the manifest says that the script created it, its name starts with the prefix, it belongs to the web application of the manifest, its site collections and its deleted site collections can be listed, and every one of them is a site collection of the manifest (a deleted one that is not of the lab would be lost for good, because `Remove-SPContentDatabase` deletes the database from SQL Server, and with it what it still holds that could be restored). Otherwise the lab site collections are removed one by one, and the database is left alone. A site collection of the manifest that is not in the database, because it existed before the database was created and was skipped, is removed one by one too, with its marker checked, whether or not the database is removed. A database that already exists with the lab name and belongs to the same web application is reused and, because the script did not create it, never removed.
- The inventory still scans the whole web application, not only the content database of the lab: the database makes the lab easy to remove and keeps it out of the other content databases, it does not narrow the scan.

## Add a scenario

A scenario is an entry of `Get-SPSLabScenario` in `tools/lab/SPSInventoryLab.psm1`: a name, a description, the site template, a script block that builds the content (it throws a message that starts with `SKIP:` when the farm lacks something) and the expectations. The tests check that every expected property is a field of the inventory record, that every expected alert is in the alert catalog, and that every scenario is in the table above, so the lab cannot drift from the toolkit.
