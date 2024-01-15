# Shortcut config
function CreateShortcut
{
    param (
        [Parameter(Mandatory = $true)][string]$shortcutPath,
        [Parameter(Mandatory = $true)][string]$targetPath
    )
    Write-Host "Creating shortcut at $shortcutPath to $targetPath"
    New-Item -ItemType Directory -Path "$([System.IO.Path]::GetDirectoryName($shortcutPath))" -Force -ErrorAction SilentlyContinue

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $targetPath
    $shortcut.Save()
}
