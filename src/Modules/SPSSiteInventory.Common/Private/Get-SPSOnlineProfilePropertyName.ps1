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
        property of the User Profile service. A property is identified by its internal name, which
        Get-SPSProfilePropertyMapping compares without regard to the case: a display name is a label that
        anybody can give to a property of their own, so it is not in the list.

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
        # UserPrincipalName: Account Name, User Name, User Principal Name
        'AccountName', 'UserName', 'SPS-UserPrincipalName'
        # DisplayName: Name
        'PreferredName'
        # GivenName, sn
        'FirstName', 'LastName'
        # telephoneNumber: Work phone
        'WorkPhone'
        # proxyAddresses: Work Email, SIP Address
        'WorkEmail', 'SPS-SipAddress'
        # PhysicalDeliveryOfficeName
        'Office'
        # Title: Title, Job Title
        'Title', 'SPS-JobTitle'
        # Department
        'Department', 'SPS-Department'
        # WWWHomePage: Public site redirect
        'PublicSiteRedirect'
        # PreferredLanguage: Language Preferences
        'SPS-MUILanguages'
        # msExchHideFromAddressList
        'SPS-HideFromAddressLists'
        # Manager
        'Manager'
    )
}
