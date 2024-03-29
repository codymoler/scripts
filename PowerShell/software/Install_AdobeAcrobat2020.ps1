﻿<#
.SYNOPSIS
    Installs and activates Adobe Acrobat Pro 2020 on Windows 8/10/11

.DESCRIPTION
    Installs and activates Adobe Acrobat Pro 2020 on Windows 8/10/11.
    Removes other versions of Adobe Acrobat and Reader if installed.

.PARAMETER serial
    Specifies the serial number XXXX-XXXX-XXXX-XXXX-XXXX-XXXX

.NOTES
    Version    : 1.0.0
    Author(s)  : Cody Moler
    License    : MIT License

.LINK
    GitHub: https://github.com/codymoler
#>

Param(
    [Parameter(Mandatory=$True,Position=1)]
    [string]$serial
)

# Get the original working directory
$OriginalLocation = Get-Location

# Remove progress bar from download command
$ProgressPreference = "SilentlyContinue"

# Check if Adobe Acrobat Pro 2020 is already installed
$AcrobatInstallPath = "C:\Program Files (x86)\Adobe\Acrobat 2020\Acrobat"
$AcrobatInstallStatus = (Get-ItemProperty "HKLM:\Software\Adobe\Adobe Acrobat\2020\InstallPath" | Where { $_.'(default)' -eq $AcrobatInstallPath }) -ne $null
If($AcrobatInstallStatus) {
    $AcrobatFlag = $true

    # Check if Acrobat is already activated. Exit script if true.
    If (Test-Path -Path "$env:ProgramData\regid.1986-12.com.adobe\regid.1986-12.com.adobe_V7{}AcrobatESR-20-Win-GM-en_US.swidtag" -PathType Leaf -ErrorAction "SilentlyContinue")
    {
        $Tag = Get-Content "$env:ProgramData\regid.1986-12.com.adobe\regid.1986-12.com.adobe_V7{}AcrobatESR-20-Win-GM-en_US.swidtag"
        foreach ($Line in $Tag)
        {
            If($Line -Like "*<swid:activation_status>*")
            {
                If($Line -NotLike "*unlicensed*") 
                {
                    Write-Output "Adobe Acrobat 2020 is already activated. Exiting script."
                    exit 1
                }
            }
        }
    }
}

# Uninstall other Adobe Acrobat installations (including Reader)
Stop-Process -Name "Acrobat" -Force -ErrorAction "SilentlyContinue"
Stop-Process -Name "AcroRd32" -Force -ErrorAction "SilentlyContinue"
$Apps = Get-WmiObject -Class Win32_Product | Where-Object{$_.Name -like "Adobe Acrobat*"}
foreach ($App in $Apps)
{
    If($App.Name -ne "Adobe Acrobat 2020")
    {
        $App.Uninstall()
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

# Install Acrobat if it's not already installed
If(-Not $AcrobatFlag)
{
    # Source for Adobe Acrobat installation files
    $linkAcrobat = 'https://trials.adobe.com/AdobeProducts/APRO/Acrobat_HelpX/win32/Acrobat_2020_Web_WWMUI.zip'

    # Destination for Adobe Acrobat installation files
    $destAcrobat = "$path\Acrobat_2020_Web_WWMUI.zip"

    # Download the installer
    Invoke-WebRequest -Uri $linkAcrobat -OutFile $destAcrobat

    # Unzip the files
    Expand-Archive -LiteralPath $destAcrobat -DestinationPath $path -Force
    
    # Install Acrobat
    Start-Process "$path\Adobe Acrobat\setup.exe" -Wait -WindowStyle Hidden -ArgumentList "/sl en_US /sALL"

    # Check if the installation was successful. Exit script if not.
    $AcrobatInstallStatus = (Get-ItemProperty "HKLM:\Software\Adobe\Adobe Acrobat\2020\InstallPath" | Where { $_.'(default)' -eq $AcrobatInstallPath }) -ne $null
    If(-Not $AcrobatInstallStatus) {
	    Write-Output "The installation failed. Exiting script."
        Set-Location $OriginalLocation.Path
        Remove-Item $path -Recurse
        exit 2
    }
    $AcrobatInstalledFlag = $true
}

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

# Generate prov.xml
Start-Process adobe_prtk.exe -Wait -WindowStyle Hidden -ArgumentList "--tool=VolumeSerialize --generate --serial=$serial --leid=V7{}AcrobatESR-20-Win-GM --regsuppress=ss --eulasuppress"

# Activate the software
$ReturnCodes = Start-Process adobe_prtk.exe -Wait -PassThru -WindowStyle Hidden -ArgumentList "--tool=VolumeSerialize --provfile=prov.xml --stream"

# Check if activation was successful. Clean up and exit script if not.
If($ReturnCodes.ExitCode -ne '0')
{
    Write-Output "Activation failed. Exiting script."
    Set-Location $OriginalLocation.Path
    Remove-Item $path -Recurse -Force
	
    # Uninstall 7-Zip
    If($7ZipFlag)
	{
		$command = (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where { $_.DisplayName -eq $7Zip }).UninstallString
		$command = $command.Trim("MsiExec.exe /I")
		Start-Process msiexec.exe -Wait -ArgumentList "/X$command /qn"
	}
    
    # Uninstall Adobe Acrobat 2020
    If($AcrobatInstalledFlag)
    {
        $Acrobat = Get-WmiObject -Class Win32_Product | Where-Object{$_.Name -eq "Adobe Acrobat 2020"}
        $Acrobat.Uninstall()
    }
    exit 3
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
