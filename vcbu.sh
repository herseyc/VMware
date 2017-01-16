#!/bin/bash
#######################################################################################
#
# vCenter Backup - vcbu.sh
# Create a Backup of the vCenter Server Appliance
#
# Modified the original script from 
# https://pubs.vmware.com/vsphere-65/topic/com.vmware.vsphere.vcsapg-rest.doc/GUID-222400F3-678E-4028-874F-1F83036D2E85.html
# Creates backup of VCSA and SCPs files to SCP_ADDRESS
# 
# Can be used to backup VCSA with or without an Embedded PSC
# To backup a VCSA configured as an external PSC change the parts from seat to common
#
# http://www.vhersey.com/
#
#######################################################################################
##### EDITABLE BY USER to specify vCenter Server instance and backup destination. #####
#######################################################################################
VC_ADDRESS="192.168.1.21" # VCSA to backup
VC_USER="administrator@vsphere.local" # VCSA SSO User
VC_PASSWORD="Password" # VCSA SSO User Password
SCP_ADDRESS="192.168.1.30" # vMA Address
SCP_USER="vi-admin" # vMA user (vi-admin)
SCP_PASSWORD="Password" # vMA user password
BACKUP_FOLDER="workspace/backups/vcenter" # Absolute path without leading or trailing /
#######################################################################################

# Authenticate with basic credentials.
curl -u "$VC_USER:$VC_PASSWORD" \
    -X POST \
    -k --cookie-jar cookies.txt \
    "https://$VC_ADDRESS/rest/com/vmware/cis/session"

# Create a message body json for the backup request.
TIME=$(date +%Y-%m-%d-%H-%M-%S)
cat << EOF >task.json
 { "piece":
      {
          "location_type":"SCP",
          "comment":"Automatic backup $TIME",
          "parts":["seat"],
          "location":"$SCP_ADDRESS/$BACKUP_FOLDER/$VC_ADDRESS/$TIME",
          "location_user":"$SCP_USER",
          "location_password":"$SCP_PASSWORD"
      }
 }
EOF

# Issue a request to start the backup operation.
echo '' >>backup.log
echo Starting backup $TIME >>backup.log
echo '' >>backup.log
curl -k --cookie cookies.txt \
     -H 'Accept:application/json' \
     -H 'Content-Type:application/json' \
     -X POST \
     --data @task.json 2>>backup.log >response.txt \
     "https://$VC_ADDRESS/rest/appliance/recovery/backup/job" 

cat response.txt >>backup.log
echo '' >>backup.log

# Parse the response to locate the unique identifier of the backup operation.
ID=$(awk '{if (match($0,/"id":"\w+-\w+-\w+"/)) \
           print substr($0, RSTART+6, RLENGTH-7);}' \
          response.txt)
echo 'Backup job id: '$ID

# Monitor progress of the operation until it is complete.
PROGRESS=INPROGRESS
until [ "$PROGRESS" != "INPROGRESS" ]
 do
      sleep 10s
      curl -k --cookie cookies.txt \
           -H 'Accept:application/json' \
           --globoff \
           "https://$VC_ADDRESS/rest/appliance/recovery/backup/job/$ID" \
           >response.txt
      cat response.txt >>backup.log
      echo ''  >>backup.log
      PROGRESS=$(awk '{if (match($0,/"state":"\w+"/)) \
                      print substr($0, RSTART+9, RLENGTH-10);}' \
                     response.txt)
      echo 'Backup job state: '$PROGRESS
 done

# Report job completion and clean up temporary files.
echo ''
echo "Backup job completion status: $PROGRESS"
rm -f task.json
rm -f response.txt
rm -f cookies.txt
echo ''  >>backup.log
