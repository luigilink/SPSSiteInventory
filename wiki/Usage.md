# Usage

## Running a scan

```powershell
.\Invoke-SPSSiteInventory.ps1 -ConfigPath .\config\inventory-settings.psd1
```

The orchestrator:

1. starts a transcript and prints a banner;
2. loads the SharePoint commands and your settings;
3. builds the farm-solution map (custom-code detection);
4. enumerates site collections;
5. collects customization signals and scores each site;
6. exports CSV, JSON and a self-contained HTML report to the configured output folder.

## Output files

Each run writes the site inventory in three timestamped formats, plus a dedicated
farm-solution report, to the output folder:

| File | Purpose |
| --- | --- |
| `*.csv` | Site inventory for review in Excel; one row per site collection. |
| `*.json` | Site inventory for downstream automation (for example feeding migration wave planning). |
| `*.html` | A shareable, self-contained site report: category summary box and a sortable / filterable site table. Opens in any browser with no external resource. |
| `*-solutions-*.csv` | Farm-solution (WSP) inventory for Excel; one row per solution, with the feature scopes/ids flattened. |
| `*-solutions-*.json` | Farm-solution (WSP) inventory for automation, with the feature scopes/ids kept as arrays. |

## Output fields

Each row in the CSV/JSON describes one site collection:

| Field | Description |
| --- | --- |
| `Url` | Site collection URL |
| `Title` | Root web title |
| `WebApp` | Web application name |
| `ContentDb` | Content database name |
| `Template` | Root web template (e.g. `STS#3`, `SITEPAGEPUBLISHING#0`) |
| `SizeGB` | Storage used, in GB |
| `SubWebCount` | Number of sub-webs |
| `LastModified` | Last item modified date (dormancy signal) |
| `Workflow2010Count` | SharePoint 2010 workflow associations (legacy engine, retired in SPO) |
| `Workflow2013Count` | SharePoint 2013 workflow subscriptions (Workflow Manager) |
| `InfoPathFormCount` | InfoPath-driven lists/libraries (retired, no SPO equivalent) |
| `UsesFullTrustCode` | Site activates a feature from a custom full-trust WSP (GAC assembly) |
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
| `IsCustom` | Name matches a `CustomSolutionPrefix` |
| `ContainsGlobalAssembly` | Deploys an assembly to the GAC (full-trust code) |
| `ContainsCasPolicy` | Ships a Code Access Security policy |
| `ContainsWebApplicationResource` | Deploys web-application-scoped resources |
| `IsFullTrustCode` | Custom **and** deploys a global assembly (SPO blocker) |
| `DeployedWebApplicationCount` / `DeployedServerCount` | Deployment reach |
| `FeatureCount` / `FeatureScopes` / `FeatureIds` | Features the solution registers |

## Reading the results

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
