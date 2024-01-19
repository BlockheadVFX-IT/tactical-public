function RunFromGit
{
    param (
        [Parameter(Mandatory = $true)][string]$script, # Path of file in GitHub repo
        $outfile, # File to execute (probably same as above sans dirs)
        $automation_name, # Used for temp dir names
        [string]$github_api_url = 'https://api.github.com/repos/BlockheadVFX-IT/boilerplates/contents', # If you are using a proxy change this
        [string]$github_raw_url = 'https://raw.githubusercontent.com/BlockheadVFX-IT', # If you are using a proxy change this
        [bool]$load_helpers = $true,
        [bool]$user_mode = $false, # If running as a logged-on user instead of the system user, will change working dir to $env:LOCALAPPDATA
        [string]$pub_branch = 'main' # used to swap to different test branches if you want
    )

    # Save the current working directory
    $prev_cwd = Get-Location

    # Load helper scripts if required
    if ($load_helpers)
    {
        $helper_files = @('create_shortcut.ps1', 'check_installed.ps1', 'set_env_var.ps1', 'set_reg_key.ps1', 'uninstall_program.ps1')
        $base_url = "$github_raw_url/tactical-public/$pub_branch/powershell/helpers"

        foreach ($file in $helper_files)
        {
            Write-Host "Sourcing $file..."
            . ([Scriptblock]::Create((Invoke-WebRequest -Uri "$base_url/$file" -UseBasicParsing).Content))
        }
    }

    # Set the appropriate temp directory based on user mode
    if ($user_mode)
    {
        $ninja_dir = "$env:LOCALAPPDATA\Temp" # In user mode, ProgramData is not writable by most users
    }
    else
    {
        $ninja_dir = 'C:\ProgramData\TacticalRMM' # Otherwise use this dir
    }

    # Get the personal access token (PAT) from S3 to access the private repo
    Write-Host 'Getting personal access token from Sagar''s private S3 bucket...'
    $pat_url_b64 = 'aHR0cHM6Ly90YW5nZWxvYnVja2V0bmluamEuczMuYXAtc291dGhlYXN0LTIuYW1hem9uYXdzLmNvbS90cm1tX2dpdGh1Yl9wYXQucGF0'
    $pat_url = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($pat_url_b64))
    $pat = Invoke-WebRequest -Uri $pat_url -UseBasicParsing | Select-Object -ExpandProperty Content
    $pat = [Text.Encoding]::UTF8.GetString($pat)

    # Check whether we are getting a file or a folder
    # Define headers for GitHub API request
    $headers = @{
        'Accept'               = 'application/vnd.github.v3.object'
        'Authorization'        = "Bearer $pat"
        'X-GitHub-Api-Version' = '2022-11-28'
    }

    # Construct the URI for GitHub API request
    $uri = "$github_api_url/$([System.Uri]::EscapeDataString($script))"

    # Invoke a REST API request using cURL and capture the response
    $curlCommand = "curl -H 'Accept: $($headers['Accept'])' -H 'Authorization: $($headers['Authorization'])' -H 'X-GitHub-Api-Version: $($headers['X-GitHub-Api-Version'])' '$uri'"
    $response = Invoke-Expression -Command $curlCommand

    # Convert the JSON response to a PowerShell object
    $responseObject = $response | ConvertFrom-Json

    # Set up temp dirs and download the script
    $outfile = Split-Path -Path $script -Leaf
    $automation_name = Format-InvalidPathCharacters -path $outfile
    New-Item -ItemType Directory "$ninja_dir\$automation_name" -Force | Out-Null
    Set-Location "$ninja_dir\$automation_name"

    Write-Host "Getting $script from GitHub..."
    Invoke-WebRequest -Uri $uri -Headers $headers -OutFile $outfile -UseBasicParsing

    if (Test-Path $outfile)
    {
        Write-Host "$outfile downloaded successfully"
    }
    else
    {
        Write-Host "$outfile not downloaded"
    }

    # Run the script
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
        $process_error = $_.Exception
    }

    # Clean up
    Set-Location "$ninja_dir"
    Remove-Item "$ninja_dir\$automation_name" -Force -Recurse

    if (Test-Path "$ninja_dir\$automation_name")
    {
        Write-Host "Failed to clean up $ninja_dir\$automation_name"
    }
    else
    {
        Write-Host "Cleaned up $ninja_dir\$automation_name"
    }

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
