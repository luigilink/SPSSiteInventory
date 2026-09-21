# SPSSiteInventory - Release Notes

## [1.0.0] - 2026-09-21

First stable release of **SPSSiteInventory**, a read-only PowerShell toolkit that inventories on-premises SharePoint Server site collections and categorizes them by migration complexity (1 Simple to 4 Blocking) to prepare a move to SharePoint Online. It complements the SPMT scan and fills the gap left by SMAT (end of support on 1 October 2026): a business-complexity categorization correlated with the farm's custom code.

Compatible with SharePoint Server 2016, 2019 and Subscription Edition. Read-only: it never changes the farm. Run it on a farm server, as the farm account, in an elevated Windows PowerShell 5.1 session.

### Highlights

- Configurable scoring engine (`Measure-SPSSiteComplexity`) turning customization signals into a 1–4 category (Simple, Moderate, Complex, Blocking).
- Customization signals per site: **2010 vs 2013 workflows** (the retired legacy engine weighted apart from Workflow Manager), **InfoPath** forms, sandbox solutions, custom master pages, event receivers and unique permissions.
- Deep **farm-solution (WSP) analysis**: full-trust code (`ContainsGlobalAssembly`), CAS policy, deployment reach and features per solution, exported as its own CSV/JSON. A `UsesFullTrustCode` per-site signal flags sites bound to custom full-trust code (a SharePoint Online blocker).
- **Migration wave** proposal: each site is assigned to a wave from a configurable category-to-wave mapping.
- Outputs: a **CSV** (Excel), a **JSON** (automation) and a **self-contained HTML report** (category summary, migration wave plan, sortable/filterable table) for sharing with stakeholders.
- 100% generic: no client-specific value ships in the repository; environment specifics live in a gitignored settings file.

### Notes

- Requires Windows PowerShell 5.1 (the SharePoint Server object model); do not use PowerShell 7.
- See the [wiki](https://github.com/luigilink/SPSSiteInventory/wiki) for setup, configuration and usage.
