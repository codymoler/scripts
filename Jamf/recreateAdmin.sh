#!/bin/bash

# Jamf Script Parameter #1: Username
# Jamf Script Parameter #2: Password

# Delete user
echo "Deleting $4..."
rm -f "/private/var/db/dslocal/nodes/Default/users/$4.plist"
/usr/bin/dscl . -delete "/Users/$4"
rm -rf "/Users/$4"

ID=$(dscl . -list /users UniqueID| sort -n -k 2 | awk '{ field = $NF }; END{ print field }' | xargs -I{} expr {} + 1)

echo "Creating user $4..."

# Create a new user account from passed parameters
dscl . -create /Users/$4
dscl . -create /Users/$4 UserShell /bin/bash
dscl . -create /Users/$4 RealName "$4"
dscl . -create /Users/$4 UniqueID $ID
dscl . -create /Users/$4 PrimaryGroupID $ID
dscl . -create /Users/$4 NFSHomeDirectory /Users/$4
dscl . -passwd /Users/$4 $5

dscl . -append /Groups/admin GroupMembership $4
