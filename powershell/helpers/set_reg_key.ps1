function SetRegKey
{
    param (
        [Parameter(Mandatory = $true)][string]$path,
        [Parameter(Mandatory = $true)][string]$name,
        [Parameter(Mandatory = $true)][string]$value,
        [Parameter(Mandatory = $true)][string]$type
    )

    Write-Host "Setting registry key: $path\$name to $value"
    # Create the registry key if it doesn't exist
    if (-not (Test-Path $path))
    {
        New-Item -Path $path -Force
    }

    # Set the registry key value
    New-ItemProperty -Path $path -Name $name -Value $value -PropertyType $type -Force
}

