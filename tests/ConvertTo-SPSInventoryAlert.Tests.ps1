# Behavior tests for ConvertTo-SPSInventoryAlert (no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    # ConvertTo-SPSInventoryAlert is private; reach it inside the module scope.
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function New-Alert {
        param ([hashtable]$Parameters)
        & $script:Module { param ($Splat) ConvertTo-SPSInventoryAlert @Splat } $Parameters
    }
}

Describe 'ConvertTo-SPSInventoryAlert' {
    It 'takes the severity, message, remediation and reference from the catalog' {
        $catalog = & $script:Module { Get-SPSAlertCatalog }

        $alert = New-Alert -Parameters @{ AlertType = 'InfoPath'; Url = 'https://intranet/sites/hr'; Value = 3 }

        $alert.AlertType | Should -Be 'InfoPath'
        $alert.Severity | Should -Be $catalog['InfoPath'].Severity
        $alert.Url | Should -Be 'https://intranet/sites/hr'
        $alert.Value | Should -Be 3
        $alert.Message | Should -Be $catalog['InfoPath'].Message
        $alert.Remediation | Should -Be $catalog['InfoPath'].Remediation
        $alert.Reference | Should -Be $catalog['InfoPath'].Reference
    }

    It 'keeps a stable property order for the alert files' {
        $alert = New-Alert -Parameters @{ AlertType = 'InfoPath'; Url = 'u'; Value = 1 }

        ($alert.PSObject.Properties.Name -join ',') | Should -Be 'AlertType,Severity,Url,Value,Message,Remediation,Reference'
    }

    It 'replaces the catalog message only when a specific message is given' {
        $catalog = & $script:Module { Get-SPSAlertCatalog }

        (New-Alert -Parameters @{ AlertType = 'UnsupportedSiteTemplate'; Url = 'u'; Value = 'APP#0'; Message = 'App webs are not migration targets.' }).Message | Should -Be 'App webs are not migration targets.'
        (New-Alert -Parameters @{ AlertType = 'UnsupportedSiteTemplate'; Url = 'u'; Value = 'APP#0'; Message = '' }).Message | Should -Be $catalog['UnsupportedSiteTemplate'].Message
        (New-Alert -Parameters @{ AlertType = 'UnsupportedSiteTemplate'; Url = 'u'; Value = 'APP#0'; Message = '   ' }).Message | Should -Be $catalog['UnsupportedSiteTemplate'].Message
        (New-Alert -Parameters @{ AlertType = 'UnsupportedSiteTemplate'; Url = 'u'; Value = 'APP#0' }).Message | Should -Be $catalog['UnsupportedSiteTemplate'].Message
    }

    It 'keeps the remediation of the catalog when the message is replaced' {
        $catalog = & $script:Module { Get-SPSAlertCatalog }

        (New-Alert -Parameters @{ AlertType = 'TemplateLanguageReview'; Url = 'u'; Value = 1036; Message = 'LCID 1036 is outside the list.' }).Remediation | Should -Be $catalog['TemplateLanguageReview'].Remediation
    }

    It 'accepts a missing URL or value' {
        $alert = New-Alert -Parameters @{ AlertType = 'BcsInventoryPartial'; Url = $null; Value = $null }

        $alert.Url | Should -BeNullOrEmpty
        $alert.Value | Should -BeNullOrEmpty
    }

    It 'rejects an alert type that is not in the catalog' {
        { New-Alert -Parameters @{ AlertType = 'Nonexistent'; Url = 'u'; Value = 1 } } | Should -Throw "*'Nonexistent' is not in the alert catalog*"
    }

    It 'takes the severity and the words of the catalog of the target mode' {
        $default = & $script:Module { Get-SPSAlertCatalog }
        $onPrem = & $script:Module { Get-SPSAlertCatalog -TargetMode 'SharePointOnPrem' }

        $online = New-Alert -Parameters @{ AlertType = 'ExternalLists'; Url = 'u'; Value = 2; TargetMode = 'SharePointOnline' }
        $local = New-Alert -Parameters @{ AlertType = 'ExternalLists'; Url = 'u'; Value = 2; TargetMode = 'SharePointOnPrem' }

        $online.Severity | Should -Be 'High'
        $online.Message | Should -Be $default['ExternalLists'].Message
        $local.Severity | Should -Be 'Low'
        $local.Message | Should -Be $onPrem['ExternalLists'].Message
        $local.Remediation | Should -Be $onPrem['ExternalLists'].Remediation
        $local.Reference | Should -Be $onPrem['ExternalLists'].Reference
    }

    It 'is the default mode when the mode is not given' {
        $without = New-Alert -Parameters @{ AlertType = 'FullTrustCode'; Url = 'u'; Value = $true }
        $with = New-Alert -Parameters @{ AlertType = 'FullTrustCode'; Url = 'u'; Value = $true; TargetMode = 'SharePointOnline' }

        ($with | ConvertTo-Json) | Should -Be ($without | ConvertTo-Json)
        $without.Severity | Should -Be 'High'
    }

    It 'puts the words of the mode before a specific message too, for the alerts that are only about a migration' {
        $onPrem = New-Alert -Parameters @{ AlertType = 'UnsupportedSiteTemplate'; Url = 'u'; Value = 'APP#0'; Message = 'App webs are not targets.'; TargetMode = 'SharePointOnPrem' }
        $online = New-Alert -Parameters @{ AlertType = 'UnsupportedSiteTemplate'; Url = 'u'; Value = 'APP#0'; Message = 'App webs are not targets.' }

        $onPrem.Message | Should -Be 'Migration to SharePoint Online only. App webs are not targets.'
        $onPrem.Severity | Should -Be 'Low'
        $online.Message | Should -Be 'App webs are not targets.'
    }

    It 'keeps the specific message as it is for an alert that matters for the modernization' {
        (New-Alert -Parameters @{ AlertType = 'InfoPath'; Url = 'u'; Value = 1; Message = 'Specific.'; TargetMode = 'SharePointOnPrem' }).Message | Should -Be 'Specific.'
    }

    It 'rejects a target mode that is not one of the two, and an alert type that is not in the catalog of the mode' {
        { New-Alert -Parameters @{ AlertType = 'InfoPath'; Url = 'u'; Value = 1; TargetMode = 'Online' } } | Should -Throw "*TargetMode must be 'SharePointOnline' or 'SharePointOnPrem'*"
        { New-Alert -Parameters @{ AlertType = 'Nonexistent'; Url = 'u'; Value = 1; TargetMode = 'SharePointOnPrem' } } | Should -Throw "*'Nonexistent' is not in the alert catalog*"
    }
}
