function CheckInstalled
{

    param(
        # Because we use -like in the comparisons, wildcard searches are supported i.e. * and ? operators
        # https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_comparison_operators?view=powershell-7.3
        [Parameter(Mandatory = $true)][string]$softwareName, 
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$softwareVersion # If you want to match higher versions, end with ^ i.e. 1.0.2^
    )

    Write-Host "Checking if $softwareName $softwareVersion is installed..."

    $matchGreater = $False
    if (-not [string]::IsNullOrEmpty($softwareVersion))
    {
        $matchGreater = $softwareVersion[-1] -eq '^'
        $softwareVersion = $softwareVersion.TrimEnd('^')     # Trim out the ^ at the end of the version string so it doesn't mess with comparisons
    }

    foreach ($hive in @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall' ))
    {
        $item = Get-ChildItem -LiteralPath $hive | Get-ItemProperty | Where-Object { $_.DisplayName -like $softwareName }

        # Exit if there is no version specified
        if ([string]::IsNullOrEmpty($softwareVersion))
        {
            Write-Host "$($item.DisplayName) (no version) already installed" 
            Return 0
        }
        
        # Match the display version exactly
        if ($item.DisplayVersion -like $softwareVersion)
        {
            Write-Host "$($item.DisplayName) $($item.DisplayVersion) already installed" 
            Return 0
        }

        # Try casting the version to a [version] and then if requested matching upwards
        try
        {
            if ($matchGreater -and ([version]$item.DisplayVersion -ge [version]$softwareVersion))
            {
                Write-Host "$($item.DisplayName) $($item.DisplayVersion)  already installed" 
                Return 0
            }
        }
        catch [System.Management.Automation.RuntimeException]
        {
            Write-Host "Error converting to [version] $($_.Exception)"
        }     

        # TODO: matching on the hidden version number for comparisons etc, this is: $item.Version
      
    }

    Write-Host "$softwareName $softwareVersion not installed"
    Return 1
}

