# Usage

## Running a scan

```powershell
.\Invoke-SPSSiteInventory.ps1 -ConfigPath .\config\inventory-settings.psd1
```

The orchestrator:

1. starts a transcript and prints a banner;
2. loads the SharePoint commands and your settings;
3. builds the farm-solution map (custom-code detection);
4. reads configured authentication across all zones, then enumerates site collections;
5. collects customization signals, content-type definitions and list bindings, and scores each site;
6. exports CSV, JSON and a self-contained HTML report to the configured output folder.

Progress is reported for both site-collection enumeration and per-site assessment.
Collection read failures are recorded as partial or failed assessments and do not
prevent later site collections from being processed. A web application whose site
list cannot be read, or whose lazy enumeration stops early, is represented by a
`WebApplication`-scope failure row; earlier site records are retained. Partial scores
are provisional; failed site assessments have no category or score and are placed in
the `Not assessed` wave. Review collector warning details, transcript progress and
the report's status fields before planning migration waves.

## Output files

Each run writes the site inventory in three timestamped formats, a modular JSON
report pack, plus a dedicated farm-solution report, to the output folder:

| File | Purpose |
| --- | --- |
| `*.csv` | Site inventory for review in Excel; one row per site collection. |
| `*.json` | Site inventory for downstream automation (for example feeding migration wave planning). |
| `*.html` | A shareable, self-contained dashboard report with summary/risk cards, migration wave plan, authentication and a sortable/filterable site table. |
| `*-manifest-*.json` | Report-pack manifest with generation metadata, top-level counters and file references. |
| `*-sites-*.json` | Site inventory dataset used by the dashboard/report-pack consumers. |
| `*-auth-*.json` | Authentication-by-web-application dataset (zone/provider summary + collection counts). |
| `*-workflows-*.json` | Workflow/template-focused dataset (`Workflow2010Count`, `Workflow2013Count`, running-instance counts, template-compatibility and template-language review fields, status, category). |
| `*-apps-*.json` | App-focused dataset (`AppInstanceCount`, `AppWebCount`, `AppInstanceExamples`, status, category). |
| `*-permissions-*.json` | Permissions and policy dataset (`CustomPermissionLevelCount`/`Examples`, `EmailEnabledListCount`/`Examples`, `HtmlFileCount`/`Examples`, plus the web application values `BrowserFileHandling`, `WebAppPolicyCount`/`Examples` repeated per site collection, status, category). Web application failure rows (`InventoryScope` = `WebApplication`) are included so the policy values read for an application whose site collections could not be enumerated are kept. |
| `*-publishing-*.json` | Publishing and customized-page dataset (`PublishingInfrastructureEnabled`, `PublishingWebCount`, `PublishingPageCount`, `PublishingPageLayoutCount`/`PublishingPageLayoutExamples`, `CustomizedPageCount`/`CustomizedPageExamples`, status, category). |
| `*-irm-locks-*.json` | Security/lock dataset (`IrmEnabledListCount`, `SiteLockState`, `IsLockedSite`, `HasNoAccessLock`). |
| `*-large-content-*.json` | Large-content risk dataset (`IsLargeSite`, large lists/views, checked-out files, high file-version counts, plus examples). |
| `*-alerts-*.csv` / `*-alerts-*.json` | Normalized risk alerts extracted from the site signals, each with its severity, an explanation and a remediation hint (and the Microsoft Learn page behind it). One alert per site collection and signal; web application and BCS alerts are written once per web application and per LOB system. The CSV is for Excel, the JSON for automation. The alert types and their advice are listed in [Alerts and remediation](Alerts). |
| `*-solutions-*.csv` | Farm-solution (WSP) inventory for Excel; one row per solution, with the feature scopes/ids flattened. |
| `*-solutions-*.json` | Farm-solution (WSP) inventory for automation, with the feature scopes/ids kept as arrays. |
| `*-contenttypes-*.csv` / `*-contenttypes-*.json` | Content-type definitions and list bindings, including standard types. One row per web definition or list binding, not per item. |
| `*-managedmetadata-*.csv` / `*-managedmetadata-*.json` | Managed metadata columns by list, following the SMAT Managed Metadata Columns report. One row per list or library with at least one visible managed metadata column. |
| `*-externallists-*.csv` / `*-externallists-*.json` | External lists by list, following the SMAT External List report. One row per list backed by a Business Connectivity Services (BCS) external content type, with its BCS binding. |
| `*-bcs-*.csv` / `*-bcs-*.json` | BCS LOB systems of the farm, following the SMAT BCS report. One row per LOB system, with its type, instances and entities. |
| `*-sharepointalerts-*.csv` / `*-sharepointalerts-*.json` | SharePoint alerts ("Alert Me" subscriptions) by alert, following the SMAT Alerts report. One row per alert, with where it applies, what triggers it, how often it is sent and who owns it. Not the risk alerts of `*-alerts-*`. They contain the login names of the owners, unless `SharePointAlerts.IncludeUserLogin` is `$false`, so they are not part of the HTML report. |

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
detail section, a managed metadata section, an external list section and a BCS application
section. Authentication errors stop the scan rather than silently
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
| `TemplateCompatibility` / `TemplateCompatibilityReason` | Baseline SPO template mapping result: `Compatible`, `Unsupported`, or `Review`, with the rule that triggered it |
| `IsUnsupportedSiteTemplate` | Template is explicitly mapped as unsupported for direct SPO migration |
| `TemplateLanguageLcid` / `TemplateLanguageTag` / `TemplateLanguageName` | Root-web language metadata used for template-language parity checks |
| `TemplateLanguageReviewRequired` / `TemplateLanguageReason` | Language metadata is missing/unrecognized or outside configured allow-list and needs review |
| `SizeGB` | Storage used, in GB |
| `SubWebCount` | Number of sub-webs |
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
| `ManagedMetadataListCount` / `ManagedMetadataColumnCount` | Lists with at least one visible managed metadata column, and those columns counted once per list. Enterprise Keywords is included; hidden columns are not |
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
| `SiteLockState` / `IsLockedSite` / `HasNoAccessLock` | Site collection lock state (`Unlock`, `ReadOnly`, `NoAdditions`, `NoAccess`, `Unknown`), whether the site has any lock, and whether the lock is `NoAccess`, the only one that makes the site unreadable (and blocking in the example configuration) |
| `UsesFullTrustCode` | Site activates a feature from a custom full-trust WSP (GAC assembly) |
| `ContentTypeCount` | Distinct content-type IDs seen in web definition collections, deduplicated within this site collection |
| `ListContentTypeBindingCount` | Number of content-type bindings across the collection's lists, not the number of distinct designs |
| `ContentTypeInventoryComplete` | False means partial collection: review warnings before interpreting counts or missing definitions |
| `AssessmentStatus` | `Complete`, `Partial` (score may omit unreadable inputs), or `Failed` (not scored) |
| `AssessmentWarnings` | Collection/assessment failures associated with this record; also shown in the HTML report |
| `Category` | Complexity category 1–4 |
| `CategoryName` | Simple / Moderate / Complex / Blocking |
| `Wave` | Proposed migration wave number (from the category-to-wave mapping) |
| `WaveName` | Proposed migration wave name |
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

## Reading the results

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
