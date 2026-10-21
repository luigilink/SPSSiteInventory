# Configuration

SPSSiteInventory reads a PowerShell data file (`.psd1`). Copy
`config/inventory-settings.example.psd1` to `config/inventory-settings.psd1` (gitignored)
and adjust it. No client-specific value ships in the repository.

## Top-level settings

| Setting | Type | Description |
| --- | --- | --- |
| `EnvName` | string | Free-form environment identifier (e.g. `PROD`), used in output file names and the banner. |
| `WebApplicationUrl` | string[] | Web application URLs to scan. Leave empty to scan every content web application. |
| `CustomSolutionPrefix` | string[] | **Optional override.** Case-insensitive name prefixes that force a farm solution (WSP) to be treated as custom. Custom solutions are auto-detected by default (see below), so this is usually left empty. |
| `AutoDetectCustomSolutions` | bool | Optional (default `$true`). When true, a solution is custom unless its name matches a known Microsoft / out-of-the-box marker. Set `$false` to rely only on `CustomSolutionPrefix`. |
| `KnownMicrosoftSolutionPrefix` | string[] | Optional extra name prefixes to treat as Microsoft / out-of-the-box during auto-detection (e.g. a known vendor package). |
| `OutputFolder` | string | Folder where the CSV/JSON reports are written. |
| `LogRetentionDays` | int | Days of run logs kept under the `Logs` folder. |
| `LargeContentThresholds` | hashtable | Thresholds for large-content parity signals (large site/list/view, checked-out files, file versions). Optional; defaults apply when omitted. |
| `TemplateParity` | hashtable | Template compatibility and language rules (supported/unsupported/review mapping, optional language allow-list). Optional; built-in defaults apply when omitted. |
| `Scoring` | hashtable | The scoring engine configuration (see below). **Mandatory.** |
| `MigrationWaves` | hashtable[] | The category-to-wave mapping (see below). Optional; a one-wave-per-category default applies when omitted. |

## Custom solution detection

Custom farm solutions (WSP) are **auto-detected**, so you normally do not configure anything
here. On a farm the solution store only holds solutions that were explicitly added, so the
safe default is "custom unless proven Microsoft": a solution is treated as custom unless its
name matches a known Microsoft / out-of-the-box marker (`microsoft.`, language packs, ...).

- To force a solution custom when auto-detection misses it, add a prefix to
  `CustomSolutionPrefix`.
- To treat a known third-party package as out-of-the-box, add its prefix to
  `KnownMicrosoftSolutionPrefix`.
- To disable auto-detection entirely and rely only on `CustomSolutionPrefix`, set
  `AutoDetectCustomSolutions = $false`.

`IsCustom` feeds `UsesCustomFarmFeature`, and combined with a global assembly it drives
`IsFullTrustCode` / `UsesFullTrustCode` — so getting it right without manual prefixes is the
point of auto-detection.

## Scoring section

The `Scoring` hashtable drives `Measure-SPSSiteComplexity`.

```powershell
Scoring = @{
    Weights = @{
        Workflow2010Count        = 3.0
        Workflow2013Count        = 1.5
        Workflow2010RunningInstanceCount = 1.0
        Workflow2013RunningInstanceCount = 0.5
        IsUnsupportedSiteTemplate = 5.0
        TemplateLanguageReviewRequired = 0.5
        InfoPathFormCount        = 3.0
        IrmEnabledListCount      = 2.5
        IsLargeSite              = 1.5
        LargeListCount           = 0.5
        LargeListViewCount       = 0.5
        CheckedOutFileCount      = 0.05
        FileVersionCount         = 0.02
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
        'IsLockedSite'
        'IrmEnabledListCount'
        'HasFbaZone'
        'IsUnsupportedSiteTemplate'
    )
}
```

### Weights

Each key is a **signal** collected by `Get-SPSSiteCustomization`. The weight is multiplied
by the signal value (booleans count as 1 when true) and summed into the site's score. Set a
weight to `0` (or omit the key) to ignore a signal.

Workflows are split by platform because their migration cost differs:

- `Workflow2010Count` — active SharePoint 2010 workflows (legacy engine,
  **retired in SharePoint Online**). Historical "previous version" associations
  are excluded when detectable so the score tracks active workflows. They always
  need a rebuild, so they are weighted heavily. Add
  `Workflow2010Count` to `BlockingSignals` if you want any legacy workflow to force
  **Blocking (4)**.
- `Workflow2010RunningInstanceCount` — active runtime instances on the 2010
  platform where per-association counters are available.
- `Workflow2013Count` — SharePoint 2013 workflows (Workflow Manager). A lighter, more
  direct remediation, so they are weighted less than their 2010 counterparts.
- `Workflow2013RunningInstanceCount` — active runtime instances on the 2013
  platform when Workflow Manager instance APIs are available.
- `IsUnsupportedSiteTemplate` — root-web template is explicitly mapped as
  unsupported for direct SharePoint Online migration.
- `TemplateLanguageReviewRequired` — root-web language metadata needs review
  (missing, unrecognized LCID, or outside the optional allow-list).

`InfoPathFormCount` counts the InfoPath-driven lists and libraries on the site. InfoPath
Forms Services is **retired and unavailable in SharePoint Online**, so it is weighted
heavily and listed in `BlockingSignals` in the example configuration.

`IrmEnabledListCount` counts lists/libraries where IRM is enabled. IRM typically requires
records-protection and compliance remediation during migration, so the example
configuration keeps it as both weighted and blocking.

Large-content parity signals are threshold-driven:

- `IsLargeSite` — site storage is at or above `LargeContentThresholds.LargeSiteSizeGB`.
- `LargeListCount` — lists at or above `LargeContentThresholds.LargeListItemCount`.
- `LargeListViewCount` — views whose row limit is at or above
  `LargeContentThresholds.LargeListViewRowLimit` on large lists.
- `CheckedOutFileCount` — checked-out files detected in document libraries.
- `FileVersionCount` — files whose version count is at or above
  `LargeContentThresholds.FileVersionCount`.

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
- `IsLockedSite` — the site collection lock state is not `Unlock` (for example
  `ReadOnly`, `NoAdditions`, `NoAccess`).
- `IrmEnabledListCount` — at least one list/library has IRM enabled.
- `HasFbaZone` — at least one zone of the site's web application is configured for
  forms-based authentication. This requires an identity/authentication redesign for
  SharePoint Online, not an on-premises farm repair. The signal does not prove that
  FBA is actively used by the site or its users.
- `IsUnsupportedSiteTemplate` — template compatibility mapping identified the
  root-web template as unsupported for direct migration.

Existing settings files are not rewritten. Add `HasFbaZone`, `IsLockedSite`,
`IrmEnabledListCount` and `IsUnsupportedSiteTemplate` to your existing
`Scoring.BlockingSignals` to apply these blocker overrides.

## TemplateParity section

```powershell
TemplateParity = @{
    UnsupportedTemplates = @(
        'APP#0'
        'SPSMSITEHOST#0'
    )
    SupportedTemplatePrefixes = @(
        'STS#'
        'COMMUNITY#'
        'PROJECTSITE#'
        'SITEPAGEPUBLISHING#'
        'CMSPUBLISHING#'
        'BLANKINTERNET#'
        'SRCHCEN#'
        'WIKI#'
        'ENTERWIKI#'
        'BDR#'
        'OFFILE#'
        'GROUP#'
        'SPSPERS#'
        'SPSNEWS#'
        'SPSNHOME#'
    )
    ReviewTemplatePrefixes = @('BLOG#')
    SupportedLanguageLcid = @()
}
```

Detection order is explicit and deterministic:

1. Exact template key in `UnsupportedTemplates` => `TemplateCompatibility = Unsupported`.
2. Template key starts with `ReviewTemplatePrefixes` => `TemplateCompatibility = Review`.
3. Template key starts with `SupportedTemplatePrefixes` => `TemplateCompatibility = Compatible`.
4. Anything else => `TemplateCompatibility = Review`.

Default intent:

- Personal sites (`SPSPERS#0`) are treated as compatible migration sources
  (migrate to OneDrive), not as unsupported blockers.
- Blog templates are flagged as `Review` by default because migrations usually
  require remapping to modern SharePoint Online structures.

Language behavior:

- `TemplateLanguageLcid` comes from the root web.
- If LCID is missing or not recognized by .NET culture metadata, `TemplateLanguageReviewRequired = True`.
- If `SupportedLanguageLcid` is non-empty, LCIDs outside that allow-list are flagged for review.

Content types are inventoried for review, including standard definitions and list
bindings. They do not contribute to the default score. Names, groups and content-type
ID prefixes alone do not reliably identify custom or non-portable definitions.

## LargeContentThresholds section

```powershell
LargeContentThresholds = @{
    LargeSiteSizeGB = 100
    LargeListItemCount = 5000
    LargeListViewRowLimit = 5000
    CheckedOutFileCount = 1
    FileVersionCount = 50
    MaxItemsForVersionScanPerLibrary = 2000
}
```

- `LargeSiteSizeGB` — marks `IsLargeSite` when `SizeGB` reaches this value.
- `LargeListItemCount` — minimum list size for `LargeListCount`.
- `LargeListViewRowLimit` — minimum view row limit for `LargeListViewCount`.
- `CheckedOutFileCount` — minimum checked-out files in a library before it is surfaced
  in examples (site-wide checked-out files are always counted).
- `FileVersionCount` — minimum file-version count for `FileVersionCount`.
- `MaxItemsForVersionScanPerLibrary` — cap for per-library file-version scanning.
  When the cap is reached, assessment stays usable but is marked partial with a warning.

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
