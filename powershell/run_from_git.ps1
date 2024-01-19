function RunFromGit
{
    param (
        [Parameter(Mandatory = $true)][string]$script, # Path of file in GitHub repo
        $outfile, # File to execute (probably same as above sans dirs)
        $automation_name, # Used for temp dir names
        [string]$github_api_url = 'https://api.github.com/repos/BlockheadVFX-IT/boilerplates/contents', # GitHub API URL for repository contents
        [string]$github_raw_url = 'https://raw.githubusercontent.com/BlockheadVFX-IT', # Raw GitHub URL for scripts
        [bool]$load_helpers = $true, # Flag to determine whether to load helper scripts
        [bool]$user_mode = $false, # If running as logged on user instead of system user, will change working dir to $env:LOCALAPPDATA
        [string]$pub_branch = 'main' # Used to swap to different test branches if needed
    )

    # Save the current working directory
    $prev_cwd = Get-Location

    # Load helper scripts if required
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

    # Determine the working directory based on user mode
    if ($user_mode)
    {
        $working_dir = "$env:LOCALAPPDATA\Temp" # In user mode, ProgramData is not writable by most users
    }
    else
    {
        $working_dir = 'C:\ProgramData\TacticalRMM' # Otherwise use this directory
    }

    # Get the personal access token (PAT) from a private S3 bucket
    Write-Host 'Getting personal access token from Sagars private S3 bucket.........'
    $pat_url_b64 = 'aHR0cHM6Ly90YW5nZWxvYnVja2V0bmluamEuczMuYXAtc291dGhlYXN0LTIuYW1hem9uYXdzLmNvbS90cm1tX2dpdGh1Yl9wYXQucGF0'
    $pat_url = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($pat_url_b64))
    $pat = Invoke-WebRequest -Uri $pat_url -UseBasicParsing | Select-Object -ExpandProperty Content
    $pat = [Text.Encoding]::UTF8.GetString($pat)

    # Display PAT and GitHub API URL for verification
    echo "Personal Access Token (PAT): $pat"
    echo "GitHub API URL: $github_api_url"

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

    # Extract the script list based on the GitHub response
    $script_list = @() # Treat as an array even if we only end up with one script at a time

    if ($responseObject.type -eq 'file')
    {
        $script_list += $responseObject.path
    }

    # Iterate through each script in the list
    foreach ($script in $script_list)
    {
        # Set up file and directory names
        $outfile = Split-Path -Path $script -Leaf
        $automation_name = Format-InvalidPathCharacters -path $outfile

        # Set up temp dirs
        New-Item -ItemType Directory "$working_dir\$automation_name" -Force | Out-Null
        Set-Location "$working_dir\$automation_name"

        # Download script from GitHub
        Write-Host "Getting $script from GitHub..."
        Invoke-WebRequest -Uri "$github_api_url/$([System.Uri]::EscapeDataString($script))" -Headers $headers -OutFile $outfile -UseBasicParsing

        # Check if the script was downloaded successfully
        if (Test-Path $outfile)
        {
            Write-Host "$outfile downloaded successfully"
        }
        else
        {
            Write-Host "$outfile not downloaded"
        }

        # Run the downloaded script
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
            # Capture any errors during script execution
            $process_error = $_.Exception 
        }

        # Clean up temporary directories
        Set-Location "$working_dir"
        Remove-Item "$working_dir\$automation_name" -Force -Recurse

        # Display the result of script execution
        Write-Host $result
    }

    # Restore the previous working directory
    Set-Location $prev_cwd

    # Throw an error if there was an error during script execution
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
