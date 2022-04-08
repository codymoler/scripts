#!/bin/bash
function promptComputerName() {
HOSTNAME=$(osascript <<EOF
use AppleScript version "2.4" -- Yosemite (10.10) or later
use scripting additions
set theTextReturned to "nil"
set appTitle to "Library IT Operations"
set okTextButton to "OK"
set changesText to "Please enter a computername for this computer:"
set theResponse to display dialog {changesText} default answer "" buttons {okTextButton} default button 1 with title {appTitle}
set theTextReturned to the text returned of theResponse
if theTextReturned is "nil" then
return "cancelled"
else
return theTextReturned
end if
EOF
)
}

promptComputerName

# Set the computername
printf "\nSetting HostName value to $HOSTNAME"
scutil --set HostName $HOSTNAME
printf "\nSetting LocalHostName value to $HOSTNAME"
scutil --set LocalHostName $HOSTNAME
printf "\nSetting ComputerName value to $HOSTNAME"
scutil --set ComputerName $HOSTNAME
printf "\nHostname configuration completed.\n"
