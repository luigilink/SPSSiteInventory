# Lab testing

The unit tests of SPSSiteInventory run against mocked SharePoint objects, so each new collector still has to be checked once on a real farm. The lab scripts do that for you: they build small test site collections on a **lab** farm, run the inventory and check the reports against what each test site must produce.

> **They write to the farm.** Unlike the toolkit, which is read-only, the lab scripts create and remove site collections. Use them on a lab farm only, and on a lab web application: the inventory scans the whole web application, not only the lab sites.

The scripts are in the `tools/lab` folder of the repository. They are not part of the release ZIP, which holds the read-only toolkit only: copy the folder to the farm server next to the extracted release you want to test.

## What you need

- A lab SharePoint Server farm (2016, 2019 or Subscription Edition) and a lab web application.
- The **SharePoint Management Shell**, elevated (Windows PowerShell 5.1), signed in as the farm account.
- The toolkit to test: the extracted release ZIP, or the `src` folder of the repository.

## Run it

```powershell
.\Invoke-SPSLabTest.ps1 -WebApplicationUrl https://lab.contoso.local -ToolkitPath C:\SPSSiteInventory
```

By default, the script runs these steps in order (`-Action` runs one of them):

1. **Provision**: writes the lab settings from the example configuration of the toolkit being tested (only the environment name, the web application, the report folder and the large-content thresholds change), then creates one site collection per scenario, `<web application>/sites/<prefix>-<scenario>`, and marks it as a lab site. A confirmation is asked before each one; `-Force` skips it and `-WhatIf` shows what would be created.
2. **Inventory**: runs `Invoke-SPSSiteInventory.ps1` of the toolkit with the lab settings.
3. **Verify**: checks the reports against the expectations of every scenario (see below) and prints the result. The exit code is 1 when a check fails.
4. **Remove**: removes the lab site collections. It runs only with `-Cleanup`, or on its own with `-Action Remove`.

| Parameter | Meaning |
| --- | --- |
| `-WebApplicationUrl` | The lab web application. There is no default: name it on purpose. |
| `-ToolkitPath` | The toolkit to test. Defaults to the `src` folder of the repository that holds the script. |
| `-Action` | `Provision`, `Inventory`, `Verify`, `Remove` or `All` (the default). |
| `-Scenario` | Builds and checks only these scenarios, for example `-Scenario subsites,infopath`. |
| `-WorkFolder` | Where the lab settings, the manifest (`lab-manifest.json`) and the reports go. Defaults to `.\SPSLab`. |
| `-Prefix` | The prefix of the site collection names (lowercase letters and digits). Defaults to `spslab`. |
| `-Owner` | The owner of the site collections. Defaults to the current account. |
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
| `SKIP` | The check could not run: the scenario was skipped because the farm lacks something it needs, or there is no alerts report. |

Every lab site also gets an `Assessment` line. A site whose assessment is `Partial` or `Failed` is how a problem with a real farm shows up (a property that cannot be read, for example), and its warnings are listed: those are the ones to send back. The reports are in the work folder; they hold lab data only.

## The scenarios

Each scenario is a site collection built to trigger known signals, and what the inventory must report for it. A scenario that cannot be built on the farm is skipped and does not stop the others. A check marked *(info)* is reported but never fails the run.

| Scenario | What it builds | What must be reported |
| --- | --- | --- |
| `baseline` | An empty team site: nothing must be flagged, and the assessment must be complete. | `AssessmentStatus = "Complete"`; `SubsiteCount = 0`; `MaxSubsiteDepth = 0`; `SubWebCount = 1`; `SiteLockState = "Unlock"`; `IsLockedSite = false`; `InfoPathFormCount = 0`; `Workflow2010Count = 0`; `SharePointAlertCount = 0`; `UsesFullTrustCode = false`; `Category = 1` |
| `subsites` | Five subsites, three levels deep: a, a/b, a/b/c, d and e. | `SubsiteCount = 5`; `MaxSubsiteDepth = 3`; `SubWebCount = 6`; `SubsiteExamples like "a/b/c (level 3)*"`; alert `Subsites` |
| `lock-readonly` | A ReadOnly lock: the site is reported as locked but not as a blocker. | `SiteLockState = "ReadOnly"`; `IsLockedSite = true`; `HasNoAccessLock = false`; alert `LockedSite` |
| `lock-noadditions` | A NoAdditions lock: the site is reported as locked but not as a blocker. | `SiteLockState = "NoAdditions"`; `IsLockedSite = true`; `HasNoAccessLock = false`; alert `LockedSite` |
| `lock-noaccess` | A NoAccess lock. The site cannot be read, so what the inventory does with it is informational: look at its assessment status. | `SiteLockState = "NoAccess"` (info); `IsLockedSite = true` (info); `HasNoAccessLock = true` (info); alert `NoAccessSite` (info) |
| `large-content` | A list above the large-list threshold with a view that has a high row limit, a document with several versions and a checked-out document. | `LargeListCount >= 1`; `LargeListViewCount >= 1`; `CheckedOutFileCount >= 1`; `FileVersionCount >= 1`; alert `LargeLists`; alert `LargeListViews`; alert `CheckedOutFiles`; alert `FileVersions` |
| `permissions` | A custom permission level. | `CustomPermissionLevelCount >= 1`; alert `CustomPermissionLevels` |
| `alerts` | Two SharePoint alerts ("Alert Me" subscriptions) of the owner of the site on a list. | `SharePointAlertCount >= 2`; alert `AlertSubscriptions` |
| `publishing` | The SharePoint Server Publishing features, and a page when the publishing API allows it. | `PublishingInfrastructureEnabled = true`; `PublishingWebCount >= 1`; `PublishingPageCount >= 1` (info); alert `PublishingSite` |
| `template-blog` | A blog site: its template is mapped to Review. | `TemplateCompatibility = "Review"`; alert `TemplateCompatibilityReview` |
| `infopath` | An InfoPath form library: a blocker in the example configuration. | `InfoPathFormCount >= 1`; `Category = 4`; alert `InfoPath` |
| `event-receiver` | A list with an event receiver registered from a custom assembly that does not exist. It never fires: it is only registered. The signal is scored but is not a column of the inventory, so the lab reads it in the score reasons. | `Reasons like "*EventReceivers=*"` |
| `custom-master` | A custom master page, set as the master page of the site. The signal is scored but is not a column of the inventory, so the lab reads it in the score reasons. | `Reasons like "*CustomMasterPage=1*"` |
| `customized-page` | The default page of the root web, edited. The inventory ignores edits of the System Account, which is the farm account: run the lab with another account for this one. | `CustomizedPageCount >= 1` (info); alert `CustomizedPages` (info) |
| `workflow-2010` | A SharePoint 2010 workflow association on a list, from an out-of-the-box template. | `Workflow2010Count >= 1`; alert `Workflow2010` |
| `email-enabled` | A list with an incoming e-mail address. Needs the incoming e-mail service of the farm. | `EmailEnabledListCount >= 1` (info); alert `EmailEnabledLists` (info) |
| `irm` | A list with Information Rights Management enabled. Needs IRM to be configured on the farm. | `IrmEnabledListCount >= 1` (info); alert `IrmEnabledLists` (info) |
| `html-files` | An .html file in a library. Only counted where the web application uses Permissive browser file handling. | `HtmlFileCount >= 1`; alert `HtmlFiles` |

Notes:

- The large-content thresholds are lowered in the lab settings (`LargeListItemCount` 200, `LargeListViewRowLimit` 100, `CheckedOutFileCount` 1, `FileVersionCount` 5) so that small fixtures trigger the signals. They are not lowered further, because the system lists of a new site (the Master Page Gallery, for example) have a hundred items.
- `EventReceivers` and `CustomMasterPage` are scored but are not columns of the inventory, so the lab reads them in the `Reasons` of the score.
- `lock-noaccess` is informational on purpose: a `NoAccess` lock makes the site unreadable, so what the inventory does with it is something to look at, not to assert.
- When the lab runs as the farm account, the edits of the farm account are those of the System Account, which the inventory ignores for customized pages: run it as another account to see `customized-page` pass.

## What stays manual

The lab does not build these, because they need services, packages or farm-level changes that a script should not make. Build them by hand when you want to test them:

- external lists and BCS applications (a Business Data Connectivity model and an external content type);
- managed metadata columns (a term store and a term set);
- SharePoint 2013 workflows (Workflow Manager), and running workflow instances;
- SharePoint add-ins and app webs (an app catalog);
- Forms-based authentication zones, web application policies and the browser file handling of the web application (`html-files` needs a Permissive web application);
- farm solutions, full-trust code and sandbox solutions (a WSP);
- a site large enough for `IsLargeSite` (the size is rounded to 0.01 GB, so a small fixture cannot reach it).

## Safety

- The web application is explicit, and every site collection of the lab has a name prefix and a marker (a property of its root web). `Remove` touches nothing that does not have both, and `-WhatIf` and `-Confirm` are supported.
- Removing a site collection unlocks it first, and the removed site collections are purged from the deleted sites, so that the lab can be built again with the same URLs.
- An existing site collection at a lab URL is never reused or changed: remove the lab first.

## Add a scenario

A scenario is an entry of `Get-SPSLabScenario` in `tools/lab/SPSInventoryLab.psm1`: a name, a description, the site template, a script block that builds the content (it throws a message that starts with `SKIP:` when the farm lacks something) and the expectations. The tests check that every expected property is a field of the inventory record, that every expected alert is in the alert catalog, and that every scenario is in the table above, so the lab cannot drift from the toolkit.
