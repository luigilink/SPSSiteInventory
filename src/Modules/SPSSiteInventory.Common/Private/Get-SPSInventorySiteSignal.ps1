function Get-SPSInventorySiteSignal {
    <#
        .SYNOPSIS
        Lists the signals that a site collection record raises, for the detail row of the HTML report.

        .DESCRIPTION
        The CSV and JSON files carry one column per signal. The HTML report is meant to be read,
        so it shows a handful of columns for each site collection and, when a row is opened,
        only the signals that the site collection raises: a count above zero, a flag that is
        set, a lock, a review that is required or an inventory that is incomplete. A signal
        that is at zero is left out instead of being repeated on every row.

        Each signal has a Label, a Value (a number, Yes, or a short text) and a Detail (the
        examples or the reason that go with it, or an empty string). The signals come in a fixed
        order: template and lock first, then code and customization, identity, workflows,
        content, volume and finally the completeness of the inventory.

        Signals that belong to a whole web application (the policies and the authentication
        modes) are not listed: the web application sections of the report show them once.

        Private because it is an implementation detail of the HTML report. The result can be
        empty: wrap the call in @() to get an array.

        .PARAMETER Record
        The scored inventory record of a site collection.

        .EXAMPLE
        Get-SPSInventorySiteSignal -Record $record | Format-Table Label, Value, Detail
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [System.Object]
        $Record
    )

    if ($null -eq $Record) {
        return
    }

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $signals = [System.Collections.Generic.List[System.Object]]::new()

    $isRaised = {
        param($Value)
        if ($null -eq $Value) { return $false }
        if ($Value -is [System.Boolean]) { return $Value }
        if ($Value -is [System.String]) {
            $text = $Value.Trim()
            if ($text.Length -eq 0 -or $text.Equals('false', [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
            $parsed = 0.0
            if ([double]::TryParse($text, [System.Globalization.NumberStyles]::Float, $invariant, [ref]$parsed)) { return $parsed -ne 0 }
            return $true
        }
        return (ConvertTo-SPSSignalNumber -Value $Value) -ne 0
    }
    $number = {
        param($Value)
        if ($null -eq $Value -or $Value -is [System.Boolean]) { return 0 }
        return ConvertTo-SPSSignalNumber -Value $Value
    }
    $formatNumber = {
        param([System.Double]$Value)
        if ($Value -eq [math]::Floor($Value)) { return ([System.Int64]$Value).ToString($invariant) }
        return $Value.ToString('0.##', $invariant)
    }
    $add = {
        param([System.String]$Label, [System.String]$Value, [System.String]$Detail)
        $signals.Add([PSCustomObject]@{ Label = $Label; Value = $Value; Detail = $Detail })
    }
    $flag = {
        param([System.String]$Name, [System.String]$Label, [System.String]$DetailName)
        if (& $isRaised $Record.$Name) {
            $detail = if ($DetailName) { [string]$Record.$DetailName } else { '' }
            & $add $Label 'Yes' $detail
        }
    }
    $count = {
        param([System.String]$Name, [System.String]$Label, [System.String]$DetailName)
        $value = & $number $Record.$Name
        if ($value -gt 0) {
            $detail = if ($DetailName) { [string]$Record.$DetailName } else { '' }
            & $add $Label (& $formatNumber $value) $detail
        }
    }

    # Template, language and lock.
    $compatibility = [string]$Record.TemplateCompatibility
    if (& $isRaised $Record.IsUnsupportedSiteTemplate) {
        & $add 'Unsupported template' ([string]$Record.Template) ([string]$Record.TemplateCompatibilityReason)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($compatibility) -and $compatibility -ne 'Compatible') {
        & $add 'Template compatibility' $compatibility ([string]$Record.TemplateCompatibilityReason)
    }
    if (& $isRaised $Record.TemplateLanguageReviewRequired) {
        $language = [string]$Record.TemplateLanguageTag
        if ([string]::IsNullOrWhiteSpace($language) -and $null -ne $Record.TemplateLanguageLcid) {
            $language = 'LCID {0}' -f $Record.TemplateLanguageLcid
        }
        & $add 'Template language review' $language ([string]$Record.TemplateLanguageReason)
    }
    $lockState = [string]$Record.SiteLockState
    if ([string]::IsNullOrWhiteSpace($lockState)) {
        if (& $isRaised $Record.HasNoAccessLock) { $lockState = 'NoAccess' }
        elseif (& $isRaised $Record.IsLockedSite) { $lockState = 'Locked' }
    }
    if (-not [string]::IsNullOrWhiteSpace($lockState) -and $lockState -ne 'Unlock') {
        & $add 'Site lock' $lockState ''
    }

    # Code and customization.
    & $flag 'UsesFullTrustCode' 'Full-trust code' ''
    & $flag 'UsesCustomFarmFeature' 'Custom farm feature' ''
    & $count 'SandboxSolutions' 'Sandbox solutions' ''
    & $count 'EventReceivers' 'Custom event receivers' ''
    & $flag 'CustomMasterPage' 'Custom master page' ''
    & $count 'AlternateCssUrlCount' 'Alternate CSS URL (webs)' 'AlternateCssUrlExamples'
    & $count 'XsltListViewCount' 'XSLT list views' 'XsltListViewExamples'
    & $count 'ScriptWebPartCount' 'Script web parts' 'ScriptWebPartExamples'
    & $count 'ClassicExperienceOptOutCount' 'Opted out of modern lists' 'ClassicExperienceOptOutExamples'
    & $count 'ClassicExperienceListCount' 'Lists forced to classic' 'ClassicExperienceListExamples'
    & $count 'CustomizedPageCount' 'Customized pages' 'CustomizedPageExamples'
    & $count 'AppInstanceCount' 'App instances' 'AppInstanceExamples'
    & $count 'AppWebCount' 'App webs' ''

    # Identity: an unknown FBA state is not a No.
    if (& $isRaised $Record.HasFbaZone) {
        & $add 'FBA configured' 'Yes' ''
    }
    elseif ($null -eq $Record.HasFbaZone -and $null -ne $Record.PSObject.Properties['HasFbaZone']) {
        & $add 'FBA configured' 'Unknown' ''
    }

    # Workflows, forms and rights management.
    foreach ($version in @('2010', '2013')) {
        $workflowCount = & $number $Record.("Workflow${version}Count")
        $runningCount = & $number $Record.("Workflow${version}RunningInstanceCount")
        if ($workflowCount -gt 0 -or $runningCount -gt 0) {
            $parts = @()
            if ($workflowCount -gt 0) { $parts += '{0} workflow(s)' -f (& $formatNumber $workflowCount) }
            if ($runningCount -gt 0) { $parts += '{0} running instance(s)' -f (& $formatNumber $runningCount) }
            & $add ('Workflow {0}' -f $version) ($parts -join ', ') ''
        }
    }
    & $count 'InfoPathFormCount' 'InfoPath forms' ''
    & $count 'IrmEnabledListCount' 'IRM-enabled lists' ''

    # Content.
    & $flag 'PublishingInfrastructureEnabled' 'Publishing infrastructure' ''
    & $count 'PublishingWebCount' 'Publishing webs' ''
    & $count 'PublishingPageCount' 'Publishing pages' ''
    & $count 'PublishingPageLayoutCount' 'Page layouts in use' 'PublishingPageLayoutExamples'
    $subsiteCount = & $number $Record.SubsiteCount
    if ($subsiteCount -gt 0) {
        $subsiteText = & $formatNumber $subsiteCount
        $depth = & $number $Record.MaxSubsiteDepth
        if ($depth -gt 0) { $subsiteText = '{0} (depth {1})' -f $subsiteText, (& $formatNumber $depth) }
        & $add 'Subsites' $subsiteText ([string]$Record.SubsiteExamples)
    }
    $metadataLists = & $number $Record.ManagedMetadataListCount
    if ($metadataLists -gt 0) {
        $parts = @('{0} list(s)' -f (& $formatNumber $metadataLists))
        $metadataColumns = & $number $Record.ManagedMetadataColumnCount
        $termSets = & $number $Record.ManagedMetadataTermSetCount
        if ($metadataColumns -gt 0) { $parts += '{0} column(s)' -f (& $formatNumber $metadataColumns) }
        if ($termSets -gt 0) { $parts += '{0} term set(s)' -f (& $formatNumber $termSets) }
        & $add 'Managed metadata' ($parts -join ', ') ([string]$Record.ManagedMetadataExamples)
    }
    & $count 'ExternalListCount' 'External lists' 'ExternalListExamples'
    & $count 'EmailEnabledListCount' 'E-mail enabled lists' 'EmailEnabledListExamples'
    & $count 'HtmlFileCount' 'HTML files' 'HtmlFileExamples'
    if ([string]$Record.BrowserFileHandling -eq 'Permissive') {
        & $add 'Browser file handling' 'Permissive' ''
    }
    & $count 'SharePointAlertCount' 'SharePoint alerts' ''
    & $count 'CustomPermissionLevelCount' 'Custom permission levels' 'CustomPermissionLevelExamples'
    & $count 'UniquePermissionsCount' 'Unique permission assignments' ''

    # Volume.
    & $flag 'IsLargeSite' 'Large site' ''
    & $count 'LargeListCount' 'Large lists' 'LargeListExamples'
    & $count 'LargeListViewCount' 'Large-list views' 'LargeListViewExamples'
    & $count 'CheckedOutFileCount' 'Checked-out files' 'CheckedOutFileExamples'
    & $count 'FileVersionCount' 'High-version files' 'FileVersionExamples'
    & $count 'LargeExcelFileCount' 'Large Excel files' 'LargeExcelFileExamples'

    # Collaboration features that do not migrate as they are.
    & $count 'AudienceTargetedItemCount' 'Audience-targeted items' 'AudienceTargetedExamples'
    & $count 'SiteNotebookCount' 'Site notebooks' 'SiteNotebookExamples'

    # Completeness of the inventory: a figure above is a lower bound when one of these is False.
    foreach ($check in @(
            @{ Name = 'SiteInventoryComplete'; Label = 'Site inventory incomplete' }
            @{ Name = 'CustomizationInventoryComplete'; Label = 'Customization inventory incomplete' }
            @{ Name = 'ContentTypeInventoryComplete'; Label = 'Content type inventory incomplete' }
        )) {
        if ($Record.($check.Name) -is [System.Boolean] -and -not $Record.($check.Name)) {
            & $add $check.Label 'Yes' ''
        }
    }

    $signals.ToArray()
}
