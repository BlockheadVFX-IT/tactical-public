function UninstallProgram
{
    param(
        [Parameter(Mandatory = $true)][string]$softwareName,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$softwareVersion
    )

    if ((CheckInstalled -softwareName $softwareName -softwareversion $softwareVersion) -ne 0)
    {
        # Software is not installed
        # Installer commands here
        Write-Host "Tried to uninstall $softwareName $softwareVersion but it is not installed"
        return 1
    }
    else
    {
        Write-Host 'Proceeding with uninstall...'
    }

    # Registry path where uninstall information is stored
    $uninstallKeyPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall'

    # Get all subkeys in the uninstall registry path
    $uninstallKeys = Get-ChildItem -Path $uninstallKeyPath

    # Iterate through each subkey to find the program
    foreach ($key in $uninstallKeys)
    {
        $program = Get-ItemProperty -Path $key.PSPath
        if ($program.DisplayName -eq $softwareName -and $program.DisplayVersion -eq $softwareVersion)
        {
            $uninstallString = $program.UninstallString
            if ($uninstallString)
            {
                # Check if the uninstall command contains "/s" for silent uninstall
                if ($uninstallString -like '*/s' -or $uninstallString -like '*/S')
                {
                    # If it's already silent, execute it
                    Invoke-Expression $uninstallString
                }
                else
                {
                    # If not silent, add the "/s" and execute
                    $silentUninstallString = $uninstallString + ' /s'
                    Invoke-Expression $silentUninstallString
                }
                break
            }
        }
    }

    # If the program is not found
    if (!$uninstallString)
    {
        Write-Host 'Program not found or uninstall information not available in the Registry.'
    }


}