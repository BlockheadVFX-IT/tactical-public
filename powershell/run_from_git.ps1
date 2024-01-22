function RunFromGit {
    param (
        [Parameter(Mandatory = $true)][string]$script,
        $outfile,
        $automation_name,
        [string]$github_api_url = 'https://api.github.com/repos/blockheadvfx-it/boilerplates/contents',
        [string]$github_raw_url = 'https://raw.githubusercontent.com/blockheadvfx-it',
        [bool]$load_helpers = $true,
        [bool]$user_mode = $false,
        [string]$pub_branch = 'main'
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
        $pat = (Invoke-WebRequest -Uri $pat_url -UseBasicParsing).Content
        return $pat
    }

    function Get-ScriptList {
        param ($github_api_url, $script)

        $headers = @{
            'Accept'               = 'application/vnd.github.v3.raw'
            'Authorization'        = "Bearer $pat"
            'X-GitHub-Api-Version' = '2022-11-28'
        }

        $response = Invoke-WebRequest -Uri "$github_api_url/$([system.uri]::EscapeDataString($script))" -UseBasicParsing -Headers $headers | ConvertFrom-Json

        $script_list = @()

        if ($response.type -eq 'dir') {
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
        $response = Invoke-WebRequest -Uri "$github_api_url/$([system.uri]::EscapeDataString($script))" -Headers $headers -OutFile $outfile -UseBasicParsing
        Write-Host "Response: $($response.StatusCode)"

        if ($response.StatusCode -eq 200) {
            Write-Host "$outfile downloaded successfully"
        } else {
            Write-Host "$outfile not downloaded. Response: $($response.Content)"
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
        $pat_url_b64 = 'aHR0cHM6Ly90YW5nZWxvYnVja2V0bmluamEuczMuYXAtc291dGhlYXN0LTIuYW1hem9uYXdzLmNvbS90cm1tX2dpdGh1Yl9wYXQucGF0'
        $pat = Get-PersonalAccessToken -pat_url_b64 $pat_url_b64

        if ($load_helpers) {
            $helper_files = @('create_shortcut.ps1', 'check_installed.ps1', 'set_env_var.ps1', 'set_reg_key.ps1', 'uninstall_program.ps1')
            $base_url = "$github_raw_url/tactical-public/$pub_branch/powershell/helpers"
            Source-Helpers -base_url $base_url -helper_files $helper_files
        }

        $trmm_dir = if ($user_mode) { "$env:LOCALAPPDATA\Temp" } else { 'C:\ProgramData\NinjaRMMAgent' }
        $script_list = Get-ScriptList -github_api_url $github_api_url -script $script

        foreach ($script in $script_list) {
            $outfile = Split-Path -Path $script -Leaf
            $automation_name = Format-InvalidPathCharacters -path $outfile

            Set-Up-Temp-Dirs -trmm_dir $trmm_dir -automation_name $automation_name

            $headers = @{
                'Accept'               = 'application/vnd.github.v3.object'
                'Authorization'        = "Bearer $pat"
                'X-GitHub-Api-Version' = '2022-11-28'
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

    $invalidCharsPattern = '[\\/:*?"<>|]'
    $escapedPath = [regex]::Replace($path, $invalidCharsPattern, '_')

    return $escapedPath
}

# Example usage:
# RunFromGit -script "path/to/your/script.ps1"
