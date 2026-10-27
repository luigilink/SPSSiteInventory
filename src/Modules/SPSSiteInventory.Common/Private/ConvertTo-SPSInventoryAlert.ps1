function ConvertTo-SPSInventoryAlert {
    <#
        .SYNOPSIS
        Creates one risk alert from the alert catalog.

        .DESCRIPTION
        The severity, the remediation and the Microsoft Learn reference of the alert come
        from the catalog entry of its type (see Get-SPSAlertCatalog), so they cannot drift
        between the places that raise the same alert. The message comes from the catalog
        too, unless the caller gives a more specific one, such as the reason a site template
        needs review.

        An alert type that is not in the catalog raises an error: every alert must carry a
        remediation.

        Private because it is an implementation detail of Get-SPSInventoryAlert.

        .PARAMETER AlertType
        The catalog key of the alert, for example 'InfoPath'.

        .PARAMETER Url
        The URL of the site collection or web application the alert is about.

        .PARAMETER Value
        The value that raised the alert, such as a count or a state.

        .PARAMETER Message
        Optional message that replaces the catalog message when it is not empty.

        .EXAMPLE
        ConvertTo-SPSInventoryAlert -AlertType 'InfoPath' -Url 'https://intranet/sites/hr' -Value 3
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $AlertType,

        [Parameter()]
        [AllowNull()]
        [System.Object]
        $Url = '',

        [Parameter()]
        [AllowNull()]
        [System.Object]
        $Value = $null,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Message = ''
    )

    $catalog = Get-SPSAlertCatalog
    if (-not $catalog.Contains($AlertType)) {
        throw "The alert type '$AlertType' is not in the alert catalog."
    }
    $entry = $catalog[$AlertType]

    [PSCustomObject]@{
        AlertType   = $AlertType
        Severity    = $entry.Severity
        Url         = $Url
        Value       = $Value
        Message     = if ([string]::IsNullOrWhiteSpace($Message)) { $entry.Message } else { $Message }
        Remediation = $entry.Remediation
        Reference   = $entry.Reference
    }
}
