@{
    RootModule        = 'SPSSiteInventory.Common.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'dbd80cd4-51b6-4987-bcae-267c6e0e6374'
    Author            = 'Jean-Cyril DROUHIN'
    CompanyName       = 'luigilink'
    Copyright         = '(c) Jean-Cyril DROUHIN. All rights reserved.'
    Description       = 'Shared functions for the SPSSiteInventory toolkit: SharePoint Server site enumeration, customization signal collection, farm-solution correlation, migration-complexity scoring, and report export.'

    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Add-SPSInventoryEvent'
        'ConvertTo-SPSInventoryHtml'
        'Export-SPSInventoryReport'
        'Export-SPSSolutionReport'
        'Get-SPSFarmSolutionMap'
        'Get-SPSInstalledProductVersion'
        'Get-SPSInventorySetting'
        'Get-SPSSiteCustomization'
        'Get-SPSSiteInventory'
        'Import-SPSSharePointCommand'
        'Initialize-SPSScript'
        'Measure-SPSSiteComplexity'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('SharePoint', 'SharePointServer', 'Migration', 'Inventory', 'Assessment', 'SharePointOnline')
            LicenseUri   = 'https://github.com/luigilink/SPSSiteInventory/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/luigilink/SPSSiteInventory'
        }
    }
}
