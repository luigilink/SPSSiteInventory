# Change log for SPSSiteInventory

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
