# Behavior tests for the customized profile page signal of Get-SPSSiteCustomization: the Person.aspx of a My Site host that was edited,
# which SharePoint Online cannot reproduce. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    function global:Get-SPAppInstance {
        param($Web)
        @()
    }

    $script:User = [PSCustomObject]@{ LoginName = 'CONTOSO\owner' }
    $script:System = [PSCustomObject]@{ LoginName = 'SHAREPOINT\system' }

    function New-TestFile {
        param ([string]$Url, $Status = 2, $ModifiedBy = $script:User)
        [PSCustomObject]@{ ServerRelativeUrl = $Url; CustomizedPageStatus = $Status; ModifiedBy = $ModifiedBy }
    }

    function New-TestSite {
        param ([object[]]$File = @(), [string]$Template = 'SPSMSITEHOST', [bool]$IsRootWeb = $true, [switch]$WithoutTemplate)
        $web = [PSCustomObject]@{
            Url = 'https://my.contoso.com'
            ContentTypes = @(); Lists = @(); WorkflowAssociations = @(); HasUniqueRoleAssignments = $false
            CustomMasterUrl = ''; Features = @(); Files = $File; IsRootWeb = $IsRootWeb; HasUniqueRoleDefinitions = $true
            RoleDefinitions = @(); Alerts = @(); AlternateCssUrl = ''; RootFolder = [PSCustomObject]@{ WelcomePage = '' }
        }
        if (-not $WithoutTemplate) {
            $web | Add-Member -NotePropertyName WebTemplate -NotePropertyValue $Template
        }
        $web | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        [PSCustomObject]@{ Url = 'https://my.contoso.com'; Features = @(); Solutions = @(); AllWebs = @($web) }
    }

    function Get-Signal {
        param ($Site)
        $warnings = @()
        $signals = Get-SPSSiteCustomization -Site $Site -WarningVariable warnings -WarningAction SilentlyContinue
        [PSCustomObject]@{ Signals = $signals; Warnings = @($warnings | ForEach-Object { [string]$_ }) }
    }
}

Describe 'Get-SPSSiteCustomization customized profile page' {
    It 'counts the customized Person.aspx at the root of the root web of a My Site host, and gives its address' {
        $result = Get-Signal -Site (New-TestSite -File @((New-TestFile '/Person.aspx')))

        $result.Signals.CustomizedProfilePageCount | Should -Be 1
        $result.Signals.CustomizedProfilePageExamples | Should -Be '/Person.aspx'
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
    }

    It 'counts it as a customized page too, with the other customized pages, and the page that is not the profile page is only a customized page' {
        $result = Get-Signal -Site (New-TestSite -File @((New-TestFile '/Person.aspx'), (New-TestFile '/default.aspx'), (New-TestFile '/Other/Person.aspx.bak')))

        $result.Signals.CustomizedPageCount | Should -Be 3
        $result.Signals.CustomizedProfilePageCount | Should -Be 1
        $result.Signals.CustomizedProfilePageExamples | Should -Be '/Person.aspx'
    }

    It 'takes the name of the page whatever its case, and a path in front of it' {
        $result = Get-Signal -Site (New-TestSite -File @((New-TestFile '/my/person.ASPX')))

        $result.Signals.CustomizedProfilePageCount | Should -Be 1
        $result.Signals.CustomizedProfilePageExamples | Should -Be '/my/person.ASPX'
    }

    It 'does not count a profile page that is not customized, or that the System Account edited' -ForEach @(
        @{ Name = 'ghosted'; Status = 1; User = 'user' }
        @{ Name = 'no status'; Status = 0; User = 'user' }
        @{ Name = 'edited by the System Account'; Status = 2; User = 'system' }
    ) {
        $by = if ($User -eq 'system') { $script:System } else { $script:User }

        $result = Get-Signal -Site (New-TestSite -File @((New-TestFile '/Person.aspx' -Status $Status -ModifiedBy $by)))

        $result.Signals.CustomizedProfilePageCount | Should -Be 0 -Because $Name
        $result.Signals.CustomizedProfilePageExamples | Should -Be ''
    }

    It 'does not count a Person.aspx on a site collection that is not a My Site host, or on a web that is not the root web' -ForEach @(
        @{ Name = 'a team site'; Template = 'STS'; IsRootWeb = $true }
        @{ Name = 'a personal site'; Template = 'SPSPERS'; IsRootWeb = $true }
        @{ Name = 'a subsite of a My Site host'; Template = 'SPSMSITEHOST'; IsRootWeb = $false }
    ) {
        $result = Get-Signal -Site (New-TestSite -File @((New-TestFile '/Person.aspx')) -Template $Template -IsRootWeb $IsRootWeb)

        $result.Signals.CustomizedProfilePageCount | Should -Be 0 -Because $Name
        $result.Signals.CustomizedPageCount | Should -Be 1
    }

    It 'does not count it when the web has no template to read, and does not make the collection partial for that' {
        $result = Get-Signal -Site (New-TestSite -File @((New-TestFile '/Person.aspx')) -WithoutTemplate)

        $result.Signals.CustomizedProfilePageCount | Should -Be 0
        $result.Signals.CustomizationInventoryComplete | Should -BeTrue
    }

    It 'marks the collection partial when the status of the page cannot be read, instead of taking it for a profile page that is not customized' {
        $result = Get-Signal -Site (New-TestSite -File @((New-TestFile '/Person.aspx' -Status $null)))

        $result.Signals.CustomizedProfilePageCount | Should -Be 0
        $result.Signals.CustomizationInventoryComplete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "Could not read the customized page status of '/Person.aspx'"
    }

    It 'has no customized profile page, without a warning, in a site collection without files at the root' {
        $result = Get-Signal -Site (New-TestSite)

        $result.Signals.CustomizedProfilePageCount | Should -Be 0
        $result.Signals.CustomizedProfilePageExamples | Should -Be ''
        $result.Warnings | Should -HaveCount 0
    }
}
