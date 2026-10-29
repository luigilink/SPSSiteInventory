function Get-SPSModernBlocker {
    <#
        .SYNOPSIS
        Lists what stands between a site collection and the modern experience.

        .DESCRIPTION
        Brings together, for one site collection, the signals that make SharePoint fall back to the
        classic experience or that have no counterpart in the modern one:

        - a custom master page (CustomMasterPage);
        - an alternate CSS URL on a web (AlternateCssUrlCount);
        - publishing features (PublishingInfrastructureEnabled or PublishingWebCount);
        - list views that render with XSLT (XsltListViewCount);
        - Script Editor and Content Editor web parts that carry script (ScriptWebPartCount);
        - the site collection or webs that opted out of the modern list and library experience
          (ClassicExperienceOptOutCount);
        - lists forced to the classic experience (ClassicExperienceListCount).

        The result has Count, the number of kinds of blocker that the site collection has (0 to 7),
        Names, the kinds in a fixed order, Summary, one text for a report: the kinds separated by
        a semicolon, with how many webs, views, web parts or lists are behind each when it is a
        count, and Kind, one object per kind found with its Name, its Label, the number of Items
        behind it (null for a custom master page, which is a state and not a count), the Unit of
        those items and its Text. A signal that is missing counts as 0.

        The function is pure: it reads no SharePoint object, so it can be tested without a farm.

        Private because it is an implementation detail of Get-SPSSiteCustomization and of the
        readiness section of the HTML report.

        .PARAMETER Signals
        The signals collected for the site collection (see Get-SPSSiteCustomization), or the fields
        of its inventory record put in a hashtable.

        .EXAMPLE
        (Get-SPSModernBlocker -Signals @{ CustomMasterPage = $true; XsltListViewCount = 3 }).Summary
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]
        $Signals
    )

    $quantity = {
        param ([double]$Count, [string]$Singular, [string]$Plural)
        return '{0} {1}' -f $Count, $(if ($Count -eq 1) { $Singular } else { $Plural })
    }

    $kinds = [System.Collections.Generic.List[object]]::new()

    $customMasterPage = [double](ConvertTo-SPSSignalNumber -Value $Signals['CustomMasterPage'])
    if ($customMasterPage -gt 0) {
        $kinds.Add([PSCustomObject]@{ Name = 'CustomMasterPage'; Label = 'Custom master page'; Items = $null; Unit = ''; Text = 'Custom master page' })
    }

    $alternateCss = [double](ConvertTo-SPSSignalNumber -Value $Signals['AlternateCssUrlCount'])
    if ($alternateCss -gt 0) {
        $kinds.Add([PSCustomObject]@{ Name = 'AlternateCssUrl'; Label = 'Alternate CSS URL'; Items = $alternateCss; Unit = 'web(s)'; Text = ('Alternate CSS URL ({0})' -f (& $quantity $alternateCss 'web' 'webs')) })
    }

    $publishingInfrastructure = [double](ConvertTo-SPSSignalNumber -Value $Signals['PublishingInfrastructureEnabled'])
    $publishingWeb = [double](ConvertTo-SPSSignalNumber -Value $Signals['PublishingWebCount'])
    if ($publishingInfrastructure -gt 0 -or $publishingWeb -gt 0) {
        $publishingText = if ($publishingWeb -gt 0) { 'Publishing features ({0})' -f (& $quantity $publishingWeb 'web' 'webs') } else { 'Publishing features' }
        $kinds.Add([PSCustomObject]@{ Name = 'Publishing'; Label = 'Publishing features'; Items = $publishingWeb; Unit = 'web(s)'; Text = $publishingText })
    }

    $xsltView = [double](ConvertTo-SPSSignalNumber -Value $Signals['XsltListViewCount'])
    if ($xsltView -gt 0) {
        $kinds.Add([PSCustomObject]@{ Name = 'XsltListView'; Label = 'XSLT list views'; Items = $xsltView; Unit = 'view(s)'; Text = ('XSLT list views ({0})' -f $xsltView) })
    }

    $scriptWebPart = [double](ConvertTo-SPSSignalNumber -Value $Signals['ScriptWebPartCount'])
    if ($scriptWebPart -gt 0) {
        $kinds.Add([PSCustomObject]@{ Name = 'ScriptWebPart'; Label = 'Script web parts'; Items = $scriptWebPart; Unit = 'web part(s)'; Text = ('Script web parts ({0})' -f $scriptWebPart) })
    }

    $optOut = [double](ConvertTo-SPSSignalNumber -Value $Signals['ClassicExperienceOptOutCount'])
    if ($optOut -gt 0) {
        $kinds.Add([PSCustomObject]@{ Name = 'ClassicExperienceOptOut'; Label = 'Opted out of modern lists'; Items = $optOut; Unit = 'opt-out(s)'; Text = ('Opted out of modern lists ({0})' -f $optOut) })
    }

    $classicList = [double](ConvertTo-SPSSignalNumber -Value $Signals['ClassicExperienceListCount'])
    if ($classicList -gt 0) {
        $kinds.Add([PSCustomObject]@{ Name = 'ClassicExperienceList'; Label = 'Lists forced to classic'; Items = $classicList; Unit = 'list(s)'; Text = ('Lists forced to classic ({0})' -f $classicList) })
    }

    return [PSCustomObject]@{
        Count   = $kinds.Count
        Names   = @($kinds | ForEach-Object { $_.Name })
        Summary = (@($kinds | ForEach-Object { $_.Text }) -join '; ')
        Kind    = $kinds.ToArray()
    }
}
