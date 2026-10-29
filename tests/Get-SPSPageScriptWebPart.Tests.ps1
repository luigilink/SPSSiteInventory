# Behavior tests for Get-SPSPageScriptWebPart (reading the web parts of a page, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function Get-PageKind {
        param ($File)
        & $script:Module { param ($Page) Get-SPSPageScriptWebPart -File $Page } $File
    }

    function New-TestWebPart {
        param ([string]$TypeName, $Content = $null)
        $webPart = [PSCustomObject]@{ Title = 'Part'; Content = $Content; ContentLink = $null }
        $webPart.PSObject.TypeNames.Insert(0, $TypeName)
        return $webPart
    }

    # A page whose web part manager records how it was opened and disposed.
    function New-TestPage {
        param ($WebParts = @(), [switch]$NoManager, [switch]$NoWebParts)
        $state = @{ Scope = $null; ManagerDisposed = 0; WebDisposed = 0 }
        $webOfManager = [PSCustomObject]@{ State = $state }
        $webOfManager | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.State.WebDisposed++ }
        $manager = [PSCustomObject]@{ WebParts = $WebParts; Web = $webOfManager; State = $state }
        if ($NoWebParts) { $manager.WebParts = $null }
        $manager | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.State.ManagerDisposed++ }
        $page = [PSCustomObject]@{ State = $state; Manager = $manager }
        if ($NoManager) { $page.Manager = $null }
        $page | Add-Member -MemberType ScriptMethod -Name GetLimitedWebPartManager -Value {
            param ($Scope)
            $this.State.Scope = $Scope
            return $this.Manager
        }
        return $page
    }
}

Describe 'Get-SPSPageScriptWebPart' {
    It 'lists the Script Editor and Content Editor web parts of the page, and no other one' {
        $page = New-TestPage -WebParts @(
            (New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.XsltListViewWebPart')
            (New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.ScriptEditorWebPart' -Content '<script>a()</script>')
            (New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.ContentEditorWebPart' -Content '<p>text only</p>')
            (New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.ContentEditorWebPart' -Content '<script>b()</script>')
        )

        $kinds = @(Get-PageKind -File $page)

        $kinds | Should -HaveCount 2
        $kinds[0] | Should -Be 'Script Editor'
        $kinds[1] | Should -Be 'Content Editor'
    }

    It 'reads the shared view of the page' {
        $page = New-TestPage
        $null = Get-PageKind -File $page
        $page.State.Scope | Should -Be 'Shared'
    }

    It 'returns nothing for a page without web parts, such as a modern page' {
        $page = New-TestPage -WebParts @()
        @(Get-PageKind -File $page) | Should -HaveCount 0
    }

    It 'disposes of the web part manager and of its web' {
        $page = New-TestPage -WebParts @((New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.ScriptEditorWebPart'))
        $null = Get-PageKind -File $page
        $page.State.ManagerDisposed | Should -Be 1
        $page.State.WebDisposed | Should -Be 1
    }

    It 'rejects a manager that is unavailable, instead of taking the page for one without script' {
        $page = New-TestPage -NoManager
        { Get-PageKind -File $page } | Should -Throw '*web part manager is unavailable*'
    }

    It 'rejects a web part collection that is unavailable, and still disposes of the manager and its web' {
        $page = New-TestPage -NoWebParts
        { Get-PageKind -File $page } | Should -Throw '*web part collection is unavailable*'
        $page.State.ManagerDisposed | Should -Be 1
        $page.State.WebDisposed | Should -Be 1
    }

    It 'disposes of the manager and its web when a web part cannot be read' {
        $broken = New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.ContentEditorWebPart'
        $broken | Add-Member -MemberType NoteProperty -Name Dummy -Value 1
        $page = New-TestPage -WebParts @($broken)
        Mock -ModuleName SPSSiteInventory.Common Get-SPSScriptWebPartKind { throw 'part unreadable' }

        { Get-PageKind -File $page } | Should -Throw '*part unreadable*'
        $page.State.ManagerDisposed | Should -Be 1
        $page.State.WebDisposed | Should -Be 1
    }

    It 'does not fail when the manager has nothing to dispose of' {
        $page = New-TestPage -WebParts @()
        $page.Manager.PSObject.Methods.Remove('Dispose')
        $page.Manager.PSObject.Properties.Remove('Web')

        { Get-PageKind -File $page } | Should -Not -Throw
    }
}
