function Read-SPSPackageXml {
    <#
        .SYNOPSIS
        Loads an XML file of a package for reading, with the DTD and the entities switched off.

        .DESCRIPTION
        The XML of a package (manifest.xml, feature manifests, element manifests) comes from a file
        that is not trusted. The document is read with DTD processing prohibited and no resolver,
        so that it cannot pull another file or a URL in (XXE), and a file above the size limit is
        refused.

        Private because it is an implementation detail of Get-SPSExpandedPackageInfo.

        .PARAMETER Path
        The path of the XML file.

        .PARAMETER MaximumMegabyte
        The size above which the file is refused. Defaults to 20.

        .OUTPUTS
        The XmlDocument.

        .EXAMPLE
        $manifest = Read-SPSPackageXml -Path .\expanded\manifest.xml
    #>
    [CmdletBinding()]
    [OutputType([System.Xml.XmlDocument])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [ValidateRange(1, 200)]
        [System.Int32]
        $MaximumMegabyte = 20
    )

    $length = (Get-Item -LiteralPath $Path -ErrorAction Stop).Length
    if ($length -gt ([System.Int64]$MaximumMegabyte * 1MB)) {
        throw "The file is larger than $MaximumMegabyte MB."
    }

    $settings = New-Object -TypeName System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        $reader = [System.Xml.XmlReader]::Create($stream, $settings)
        try {
            $document = New-Object -TypeName System.Xml.XmlDocument
            $document.XmlResolver = $null
            $document.Load($reader)
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }

    # The comma keeps the pipeline from enumerating the nodes of the document.
    return , $document
}
