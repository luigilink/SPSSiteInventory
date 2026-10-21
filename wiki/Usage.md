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
| `*-workflows-*.json` | Workflow-focused dataset (`Workflow2010Count`, `Workflow2013Count`, status, category). |
| `*-irm-locks-*.json` | Security/lock dataset (`IrmEnabledListCount`, `SiteLockState`, `IsLockedSite`). |
| `*-large-content-*.json` | Large-content risk dataset (`IsLargeSite`, large lists/views, checked-out files, high file-version counts, plus examples). |
| `*-alerts-*.json` | Normalized risk alerts extracted from site signals (partial/failed, FBA, full-trust, workflows, InfoPath, IRM, lock, large content). |
| `*-solutions-*.csv` | Farm-solution (WSP) inventory for Excel; one row per solution, with the feature scopes/ids flattened. |
| `*-solutions-*.json` | Farm-solution (WSP) inventory for automation, with the feature scopes/ids kept as arrays. |
| `*-contenttypes-*.csv` / `*-contenttypes-*.json` | Content-type definitions and list bindings, including standard types. One row per web definition or list binding, not per item. |

The HTML report also includes configured authentication by web application/zone and
a content-type detail section. Authentication errors stop the scan rather than
silently producing Windows-only results. Unrecognized/federated providers are flagged
for identity review; a missing provider identity leaves `HasFbaZone` unknown unless
FBA was positively detected in another provider or zone.

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
| `SizeGB` | Storage used, in GB |
| `SubWebCount` | Number of sub-webs |
| `LastModified` | Last item modified date (dormancy signal) |
| `InventoryScope` | `SiteCollection` for site rows or `WebApplication` for enumeration failure rows |
| `SiteInventoryComplete` / `SiteInventoryWarnings` | Whether identity, size and root-web metadata were collected; warning text describes missing data |
| `CustomizationInventoryComplete` | False means one or more customization signals may be missing |
| `Workflow2010Count` | Active SharePoint 2010 workflow associations (legacy engine, retired in SPO); historical "previous version" associations are excluded when detectable |
| `Workflow2013Count` | SharePoint 2013 workflow subscriptions (Workflow Manager) |
| `InfoPathFormCount` | InfoPath-driven lists/libraries (retired, no SPO equivalent) |
| `IrmEnabledListCount` | Number of lists/libraries with IRM enabled |
| `IsLargeSite` | Site is above the configured large-site threshold |
| `LargeListCount` / `LargeListExamples` | Number of large lists and up to five list examples with item counts |
| `LargeListViewCount` / `LargeListViewExamples` | Number of large-list views and up to five list/view examples with row limits |
| `CheckedOutFileCount` / `CheckedOutFileExamples` | Number of checked-out files and up to five impacted libraries |
| `FileVersionCount` / `FileVersionExamples` | Number of files above the configured file-version threshold and up to five examples |
| `SiteLockState` / `IsLockedSite` | Site collection lock state (`Unlock`, `ReadOnly`, `NoAdditions`, `NoAccess`, `Unknown`) and whether that state is blocking |
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
