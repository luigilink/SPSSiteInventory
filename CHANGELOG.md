# Change log for SPSSiteInventory

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial scaffold of the **SPSSiteInventory** toolkit (read-only SharePoint Server site inventory and migration-complexity categorization).
- `SPSSiteInventory.Common` module with the V1 building blocks:
  - `Measure-SPSSiteComplexity` — configurable scoring engine mapping customization signals to a category from 1 (Simple) to 4 (Blocking).
  - `Get-SPSInventorySetting` — loads and validates the `.psd1` settings file.
  - `Get-SPSSiteInventory` — enumerates site collections with identity and volumetry.
  - `Get-SPSSiteCustomization` — collects per-site customization signals.
  - `Get-SPSFarmSolutionMap` — correlates farm solutions (WSP) with the features they deploy.
  - `Export-SPSInventoryReport` — writes the scored inventory to CSV and JSON.
  - `Import-SPSSharePointCommand`, `Get-SPSInstalledProductVersion`, `Initialize-SPSScript`, `Add-SPSInventoryEvent` — session and logging helpers.
- `Invoke-SPSSiteInventory.ps1` orchestrator and `Test-SPSSiteInventoryReadiness.ps1` prerequisite check.
- `inventory-settings.example.psd1` neutral configuration example (scoring weights, thresholds, blocking signals, custom-solution prefixes).
- Pester tests for the pure scoring and settings functions, PSScriptAnalyzer settings, and CI workflows (Pester, Release, Wiki).
