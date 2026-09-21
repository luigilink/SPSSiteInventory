# SPSSiteInventory Wiki

**SPSSiteInventory** inventories on-premises **SharePoint Server** site collections and **categorizes them by migration complexity** to prepare a move to **SharePoint Online**. It is read-only and produces a scriptable CSV/JSON inventory that feeds a migration wave plan.

## When to use SPSSiteInventory

Use this toolkit when:

- You are **planning a migration** from SharePoint Server (2016/2019/SE) to SharePoint Online and need a defensible **site-by-site complexity picture**.
- You want to know which sites are **quick wins** (lift & shift) and which carry **custom code** (full-trust solutions, workflows, event receivers) that requires a project.
- You need an inventory that is **reproducible, versionable and diff-friendly**, not a one-off GUI export.

It complements Microsoft's **SPMT scan** (content + migration risks): SPSSiteInventory adds the **business-complexity categorization** and the **WSP↔site correlation** that the built-in tooling does not provide.

## How it works

```text
Import-SPSSharePointCommand
        |
        v
Get-SPSFarmSolutionMap        -> which WSP deploys which feature (custom-code map)
        |
        v
Get-SPSSiteInventory          -> identity + volumetry per site collection
        |
        v
Get-SPSSiteCustomization      -> customization signals per site
        |
        v
Measure-SPSSiteComplexity     -> score + category (1 Simple .. 4 Blocking)
        |
        v
Export-SPSInventoryReport     -> CSV + JSON
```

## Categories

| Category | Meaning | Typical migration strategy |
| --- | --- | --- |
| 1 — Simple | Standard collaboration, no workflows, no custom code | Lift & shift |
| 2 — Moderate | Light workflows / InfoPath, some unique permissions | Migrate + light remediation |
| 3 — Complex | Sandbox solutions, custom branding, many customizations | Partial rebuild (SPFx / Power Platform) |
| 4 — Blocking | Full-trust custom code, custom auth, legacy integrations | Dedicated project / arbitration |

## Next steps

- [Getting Started](Getting-Started)
- [Configuration](Configuration)
- [Usage](Usage)
