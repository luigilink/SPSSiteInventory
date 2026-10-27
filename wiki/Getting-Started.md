# Getting Started

This guide walks through preparing and running a first inventory.

## 1. Prerequisites

- A **SharePoint Server** farm (2016, 2019 or Subscription Edition).
- Run on a **farm server**, from an elevated **SharePoint Management Shell**
  (Windows PowerShell 5.1, not PowerShell 7). This initializes the SharePoint commands
  before the toolkit imports its module.
- Sign in as the **farm account** (or an account with read access to all web applications and Full Control on the User Profile service application).

## 2. Get the toolkit

Download the latest release ZIP from the [Releases](https://github.com/luigilink/SPSSiteInventory/releases) page and extract it, or clone the repository and use the `src/` folder.

The extracted layout is:

```text
Invoke-SPSSiteInventory.ps1
Test-SPSSiteInventoryReadiness.ps1
config/inventory-settings.example.psd1
Modules/SPSSiteInventory.Common/
```

## 3. Create your settings file

Copy the example and adjust it for your farm:

```powershell
Copy-Item .\config\inventory-settings.example.psd1 .\config\inventory-settings.psd1
notepad .\config\inventory-settings.psd1
```

See the [Configuration](Configuration) page for every setting. At minimum, set `OutputFolder`. Custom farm solutions are auto-detected, so `CustomSolutionPrefix` is optional (leave it empty unless you need to override the detection).

When reusing an older settings file, add `HasFbaZone` to `Scoring.BlockingSignals`
if FBA must block migration to SharePoint Online. The current example includes it.

## 4. Check readiness

```powershell
.\Test-SPSSiteInventoryReadiness.ps1
```

The check is read-only: it changes nothing on the farm and writes no file. It prints one line per check, grouped by section, then a summary and a verdict:

```text
== Toolkit ==
[ OK ]  SPSSiteInventory.Common module - Version 2.0.0

== PowerShell ==
[ OK ]  Windows PowerShell 5.1 - Version 5.1.14393.6343
[ OK ]  Elevated session - Running as CONTOSO\spfarm.

== Settings ==
[ OK ]  Settings file - D:\SPSSiteInventory\config\inventory-settings.psd1
[ OK ]  Settings content - The file loads and has its Scoring section.
[ OK ]  Output folder - D:\SPSSiteInventory\Reports
[WARN]  Blocking signals - 2 blocking signal(s) of the example configuration are not in Scoring.BlockingSignals: HasFbaZone, ExternalListCount. Sites that have them are not classified as Blocking.
[ OK ]  Signal weights - Every signal of the example configuration has a weight.

== SharePoint ==
[ OK ]  SharePoint installed - Build 16.0.18526.20424
[ OK ]  SharePoint commands - The SharePoint commands are loaded.
[ERR ]  Farm connection - The farm cannot be reached: Cannot connect to the configuration database.
[SKIP]  Farm administrator - The farm cannot be reached.
[SKIP]  Web applications - The farm cannot be reached.

 Summary : 9 OK, 1 warning(s), 1 error(s), 2 skipped
 Not ready: fix the error(s) above before you run Invoke-SPSSiteInventory.ps1. Warnings do not block the scan.
```

| Status | Mark | Meaning |
| --- | --- | --- |
| OK | `[ OK ]` (green) | The check passed. |
| Warning | `[WARN]` (yellow) | The scan can run, but the result deserves a look. |
| Error | `[ERR ]` (red) | The scan cannot run, or would fail, until this is fixed. |
| Skipped | `[SKIP]` (gray) | The check could not run, because a check it depends on failed or because you asked to skip it. |

It checks:

- **PowerShell**: Windows PowerShell 5.1 (PowerShell 7 cannot load the SharePoint snap-in) and an elevated session.
- **Settings**: the settings file exists and loads, with its `Scoring` section and a valid `SharePointAlerts` section; `OutputFolder` is set and usable (a folder that does not exist yet is fine, the scan creates it); and the blocking signals and weights of `config\inventory-settings.example.psd1` that your file does not have yet. That last comparison is a warning that helps when you reuse the settings file of an older release: those signals are collected but do not influence the score.
- **SharePoint**: SharePoint is installed (and its build), the SharePoint commands load, the farm can be reached, the account is a farm administrator (a warning if not: read access to every site collection is enough, but the farm account is recommended), and the web applications to scan exist: each `WebApplicationUrl` of the settings, or at least one content web application when the setting is empty.

The script exits with code 1 when there is an error, or when the checks themselves could not run, and with 0 otherwise, so that it can gate an automated run. `-ConfigPath` points to another settings file, `-SkipSharePoint` checks the host and the settings file on a machine that is not a farm server, and `-PassThru` also returns a summary object (counts, `IsReady` and the checks).

## 5. Run the inventory

```powershell
.\Invoke-SPSSiteInventory.ps1
```

The scan is read-only. On a large farm it can take a while (it enumerates every site collection). When it finishes, the CSV and JSON reports are in the `OutputFolder` from your settings.

## 6. Review the output

Open the CSV in Excel and sort by `Category` and `Score`. Category 1 sites are your quick wins; category 4 sites need a dedicated plan. A text cell that Excel could read as a formula starts with a quote: that is deliberate (see [Usage](Usage#csv-files-and-spreadsheet-formulas)). See [Usage](Usage) for how to read and act on the report.
