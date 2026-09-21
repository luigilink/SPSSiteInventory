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

## Scoring section

The `Scoring` hashtable drives `Measure-SPSSiteComplexity`.

```powershell
Scoring = @{
    Weights = @{
        WorkflowAssociationCount = 2.0
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
    )
}
```

### Weights

Each key is a **signal** collected by `Get-SPSSiteCustomization`. The weight is multiplied
by the signal value (booleans count as 1 when true) and summed into the site's score. Set a
weight to `0` (or omit the key) to ignore a signal.

### Thresholds

- `Moderate` — a score at or above this value promotes the site from **Simple (1)** to **Moderate (2)**.
- `Complex` — a score at or above this value promotes the site to **Complex (3)**.

### BlockingSignals

A list of signal names. If **any** of them is truthy for a site, the site is forced to
**Blocking (4)**, regardless of the score. Use this for signals that make a site
non-portable as-is (for example a feature coming from a custom full-trust solution).

## Tuning

Start from the example weights and run the inventory once. Review the distribution of
categories, then adjust the weights and thresholds so the categories match your migration
reality. Because scoring is a pure function, you can re-score an exported JSON without
re-scanning the farm.
