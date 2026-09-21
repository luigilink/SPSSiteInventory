# SPSSiteInventory - Release Notes

## [Unreleased]

First scaffold of **SPSSiteInventory**, a read-only PowerShell toolkit that inventories on-premises SharePoint Server site collections and categorizes them by migration complexity to prepare a move to SharePoint Online.

### Highlights

- Configurable scoring engine (`Measure-SPSSiteComplexity`) turning customization signals into a 1–4 category (Simple, Moderate, Complex, Blocking).
- Collectors for site volumetry, per-site customization signals, and farm-solution (WSP) correlation.
- CSV and JSON export for review and downstream migration-wave planning.
- Windows PowerShell 5.1, read-only, runs on a farm server as the farm account.

### Notes

- This is a pre-1.0 scaffold. Collector coverage (workflow 2010/2013 split, InfoPath detection) and a self-contained HTML report are planned for the next iterations.
