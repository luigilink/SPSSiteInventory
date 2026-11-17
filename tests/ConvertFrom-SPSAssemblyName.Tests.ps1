# Behavior tests for ConvertFrom-SPSAssemblyName (pure text parsing, no farm needed).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function Split-Name {
        param ($Text)
        & $script:Module { param ($Value) ConvertFrom-SPSAssemblyName -DisplayName $Value } $Text
    }
}

Describe 'ConvertFrom-SPSAssemblyName' {
    It 'splits a strong name into its name, version, culture and public key token' {
        $result = Split-Name 'Contoso.Intranet, Version=1.0.0.0, Culture=neutral, PublicKeyToken=0123456789abcdef'

        $result.Name | Should -Be 'Contoso.Intranet'
        $result.Version | Should -Be '1.0.0.0'
        $result.Culture | Should -Be 'neutral'
        $result.PublicKeyToken | Should -Be '0123456789abcdef'
    }

    It 'writes the token in lower case, and reads the keys whatever their case and spacing' {
        $result = Split-Name '  Contoso.Intranet ,  version = 2.0.0.0 ,CULTURE=fr-FR, publickeytoken = ABCDEF0123456789  '

        $result.Name | Should -Be 'Contoso.Intranet'
        $result.Version | Should -Be '2.0.0.0'
        $result.Culture | Should -Be 'fr-FR'
        $result.PublicKeyToken | Should -BeExactly 'abcdef0123456789'
    }

    It 'gives no token for an assembly that is not signed' -ForEach @(
        @{ Text = 'Contoso.Intranet, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null' }
        @{ Text = 'Contoso.Intranet, Version=1.0.0.0, Culture=neutral, PublicKeyToken=NULL' }
        @{ Text = 'Contoso.Intranet, Version=1.0.0.0, Culture=neutral' }
        @{ Text = 'Contoso.Intranet' }
    ) {
        $result = Split-Name $Text

        $result.Name | Should -Be 'Contoso.Intranet'
        $result.PublicKeyToken | Should -Be ''
    }

    It 'gives the name alone, with the other parts empty, when there is no more than a name' {
        $result = Split-Name 'Contoso.Intranet'

        $result.Version | Should -Be ''
        $result.Culture | Should -Be ''
    }

    It 'keeps what follows the first equal sign of a part as its value' {
        (Split-Name 'Contoso.Intranet, Version=1.0=beta').Version | Should -Be '1.0=beta'
    }

    It 'ignores a part that it does not know' {
        $result = Split-Name 'Contoso.Intranet, Version=1.0.0.0, Culture=neutral, PublicKeyToken=0123456789abcdef, processorArchitecture=MSIL'

        $result.Name | Should -Be 'Contoso.Intranet'
        $result.PublicKeyToken | Should -Be '0123456789abcdef'
    }

    It 'does not fail on a value that is empty or that is not a display name' -ForEach @(
        @{ Text = $null }
        @{ Text = '' }
        @{ Text = '   ' }
        @{ Text = ',,,' }
        @{ Text = 'Contoso, Version, =x, Culture=' }
    ) {
        $result = Split-Name $Text

        $result.PublicKeyToken | Should -Be ''
        $result.Version | Should -Be ''
    }

    It 'gives an empty name for an empty value, and the first part for a value that starts with a comma' {
        (Split-Name $null).Name | Should -Be ''
        (Split-Name ', Version=1.0.0.0').Name | Should -Be ''
        (Split-Name ', Version=1.0.0.0').Version | Should -Be '1.0.0.0'
    }
}
