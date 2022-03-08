<#
.SYNOPSIS
    Deletes inactive domain users
.DESCRIPTION
    Deletes the user profiles for domain users who have not logged on to the local machine in over 30 days.
.NOTES
    Version    : 1.0.0
    Author(s)  : Cody Moler
    License    : MIT License
.LINK
    GitHub: https://github.com/codymoler
#>

#Function to calculate the last logon time for a user. Requires the user's SID.
function Get-LocalLogonTime {
    param (
        [Alias('SID')]
        [string[]] $SidString
    )

    $RegKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$SidString"
    #Gather user information from registry key
    $Raw = Get-ItemProperty -Path $RegKey -Verbose:$false
    #Calculate logon time value
    $LocalLogonTime = ([uint64] ($Raw.LocalProfileLoadTimeHigh * ([Math]::Pow(2,32))) + $Raw.LocalProfileLoadTimeLow)
    #Convert logon time value from FileTime to DateTime
    $LocalLogonTime = [datetime]::fromfiletime($LocalLogonTime)
    #Return the DateTime value
    $LocalLogonTime
}

#Search the Registry to collect the SIDs of all domain users that have logged onto the machine.
$DomainUsers = (Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileGUID" | Get-ItemProperty).SidString

#For each domain user, check if they've logged on in the last 30 days. If not, delete them.
ForEach ($DomainUser in $DomainUsers) {
    $LastLogon = Get-LocalLogonTime -SidString "$DomainUser"
    If ($LastLogon -lt (Get-Date).AddDays(-30)) {
        $UserProfile = Get-WMIObject -class Win32_UserProfile | Where-Object -Property SID -like "$DomainUser"
        $UserProfile.Delete()
    }
}
