function RunFromGit {
    param (
        [Parameter(Mandatory = $true)][string]$script,        # Path of file in GitHub repo
        $outfile,                                              # File to execute (probably same as above sans dirs)
        $automation_name,                                      # Used for temp dir names
        [string]$github_api_url = 'https://api.github.com/repos/blockheadvfx-it/boilerplates/contents', # If you are using a proxy change this
        [string]$github_raw_url = 'https://raw.githubusercontent.com/blockheadvfx-it',              # If you are using a proxy change this
        [bool]$load_helpers = $true,
        [bool]$user_mode = $false,                              # If running as logged on user instead of system user, will change working dir to $env:LOCALAPPDATA
        [string]$pub_branch = 'main'                            # Used to swap to different test branches if needed
    )

    function Source-Helpers {
        param ($base_url, $helper_files)

        foreach ($file in $helper_files) {
            Write-Host "Sourcing $file..."
            . ([Scriptblock]::Create((Invoke-WebRequest -Uri "$base_url/$file" -UseBasicParsing).Content))
        }
    }

    function Get-PersonalAccessToken {
        param ($pat_url_b64)

        $pat_url = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($pat_url_b64))
        $pat = (Invoke-WebRequest -Uri $pat_url -UseBasicParsing).Content | Out-String | Out-Null
        echo $pat
    }

    function Get-ScriptList {
        param ($github_api_url, $script)

        $headers = @{
            'Accept'               = 'application/vnd.github.v3.raw'
            'Authorization'        = "Bearer $pat"
            'X-GitHub-Api-Version' = '2022-11-28'
        }

        $response = Invoke-WebRequest -Uri "$github_api_url/$([system.uri]::EscapeDataString($script))" -UseBasicParsing -Headers $headers | ConvertFrom-Json

        $script_list = @() # Treat as an array even if we only end up with one script at a time

        if ($response.type -eq 'dir') {
            # If we get a directory, we will want to download and run every script within it
            foreach ($entry in $response.entries) {
                $script_list += $entry.path
            }
        } elseif ($response.type -eq 'file') {
            $script_list += $response.path
        }

        return $script_list
    }

    function Set-Up-Temp-Dirs {
        param ($trmm_dir, $automation_name)

        New-Item -ItemType Directory "$trmm_dir\$automation_name" -Force | Out-Null
        Set-Location "$trmm_dir\$automation_name"
    }

    function Download-Script {
        param ($github_api_url, $script, $headers, $outfile)

        Write-Host "Getting $script from GitHub..."
        Invoke-WebRequest -Uri "$github_api_url/$([system.uri]::EscapeDataString($script))" -Headers $headers -OutFile $outfile -UseBasicParsing

        if (Test-Path $outfile) {
            Write-Host "$outfile downloaded successfully"
        } else {
            Write-Host "$outfile not downloaded"
        }
    }

    function Run-Script {
        param ($outfile)

        $process_error = $false
        try {
            Write-Host "Running $outfile ..."
            & ".\$outfile" 2>&1 | Out-String
            $result = $LASTEXITCODE
            Write-Host "$outfile done, cleaning up..."
        } catch {
            # We will throw any errors later, after we have cleaned up dirs
            $process_error = $_.Exception 
        }

        return $result, $process_error
    }

    function Clean-Up {
        param ($trmm_dir, $automation_name)

        Set-Location "$trmm_dir"
        Remove-Item "$trmm_dir\$automation_name" -Force -Recurse

        if (Test-Path "$trmm_dir\$automation_name") {
            Write-Host "Failed to clean up $trmm_dir\$automation_name"
        } else {
            Write-Host "Cleaned up $trmm_dir\$automation_name"
        }
    }

    $prev_cwd = Get-Location

    try {
        # Get the install script from GitHub
        # Start by getting the PAT from S3 to access our private repo
        Write-Host 'Getting personal access token from S3...'
        # pat URL encoded with b64 here just to avoid getting grabbed by scrapers
        $pat_url_b64 = 'aHR0cHM6Ly90YW5nZWxvYnVja2V0bmluamEuczMuYXAtc291dGhlYXN0LTIuYW1hem9uYXdzLmNvbS90cm1tX2dpdGh1Yl9wYXQucGF0'
        Get-PersonalAccessToken -pat_url_b64 $pat_url_b64

        if ($load_helpers) {
            # If you want to add more helpers, include their names here and upload them to the 
            # powershell/helpers/ folder for the public GitHub repo
            $helper_files = @('create_shortcut.ps1', 'check_installed.ps1', 'set_env_var.ps1', 'set_reg_key.ps1', 'uninstall_program.ps1')
            $base_url = "$github_raw_url/tactical-public/$pub_branch/powershell/helpers"
            Source-Helpers -base_url $base_url -helper_files $helper_files
        }

        # Preconfigured variables:
        $trmm_dir = if ($user_mode) { "$env:LOCALAPPDATA\Temp" } else { 'C:\ProgramData\NinjaRMMAgent' }

        $script_list = Get-ScriptList -github_api_url $github_api_url -script $script

        foreach ($script in $script_list) {
            $outfile = Split-Path -Path $script -Leaf
            $automation_name = Format-InvalidPathCharacters -path $outfile

            Set-Up-Temp-Dirs -trmm_dir $trmm_dir -automation_name $automation_name

            # Download URL
            $headers = @{
                'Accept'               = 'application/vnd.github.v3.object'
                'Authorization'        = "Bearer $pat"
                'X-GitHub-Api-Version' = '2022-11-28'
            }

            if ($pat -like 'github_pat*') {
                Write-Host 'Got personal access token'
            } else {
                Write-Host 'Did not get personal access token'
            }

            Download-Script -github_api_url $github_api_url -script $script -headers $headers -outfile $outfile

            $result, $process_error = Run-Script -outfile $outfile

            Clean-Up -trmm_dir $trmm_dir -automation_name $automation_name

            Write-Host $result
        }

        Set-Location $prev_cwd

        if ($process_error) {
            throw $process_error
        } else {
            return $result
        }
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)"
        throw $_.Exception
    }
}

function Format-InvalidPathCharacters {
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
# RunFromGit -script "path/to/your/script.ps1"
