# Behavior tests for the event receiver detail of Get-SPSSiteCustomization: which assemblies and classes the EventReceivers
# signal counts, and the solution that ships each assembly. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function global:Get-SPAppInstance {
        param($Web)
        @()
    }

    $script:Contoso = 'Contoso.Intranet, Version=1.0.0.0, Culture=neutral, PublicKeyToken=0123456789abcdef'
    $script:Fabrikam = 'Fabrikam.Docs, Version=2.0.0.0, Culture=neutral, PublicKeyToken=null'
    $script:Native = 'Microsoft.SharePoint, Version=16.0.0.0, Culture=neutral, PublicKeyToken=71e9bce111e9429c'

    function New-TestReceiver {
        param ([string]$Assembly = $script:Contoso, [string]$Class = 'Contoso.Intranet.ItemReceiver', [string]$Type = 'ItemAdded')
        [PSCustomObject]@{ Assembly = $Assembly; Class = $Class; Type = $Type }
    }

    function New-TestList {
        param ([string]$Title = 'Tasks', [string]$Url = '/sites/team/Lists/Tasks', [object[]]$Receiver = @())
        [PSCustomObject]@{
            ID = [guid]::NewGuid()
            Title = $Title
            RootFolder = [PSCustomObject]@{ ServerRelativeUrl = $Url; Properties = @{} }
            ContentTypes = @()
            WorkflowAssociations = @()
            EventReceivers = $Receiver
            IrmEnabled = $false
            ItemCount = 0
            Views = @()
            CheckedOutFiles = @()
            EnableVersioning = $false
            Items = @()
            BaseTemplate = 100
            Fields = @()
            HasExternalDataSource = $false
        }
    }

    function New-TestWeb {
        param ([string]$Url = 'https://intranet.contoso.com/sites/team', [object[]]$List = @(), [bool]$IsRootWeb = $true)
        $web = [PSCustomObject]@{
            Url = $Url
            ContentTypes = @(); Lists = $List; WorkflowAssociations = @(); HasUniqueRoleAssignments = $false
            CustomMasterUrl = ''; Features = @(); Files = @(); IsRootWeb = $IsRootWeb; HasUniqueRoleDefinitions = $true
            RoleDefinitions = @(); Alerts = @(); AlternateCssUrl = ''; RootFolder = [PSCustomObject]@{ WelcomePage = '' }
        }
        $web | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        $web
    }

    function New-TestSite {
        param ([object[]]$Web)
        [PSCustomObject]@{ Url = 'https://intranet.contoso.com/sites/team'; Features = @(); Solutions = @(); AllWebs = @($Web) }
    }

    function Get-Signal {
        param ($Site, $Index = $null)
        $warnings = @()
        $parameters = @{ Site = $Site }
        if ($null -ne $Index) { $parameters['SolutionAssemblyIndex'] = $Index }
        $signals = Get-SPSSiteCustomization @parameters -WarningVariable warnings -WarningAction SilentlyContinue
        [PSCustomObject]@{ Signals = $signals; Warnings = @($warnings | ForEach-Object { [string]$_ }) }
    }

    function New-Index {
        param ([object[]]$Package)
        & $script:Module { param ($Value) Get-SPSSolutionAssemblyIndex -SolutionPackages $Value } $Package
    }
}

Describe 'Get-SPSSiteCustomization event receivers' {
    It 'counts the custom receivers as before, and leaves out the Microsoft ones' {
        $list = New-TestList -Receiver @(
            (New-TestReceiver)
            (New-TestReceiver -Type 'ItemUpdated')
            (New-TestReceiver -Assembly $script:Native -Class 'Microsoft.SharePoint.Native' -Type 'ItemDeleting')
            (New-TestReceiver -Assembly $script:Fabrikam -Class 'Fabrikam.Docs.Receiver')
        )

        $result = Get-Signal -Site (New-TestSite -Web @((New-TestWeb -List @($list))))

        $result.Signals.EventReceivers | Should -Be 3
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
    }

    It 'groups the custom receivers by assembly and class over all the lists and the webs of the site collection' {
        $first = New-TestList -Title 'First' -Url '/sites/team/Lists/First' -Receiver @((New-TestReceiver -Type 'ItemAdded'), (New-TestReceiver -Type 'ItemUpdated'))
        $second = New-TestList -Title 'Second' -Url '/sites/team/hr/Lists/Second' -Receiver @((New-TestReceiver -Type 'ItemAdded'), (New-TestReceiver -Assembly $script:Fabrikam -Class 'Fabrikam.Docs.Receiver'))
        $site = New-TestSite -Web @((New-TestWeb -List @($first)), (New-TestWeb -Url 'https://intranet.contoso.com/sites/team/hr' -List @($second) -IsRootWeb $false))

        $result = Get-Signal -Site $site

        $row = @($result.Signals.EventReceiverClasses)
        $row | Should -HaveCount 2
        $contoso = @($row | Where-Object { $_.AssemblyName -eq 'Contoso.Intranet' })[0]
        $contoso.SiteUrl | Should -Be 'https://intranet.contoso.com/sites/team'
        $contoso.Class | Should -Be 'Contoso.Intranet.ItemReceiver'
        $contoso.ReceiverCount | Should -Be 3
        $contoso.ListCount | Should -Be 2
        $contoso.EventTypes | Should -Be 'ItemAdded; ItemUpdated'
        $contoso.FirstListUrl | Should -Be '/sites/team/Lists/First'
        $result.Signals.EventReceivers | Should -Be 4
    }

    It 'splits the assembly into its name, version and public key token' {
        $list = New-TestList -Receiver @((New-TestReceiver), (New-TestReceiver -Assembly $script:Fabrikam -Class 'Fabrikam.Docs.Receiver'))

        $row = @((Get-Signal -Site (New-TestSite -Web @((New-TestWeb -List @($list))))).Signals.EventReceiverClasses)

        $contoso = @($row | Where-Object { $_.AssemblyName -eq 'Contoso.Intranet' })[0]
        $contoso.Assembly | Should -Be $script:Contoso
        $contoso.AssemblyVersion | Should -Be '1.0.0.0'
        $contoso.PublicKeyToken | Should -Be '0123456789abcdef'
        $fabrikam = @($row | Where-Object { $_.AssemblyName -eq 'Fabrikam.Docs' })[0]
        $fabrikam.PublicKeyToken | Should -Be ''
    }

    It 'writes the examples: the largest rows first, with the counts and where the first receiver is' {
        $list = New-TestList -Url '/sites/team/Lists/Tasks' -Receiver @(
            (New-TestReceiver -Class 'Contoso.Intranet.Small')
            (New-TestReceiver -Class 'Contoso.Intranet.Big' -Type 'ItemAdded')
            (New-TestReceiver -Class 'Contoso.Intranet.Big' -Type 'ItemUpdated')
        )

        $result = Get-Signal -Site (New-TestSite -Web @((New-TestWeb -List @($list))))

        $result.Signals.EventReceiverExamples | Should -Be 'Contoso.Intranet / Contoso.Intranet.Big: 2 receiver(s) on 1 list(s), first /sites/team/Lists/Tasks; Contoso.Intranet / Contoso.Intranet.Small: 1 receiver(s) on 1 list(s), first /sites/team/Lists/Tasks'
    }

    It 'gives five examples at most, and a row for each class' {
        $receiver = 1..7 | ForEach-Object { New-TestReceiver -Class ('Contoso.Intranet.C{0}' -f $_) }
        $list = New-TestList -Receiver $receiver

        $result = Get-Signal -Site (New-TestSite -Web @((New-TestWeb -List @($list))))

        @($result.Signals.EventReceiverClasses) | Should -HaveCount 7
        @($result.Signals.EventReceiverExamples -split '; ') | Should -HaveCount 5
    }

    It 'gives no row and no example when the receivers are Microsoft ones, or there is none' -ForEach @(
        @{ Case = 'no receiver'; Kind = 'none' }
        @{ Case = 'Microsoft receivers'; Kind = 'microsoft' }
        @{ Case = 'a receiver with no assembly'; Kind = 'unknown' }
    ) {
        $receiver = switch ($Kind) {
            'none' { @() }
            'microsoft' { @((New-TestReceiver -Assembly $script:Native -Class 'Microsoft.SharePoint.Native')) }
            'unknown' { @((New-TestReceiver -Assembly '' -Class 'Remote')) }
        }
        $list = New-TestList -Receiver $receiver

        $result = Get-Signal -Site (New-TestSite -Web @((New-TestWeb -List @($list))))

        $result.Signals.EventReceivers | Should -Be 0 -Because $Case
        @($result.Signals.EventReceiverClasses) | Should -HaveCount 0
        $result.Signals.EventReceiverExamples | Should -Be ''
    }

    It 'says NotChecked, and names no solution, when no package was inspected' {
        $list = New-TestList -Receiver @((New-TestReceiver))

        $row = @((Get-Signal -Site (New-TestSite -Web @((New-TestWeb -List @($list))))).Signals.EventReceiverClasses)

        $row[0].SolutionMatch | Should -BeExactly 'NotChecked'
        $row[0].FarmSolutionName | Should -Be ''
    }

    It 'names the farm solution that ships the assembly when the packages were inspected, in the rows and in the examples' {
        $index = New-Index @(
            [PSCustomObject]@{ PackageName = 'Contoso.Intranet.wsp'; FarmSolutionName = 'contoso.intranet.wsp'; Assemblies = @([PSCustomObject]@{ Name = 'Contoso.Intranet'; PublicKeyToken = '0123456789abcdef'; Version = '1.0.0.0'; IsSatellite = $false; IsManaged = $true }) }
        )
        $list = New-TestList -Receiver @((New-TestReceiver), (New-TestReceiver -Assembly $script:Fabrikam -Class 'Fabrikam.Docs.Receiver'))

        $result = Get-Signal -Site (New-TestSite -Web @((New-TestWeb -List @($list)))) -Index $index

        $row = @($result.Signals.EventReceiverClasses)
        $contoso = @($row | Where-Object { $_.AssemblyName -eq 'Contoso.Intranet' })[0]
        $contoso.SolutionMatch | Should -BeExactly 'AssemblyNameAndKey'
        $contoso.FarmSolutionName | Should -Be 'contoso.intranet.wsp'
        $contoso.PackageName | Should -Be 'Contoso.Intranet.wsp'
        $fabrikam = @($row | Where-Object { $_.AssemblyName -eq 'Fabrikam.Docs' })[0]
        $fabrikam.SolutionMatch | Should -BeExactly 'None'
        $result.Signals.EventReceiverExamples | Should -Match 'Contoso\.Intranet / Contoso\.Intranet\.ItemReceiver: 1 receiver\(s\) on 1 list\(s\), first /sites/team/Lists/Tasks \(solution contoso\.intranet\.wsp\)'
        $result.Signals.EventReceiverExamples | Should -Match 'Fabrikam\.Docs / Fabrikam\.Docs\.Receiver: 1 receiver\(s\) on 1 list\(s\), first /sites/team/Lists/Tasks$'
    }

    It 'keeps the count exact, leaves the site complete and warns once when it has more than 200 assemblies and classes' {
        $receiver = 1..205 | ForEach-Object { New-TestReceiver -Class ('Contoso.Intranet.C{0:000}' -f $_) }
        $list = New-TestList -Receiver $receiver

        $result = Get-Signal -Site (New-TestSite -Web @((New-TestWeb -List @($list))))

        $result.Signals.EventReceivers | Should -Be 205
        @($result.Signals.EventReceiverClasses) | Should -HaveCount 200
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
        $result.Warnings | Should -HaveCount 1
        $result.Warnings[0] | Should -Match "Event receiver rows stopped after 200 assemblies and classes on site 'https://intranet\.contoso\.com/sites/team'; EventReceivers stays exact\."
    }

    It 'keeps counting the classes that have a row after the limit, and does not warn at the limit' {
        $receiver = @(1..200 | ForEach-Object { New-TestReceiver -Class ('Contoso.Intranet.C{0:000}' -f $_) }) + @(New-TestReceiver -Class 'Contoso.Intranet.C001')
        $list = New-TestList -Receiver $receiver

        $result = Get-Signal -Site (New-TestSite -Web @((New-TestWeb -List @($list))))

        @($result.Signals.EventReceiverClasses) | Should -HaveCount 200
        @($result.Signals.EventReceiverClasses | Where-Object { $_.Class -eq 'Contoso.Intranet.C001' })[0].ReceiverCount | Should -Be 2
        $result.Warnings | Should -HaveCount 0
    }

    It 'keeps the signal and the other counts when the detail cannot be built, and warns with the reason' -ForEach @(
        @{ Detail = 'ConvertTo-SPSEventReceiverClassRow' }
        @{ Detail = 'Get-SPSEventReceiverExample' }
    ) {
        Mock -ModuleName SPSSiteInventory.Common -CommandName $Detail -MockWith { throw 'The detail failed.' }
        $list = New-TestList -Receiver @((New-TestReceiver), (New-TestReceiver -Type 'ItemUpdated'))

        $result = Get-Signal -Site (New-TestSite -Web @((New-TestWeb -List @($list))))

        $result.Signals.EventReceivers | Should -Be 2
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
        @($result.Signals.EventReceiverClasses) | Should -HaveCount 0
        $result.Signals.EventReceiverExamples | Should -BeExactly ''
        $result.Warnings | Should -HaveCount 1
        $result.Warnings[0] | Should -Match "The event receivers of site 'https://intranet\.contoso\.com/sites/team' could not be listed by assembly and class: The detail failed\.; EventReceivers stays exact\."
    }

    It 'gives the rows of a site collection its own URL' {
        $list = New-TestList -Receiver @((New-TestReceiver))

        $row = @((Get-Signal -Site (New-TestSite -Web @((New-TestWeb -List @($list))))).Signals.EventReceiverClasses)

        $row[0].SiteUrl | Should -Be 'https://intranet.contoso.com/sites/team'
    }
}
