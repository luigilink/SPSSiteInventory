# SPSSiteInventory - Release Notes

## [1.1.0] - 2026-09-21

This release surfaces and sharpens the farm-solution (WSP) analysis - the main
differentiator versus SMAT/SPMT - and removes almost all per-client configuration.
It is backward compatible with 1.0.0 (existing settings keep working).

### Highlights

- **Farm solutions (WSP) in the HTML report**: the shareable, self-contained report now has a
  dedicated section - a summary box (total solutions, custom, full-trust code, web-app
  resource), a per-solution table (Deployed, Custom, full-trust, CAS policy, web-app
  resource, features, scopes) and a "sites bound to full-trust code" table linking the
  farm-level finding to the affected sites. The WSP analysis is no longer buried in the
  CSV/JSON only.
- **Zero-config custom detection**: custom farm solutions are now auto-detected (custom
  unless the name matches a known Microsoft / out-of-the-box marker), so `CustomSolutionPrefix`
  is optional. New `AutoDetectCustomSolutions` / `KnownMicrosoftSolutionPrefix` settings let
  you tune or disable it.
- **More accurate scoring**: the `EventReceivers` signal now counts only custom event
  receivers (non-Microsoft assemblies), so stock sites are no longer wrongly promoted to a
  higher complexity category.
- **Better WSP reporting**: `FeatureCount` is now reported for solutions that are added but
  not yet deployed.

### Notes

- Requires Windows PowerShell 5.1 (the SharePoint Server object model); do not use PowerShell 7.
- Read-only; 100% generic (no client-specific value ships in the repository).
- See the [wiki](https://github.com/luigilink/SPSSiteInventory/wiki) for setup, configuration and usage.
