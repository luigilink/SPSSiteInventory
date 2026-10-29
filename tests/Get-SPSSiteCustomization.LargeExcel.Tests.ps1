# Behavior tests for the large Excel files signal of Get-SPSSiteCustomization: the workbooks of a document library that
# SharePoint Online does not open in the browser. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    # A file whose size cannot be read. It is a real .NET type: PowerShell turns an exception of a getter into $null.
    if (-not ('SPSTestUnsizedFile' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
public class SPSTestUnsizedFile
{
    public string ServerRelativeUrl { get; set; }
    public long Length { get { throw new InvalidOperationException("size unavailable"); } }
}
'@
    }

    function global:Get-SPAppInstance {
        param($Web)
        @()
    }

    function New-TestWorkbook {
        param ([string]$Name, [double]$Megabyte)
        $file = [PSCustomObject]@{ ServerRelativeUrl = "/sites/team/Docs/$Name"; Length = [long]($Megabyte * 1MB) }
        [PSCustomObject]@{ File = $file }
    }

    function New-TestBatch {
        param ([object[]]$Item, $Position = $null)
        [PSCustomObject]@{ Items = @($Item); Position = $Position }
    }

    # A library that answers the query for the workbooks and finds nothing for the other scans.
    function New-TestLibrary {
        param ([string]$Title = 'Docs', [string]$Url = '/sites/team/Docs', [int]$BaseTemplate = 101, [object[]]$Batches = @(), [switch]$Throttled)
        $library = [PSCustomObject]@{
            Title = $Title
            RootFolder = [PSCustomObject]@{ ServerRelativeUrl = $Url; Properties = @{} }
            ContentTypes = @()
            WorkflowAssociations = @()
            EventReceivers = @()
            IrmEnabled = $false
            ItemCount = 0
            Views = @()
            CheckedOutFiles = @()
            EnableVersioning = $false
            Items = @()
            BaseTemplate = $BaseTemplate
            Fields = @()
            HasExternalDataSource = $false
            Batches = $Batches
            BatchIndex = 0
            Throttled = [bool]$Throttled
            Queries = [System.Collections.Generic.List[object]]::new()
        }
        $library | Add-Member -MemberType ScriptMethod -Name GetItems -Value {
            param ($Query)
            if (-not ($Query.PSObject.Properties['Query'] -and [string]$Query.Query -match '>xlsx<')) {
                return [PSCustomObject]@{ Items = @(); ListItemCollectionPosition = $null }
            }
            $this.Queries.Add($Query)
            if ($this.Throttled) { throw 'The query exceeds the list view threshold.' }
            $batch = $this.Batches[$this.BatchIndex]
            $this.BatchIndex++
            return [PSCustomObject]@{ Items = @($batch.Items); ListItemCollectionPosition = $batch.Position }
        }
        return $library
    }

    function New-TestSite {
        param ([object[]]$Library)
        $web = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            ContentTypes = @(); Lists = $Library; WorkflowAssociations = @(); HasUniqueRoleAssignments = $false
            CustomMasterUrl = ''; Features = @(); Files = @(); IsRootWeb = $true; HasUniqueRoleDefinitions = $true
            RoleDefinitions = @(); Alerts = @(); AlternateCssUrl = ''; RootFolder = [PSCustomObject]@{ WelcomePage = '' }
        }
        $web | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        [PSCustomObject]@{ Url = 'https://intranet.contoso.com/sites/team'; Features = @(); Solutions = @(); AllWebs = @($web) }
    }

    function Get-Signal {
        param ($Site, [hashtable]$Threshold = @{})
        $warnings = @()
        $signals = Get-SPSSiteCustomization -Site $Site -LargeContentThresholds $Threshold -WarningVariable warnings -WarningAction SilentlyContinue
        [PSCustomObject]@{ Signals = $signals; Warnings = @($warnings | ForEach-Object { [string]$_ }) }
    }
}

Describe 'Get-SPSSiteCustomization large Excel files' {
    It 'counts the workbooks of at least 10 MB by default and lists them with their size' {
        $library = New-TestLibrary -Batches @((New-TestBatch -Item @((New-TestWorkbook 'big.xlsx' 12.5), (New-TestWorkbook 'small.xlsx' 0.4), (New-TestWorkbook 'huge.xlsx' 80))))

        $result = Get-Signal -Site (New-TestSite -Library @($library))

        $result.Signals.LargeExcelFileCount | Should -Be 2
        $result.Signals.LargeExcelFileExamples | Should -Be '/sites/team/Docs/big.xlsx (12.5 MB); /sites/team/Docs/huge.xlsx (80 MB)'
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
    }

    It 'counts a workbook that is exactly at the threshold, and not one a byte below it' {
        $atLimit = New-TestWorkbook 'limit.xlsx' 10
        $below = New-TestWorkbook 'below.xlsx' 10
        $below.File.Length = $below.File.Length - 1
        $library = New-TestLibrary -Batches @((New-TestBatch -Item @($atLimit, $below)))

        (Get-Signal -Site (New-TestSite -Library @($library))).Signals.LargeExcelFileCount | Should -Be 1
    }

    It 'reads the threshold from LargeExcelFileSizeMB' {
        $library = New-TestLibrary -Batches @((New-TestBatch -Item @((New-TestWorkbook 'a.xlsx' 3), (New-TestWorkbook 'b.xlsx' 0.5))))

        $result = Get-Signal -Site (New-TestSite -Library @($library)) -Threshold @{ LargeExcelFileSizeMB = 1 }

        $result.Signals.LargeExcelFileCount | Should -Be 1
        $result.Signals.LargeExcelFileExamples | Should -Be '/sites/team/Docs/a.xlsx (3 MB)'
    }

    It 'falls back to 10 MB when the threshold is not a usable number' -ForEach @(
        @{ Value = 0 }
        @{ Value = -5 }
        @{ Value = 'big' }
    ) {
        $library = New-TestLibrary -Batches @((New-TestBatch -Item @((New-TestWorkbook 'a.xlsx' 3))))

        (Get-Signal -Site (New-TestSite -Library @($library)) -Threshold @{ LargeExcelFileSizeMB = $Value }).Signals.LargeExcelFileCount | Should -Be 0
    }

    It 'writes the size with a point, whatever the culture of the server' {
        $library = New-TestLibrary -Batches @((New-TestBatch -Item @((New-TestWorkbook 'a.xlsx' 12.5))))
        $original = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
            $result = Get-Signal -Site (New-TestSite -Library @($library))
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $original
        }

        $result.Signals.LargeExcelFileExamples | Should -Be '/sites/team/Docs/a.xlsx (12.5 MB)'
    }

    It 'asks for the .xlsx files in pages of 200, with the throttle override, and only in document libraries' {
        $docs = New-TestLibrary -Batches @((New-TestBatch -Item @()))
        $list = New-TestLibrary -Title 'Tasks' -BaseTemplate 100 -Batches @((New-TestBatch -Item @()))

        $null = Get-Signal -Site (New-TestSite -Library @($docs, $list))

        $docs.Queries | Should -HaveCount 1
        $docs.Queries[0].RowLimit | Should -Be 200
        $docs.Queries[0].Query | Should -Match '<FieldRef Name="File_x0020_Type" /><Value Type="Text">xlsx</Value>'
        $docs.Queries[0].ViewFields | Should -Match 'FileRef'
        $docs.Queries[0].QueryThrottleMode | Should -Be 'Override'
        $list.Queries | Should -HaveCount 0
    }

    It 'skips the system catalogs' {
        $catalog = New-TestLibrary -Title 'Master Page Gallery' -Url '/sites/team/_catalogs/masterpage' -Batches @((New-TestBatch -Item @((New-TestWorkbook 'x.xlsx' 50))))

        $result = Get-Signal -Site (New-TestSite -Library @($catalog))

        $catalog.Queries | Should -HaveCount 0
        $result.Signals.LargeExcelFileCount | Should -Be 0
    }

    It 'follows the workbooks of a library from one batch to the next' {
        $library = New-TestLibrary -Batches @(
            (New-TestBatch -Item @((New-TestWorkbook 'a.xlsx' 11)) -Position 'next')
            (New-TestBatch -Item @((New-TestWorkbook 'b.xlsx' 12)))
        )

        $result = Get-Signal -Site (New-TestSite -Library @($library))

        $library.Queries | Should -HaveCount 2
        $result.Signals.LargeExcelFileCount | Should -Be 2
    }

    It 'adds up the workbooks of every library' {
        $one = New-TestLibrary -Title 'One' -Url '/sites/team/One' -Batches @((New-TestBatch -Item @((New-TestWorkbook 'a.xlsx' 11))))
        $two = New-TestLibrary -Title 'Two' -Url '/sites/team/Two' -Batches @((New-TestBatch -Item @((New-TestWorkbook 'b.xlsx' 12), (New-TestWorkbook 'c.xlsx' 13))))

        (Get-Signal -Site (New-TestSite -Library @($one, $two))).Signals.LargeExcelFileCount | Should -Be 3
    }

    It 'lists at most five examples and still counts every workbook' {
        $items = 1..7 | ForEach-Object { New-TestWorkbook ('w{0}.xlsx' -f $_) 20 }
        $library = New-TestLibrary -Batches @((New-TestBatch -Item $items))

        $result = Get-Signal -Site (New-TestSite -Library @($library))

        $result.Signals.LargeExcelFileCount | Should -Be 7
        @($result.Signals.LargeExcelFileExamples -split '; ') | Should -HaveCount 5
    }

    It 'stops at the cap of each library, marks the collection partial and names the setting' {
        $items = 1..3 | ForEach-Object { New-TestWorkbook ('w{0}.xlsx' -f $_) 20 }
        $library = New-TestLibrary -Batches @((New-TestBatch -Item $items))

        $result = Get-Signal -Site (New-TestSite -Library @($library)) -Threshold @{ MaxItemsForExcelFileScanPerLibrary = 2 }

        $result.Signals.LargeExcelFileCount | Should -Be 2
        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match 'MaxItemsForExcelFileScanPerLibrary'
    }

    It 'marks the collection partial when the cap is reached with more workbooks to come, and checks 2000 by default' {
        $first = New-TestLibrary -Batches @((New-TestBatch -Item @((New-TestWorkbook 'a.xlsx' 20), (New-TestWorkbook 'b.xlsx' 20)) -Position 'next'))
        (Get-Signal -Site (New-TestSite -Library @($first)) -Threshold @{ MaxItemsForExcelFileScanPerLibrary = 2 }).Signals.CustomizationInventoryComplete | Should -BeFalse

        $many = 1..2001 | ForEach-Object { New-TestWorkbook ('w{0}.xlsx' -f $_) 20 }
        $big = New-TestLibrary -Batches @((New-TestBatch -Item $many))
        $result = Get-Signal -Site (New-TestSite -Library @($big))
        $result.Signals.LargeExcelFileCount | Should -Be 2000
        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
    }

    It 'marks the collection partial and names the library when the workbooks cannot be listed' {
        $library = New-TestLibrary -Throttled

        $result = Get-Signal -Site (New-TestSite -Library @($library))

        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "Could not scan the Excel files on 'Docs' in web 'https://intranet.contoso.com/sites/team': .*list view threshold"
    }

    It 'marks the collection partial, instead of taking the workbook for a small one, when its size cannot be read' {
        $unsized = [SPSTestUnsizedFile]::new()
        $unsized.ServerRelativeUrl = '/sites/team/Docs/odd.xlsx'
        $library = New-TestLibrary -Batches @((New-TestBatch -Item @([PSCustomObject]@{ File = $unsized })))

        $result = Get-Signal -Site (New-TestSite -Library @($library))

        $result.Signals.LargeExcelFileCount | Should -Be 0
        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match 'size unavailable'
    }

    It 'marks the collection partial when a workbook has no file' {
        $library = New-TestLibrary -Batches @((New-TestBatch -Item @([PSCustomObject]@{ File = $null })))

        $result = Get-Signal -Site (New-TestSite -Library @($library))

        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match 'file of a workbook is unavailable'
    }

    It 'reports nothing for a site collection without workbooks' {
        $library = New-TestLibrary -Batches @((New-TestBatch -Item @()))

        $result = Get-Signal -Site (New-TestSite -Library @($library))

        $result.Signals.LargeExcelFileCount | Should -Be 0
        $result.Signals.LargeExcelFileExamples | Should -Be ''
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
    }
}
