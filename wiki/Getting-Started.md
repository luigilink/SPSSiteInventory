# Getting Started

This guide walks through preparing and running a first inventory.

## 1. Prerequisites

- A **SharePoint Server** farm (2016, 2019 or Subscription Edition).
- Run on a **farm server**, in an elevated **Windows PowerShell 5.1** session (not PowerShell 7).
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

## 4. Check readiness

```powershell
.\Test-SPSSiteInventoryReadiness.ps1
```

This reports the PowerShell edition/version, whether SharePoint is installed and its build, whether the SharePoint commands load, and whether the settings file exists. It changes nothing.

## 5. Run the inventory

```powershell
.\Invoke-SPSSiteInventory.ps1
```

The scan is read-only. On a large farm it can take a while (it enumerates every site collection). When it finishes, the CSV and JSON reports are in the `OutputFolder` from your settings.

## 6. Review the output

Open the CSV in Excel and sort by `Category` and `Score`. Category 1 sites are your quick wins; category 4 sites need a dedicated plan. See [Usage](Usage) for how to read and act on the report.
