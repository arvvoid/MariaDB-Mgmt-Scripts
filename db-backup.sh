#!/bin/bash

# ------------------------------------------------------------------------------
# MariaDB Backup Script with Secure Encryption
# This script creates an encrypted backup of a MariaDB database and uploads it
# to a Hetzner StorageBox. Send notification to Discord via WebHook.
# ------------------------------------------------------------------------------

# NOTE:
# To enable secure, passwordless uploads to the Hetzner StorageBox, ensure that
# an SSH key is generated and configured. This SSH key should be created on the
# database host machine and added to the Hetzner StorageBox under SSH keys.
#
# Steps for setting up SSH key access to Hetzner StorageBox:
# 1. Generate an SSH key (if not already done) on the database host:
#      ssh-keygen -t ed25519 -f ~/.ssh/hetzner_storagebox_key -C "Hetzner StorageBox Key"
#
# 2. Copy the public key to the Hetzner StorageBox.
#    https://docs.hetzner.com/storage/storage-box/backup-space-ssh-keys/
#
# 3. Ensure the path to the SSH key is correct in this script or use the default
#    `~/.ssh/hetzner_storagebox_key`.
#
# This setup allows secure, passwordless transfers, enhancing automation and security.
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

# Path to .env file (optional) - if not found, only environment variables will be used
ENV_FILE="/path/to/.env"

# Load environment variables from .env file if it exists and variables are not already set
if [ -f "$ENV_FILE" ]; then
    # Load each variable only if not already set in the environment
    export $(grep -v '^#' "$ENV_FILE" | xargs -d '\n')
fi

# Set required variables, allowing them to be overridden by environment variables
DB_USER="${DB_USER:-dbuser}"                      # User with sufficient privileges to run mariabackup
DB_PASS="${DB_PASS:-your_database_password}"       # Replace with actual password
BACKUP_DIR="${BACKUP_DIR:-/mnt/db-backup}"         # Backup directory path
WEBHOOK_URL="${WEBHOOK_URL:-YOUR_DISCORD_WEBHOOK_URL_HERE}"
ENCRYPTION_PASSWORD="${ENCRYPTION_PASSWORD:-your_secure_password}"
STORAGE_BOX_USER="${STORAGE_BOX_USER:-u12345}"     # Storage Box username
STORAGE_BOX_HOST="${STORAGE_BOX_HOST:-u12345.your-storagebox.de}" # Storage Box hostname
STORAGE_BOX_DIR="${STORAGE_BOX_DIR:-/backup_dir}"  # Remote directory to store backups

# Additional variables
DATE=$(date +"%Y%m%d%H%M")
TEMP_BACKUP_DIR="$BACKUP_DIR/tmp_$DATE"
DAYS_TO_KEEP="${DAYS_TO_KEEP:-4}"                 # Number of days to retain old backups in backup folder on db server
MAX_BOX_FILES="${MAX_BOX_FILES:-30}"             # Max number of files on Hetzner Storage Box

# Get MariaDB version
MARIADB_VERSION=$(mysql -u$DB_USER -p$DB_PASS -e "SELECT VERSION();" -ss | tr -d '\n' | tr -d '\r')
BACKUP_NAME="backup_${MARIADB_VERSION}_${DATE}.tar.gz.enc"

# ------------------------------------------------------------------------------
# Script
# ------------------------------------------------------------------------------

# Step 1: Initial backup to a temporary directory
mariabackup --user=$DB_USER --password=$DB_PASS --backup --target-dir=$TEMP_BACKUP_DIR

# Step 2: Verify the backup by preparing it
if mariabackup --prepare --target-dir=$TEMP_BACKUP_DIR; then
    STATUS="Backup prepared and verified successfully for $DATE."
    COLOR="3066993" # Green color in Discord

    # Step 3: Compress and encrypt the verified backup
    tar -czf - -C "$TEMP_BACKUP_DIR" . | \
    openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:$ENCRYPTION_PASSWORD -out "$BACKUP_DIR/$BACKUP_NAME"

    # Step 4: Verify the encrypted backup by attempting to decrypt and list contents
    if openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:$ENCRYPTION_PASSWORD -in "$BACKUP_DIR/$BACKUP_NAME" | tar -tzf - > /dev/null; then
        # Verification passed, delete the temporary backup directory
        rm -rf "$TEMP_BACKUP_DIR"

        # Step 5: Delete backups older than the configured retention period
        find $BACKUP_DIR -mindepth 1 -type f -name "*.tar.gz.enc" -mtime +$DAYS_TO_KEEP -exec rm -rf {} \;

        # Step 6: Copy backup to Hetzner Storage Box via rsync
        rsync -av -e "ssh -p 23 -i ~/.ssh/hetzner_storagebox_key" "$BACKUP_DIR/$BACKUP_NAME" "$STORAGE_BOX_USER@$STORAGE_BOX_HOST:$STORAGE_BOX_DIR/"

        if [ $? -eq 0 ]; then
            STATUS="Backup completed, verified, encrypted, and successfully copied to Hetzner Storage Box for $DATE."

            # Fetch list of files on Storage Box and save it locally
            ssh -p 23 -i ~/.ssh/hetzner_storagebox_key "$STORAGE_BOX_USER@$STORAGE_BOX_HOST" "ls -1t $STORAGE_BOX_DIR" > /tmp/storagebox_file_list.txt

            # Count files and delete oldest if more than 18 exist
            FILE_COUNT=$(wc -l < /tmp/storagebox_file_list.txt)

            if [ "$FILE_COUNT" -gt "$MAX_BOX_FILES" ]; then
                STATUS="$STATUS\nMore than $MAX_BOX_FILES backups found. Deleting oldest files to maintain limit."

                # Calculate number of files to delete
                FILES_TO_DELETE=$(( FILE_COUNT - MAX_BOX_FILES ))

                # Extract the oldest files to delete from the file list and loop through them
                tail -n "$FILES_TO_DELETE" /tmp/storagebox_file_list.txt | while read -r OLD_FILE; do
                    ssh -p 23 -i ~/.ssh/hetzner_storagebox_key "$STORAGE_BOX_USER@$STORAGE_BOX_HOST" "rm -f $STORAGE_BOX_DIR/$OLD_FILE"
                    STATUS="$STATUS\nDeleted $OLD_FILE to free up space."
                done
            fi

            # Cleanup
            rm -f /tmp/storagebox_file_list.txt

        else
            STATUS="Backup copied locally but failed to transfer to Hetzner Storage Box for $DATE."
            COLOR="15158332" # Red color in Discord notification
        fi

    else
        STATUS="Verification of encrypted backup failed for $DATE."
        COLOR="15158332" # Red color in Discord
    fi
else
    STATUS="Backup verification failed for $DATE."
    COLOR="15158332" # Red color in Discord
fi

# Prepare the JSON payload for the Discord webhook
PAYLOAD=$(cat <<EOF
{
    "embeds": [
        {
            "title": "Backup Status",
            "description": "$STATUS",
            "color": $COLOR,
            "footer": {
                "text": "Automated Backup System"
            }
        }
    ]
}
EOF
)

# Send notification to Discord
curl -H "Content-Type: application/json" -X POST -d "$PAYLOAD" $WEBHOOK_URL

echo "$STATUS"
