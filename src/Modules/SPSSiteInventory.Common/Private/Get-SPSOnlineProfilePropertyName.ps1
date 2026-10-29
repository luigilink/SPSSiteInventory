function Get-SPSOnlineProfilePropertyName {
    <#
        .SYNOPSIS
        Lists the profile properties that SharePoint Online fills in from Microsoft Entra ID.

        .DESCRIPTION
        SharePoint Online does not have the profile property mappings of the User Profile service: it
        synchronizes a fixed set of Microsoft Entra attributes into profile properties, "isn't configurable"
        and the same for every tenant (https://learn.microsoft.com/en-us/sharepoint/user-profile-sync):

        | Microsoft Entra attribute  | SharePoint Online property            |
        | UserPrincipalName          | Account Name, User Name, UPN          |
        | DisplayName                | Name                                  |
        | GivenName                  | FirstName                             |
        | sn                         | LastName                              |
        | telephoneNumber            | Work phone                            |
        | proxyAddresses             | Work Email, SIP Address               |
        | PhysicalDeliveryOfficeName | Office                                |
        | Title                      | Title, Job Title                      |
        | Department                 | Department                            |
        | WWWHomePage                | Public site redirect                  |
        | PreferredLanguage          | Language Preferences                  |
        | msExchHideFromAddressList  | SPS-HideFromAddressLists              |
        | Manager                    | Manager                               |

        A mapping of the farm whose profile property is one of those has an equivalent in the target; any
        other mapping does not (the Phonetic Search properties, for example, which the SMAT report lists too).
        The page gives the properties by their display names, so the list holds the internal name of each
        property of the User Profile service and its display name; the comparison, which
        Get-SPSProfilePropertyMapping does, ignores the case and whatever is not a letter or a digit.

        The function is pure: it reads no farm. Private because it is an implementation detail of
        Get-SPSProfilePropertyMapping.

        .OUTPUTS
        The names, as strings.

        .EXAMPLE
        Get-SPSOnlineProfilePropertyName
    #>
    [CmdletBinding()]
    [OutputType([System.String[]])]
    param ()

    return [string[]]@(
        # UserPrincipalName
        'AccountName', 'UserName', 'SPS-UserPrincipalName', 'UPN'
        # DisplayName
        'PreferredName', 'Name'
        # GivenName, sn
        'FirstName', 'LastName'
        # telephoneNumber
        'WorkPhone', 'Work phone'
        # proxyAddresses
        'WorkEmail', 'Work Email', 'SPS-SipAddress', 'SIP Address'
        # PhysicalDeliveryOfficeName
        'Office'
        # Title
        'Title', 'SPS-JobTitle', 'Job Title'
        # Department
        'Department', 'SPS-Department'
        # WWWHomePage
        'PublicSiteRedirect', 'Public site redirect'
        # PreferredLanguage
        'SPS-MUILanguages', 'Language Preferences'
        # msExchHideFromAddressList
        'SPS-HideFromAddressLists'
        # Manager
        'Manager'
    )
}
