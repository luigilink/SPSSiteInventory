# Behavior tests for ConvertTo-SPSEventReceiverClassRow (the rows of the event receiver report of a site collection).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    $script:Contoso = 'Contoso.Intranet, Version=1.0.0.0, Culture=neutral, PublicKeyToken=0123456789abcdef'
    $script:Fabrikam = 'Fabrikam.Docs, Version=2.0.0.0, Culture=neutral, PublicKeyToken=null'

    function New-Receiver {
        param ([string]$Assembly = $script:Contoso, [string]$Class = 'Contoso.Intranet.ItemReceiver', [string]$Type = 'ItemAdded')
        [PSCustomObject]@{ Assembly = $Assembly; Class = $Class; Type = $Type }
    }

    function New-List {
        param ([string]$Url = '/sites/team/Lists/Tasks')
        [PSCustomObject]@{ ID = [guid]::NewGuid(); Title = 'Tasks'; RootFolder = [PSCustomObject]@{ ServerRelativeUrl = $Url } }
    }

    # The groups that Add-SPSEventReceiverClass builds, then the rows. Each entry is @(receiver, list, how many times).
    function Get-Row {
        param ([object[]]$Entry, $Index = $null, [string]$SiteUrl = 'https://intranet/sites/team')
        & $script:Module {
            param ($Entry, $Index, $SiteUrl)
            $table = [System.Collections.Generic.Dictionary[System.String, System.Object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($item in $Entry) {
                for ($count = 0; $count -lt $item.Times; $count++) {
                    $null = Add-SPSEventReceiverClass -Table $table -Receiver $item.Receiver -List $item.List
                }
            }
            $parameters = @{ Table = $table; SiteUrl = $SiteUrl }
            if ($null -ne $Index) { $parameters['SolutionAssemblyIndex'] = $Index }
            ConvertTo-SPSEventReceiverClassRow @parameters
        } $Entry $Index $SiteUrl
    }

    function New-Entry {
        param ($Receiver, $List = (New-List), [int]$Times = 1)
        [PSCustomObject]@{ Receiver = $Receiver; List = $List; Times = $Times }
    }

    function New-Index {
        param ([object[]]$Package)
        & $script:Module { param ($Value) Get-SPSSolutionAssemblyIndex -SolutionPackages $Value } $Package
    }
}

Describe 'ConvertTo-SPSEventReceiverClassRow' {
    It 'returns no row for an empty table' {
        @(Get-Row -Entry @()) | Should -HaveCount 0
    }

    It 'gives one row for each assembly and class, with the site collection, the counts and the first list' {
        $one = New-List -Url '/sites/team/Lists/One'
        $two = New-List -Url '/sites/team/Lists/Two'
        $row = @(Get-Row -Entry @(
                (New-Entry (New-Receiver -Type 'ItemAdded') $one)
                (New-Entry (New-Receiver -Type 'ItemUpdated') $one)
                (New-Entry (New-Receiver -Type 'ItemAdded') $two)
            ))

        $row | Should -HaveCount 1
        $row[0].SiteUrl | Should -Be 'https://intranet/sites/team'
        $row[0].Assembly | Should -Be $script:Contoso
        $row[0].Class | Should -Be 'Contoso.Intranet.ItemReceiver'
        $row[0].ReceiverCount | Should -Be 3
        $row[0].ListCount | Should -Be 2
        $row[0].EventTypes | Should -Be 'ItemAdded; ItemUpdated'
        $row[0].FirstListUrl | Should -Be '/sites/team/Lists/One'
    }

    It 'writes the event types in alphabetical order, whatever the order in which the receivers were found' {
        $row = @(Get-Row -Entry @(
                (New-Entry (New-Receiver -Type 'ItemUpdated'))
                (New-Entry (New-Receiver -Type 'ItemDeleting'))
                (New-Entry (New-Receiver -Type 'ItemAdded'))
            ))

        $row[0].EventTypes | Should -Be 'ItemAdded; ItemDeleting; ItemUpdated'
    }

    It 'splits the assembly into its name, its version and its public key token' {
        $row = @(Get-Row -Entry @((New-Entry (New-Receiver)), (New-Entry (New-Receiver -Assembly $script:Fabrikam -Class 'Fabrikam.Docs.Receiver'))))

        $contoso = @($row | Where-Object { $_.AssemblyName -eq 'Contoso.Intranet' })
        $contoso[0].AssemblyVersion | Should -Be '1.0.0.0'
        $contoso[0].PublicKeyToken | Should -Be '0123456789abcdef'
        $fabrikam = @($row | Where-Object { $_.AssemblyName -eq 'Fabrikam.Docs' })
        $fabrikam[0].AssemblyVersion | Should -Be '2.0.0.0'
        $fabrikam[0].PublicKeyToken | Should -Be ''
    }

    It 'lists the largest row first, then by assembly name, then by class' {
        $row = @(Get-Row -Entry @(
                (New-Entry (New-Receiver -Assembly $script:Fabrikam -Class 'Fabrikam.Docs.B') -Times 2)
                (New-Entry (New-Receiver -Class 'Contoso.Intranet.Z') -Times 2)
                (New-Entry (New-Receiver -Class 'Contoso.Intranet.A') -Times 2)
                (New-Entry (New-Receiver -Class 'Contoso.Intranet.Big') -Times 5)
                (New-Entry (New-Receiver -Class 'Contoso.Intranet.Small') -Times 1)
            ))

        @($row | ForEach-Object { $_.Class }) | Should -Be @('Contoso.Intranet.Big', 'Contoso.Intranet.A', 'Contoso.Intranet.Z', 'Fabrikam.Docs.B', 'Contoso.Intranet.Small')
    }

    It 'gives the same order whatever the order of the receivers' {
        $first = @(Get-Row -Entry @((New-Entry (New-Receiver -Class 'A')), (New-Entry (New-Receiver -Class 'B'))))
        $second = @(Get-Row -Entry @((New-Entry (New-Receiver -Class 'B')), (New-Entry (New-Receiver -Class 'A'))))

        @($first | ForEach-Object { $_.Class }) | Should -Be @($second | ForEach-Object { $_.Class })
    }

    It 'has the columns of the event receivers files, in their order' {
        $row = @(Get-Row -Entry @((New-Entry (New-Receiver))))

        ($row[0].PSObject.Properties.Name -join ',') | Should -BeExactly 'SiteUrl,Assembly,AssemblyName,AssemblyVersion,PublicKeyToken,Class,ReceiverCount,ListCount,EventTypes,FirstListUrl,SolutionMatch,FarmSolutionName,PackageName'
    }

    It 'says NotChecked, with no solution, when no index of the packages is given' {
        $row = @(Get-Row -Entry @((New-Entry (New-Receiver))))

        $row[0].SolutionMatch | Should -BeExactly 'NotChecked'
        $row[0].FarmSolutionName | Should -Be ''
        $row[0].PackageName | Should -Be ''
    }

    It 'says None when the packages were inspected and none of them ships the assembly, even when the index is empty' {
        $index = New-Index @([PSCustomObject]@{ PackageName = 'Declarative.wsp'; FarmSolutionName = ''; Assemblies = @() })

        $row = @(Get-Row -Entry @((New-Entry (New-Receiver))) -Index $index)

        $row[0].SolutionMatch | Should -BeExactly 'None'
    }

    It 'names the package and the farm solution that ship the assembly, and how they were matched' {
        $index = New-Index @([PSCustomObject]@{ PackageName = 'Contoso.Intranet.wsp'; FarmSolutionName = 'contoso.intranet.wsp'; Assemblies = @([PSCustomObject]@{ Name = 'Contoso.Intranet'; PublicKeyToken = '0123456789abcdef'; Version = '1.0.0.0'; IsSatellite = $false; IsManaged = $true }, [PSCustomObject]@{ Name = 'Fabrikam.Docs'; PublicKeyToken = ''; Version = '2.0.0.0'; IsSatellite = $false; IsManaged = $true }) })

        $row = @(Get-Row -Entry @((New-Entry (New-Receiver)), (New-Entry (New-Receiver -Assembly $script:Fabrikam -Class 'Fabrikam.Docs.Receiver'))) -Index $index)

        $contoso = @($row | Where-Object { $_.AssemblyName -eq 'Contoso.Intranet' })[0]
        $contoso.SolutionMatch | Should -BeExactly 'AssemblyNameAndKey'
        $contoso.PackageName | Should -Be 'Contoso.Intranet.wsp'
        $contoso.FarmSolutionName | Should -Be 'contoso.intranet.wsp'
        $fabrikam = @($row | Where-Object { $_.AssemblyName -eq 'Fabrikam.Docs' })[0]
        $fabrikam.SolutionMatch | Should -BeExactly 'AssemblyName'
        $fabrikam.PackageName | Should -Be 'Contoso.Intranet.wsp'
    }
}
