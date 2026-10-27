function ConvertTo-SPSSharePointAlertRecord {
    <#
        .SYNOPSIS
        Projects a SharePoint alert into a portable inventory row.

        .DESCRIPTION
        A SharePoint alert is an "Alert Me" subscription: a user asks to be notified when a
        list, a list item or a custom object changes. Migration tools do not migrate alerts,
        so users have to recreate them in the destination; this row gives the administrator
        what is needed to tell them where (site, list or item), what for (event type) and
        how (frequency, delivery channel, status). It matches the columns of the SMAT
        alerts report.

        Some SPAlert properties are only defined for some alert types, and SharePoint
        throws for the others: ListUrl and ListID for a custom alert, ItemID unless the
        alert targets an item, AlertTime for an immediate alert. They are read only when
        the alert type defines them, so a throwing getter is never mistaken for a read
        failure. Every other property is read strictly: PowerShell turns a failing .NET
        getter into $null, so a value that cannot be read raises an error instead of an
        empty cell, and the collector marks the inventory partial.

        ListUrl comes from the alert data, so an alert whose list no longer exists keeps
        its row with an empty list URL (the list ID still identifies it).

        UserLoginName is the account that owns the alert. It is personal data, so it is
        only written to the alert CSV and JSON files. It is empty when the owner is a
        system alert or no longer exists in the site. Resolving an owner is a query, so
        the caller can pass a cache shared by the alerts of a site collection, where user
        IDs are unique: each owner is then resolved once, even when it cannot be found.

        Private because it is an implementation detail of Get-SPSSiteCustomization.

        .PARAMETER Alert
        The SPAlert to project.

        .PARAMETER SiteUrl
        URL of the site collection that owns the alert.

        .PARAMETER WebUrl
        URL of the web that owns the alert.

        .PARAMETER UserLoginCache
        Optional hashtable that maps the user ID of an owner to its login name. It is
        filled by this function, so share one per site collection.

        .EXAMPLE
        ConvertTo-SPSSharePointAlertRecord -Alert $alert -SiteUrl $site.Url -WebUrl $web.Url
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $Alert,

        [Parameter(Mandatory = $true)]
        [System.String]
        $SiteUrl,

        [Parameter(Mandatory = $true)]
        [System.String]
        $WebUrl,

        [Parameter()]
        [System.Collections.Hashtable]
        $UserLoginCache
    )

    $alertIdValue = Get-SPSPropertyValue -InputObject $Alert -Name 'ID'
    $alertId = if ($null -ne $alertIdValue) { [string]$alertIdValue } else { '' }
    if ([string]::IsNullOrWhiteSpace($alertId) -or $alertId -eq [System.Guid]::Empty.ToString()) {
        throw 'The alert ID could not be read.'
    }

    $readRequired = {
        param ([string]$Name)
        $value = Get-SPSPropertyValue -InputObject $Alert -Name $Name
        if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
            throw "The $Name of alert '$alertId' could not be read."
        }
        $value
    }

    $alertType = [string](& $readRequired 'AlertType')
    $title = [string](& $readRequired 'Title')
    $eventType = [string](& $readRequired 'EventType')
    $frequency = [string](& $readRequired 'AlertFrequency')
    $status = [string](& $readRequired 'Status')
    $deliveryChannels = [string](& $readRequired 'DeliveryChannels')
    $alwaysNotify = [bool](& $readRequired 'AlwaysNotify')
    $userId = [int](& $readRequired 'UserId')

    $listUrl = ''
    $listId = ''
    $itemId = ''
    if ($alertType -eq 'List' -or $alertType -eq 'Item') {
        $listUrl = [string](Get-SPSPropertyValue -InputObject $Alert -Name 'ListUrl')
        $listId = ([System.Guid](& $readRequired 'ListID')).ToString()
        if ($alertType -eq 'Item') {
            $itemId = [string][int](& $readRequired 'ItemID')
        }
    }

    # SharePoint throws for the time of an immediate alert: only digests have one.
    $alertTime = ''
    if ($frequency -ne 'Immediate') {
        $alertTime = ([datetime](& $readRequired 'AlertTime')).ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
    }

    $userLoginName = ''
    if ($userId -ne 0) {
        if ($null -ne $UserLoginCache -and $UserLoginCache.ContainsKey($userId)) {
            $userLoginName = [string]$UserLoginCache[$userId]
        }
        else {
            # A user removed from the site makes the getter fail; the owner is then unknown, not an error.
            $user = $Alert.User
            if ($null -ne $user) {
                $userLoginName = [string]$user.LoginName
            }
            if ($null -ne $UserLoginCache) {
                $UserLoginCache[$userId] = $userLoginName
            }
        }
    }

    [PSCustomObject]@{
        SiteUrl           = $SiteUrl
        WebUrl            = $WebUrl
        AlertId           = $alertId
        Title             = $title
        AlertTemplateName = [string](Get-SPSPropertyValue -InputObject $Alert -Name 'AlertTemplateName')
        AlertType         = $alertType
        ListUrl           = $listUrl
        ListId            = $listId
        ItemId            = $itemId
        EventType         = $eventType
        AlertFrequency    = $frequency
        AlertTime         = $alertTime
        Status            = $status
        DeliveryChannels  = $deliveryChannels
        AlwaysNotify      = $alwaysNotify
        DynamicRecipient  = [string](Get-SPSPropertyValue -InputObject $Alert -Name 'DynamicRecipient')
        Filter            = [string](Get-SPSPropertyValue -InputObject $Alert -Name 'Filter')
        UserId            = $userId
        UserLoginName     = $userLoginName
    }
}
