<#
.SYNOPSIS
    Deactivates Adobe Acrobat Pro 2020 on Windows

.DESCRIPTION
    Deactivates Adobe Acrobat Pro 2020 on Windows

.NOTES
    Version    : 1.0.0
    Author(s)  : Cody Moler
    License    : MIT License

.LINK
    GitHub: https://github.com/codymoler
#>

# Get the original working directory
$OriginalLocation = Get-Location

# Remove progress bar from download command
$ProgressPreference = "SilentlyContinue"

# Check if Adobe Acrobat Pro 2020 is installed
$AcrobatInstallPath = "C:\Program Files (x86)\Adobe\Acrobat 2020\Acrobat"
$AcrobatInstallStatus = (Get-ItemProperty "HKLM:\Software\Adobe\Adobe Acrobat\2020\InstallPath" | Where { $_.'(default)' -eq $AcrobatInstallPath }) -ne $null
If($AcrobatInstallStatus) {
    $AcrobatFlag = $true

    # Check if Acrobat is activated. Exit script if not.
    If (Test-Path -Path "$env:ProgramData\regid.1986-12.com.adobe\regid.1986-12.com.adobe_V7{}AcrobatESR-20-Win-GM-en_US.swidtag" -PathType Leaf -ErrorAction 'silentlycontinue')
    {
        $Tag = Get-Content "$env:ProgramData\regid.1986-12.com.adobe\regid.1986-12.com.adobe_V7{}AcrobatESR-20-Win-GM-en_US.swidtag"
        foreach ($Line in $Tag)
        {
            If($Line -Like "*<swid:activation_status>*")
            {
                If($Line -Like "*unlicensed*") 
                {
                    Write-Output "Adobe Acrobat 2020 is already deactivated. Exiting script."
                    exit 1
                }
            }
        }
    }
}

# Check if the temporary directory exists. Create it if not.
$path = "$env:ProgramData\acrobat_temp"
If(!(Test-Path $path))
{
      New-Item -ItemType Directory -Force -Path $path
}
Else
{
    Remove-Item $path -Recurse -Force
    New-Item -ItemType Directory -Force -Path $path
}

# Set the location to the temp directory
Set-Location $path

# Check if 7-Zip is already installed. Install it if not. (Required to extract the Adobe Provisioning Toolkit)
$7Zip = "7-Zip 19.00 (x64 edition)"
$7ZipInstallStatus = (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where { $_.DisplayName -eq $7Zip }) -ne $null
If(-Not $7ZipInstallStatus)
{
    # Source for 7-Zip installer
    $link7Zip = 'https://www.7-zip.org/a/7z1900-x64.msi'

    # Destination for 7-Zip installer
    $dest7Zip = "$path\7z1900-x64.msi"

    # Download the installer
    Invoke-WebRequest -Uri $link7Zip -OutFile $dest7Zip

    # Install 7-Zip
    Start-Process msiexec.exe -Wait -WindowStyle Hidden -ArgumentList "/I $dest7Zip /quiet"

    # Set flag for uninstall at end of script
    $7ZipFlag = $true
}

# Source for Adobe Provisioning Toolkit
$linkToolkit = 'https://helpx.adobe.com/content/dam/help/en/enterprise/kb/provisioning-toolkit-enterprise/jcr_content/main-pars/download_section/download-1/adobe_prtk.zip'

# Destination for Adobe Provisioning Toolkit
$destToolkit = "$path\adobe_prtk.zip"

# Download the toolkit
Invoke-WebRequest -Uri $linkToolkit -OutFile $destToolkit

# Unzip the toolkit
Expand-Archive -LiteralPath $destToolkit -DestinationPath $path -Force
Start-Process "$env:ProgramW6432\7-Zip\7z.exe" -Wait -WindowStyle Hidden -ArgumentList "x $path\adobe_prtk.exe -o$path"

# Set the location to the toolkit directory
Set-Location "Adobe_Provisioning_Toolkit*\Adobe Provisioning Toolkit Enterprise Edition"

# Deactivate the software
$ReturnCodes = Start-Process adobe_prtk.exe -Wait -PassThru -WindowStyle Hidden -ArgumentList "--tool=UnSerialize --leid=V7{}AcrobatESR-20-Win-GM --deactivate --force [-removeSWTag]"

# Check if deactivation was successful. Clean up and exit script if not.
If($ReturnCodes.ExitCode -ne '0')
{
    Write-Output "Dectivation failed. Exiting script."
    Set-Location $OriginalLocation.Path
    Remove-Item $path -Recurse -Force
	
    # Uninstall 7-Zip
    If($7ZipFlag)
	{
		$command = (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where { $_.DisplayName -eq $7Zip }).UninstallString
		$command = $command.Trim("MsiExec.exe /I")
		Start-Process msiexec.exe -Wait -ArgumentList "/X$command /qn"
	}
    exit 2
}

# Activation Successful. Cleanup.
Set-Location $OriginalLocation.Path
Remove-Item $path -Recurse -Force

# Uninstall 7-Zip
If($7ZipFlag)
{
    $command = (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where { $_.DisplayName -eq $7Zip }).UninstallString
    $command = $command.Trim("MsiExec.exe /I")
    Start-Process msiexec.exe -Wait -ArgumentList "/X$command /qn"
}
