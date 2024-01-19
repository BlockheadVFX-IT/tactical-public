function RunFromGit
{
    param (
        [Parameter(Mandatory = $true)][string]$script, # Path of file in GitHub repo
        $outfile, # File to execute (probably same as above sans dirs)
        $automation_name, # Used for temp dir names
        [string]$github_api_url = 'https://api.github.com/repos/BlockheadVFX-IT/boilerplates/contents', # If you are using a proxy change this
        [string]$github_raw_url = 'https://raw.githubusercontent.com/BlockheadVFX-IT', # If you are using a proxy change this
        [bool]$load_helpers = $true,
        [bool]$user_mode = $false, # If running as logged on user instead of system user, will change working dir to $env:LOCALAPPDATA
        [string]$pub_branch = 'main' # used to swap to different test branches if you want
    )

    $prev_cwd = Get-Location

    if ($load_helpers)
    {
        # If you want to add more helpers, include their names here and upload them to the 
        # powershell/helpers/ folder for the public GitHub repo
        $helper_files = @('create_shortcut.ps1', 'check_installed.ps1', 'set_env_var.ps1', 'set_reg_key.ps1', 'uninstall_program.ps1')
        $base_url = "$github_raw_url/tactical-public/$pub_branch/powershell/helpers"

        foreach ($file in $helper_files)
        {
            Write-Host "Sourcing $file..."
            . ([Scriptblock]::Create((Invoke-WebRequest -Uri "$base_url/$file" -UseBasicParsing).Content))
        }
    }

    # Get the Personal Access Token (PAT) from S3 to access the private repo
    Write-Host 'Getting personal access token from Sagar''s private S3 bucket.........'
    $pat_url_b64 = 'aHR0cHM6Ly90YW5nZWxvYnVja2V0bmluamEuczMuYXAtc291dGhlYXN0LTIuYW1hem9uYXdzLmNvbS90cm1tX2dpdGh1Yl9wYXQucGF0'
    $pat_url = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($pat_url_b64))
    $pat = Invoke-WebRequest -Uri $pat_url -UseBasicParsing | Select-Object -ExpandProperty Content
    $pat = [Text.Encoding]::UTF8.GetString($pat)
    echo $pat

    # Set up headers with the PAT for authorization
    $headers = @{
        'Accept'               = 'application/vnd.github.v3.raw'
        'Authorization'        = "Bearer $pat"
        'X-GitHub-Api-Version' = '2022-11-28'
    }

    # Set up temp dirs
    New-Item -ItemType Directory "$trmm_dir\$automation_name" -Force | Out-Null
    Set-Location "$trmm_dir\$automation_name"

    # Download script from the private repo using PAT
    Write-Host "Getting $script from GitHub..."
    Invoke-WebRequest -Uri "$github_raw_url/$pub_branch/$script" -Headers $headers -OutFile $outfile -UseBasicParsing

    # We've got the script, now to run it...
    $process_error = $false
    try
    {
        Write-Host "Running $outfile ..."
        & ".\$outfile" 2>&1 | Out-String
        $result = $LASTEXITCODE
        Write-Host "$outfile done, cleaning up..."
    }
    catch
    {
        # We will throw any errors later, after we have cleaned up dirs
        $process_error = $_.Exception 
    }

    # Clean up 
    Set-Location "$trmm_dir"
    Remove-Item "$trmm_dir\$automation_name" -Force -Recurse
    if (Test-Path "$trmm_dir\$automation_name")
    {
        Write-Host "Failed to clean up $trmm_dir\$automation_name"
    }
    else
    {
        Write-Host "Cleaned up $trmm_dir\$automation_name"
    }
    Write-Host $result

    Set-Location $prev_cwd
    if ($process_error)
    {
        throw $process_error
    }
    else
    {
        return $result
    }
}

function Format-InvalidPathCharacters
{
    param (
        [string]$path
    )

    # Define a regex pattern to match non-standard characters
    $invalidCharsPattern = '[\\/:*?"<>|]'

    # Replace non-standard characters with an underscore
    $escapedPath = [regex]::Replace($path, $invalidCharsPattern, '_')

    return $escapedPath
}

# Example usage:
# RunFromGit -script "path/to/script.ps1" -outfile "output.ps1" -automation_name "AutomationName"
