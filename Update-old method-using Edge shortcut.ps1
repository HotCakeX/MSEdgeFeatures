$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
$URL1 = 'https://go.microsoft.com/fwlink/?linkid=2084706&Channel=Canary&language=en'
$URL2 = 'https://c2rsetup.edog.officeapps.live.com/c2r/downloadEdge.aspx?platform=Default&source=EdgeInsiderPage&Channel=Canary&language=en'
$EdgeCanaryInstallerPath = "$env:tmp\MicrosoftEdgeSetupCanary.exe"
$AppPath = "C:\Users\$env:USERNAME\AppData\Local\Microsoft\Edge SxS\Application"
$StringsExe = "$env:tmp\strings64.exe"

#Region Downloading-Stuff
Write-Host 'Downloading Edge Canary'
try {
    Invoke-RestMethod -Uri $URL1 -OutFile $EdgeCanaryInstallerPath | Out-Null
}
catch {
    try {
        Invoke-RestMethod -Uri $URL2 -OutFile $EdgeCanaryInstallerPath | Out-Null
    }
    catch {
        Write-Host 'Failed to download Edge from both URLs. Exiting...'
        exit
    }
}

Write-Host 'Downloading Strings64.exe'
try {
    Invoke-RestMethod -Uri 'https://live.sysinternals.com/strings64.exe' -OutFile $StringsExe | Out-Null
}
catch {
    Write-Host 'Failed to download Strings64. Exiting...'
    exit
}
#EndRegion Downloading-Stuff

Write-Host 'Installing Edge Canary'
Start-Process -FilePath $EdgeCanaryInstallerPath

Write-Host 'Waiting for Edge Canary to be downloaded and installed' -ForegroundColor Green

# Checking for completion of the Edge Canary online installer by actively checking for the presence of the dll file that we need, every 5 seconds
do {
    $file = Get-ChildItem -Path $AppPath -Filter 'msedge.dll' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($file) {
        Write-Host "File found: $($file.FullName)"
        Start-Sleep -Seconds 5
        break
    }
    else {
        Write-Host 'File not found. Waiting for 5 second...'
        Start-Sleep -Seconds 5
    }
}
while ($true)


Write-Host "Accepting Strings64's EULA via Registry"

# Add the necessary registry key to accept the EULA of the Strings from SysInternals
$RegistryPath = 'HKCU:\Software\Sysinternals\Strings'
$Name = 'EulaAccepted'
$Value = 1
if (Test-Path -Path $RegistryPath) {
    Set-ItemProperty -Path $RegistryPath -Name $Name -Value $Value
}
else {
    New-Item -Path $RegistryPath -Force | Out-Null
    New-ItemProperty -Path $RegistryPath -Name $Name -Value $Value -PropertyType DWORD -Force | Out-Null
}

# Finding the latest version of the Edge Canary from its installation directory's name
Write-Host 'Searching for the Edge Canary version that was just downloaded'
$Version = (Get-ChildItem $AppPath -Directory | Where-Object { $_.Name -like '1*' } | Select-Object -First 1).Name
$Split = $Version.Split('.')
$DllPath = "$AppPath\$Version\msedge.dll"
Write-Host "DLL PATH = $DllPath"

# Expanding the current directory structure that is in GitHub repository to include the new Edge Canary version
if (!(Test-Path '.\Edge Canary')) { New-Item '.\Edge Canary' -ItemType Directory -Force | Out-Null }
if (!(Test-Path ".\Edge Canary\$($Split[0])")) { New-Item ".\Edge Canary\$($Split[0])" -ItemType Directory -Force | Out-Null }
# Check to make sure there is no directory with the same name as the current Edge Canary version and it's not empty
if (!(Test-Path -Path ".\Edge Canary\$($Split[0])\$Version\*")) {

    # Creating a new directory for the new available Edge Canary version
    New-Item ".\Edge Canary\$($Split[0])\$Version" -ItemType Directory -Force | Out-Null

    # Check whether the current Edge Canary version is the first release in a new major version. If it is, then some actions will be triggered
    if ((Get-ChildItem ".\Edge Canary\$($Split[0])" -Directory).count -eq 1) {

        # Loop through each directory of major Edge canary versions and get the directory that belongs to the last previous version
        foreach ($CurrentPipelineVersion in ((Get-ChildItem '.\Edge Canary\' -Directory | Where-Object { $_.Name -match '^\d\d\d$' } | Sort-Object Name -Descending).Name | Select-Object -Skip 1)) {

            # Make sure the directory is not empty (which is kinda impossible to be empty, but just in case)
            if ((Get-ChildItem ".\Edge Canary\$CurrentPipelineVersion" -Directory | Sort-Object Name -Descending | Select-Object -First 1).count -ne 0) {

                # Locating the last version of Edge Canary that was processed prior to this current version so we can access its directory on repository
                $PreviousVersion = (Get-ChildItem ".\Edge Canary\$CurrentPipelineVersion" -Directory | Sort-Object Name -Descending | Select-Object -First 1).Name
                # Get the major version
                $PreviousVersionSplit = $PreviousVersion.Split('.')
                # if the directory is found, stop the loop
                break
            }
            else {
                # if the directory that belongs to the previous major Edge canary version is completely empty, then skip the currently processing major version entirely and look for the one before it
                continue
            }
        }
    }
    # if the current Edge canary version is not the first release in a major version
    else {
        $PreviousVersion = (Get-ChildItem ".\Edge Canary\$($Split[0])" -Directory | Sort-Object -Descending | Select-Object -Skip 1 -First 1).Name
        $PreviousVersionSplit = $PreviousVersion.Split('.')
    }

    Write-Host "Comparing version: $version with version: $PreviousVersion" -ForegroundColor Cyan

    Write-Host 'Strings64 Running...'

    # Storing the output of the Strings64 in an object
    $Objs = & $StringsExe $DllPath |
    Select-String -Pattern '^(ms[a-zA-Z0-9]{4,})$' |
    ForEach-Object { $_.Matches.Groups[0].Value } | Sort-Object

    # Outputting the object containing the final original results to a file
    $Objs | Out-File ".\Edge Canary\$($Split[0])\$Version\original.txt"

    Write-Host "Saved = .\Edge Canary\$($Split[0])\$Version\original.txt ($($Objs.count) entries)"

    $PreviousObjs = Get-Content ".\Edge Canary\$($PreviousVersionSplit[0])\$PreviousVersion\original.txt" | Sort-Object

    $Added = $Objs | Where-Object { $_ -notin $PreviousObjs }
    $Added | Out-File ".\Edge Canary\$($Split[0])\$Version\added.txt"

    $Removed = $PreviousObjs | Where-Object { $_ -notin $Objs }
    $Removed | Out-File ".\Edge Canary\$($Split[0])\$Version\removed.txt"

    Write-Host "Added features .\Edge Canary\$($Split[0])\$Version\added.txt ($($Added.count) entries)"
    Write-Host "Removed features .\Edge Canary\$($Split[0])\$Version\removed.txt ($($Removed.count) entries)"

    # Storing the latest version in a file
    $Version | Out-File .\last.txt

    #region ReadMe-Updater
    $DetailsToReplace = @"
`n### <a href="https://github.com/HotCakeX/MSEdgeFeatures"><img width="35" src="https://github.com/HotCakeX/Harden-Windows-Security/raw/main/images/WebP/Edge%20Canary.webp"></a> Latest Edge Canary version: $Version`n
### Last processed at: $(Get-Date -AsUTC) (UTC+00:00)`n
<details>
<summary>$($added.count) new features were added in the latest Edge Canary update</summary>

<br>

$($added | ForEach-Object {"* $_`n"})
</details>`n
"@

    # Showing extra details on the Readme page of the repository about the latest Edge Canary version
    $readme = Get-Content -Raw -Path 'README.md'
    $readme = $readme -replace '(?s)(?<=<!-- Edge-Canary-Version:START -->).*(?=<!-- Edge-Canary-Version:END -->)', $DetailsToReplace
    Set-Content -Path 'README.md' -Value $readme.TrimEnd()
    #endregion ReadMe-Updater

    #region GitHub-Committing

    # Committing the changes back to the repository
    git config --global user.email 'spynetgirl@outlook'
    git config --global user.name 'HotCakeX'
    git add --all
    git commit -m 'Automated Update'
    git push

    #endregion GitHub-Committing


    #region Edge-Canary-ShortCut-Maker-Code

    # Putting the Edge canary shortcut maker's code in the EdgeCanaryShortcutMaker.ps1 file

    New-Item -Path '.\EdgeCanaryShortcutMaker.ps1' -Force


    $AddedArray = $Added -join ','
    $PreArguments = "--enable-features=$AddedArray"
    $PreArguments = $PreArguments.TrimEnd(',')

    $contenttoadd = @"

    `$arguments = `"$PreArguments`"

    function New-Shortcut {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = `$true)][ValidateNotNullOrEmpty()][string]`$Path,
            [Parameter(Mandatory = `$true)][ValidateNotNullOrEmpty()][string]`$Target,
            [Parameter(Mandatory = `$true)][ValidateNotNullOrEmpty()][string]`$Description,
            [Parameter(Mandatory = `$true)][ValidateNotNullOrEmpty()][string]`$WorkingDirectory,
            [string]`$Arguments,
            [string]`$Icon
        )
        if (!(Test-Path `$Path)) {
            if (!(Test-Path `$Path)) {
                `$WshShell = New-Object -ComObject WScript.Shell
                `$Shortcut = `$WshShell.CreateShortcut(`$Path)
                `$Shortcut.TargetPath = `$Target
                if (![string]::IsNullOrEmpty(`$Arguments)) { `$Shortcut.Arguments = `$Arguments }
                if (![string]::IsNullOrEmpty(`$Icon)) { `$Shortcut.IconLocation = `$Icon }
                `$Shortcut.Description = `$Description
                `$Shortcut.WorkingDirectory = `$WorkingDirectory
                `$Shortcut.Save()
            }
        }
    }
    if (Test-Path "C:\Users\`$env:USERNAME\Downloads\EDGECAN.lnk") { Remove-Item "C:\Users\`$env:USERNAME\Downloads\EDGECAN.lnk" }
    New-Shortcut -Path "C:\Users\`$env:USERNAME\Downloads\EDGECAN.lnk" ``
        -Target "C:\Users\`$env:USERNAME\AppData\Local\Microsoft\Edge SxS\Application\msedge.exe" ``
        -Description "Microsoft Edge" ``
        -WorkingDirectory "C:\Users\`$env:USERNAME\AppData\Local\Microsoft\Edge SxS\Application" ``
        -Icon "C:\Users\`$env:USERNAME\AppData\Local\Microsoft\Edge SxS\User Data\Default\Edge Profile.ico" ``
        -Arguments `$arguments

"@

    Set-Content -Value $contenttoadd -Path '.\EdgeCanaryShortcutMaker.ps1' -Force

    #endregion Edge-Canary-ShortCut-Maker-Code

    #region GitHub-Release-Publishing

    # Publishing the Release without Body of the Release (i.e. text)

    # Doing this first so that people watching the repository will see this in the Emails that they get
    # But won't see the PowerShell link because it will be added to the Release body using the Patch method, after this
    # Without this, the email would have empty content for the body of the Release

    $GitHubReleaseBodyContent = @"
# <img width="35" src="https://github.com/HotCakeX/Harden-Windows-Security/raw/main/images/WebP/Edge%20Canary.webp"> Automated update

## Processed at: $(Get-Date -AsUTC) (UTC+00:00)`n

Visit the GitHub's release section for full details on how to use it:
https://github.com/HotCakeX/MSEdgeFeatures/releases/tag/$Version

### $($added.count) New features were added

$($added | ForEach-Object {"* $_`n"})

<br>

### $($Removed.count) Features were removed

$($Removed | ForEach-Object {"* $_`n"})

<br>

"@

    # Get the latest commit SHA
    $LATEST_SHA = git rev-parse HEAD
    # Create a release with the latest commit as tag and target
    $RELEASE_RESPONSE = Invoke-RestMethod -Uri 'https://api.github.com/repos/HotCakeX/MSEdgeFeatures/releases' `
        -Method POST `
        -Headers @{Authorization = "token $env:GITHUB_TOKEN" } `
        -Body (@{tag_name = "$Version"; target_commitish = $LATEST_SHA; name = "Edge Canary version $Version"; body = "$GitHubReleaseBodyContent"; draft = $false; prerelease = $false } | ConvertTo-Json)

    # Use the gh CLI command to upload the EdgeCanaryShortcutMaker.ps1 file to the release as asset
    gh release upload $Version ./EdgeCanaryShortcutMaker.ps1 --clobber

    $ASSET_NAME = 'EdgeCanaryShortcutMaker.ps1'

    # Making sure the download link is direct
    $ASSET_DOWNLOAD_URL = "https://github.com/HotCakeX/MSEdgeFeatures/releases/download/$Version/$ASSET_NAME"


    # Body of the Release that is going to be added via a patch method
    $GitHubReleaseBodyContent = @"
# <img width="35" src="https://github.com/HotCakeX/Harden-Windows-Security/raw/main/images/WebP/Edge%20Canary.webp"> Automated update

## Processed at: $(Get-Date -AsUTC) (UTC+00:00)`n

### $($added.count) New features were added

$($added | ForEach-Object {"* $_`n"})

<br>

### $($Removed.count) Features were removed

$($Removed | ForEach-Object {"* $_`n"})

<br>

### How to use the new features in this Edge canary update

1. First make sure your Edge canary is up to date

2. Copy and paste the code below in your PowerShell. NO admin privileges required. An Edge canary shortcut will be created in your Downloads folder. Double-click/tap on it to launch Edge canary with the features added in this update.

<br>

``````powershell
invoke-restMethod '$ASSET_DOWNLOAD_URL' | Invoke-Expression
``````

"@

    # Add the body of the Release with the link to the EdgeCanaryShortcutMaker.ps1 asset file included
    Invoke-RestMethod -Uri "https://api.github.com/repos/HotCakeX/MSEdgeFeatures/releases/$($RELEASE_RESPONSE.id)" -Method PATCH -Headers @{Authorization = "token $env:GITHUB_TOKEN" } -Body (@{body = "$GitHubReleaseBodyContent" } | ConvertTo-Json)

    #endregion GitHub-Release-Publishing

}
else {
    Write-Host 'BUILD ALREADY EXISTS, EXITING.' -ForegroundColor Red
    Exit 0
}
