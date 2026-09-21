# SPSSiteInventory

![Latest release date](https://img.shields.io/github/release-date/luigilink/spssiteinventory.svg?style=flat)
![Total downloads](https://img.shields.io/github/downloads/luigilink/spssiteinventory/total.svg?style=flat)  
![Issues opened](https://img.shields.io/github/issues/luigilink/spssiteinventory.svg?style=flat)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](CODE_OF_CONDUCT.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**SPSSiteInventory** is a PowerShell toolkit that inventories on-premises **SharePoint Server** site collections and **categorizes them by migration complexity** (Simple → Moderate → Complex → Blocking) to prepare a move to **SharePoint Online**.

It is read-only by design and produces a scriptable, diff-friendly CSV/JSON inventory plus a shareable, self-contained HTML report that feed a migration wave plan.

Compatible with **SharePoint Server 2016, 2019 and Subscription Edition**.

## Why

Microsoft's assessment tooling has shifted: **SMAT reaches end of support on 1 October 2026**, and the **SPMT scan** capability now covers content inventory and migration risks. Neither produces a **business-complexity categorization** correlated with the farm's custom code (which full-trust solution feeds which site). SPSSiteInventory fills that gap: a configurable scoring engine turns raw customization signals into an actionable 1–4 category, so you know which sites are quick wins and which need a project.

## What it collects

- Site identity and volumetry (URL, template, size, sub-webs, last activity)
- Customization signals: 2010 vs 2013 workflows, InfoPath forms, sandbox solutions, custom master pages, event receivers, unique permissions
- Correlation between **farm solutions (WSP)** and the sites that activate their features, including **full-trust code** detection (assemblies deployed to the GAC), CAS policy, deployment reach and features per solution
- A **complexity score and category** per site, driven by a per-environment configuration
- Outputs: a **CSV** (Excel), a **JSON** (automation) and a **self-contained HTML report** (category summary, sortable/filterable table) for sharing with stakeholders, plus a dedicated **farm-solution (WSP) CSV/JSON** report

## Quick links

- 📦 [Latest release](https://github.com/luigilink/SPSSiteInventory/releases/latest)
- 📖 [Documentation (Wiki)](https://github.com/luigilink/SPSSiteInventory/wiki)
- 🚀 [Getting Started](https://github.com/luigilink/SPSSiteInventory/wiki/Getting-Started)
- ⚙️ [Configuration reference](https://github.com/luigilink/SPSSiteInventory/wiki/Configuration)
- 📝 [Changelog](CHANGELOG.md)
- 🔒 [Security policy](SECURITY.md)
- 🤝 [Contributing](.github/CONTRIBUTING.md)

## Requirements

- **Windows PowerShell 5.1** (the SharePoint Server object model requires it; do not use PowerShell 7)
- Run on a **SharePoint farm server**, as the **farm account** (read access to all web applications and the User Profile service), in an elevated session

## Code of conduct

This project adopts the [Contributor Covenant](CODE_OF_CONDUCT.md).
