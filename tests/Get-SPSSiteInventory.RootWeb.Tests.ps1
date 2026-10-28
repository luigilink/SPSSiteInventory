# Behavior tests for the root web of Get-SPSSiteInventory, with a root web whose getters raise the error
# that SharePoint raises for a site collection locked with NoAccess. A PSCustomObject cannot reproduce it:
# PowerShell turns the exception of a .NET property getter into $null, which is how such a site collection
# was reported with the template '#' and the language 0.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    function global:Get-SPWebApplication { throw 'Unmocked SharePoint call' }

    if (-not ('SPSRootWebTestWeb' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public sealed class SPSRootWebTestWeb
{
    public string TitleValue = "Team";
    public string WebTemplateValue = "STS";
    public int ConfigurationValue = 0;
    public uint LanguageValue = 1033;
    public DateTime LastItemModifiedDateValue = new DateTime(2026, 1, 1);
    // The names of the properties whose getter raises the error of a NoAccess lock, separated by semicolons.
    public string Failing = "";
    public string ErrorMessage = "Access to this Web site has been blocked. Please contact the administrator to resolve this problem.";

    private void Raise(string name)
    {
        if ((";" + Failing + ";").IndexOf(";" + name + ";", StringComparison.Ordinal) >= 0)
        {
            throw new COMException(ErrorMessage, unchecked((int)0x81020071));
        }
    }

    public string Title { get { Raise("Title"); return TitleValue; } }
    public string WebTemplate { get { Raise("WebTemplate"); return WebTemplateValue; } }
    public int Configuration { get { Raise("Configuration"); return ConfigurationValue; } }
    public uint Language { get { Raise("Language"); return LanguageValue; } }
    public DateTime LastItemModifiedDate { get { Raise("LastItemModifiedDate"); return LastItemModifiedDateValue; } }
    public void Dispose() { }
}
'@
    }

    $script:AllProperties = 'Title;WebTemplate;Configuration;Language;LastItemModifiedDate'

    function New-RootWebSite {
        param ([string]$Failing = '', [string]$WebTemplate = 'STS', [int]$Configuration = 0)
        $root = [SPSRootWebTestWeb]::new()
        $root.Failing = $Failing
        $root.WebTemplateValue = $WebTemplate
        $root.ConfigurationValue = $Configuration
        $site = [PSCustomObject]@{ Url = 'https://intranet.contoso.com/sites/locked'; RootWeb = $root }
        $site | Add-Member -MemberType ScriptProperty -Name ContentDatabase -Value { [PSCustomObject]@{ Name = 'WSS_Content' } }
        $site | Add-Member -MemberType ScriptProperty -Name Usage -Value { [PSCustomObject]@{ Storage = 1GB } }
        $site | Add-Member -MemberType ScriptProperty -Name AllWebs -Value { , @($this.RootWeb) }
        $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        $site
    }

    function Get-Inventory {
        param ([object]$Site)
        $script:webApp = [PSCustomObject]@{ Url = 'https://intranet.contoso.com'; Name = 'Fake'; Sites = @($Site) }
        @(Get-SPSSiteInventory)
    }
}

Describe 'Get-SPSSiteInventory root web' {
    BeforeEach {
        Mock Get-SPWebApplication -ModuleName SPSSiteInventory.Common { $script:webApp }
        Mock Get-SPSWebApplicationAuthentication -ModuleName SPSSiteInventory.Common {
            [PSCustomObject]@{
                AuthenticationModes = 'Windows'; AuthenticationZones = 'Default: Windows'
                HasFbaZone = $false; AuthenticationReviewRequired = $false
            }
        }
        Mock Get-SPSWebApplicationPolicy -ModuleName SPSSiteInventory.Common {
            [PSCustomObject]@{ BrowserFileHandling = 'Strict'; WebAppPolicyCount = 0; WebAppPolicyExamples = ''; Policies = @() }
        }
        Mock Add-SPSInventoryEvent -ModuleName SPSSiteInventory.Common { }
        Mock Write-Progress -ModuleName SPSSiteInventory.Common { }
    }

    It 'leaves the template and the language empty, and does not call them to review, when the root web raises on every property' {
        $record = (Get-Inventory -Site (New-RootWebSite -Failing $script:AllProperties))[0]

        $record.Template | Should -Be ''
        $record.Title | Should -Be ''
        $record.LastModified | Should -BeNullOrEmpty
        $record.TemplateLanguageLcid | Should -BeNullOrEmpty
        $record.TemplateLanguageTag | Should -Be ''
        $record.TemplateCompatibility | Should -Be 'NotCollected'
        $record.TemplateCompatibilityReason | Should -Be 'Template could not be collected.'
        $record.TemplateLanguageReviewRequired | Should -BeNullOrEmpty
        $record.TemplateLanguageReason | Should -Be 'Template language could not be collected.'
        $record.IsUnsupportedSiteTemplate | Should -BeFalse
        # Everything else is still read.
        $record.ContentDb | Should -Be 'WSS_Content'
        $record.SizeGB | Should -Be 1
    }

    It 'says once, with the properties and the error, that the root web could not be read, and marks the inventory partial' {
        $record = (Get-Inventory -Site (New-RootWebSite -Failing $script:AllProperties))[0]

        $record.SiteInventoryComplete | Should -BeFalse
        $record.SiteInventoryWarnings | Should -Match 'Root web metadata could not be fully read \(Title, WebTemplate, Configuration, Language, LastItemModifiedDate\): Access to this Web site has been blocked'
        ([regex]::Matches($record.SiteInventoryWarnings, 'Root web metadata')).Count | Should -Be 1
    }

    It 'reads what it can: a language that cannot be read leaves the template read and the language empty' {
        $record = (Get-Inventory -Site (New-RootWebSite -Failing 'Language'))[0]

        $record.Title | Should -Be 'Team'
        $record.Template | Should -Be 'STS#0'
        $record.TemplateCompatibility | Should -Be 'Compatible'
        $record.LastModified | Should -Be ([datetime]'2026-01-01')
        $record.TemplateLanguageLcid | Should -BeNullOrEmpty
        $record.TemplateLanguageReviewRequired | Should -BeNullOrEmpty
        $record.TemplateLanguageReason | Should -Be 'Template language could not be collected.'
        $record.SiteInventoryComplete | Should -BeFalse
        $record.SiteInventoryWarnings | Should -Match 'could not be fully read \(Language\):'
    }

    It 'reads what it can: a template that cannot be read leaves the language read and the template empty' {
        foreach ($failing in @('WebTemplate', 'Configuration')) {
            $record = (Get-Inventory -Site (New-RootWebSite -Failing $failing))[0]

            $record.Template | Should -Be '' -Because $failing
            $record.TemplateCompatibility | Should -Be 'NotCollected' -Because $failing
            $record.TemplateLanguageLcid | Should -Be 1033 -Because $failing
            $record.TemplateLanguageTag | Should -Be 'en-US' -Because $failing
            $record.TemplateLanguageReviewRequired | Should -BeFalse -Because $failing
            $record.SiteInventoryWarnings | Should -Match "could not be fully read \($failing\):" -Because $failing
        }
    }

    It 'does not change the record of a root web that can be read' {
        $record = (Get-Inventory -Site (New-RootWebSite))[0]

        $record.Title | Should -Be 'Team'
        $record.Template | Should -Be 'STS#0'
        $record.TemplateCompatibility | Should -Be 'Compatible'
        $record.TemplateLanguageLcid | Should -Be 1033
        $record.TemplateLanguageTag | Should -Be 'en-US'
        $record.TemplateLanguageReviewRequired | Should -BeFalse
        $record.SiteInventoryComplete | Should -BeTrue
        $record.SiteInventoryWarnings | Should -Be ''
    }

    It 'still calls a template that is read and mapped to Review one to review' {
        $record = (Get-Inventory -Site (New-RootWebSite -WebTemplate 'BLOG'))[0]

        $record.Template | Should -Be 'BLOG#0'
        $record.TemplateCompatibility | Should -Be 'Review'
    }

    It 'raises neither template alert for the record of an unreadable root web, and still raises the one of the partial assessment' {
        $unreadable = (Get-Inventory -Site (New-RootWebSite -Failing $script:AllProperties))[0]
        $blog = (Get-Inventory -Site (New-RootWebSite -WebTemplate 'BLOG'))[0]
        $module = Get-Module -Name SPSSiteInventory.Common

        $unreadable | Add-Member -NotePropertyName AssessmentStatus -NotePropertyValue 'Partial' -Force
        $unreadable | Add-Member -NotePropertyName AssessmentWarnings -NotePropertyValue $unreadable.SiteInventoryWarnings -Force
        $blog | Add-Member -NotePropertyName AssessmentStatus -NotePropertyValue 'Complete' -Force

        $unreadableAlerts = @(& $module { param ($Record) Get-SPSInventoryAlert -InputObject @($Record) } $unreadable)
        $types = @($unreadableAlerts | ForEach-Object { $_.AlertType })
        $types | Should -Not -Contain 'TemplateCompatibilityReview'
        $types | Should -Not -Contain 'TemplateLanguageReview'
        $types | Should -Contain 'AssessmentPartial'

        $blogAlerts = @(& $module { param ($Record) Get-SPSInventoryAlert -InputObject @($Record) } $blog)
        @($blogAlerts | ForEach-Object { $_.AlertType }) | Should -Contain 'TemplateCompatibilityReview'
    }
}
