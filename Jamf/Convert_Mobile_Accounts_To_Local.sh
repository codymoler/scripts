#!/bin/bash
# Original source is from MigrateUserHomeToDomainAcct.sh
# Written by Patrick Gallagher | Modified by Rich Trouton | Rewritten by Cody Moler to run silently

# Unbinds a Mac from an AD domain and converts all mobile accounts to local

RemoveAD(){

    # This function force-unbinds the Mac from the existing Active Directory domain
    # and updates the search path settings to remove references to Active Directory

    searchPath=`/usr/bin/dscl /Search -read . CSPSearchPath | grep Active\ Directory | sed 's/^ //'`

    # Force unbind from Active Directory
    /usr/sbin/dsconfigad -remove -force -u none -p none

    # Deletes the Active Directory domain from the custom /Search
    # and /Search/Contacts paths
    /usr/bin/dscl /Search/Contacts -delete . CSPSearchPath "$searchPath"
    /usr/bin/dscl /Search -delete . CSPSearchPath "$searchPath"

    # Changes the /Search and /Search/Contacts path type from Custom to Automatic
    /usr/bin/dscl /Search -change . SearchPolicy dsAttrTypeStandard:CSPSearchPath dsAttrTypeStandard:NSPSearchPath
    /usr/bin/dscl /Search/Contacts -change . SearchPolicy dsAttrTypeStandard:CSPSearchPath dsAttrTypeStandard:NSPSearchPath
}

PasswordMigration(){

    # macOS 10.14.4 will remove the the actual ShadowHashData key immediately
    # if the AuthenticationAuthority array value which references the ShadowHash
    # is removed from the AuthenticationAuthority array. To address this, the
    # existing AuthenticationAuthority array will be modified to remove the Kerberos
    # and LocalCachedUser user values.

    AuthenticationAuthority=$(/usr/bin/dscl -plist . -read /Users/$netname AuthenticationAuthority)
    Kerberosv5=$(echo "${AuthenticationAuthority}" | xmllint --xpath 'string(//string[contains(text(),"Kerberosv5")])' -)
    LocalCachedUser=$(echo "${AuthenticationAuthority}" | xmllint --xpath 'string(//string[contains(text(),"LocalCachedUser")])' -)

    # Remove Kerberosv5 and LocalCachedUser
    if [[ ! -z "${Kerberosv5}" ]]; then
        /usr/bin/dscl -plist . -delete /Users/$netname AuthenticationAuthority "${Kerberosv5}"
    fi

    if [[ ! -z "${LocalCachedUser}" ]]; then
        /usr/bin/dscl -plist . -delete /Users/$netname AuthenticationAuthority "${LocalCachedUser}"
    fi
}

# Save current IFS state
OLDIFS=$IFS

# Obtain list of users
listUsers="$(/usr/bin/dscl . list /Users UniqueID | awk '$2 > 1000 {print $1}')"

# Create array from Users List string
set -o noglob
IFS=$'\n' list=($listUsers)
set +o noglob

# Check if the device is connected to AD
check4AD=`/usr/bin/dscl localhost -list . | grep "Active Directory"`

# restore IFS to previous state
IFS=$OLDIFS

# Check for AD binding and unbind if found.
if [[ "${check4AD}" = "Active Directory" ]]; then
	RemoveAD
	/bin/echo "AD binding has been removed."
fi

for netname in "${list[@]}"; do
	# Check if the user is an AD mobile account
	accounttype=`/usr/bin/dscl . -read /Users/"$netname" AuthenticationAuthority | head -2 | awk -F'/' '{print $2}' | tr -d '\n'`

	if [[ "$accounttype" = "Active Directory" ]]; then
		mobileusercheck=`/usr/bin/dscl . -read /Users/"$netname" AuthenticationAuthority | head -2 | awk -F'/' '{print $1}' | tr -d '\n' | sed 's/^[^:]*: //' | sed s/\;/""/g`
		if [[ "$mobileusercheck" = "LocalCachedUser" ]]; then
			/usr/bin/printf "$netname has an AD mobile account.\nConverting to a local account with the same username and UID.\n"
		else
			/usr/bin/printf "The $netname account is not am AD mobile account\n"
			break
		fi
	else
		/usr/bin/printf "The $netname account is not an AD mobile account\n"
		break
	fi

	# Check if the account has admin rights
	if id -Gn $netname | grep -q -w admin; then
		admin=true
	else
		admin=false
	fi

	# Remove the account attributes that identify it as an Active Directory mobile account
	/usr/bin/dscl . -delete /users/$netname cached_groups
	/usr/bin/dscl . -delete /users/$netname cached_auth_policy
	/usr/bin/dscl . -delete /users/$netname CopyTimestamp
	/usr/bin/dscl . -delete /users/$netname AltSecurityIdentities
	/usr/bin/dscl . -delete /users/$netname SMBPrimaryGroupSID
	/usr/bin/dscl . -delete /users/$netname OriginalAuthenticationAuthority
	/usr/bin/dscl . -delete /users/$netname OriginalNodeName
	/usr/bin/dscl . -delete /users/$netname SMBSID
	/usr/bin/dscl . -delete /users/$netname SMBScriptPath
	/usr/bin/dscl . -delete /users/$netname SMBPasswordLastSet
	/usr/bin/dscl . -delete /users/$netname SMBGroupRID
	/usr/bin/dscl . -delete /users/$netname PrimaryNTDomain
	/usr/bin/dscl . -delete /users/$netname AppleMetaRecordName
	/usr/bin/dscl . -delete /users/$netname PrimaryNTDomain
	/usr/bin/dscl . -delete /users/$netname MCXSettings
	/usr/bin/dscl . -delete /users/$netname MCXFlags

	# Migrate password and remove AD-related attributes
	PasswordMigration

	# Refresh Directory Services
	if [[ ( ${osvers_major} -eq 10 && ${osvers_minor} -lt 7 ) ]]; then
		/usr/bin/killall DirectoryService
	else
		/usr/bin/killall opendirectoryd
	fi

	sleep 20

	accounttype=`/usr/bin/dscl . -read /Users/"$netname" AuthenticationAuthority | head -2 | awk -F'/' '{print $2}' | tr -d '\n'`
	if [[ "$accounttype" = "Active Directory" ]]; then
		/usr/bin/printf "Something went wrong with the conversion process.\nThe $netname account is still an AD mobile account.\n"
		fail=true
	else
		/usr/bin/printf "Conversion process was successful.\nThe $netname account is now a local account.\n"
	fi

	homedir=`/usr/bin/dscl . -read /Users/"$netname" NFSHomeDirectory  | awk '{print $2}'`
	if [[ "$homedir" != "" ]]; then
		/bin/echo "Home directory location: $homedir"
		/bin/echo "Updating home folder permissions for the $netname account"
		/usr/sbin/chown -R "$netname" "$homedir" > /dev/null 2>&1
	fi

	# Add user to the staff group on the Mac
	/bin/echo "Adding $netname to the staff group on this Mac."
	/usr/sbin/dseditgroup -o edit -a "$netname" -t user staff

	# Give the local account admin rights if the AD account did
	if [[ "$admin" = true ]]; then
		/usr/sbin/dseditgroup -o edit -a "$netname" -t user admin
		/bin/echo "Admin rights given to $netname"
	fi
done

/bin/echo "Finished converting users to local accounts"

# Check if any conversions failed
if [ "$fail" = true ]; then
	echo "One or more accounts failed to convert"
	exit 1
fi

exit 0
