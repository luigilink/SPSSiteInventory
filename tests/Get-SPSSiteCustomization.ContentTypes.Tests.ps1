BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    function Get-TestContentType {
        param ([string]$Id, [string]$Name)
        [PSCustomObject]@{
            Id = $Id; Name = $Name; Group = 'Contoso Types'
            Parent = [PSCustomObject]@{ Id = '0x01' }
            Fields = @(
                [PSCustomObject]@{ TypeAsString = 'Text' },
                [PSCustomObject]@{ TypeAsString = 'TaxonomyFieldType' }
            )
            DocumentTemplateUrl = '/templates/document.dotx'
            Hidden = $false; ReadOnly = $false; Sealed = $false
        }
    }

    function Get-TestWeb {
        param ([object[]]$Definitions, [object[]]$Bindings)
        $list = [PSCustomObject]@{
            Title = 'Documents'
            RootFolder = [PSCustomObject]@{
                ServerRelativeUrl = '/sites/team/Documents'
                Properties = @{}
            }
            ContentTypes = $Bindings
            WorkflowAssociations = @()
            EventReceivers = @()
            BaseTemplate = 101
        }
        $web = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            ContentTypes = $Definitions
            Lists = @($list)
            WorkflowAssociations = @()
            HasUniqueRoleAssignments = $false
            CustomMasterUrl = ''
        }
        $web | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        return $web
    }
}

Describe 'Get-SPSSiteCustomization content types' {
    It 'records web definitions and list bindings without declaring them custom' {
        $definition = Get-TestContentType -Id '0x0101' -Name 'Document & Notes'
        $binding = Get-TestContentType -Id '0x010100AAAA' -Name 'Document & Notes'
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Solutions = @()
            AllWebs = @(Get-TestWeb -Definitions @($definition) -Bindings @($binding))
        }

        $signals = Get-SPSSiteCustomization -Site $site

        $signals.ContentTypeCount | Should -Be 1
        $signals.ListContentTypeBindingCount | Should -Be 1
        $signals.ContentTypeInventoryComplete | Should -BeTrue
        $signals.ContentTypes | Should -HaveCount 2
        $signals.ContentTypes[0].FieldCount | Should -Be 2
        $signals.ContentTypes[0].FieldTypes | Should -Be 'TaxonomyFieldType; Text'
        $signals.ContentTypes[0].ParentContentTypeId | Should -Be '0x01'
        $signals.ContentTypes[1].ListUrl | Should -Be '/sites/team/Documents'
        $signals.ContentTypes[1].ContentTypeId | Should -Be '0x010100AAAA'
        $signals.Keys | Should -Not -Contain 'UsesCustomContentType'
    }

    It 'marks a partial read explicitly and retains the data collected elsewhere' {
        $definition = Get-TestContentType -Id '0x0101' -Name 'Document'
        $web = Get-TestWeb -Definitions @($definition) -Bindings @()
        $badBinding = Get-TestContentType -Id '' -Name 'Unreadable'
        $web.Lists[0].ContentTypes = @($badBinding)
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningAction SilentlyContinue

        $signals.ContentTypeInventoryComplete | Should -BeFalse
        $signals.ContentTypeCount | Should -Be 1
        $signals.ListContentTypeBindingCount | Should -Be 0
        $signals.ContentTypes | Should -HaveCount 1
    }

    It 'marks unreadable field metadata as partial rather than exporting zero fields' {
        $definition = Get-TestContentType -Id '0x0101' -Name 'Document'
        $definition | Add-Member -MemberType ScriptProperty -Name Fields -Value { throw 'Access denied' } -Force
        $binding = Get-TestContentType -Id '0x010100AAAA' -Name 'Document'
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Solutions = @()
            AllWebs = @(Get-TestWeb -Definitions @($definition) -Bindings @($binding))
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningVariable warnings -WarningAction SilentlyContinue

        $signals.ContentTypeInventoryComplete | Should -BeFalse
        $signals.ContentTypeCount | Should -Be 0
        $signals.ListContentTypeBindingCount | Should -Be 1
        $signals.ContentTypes | Should -HaveCount 1
        $signals.ContentTypes[0].FieldCount | Should -Be 2
        ($warnings -join ';') | Should -Match 'Content-type definitions could not be fully read'
    }

    It 'marks null field metadata as partial' {
        $definition = Get-TestContentType -Id '0x0101' -Name 'Document'
        $definition.Fields = $null
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Solutions = @()
            AllWebs = @(Get-TestWeb -Definitions @($definition) -Bindings @())
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningAction SilentlyContinue

        $signals.ContentTypeInventoryComplete | Should -BeFalse
        $signals.ContentTypes | Should -HaveCount 0
    }

    It 'marks missing web definitions as partial while retaining list bindings' {
        $binding = Get-TestContentType -Id '0x010100AAAA' -Name 'Document'
        $web = Get-TestWeb -Definitions @() -Bindings @($binding)
        $web.ContentTypes = $null
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningAction SilentlyContinue

        $signals.ContentTypeInventoryComplete | Should -BeFalse
        $signals.ContentTypeCount | Should -Be 0
        $signals.ListContentTypeBindingCount | Should -Be 1
        $signals.ContentTypes | Should -HaveCount 1
    }

    It 'marks a throwing list ContentTypes getter as partial while retaining definitions' {
        $definition = Get-TestContentType -Id '0x0101' -Name 'Document'
        $web = Get-TestWeb -Definitions @($definition) -Bindings @()
        $web.Lists[0] | Add-Member -MemberType ScriptProperty -Name ContentTypes -Value { throw 'Access denied' } -Force
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            Solutions = @()
            AllWebs = @($web)
        }

        $signals = Get-SPSSiteCustomization -Site $site -WarningAction SilentlyContinue

        $signals.ContentTypeInventoryComplete | Should -BeFalse
        $signals.ContentTypeCount | Should -Be 1
        $signals.ListContentTypeBindingCount | Should -Be 0
        $signals.ContentTypes | Should -HaveCount 1
    }
}
