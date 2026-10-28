# Inspecting WSP packages (offline)

A farm solution (SPSolution) only tells you a few booleans: does it deploy a global assembly, does it have a code access security policy. The package itself tells you much more. `Get-SPSSolutionPackageInfo` reads WSP files that sit on disk and reports what they contain, **with no farm, no SharePoint command and no `Add-SPSolution`**. It is read-only: nothing in a package is run or loaded.

Use it to assess a solution before any environment is touched, to settle whether a solution is really custom code, and to see the features and assemblies of a solution that is added but not deployed (the farm reports no feature for it).

## What you need

- PowerShell 5.1 or later. Any machine will do: it does not have to be a farm server.
- A tool to expand the package, which is a cabinet (CAB) archive: `expand.exe` on Windows (it is part of the system), or `cabextract` elsewhere. If you have neither, expand the package with another tool and give the folder to `-Path`: a folder that has `manifest.xml` at its root is read as a package that is already expanded.
- The WSP files. To get the packages of a farm, save them from the farm (this reads the configuration database and changes nothing):

  ```powershell
  Get-SPSolution | ForEach-Object { $_.SolutionFile.SaveAs((Join-Path 'D:\Packages' $_.Name)) }
  ```

## Run it

```powershell
Import-Module .\Modules\SPSSiteInventory.Common\SPSSiteInventory.Common.psd1

# Every .wsp and .cab file of a folder and its subfolders, to a CSV and a JSON file
Get-SPSSolutionPackageInfo -Path D:\Packages -Recurse |
    Export-SPSSolutionPackageReport -OutputFolder D:\Inventory

# One package, on screen
Get-SPSSolutionPackageInfo -Path .\Contoso.Intranet.wsp | Format-List *
```

On a farm server, add the farm solutions to compare each package with the solution of the farm:

```powershell
$map = Get-SPSFarmSolutionMap
Get-SPSSolutionPackageInfo -Path D:\Packages -FarmSolutionMap $map
```

A package that cannot be inspected is returned with `Status` `Failed` and the reason in `Detail`, so that one bad file does not stop the others. `Status` is `Partial` when the package was read but a part of it could not be (a feature manifest or an assembly that is not in the package).

| Parameter | Meaning |
| --- | --- |
| `-Path` | WSP or CAB files, folders that hold them, or folders of expanded packages. Wildcards and the pipeline (`Get-ChildItem *.wsp \| Get-SPSSolutionPackageInfo`) are accepted. |
| `-Recurse` | Searches the subfolders of a folder for packages. |
| `-FarmSolutionMap` | The farm solutions (`Get-SPSFarmSolutionMap`) to compare the packages with. |
| `-KnownMicrosoftPublicKeyToken` | Extra public key tokens that count as Microsoft. |
| `-KnownMicrosoftPrefix` | Extra solution name prefixes that count as Microsoft, used only for a package that has no assembly. |
| `-MaximumMegabyte` | The size that a package may expand to. Defaults to 512. |
| `-TemporaryFolder` | Where the packages are expanded (and removed from again). Defaults to the temporary folder of the user. |

## The files

`Export-SPSSolutionPackageReport` writes three files, next to the other reports (`-BaseName` and a timestamp are added to the names, as for `*-solutions-*`):

| File | Purpose |
| --- | --- |
| `*-solution-packages-*.csv` | One row per package, for Excel, with the lists flattened to semicolon-separated text. |
| `*-solution-assemblies-*.csv` | One row per assembly of the packages, with its strong name, its public key token, the framework it was built for and where it is deployed. |
| `*-solution-packages-*.json` | The full structure, with the assemblies and the features of each package, for automation. |

The text of a package comes from files that are not trusted, so the CSV files neutralize the cells that a spreadsheet could read as a formula, like the other reports (see [Usage](Usage#csv-files-and-spreadsheet-formulas)).

## Package fields

| Field | Description |
| --- | --- |
| `PackageName` / `PackagePath` / `Source` | The file (or the folder) and whether it was a cabinet or an expanded folder. |
| `PackageSizeBytes` / `Sha256` | The size and the SHA-256 of the file, to know exactly which package was read. |
| `Status` / `Detail` | `Inspected`, `Partial` or `Failed`, and why. |
| `SolutionId` / `SharePointProductVersion` / `DeploymentServerType` / `ResetWebServer` | From `manifest.xml`. The solution id is the id that the farm gives the solution when it is added. |
| `IsCustom` / `IsCustomSource` | Whether the package is custom code, and what it was judged on: `Assembly` or `Name` (see below). |
| `IsFullTrustCode` | Custom **and** deploys a global assembly, as in the farm-solution report. |
| `ContainsGlobalAssembly` / `ContainsWebApplicationAssembly` | An assembly is deployed to the global assembly cache, or to the web application (the `bin` folder). |
| `ContainsCasPolicy` / `ContainsWebApplicationResource` | A code access security policy, or application resource files (or a web application assembly). |
| `AssemblyCount` / `CustomAssemblyCount` / `UnsignedAssemblyCount` | The DLLs of the package, the custom ones, and the .NET ones that are not signed. |
| `LegacyFrameworkAssemblyCount` / `TargetFrameworks` | The custom assemblies built for .NET 3.5 or before, and the frameworks that the DLLs target. |
| `FeatureCount` / `FeatureScopes` / `FeatureIds` | The features of the manifest, read from their own `Feature.xml`, with their id in the form that the farm uses. |
| `FeatureReceiverCount` | The features that have a receiver (a feature receiver, or event receivers in an element manifest). |
| `SafeControlCount` | The safe control entries of the manifest. |
| `TemplateFileCount` / `RootFileCount` / `DwpFileCount` / `SiteDefinitionCount` | The template files, the root files, the web part files (`.dwp`) and the site definitions. |
| `ElementSummary` | The kind of elements that the features provision, for example `ContentType=2; Field=14; Module=1; Receiver=1`. |
| `FileCount` / `ExpandedSizeBytes` | What the package holds once it is expanded. |
| `InFarm` / `FarmMatch` / `FarmSolutionName` / `FarmDeployed` / `FarmDeploymentState` / `FarmFeatureCount` | With `-FarmSolutionMap`: the farm solution that has the solution id of the package, or else its file name. |
| `Difference` | With `-FarmSolutionMap`: what the farm and the package disagree on (the number of features, the global assembly, the policy, whether it is custom). |
| `Assemblies` / `Features` | The details (JSON only): one entry per DLL and per feature. |

Each assembly has `Location`, `DeploymentTarget` (`GlobalAssemblyCache`, `WebApplication`, or `Other` for a DLL that is in the package and not in the manifest), `Name`, `Version`, `Culture`, `PublicKeyToken`, `IsSigned`, `IsMicrosoft`, `IsSatellite`, `IsCustom`, `RuntimeVersion`, `TargetFramework`, `Architecture`, `BuiltForLegacyFramework` and `SafeControlCount`.

## Custom or Microsoft

The farm-solution report decides `IsCustom` from the **name** of the solution: custom unless the name looks like a Microsoft one. A package gives something better, the **public key token** of each of its assemblies:

- an assembly signed with a token that Microsoft signs with is Microsoft: `71e9bce111e9429c` (SharePoint and Office Server), `31bf3856ad364e35`, `b77a5c561934e089` and `b03f5f7f11d50a3a` (Windows and .NET). Add others with `-KnownMicrosoftPublicKeyToken`;
- any other assembly, including one that is not signed, is custom;
- a satellite assembly (it has a culture) holds resources only and does not count;
- the package is custom as soon as one assembly is custom (`IsCustomSource` is `Assembly`).

A package that has no assembly at all (a declarative solution) is judged on its name, as the farm report does (`IsCustomSource` is `Name`).

A solution that is signed by a vendor with its own key is custom here, like any code that is not Microsoft's: the toolkit does not keep a list of vendors.

## Built for an older .NET

`RuntimeVersion` is the version of the runtime that an assembly asks for, read from its metadata: `v2.0.50727` is the runtime of .NET 2.0 to 3.5 (SharePoint 2010 and before), `v4.0.30319` that of .NET 4.x. `TargetFramework` is the framework named by the assembly attribute, for example `.NETFramework,Version=v4.8`; an assembly built before .NET 4.0 does not have one. A custom assembly that asks for the runtime v2.0 or targets a framework before 4.0 is counted in `LegacyFrameworkAssemblyCount`: it was built for SharePoint 2010 or before and has to be rebuilt for SharePoint 2016 and later, and it can never run in SharePoint Online.

## Safety

The package is not trusted, so the function is careful with it:

- the file table of the cabinet is read first, and the package is refused, before anything is written, when it lists a file name that goes up with `..`, is rooted or has a drive or a stream, when it lists more than 20000 files, or when its declared size is above `-MaximumMegabyte`;
- the files are only read, as text (XML) and as bytes (the DLLs). No DLL is loaded or run, and nothing in the package is executed;
- the XML is read with the DTD and the external entities switched off, and a location in a manifest that leaves the package is not followed;
- the package is expanded in a folder of its own in the temporary folder, which is removed when the package has been read, also when it failed.

## Limits

- Only cabinets are read: a WSP, including the ones of sandboxed solutions. A `.sppkg` (SPFx) is not a cabinet.
- The target framework is read from the text of the assembly attribute. It is a good indication, not a proof, and it is absent from old assemblies (the runtime version then tells).
- The code of the assemblies is not analyzed. The package says what the solution is made of and what it was built for, not what the code does. In particular, the changes to `web.config` that a feature receiver makes in code (`SPWebConfigModification`) cannot be seen: the package says that a feature has a receiver (`FeatureReceiverCount`), not what it does. What it declares is read: the safe controls, the code access security policy and where each assembly is deployed.
- A package that was split in several cabinets is refused.
