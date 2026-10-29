# Behavior tests for Get-SPSAudienceTargetingField (no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    # Get-SPSAudienceTargetingField is private; reach it inside the module scope.
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    # A column whose ID cannot be read. It is a real .NET type: PowerShell turns an exception of a getter into $null.
    if (-not ('SPSTestFailingIdField' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
public class SPSTestFailingIdField
{
    public Guid Id { get { throw new InvalidOperationException("id unavailable"); } }
    public string InternalName { get { return "Broken"; } }
}
'@
    }

    $script:TargetingId = '61cbb965-1e04-4273-b658-eedaa662f48d'

    function New-Field {
        param ([string]$InternalName = 'Title', [string]$Id = ([guid]::NewGuid().ToString()), [string]$TypeAsString = 'Text')
        [PSCustomObject]@{ InternalName = $InternalName; Id = [guid]$Id; TypeAsString = $TypeAsString }
    }

    function Find-Field {
        param ($List)
        & $script:Module { param ($Candidate) Get-SPSAudienceTargetingField -List $Candidate } $List
    }
}

Describe 'Get-SPSAudienceTargetingField' {
    It 'finds the column of a list by its ID' {
        $field = New-Field -InternalName 'Target_x0020_Audiences' -Id $script:TargetingId -TypeAsString 'TargetTo'
        $list = [PSCustomObject]@{ Title = 'Announcements'; Fields = @((New-Field), $field, (New-Field -InternalName 'Body')) }

        (Find-Field -List $list).InternalName | Should -Be 'Target_x0020_Audiences'
    }

    It 'finds the column by its ID whatever its type says' {
        $list = [PSCustomObject]@{ Title = 'Announcements'; Fields = @((New-Field), (New-Field -InternalName 'Target_x0020_Audiences' -Id $script:TargetingId -TypeAsString 'Note')) }

        (Find-Field -List $list).InternalName | Should -Be 'Target_x0020_Audiences'
    }

    It 'finds the column of a Pages library, which has the same ID and another internal name' {
        $list = [PSCustomObject]@{ Title = 'Pages'; Fields = @((New-Field), (New-Field -InternalName 'Audience' -Id $script:TargetingId -TypeAsString 'TargetTo')) }

        (Find-Field -List $list).InternalName | Should -Be 'Audience'
    }

    It 'finds a column of the type TargetTo that has another ID' {
        $list = [PSCustomObject]@{ Title = 'Links'; Fields = @((New-Field), (New-Field -InternalName 'Targets' -TypeAsString 'TargetTo')) }

        (Find-Field -List $list).InternalName | Should -Be 'Targets'
    }

    It 'does not take a column of another type that is named like it for the audience targeting column' {
        $list = [PSCustomObject]@{ Title = 'Links'; Fields = @((New-Field -InternalName 'Target_x0020_Audiences' -TypeAsString 'Text')) }

        Find-Field -List $list | Should -BeNullOrEmpty
    }

    It 'returns nothing for a list without the column, or without any column' {
        Find-Field -List ([PSCustomObject]@{ Title = 'Tasks'; Fields = @((New-Field), (New-Field -InternalName 'Body')) }) | Should -BeNullOrEmpty
        Find-Field -List ([PSCustomObject]@{ Title = 'Empty'; Fields = @() }) | Should -BeNullOrEmpty
    }

    It 'raises an error when the columns of the list cannot be read' {
        { Find-Field -List ([PSCustomObject]@{ Title = 'Broken'; Fields = $null }) } | Should -Throw "*columns of list 'Broken' could not be read*"
    }

    It 'raises an error instead of taking a column whose ID cannot be read for no column' {
        $list = [PSCustomObject]@{ Title = 'Broken'; Fields = @([SPSTestFailingIdField]::new(), (New-Field -InternalName 'Target_x0020_Audiences' -Id $script:TargetingId)) }

        { Find-Field -List $list } | Should -Throw '*id unavailable*'
    }
}
