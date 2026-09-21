# Configuration

SPSSiteInventory reads a PowerShell data file (`.psd1`). Copy
`config/inventory-settings.example.psd1` to `config/inventory-settings.psd1` (gitignored)
and adjust it. No client-specific value ships in the repository.

## Top-level settings

| Setting | Type | Description |
| --- | --- | --- |
| `EnvName` | string | Free-form environment identifier (e.g. `PROD`), used in output file names and the banner. |
| `WebApplicationUrl` | string[] | Web application URLs to scan. Leave empty to scan every content web application. |
| `CustomSolutionPrefix` | string[] | Case-insensitive name prefixes marking a farm solution (WSP) as custom/in-house. Sites activating a feature from a matching solution are flagged. |
| `OutputFolder` | string | Folder where the CSV/JSON reports are written. |
| `LogRetentionDays` | int | Days of run logs kept under the `Logs` folder. |
| `Scoring` | hashtable | The scoring engine configuration (see below). **Mandatory.** |
| `MigrationWaves` | hashtable[] | The category-to-wave mapping (see below). Optional; a one-wave-per-category default applies when omitted. |

## Scoring section

The `Scoring` hashtable drives `Measure-SPSSiteComplexity`.

```powershell
Scoring = @{
    Weights = @{
        Workflow2010Count        = 3.0
        Workflow2013Count        = 1.5
        InfoPathFormCount        = 3.0
        SandboxSolutions         = 3.0
        CustomMasterPage         = 2.0
        EventReceivers           = 1.5
        UniquePermissionsCount   = 0.01
        SizeGB                   = 0.02
    }
    Thresholds = @{
        Moderate = 1.0
        Complex  = 6.0
    }
    BlockingSignals = @(
        'UsesCustomFarmFeature'
        'UsesFullTrustCode'
        'InfoPathFormCount'
    )
}
```

### Weights

Each key is a **signal** collected by `Get-SPSSiteCustomization`. The weight is multiplied
by the signal value (booleans count as 1 when true) and summed into the site's score. Set a
weight to `0` (or omit the key) to ignore a signal.

Workflows are split by platform because their migration cost differs:

- `Workflow2010Count` — SharePoint 2010 workflows (legacy engine, **retired in SharePoint
  Online**). They always need a rebuild, so they are weighted heavily. Add
  `Workflow2010Count` to `BlockingSignals` if you want any legacy workflow to force
  **Blocking (4)**.
- `Workflow2013Count` — SharePoint 2013 workflows (Workflow Manager). A lighter, more
  direct remediation, so they are weighted less than their 2010 counterparts.

`InfoPathFormCount` counts the InfoPath-driven lists and libraries on the site. InfoPath
Forms Services is **retired and unavailable in SharePoint Online**, so it is weighted
heavily and listed in `BlockingSignals` in the example configuration.

`EventReceivers` counts only **custom** event receivers (those registered from a
non-Microsoft assembly). Out-of-the-box receivers on native lists are ignored, so a stock
site is not promoted just because SharePoint's own lists carry many built-in receivers.

### Thresholds

- `Moderate` — a score at or above this value promotes the site from **Simple (1)** to **Moderate (2)**.
- `Complex` — a score at or above this value promotes the site to **Complex (3)**.

### BlockingSignals

A list of signal names. If **any** of them is truthy for a site, the site is forced to
**Blocking (4)**, regardless of the score. Use this for signals that make a site
non-portable as-is:

- `UsesCustomFarmFeature` — the site activates a feature from a custom farm solution.
- `UsesFullTrustCode` — the site activates a feature from a custom **full-trust** solution
  (a WSP deploying a global assembly to the GAC), correlated through the farm-solution map.
- `InfoPathFormCount` — the site uses InfoPath forms.

## MigrationWaves section

`MigrationWaves` maps complexity categories to ordered migration waves, consumed by
`Group-SPSMigrationWave`. In a SharePoint Server to SharePoint Online migration the
migrated unit is the **site collection**, so waves are planned per site by complexity —
content databases are an on-premises storage concern with no SharePoint Online equivalent
and are not used here.

```powershell
MigrationWaves = @(
    @{ Wave = 1; Name = 'Quick wins'; Categories = @(1) }
    @{ Wave = 2; Name = 'Light remediation'; Categories = @(2) }
    @{ Wave = 3; Name = 'Rebuild'; Categories = @(3) }
    @{ Wave = 4; Name = 'Projects / blockers'; Categories = @(4) }
)
```

Each entry lists the categories it groups. The default above is **one wave per category**.
To put every non-blocking site in the first wave instead:

```powershell
MigrationWaves = @(
    @{ Wave = 1; Name = 'Migrate now'; Categories = @(1, 2, 3) }
    @{ Wave = 2; Name = 'Projects';    Categories = @(4) }
)
```

A site whose category is not listed in any wave lands in an **Unassigned** bucket (wave 0),
surfaced in the report rather than silently dropped. When `MigrationWaves` is omitted from
the settings, the one-wave-per-category default is applied.

## Tuning

Start from the example weights and run the inventory once. Review the distribution of
categories, then adjust the weights and thresholds so the categories match your migration
reality. Because scoring is a pure function, you can re-score an exported JSON without
re-scanning the farm.
