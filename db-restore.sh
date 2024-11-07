#!/bin/bash

# Set variables
DB_DATA_DIR="/var/lib/mysql"  # MariaDB data directory, adjust as needed
TMP_RESTORE_DIR="/tmp/mariadb_restore"  # Temporary directory for restore operation
OLD_DB_DIR="${DB_DATA_DIR}-old-$(date +"%Y%m%d%H%M")"  # Directory to rename current DB data

# Check for the backup file argument
if [ -z "$1" ]; then
    echo "Usage: $0 <backup_file>"
    exit 1
fi

BACKUP_FILE="$1"

# Ensure backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo "Backup file not found: $BACKUP_FILE"
    exit 1
fi

# Prompt for the decryption passphrase
read -sp "Enter the decryption passphrase: " ENCRYPTION_PASSWORD
echo ""

# Step 1: Decrypt and decompress the backup file to the temporary restore directory
mkdir -p "$TMP_RESTORE_DIR"
if pv "$BACKUP_FILE" | openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:$ENCRYPTION_PASSWORD | tar -xz -C "$TMP_RESTORE_DIR"; then
    echo "Decryption and decompression successful for $BACKUP_FILE."
else
    echo "Failed to decrypt or decompress $BACKUP_FILE."
    rm -rf "$TMP_RESTORE_DIR"  # Clean up temporary directory
    exit 1
fi

# Step 2: Run mariabackup --prepare on the extracted files to ensure consistency
echo "Preparing the backup files to ensure consistency..."
mariabackup --prepare --target-dir="$TMP_RESTORE_DIR"
if [ $? -eq 0 ]; then
    echo "Backup preparation completed successfully."
else
    echo "Backup preparation failed."
    rm -rf "$TMP_RESTORE_DIR"  # Clean up temporary directory
    exit 1
fi

# Step 3: Stop the MariaDB service (ensure no active connections)
echo "Stopping MariaDB service..."
systemctl stop mariadb

# Step 4: Rename the current MariaDB data directory for backup
if [ -d "$DB_DATA_DIR" ]; then
    echo "Renaming current MariaDB data directory to $OLD_DB_DIR"
    mv "$DB_DATA_DIR" "$OLD_DB_DIR"
else
    echo "No existing MariaDB data directory found. Proceeding with restore."
fi

# Step 5: Copy the backup files to the MariaDB data directory
echo "Restoring backup to MariaDB data directory..."
mariabackup --copy-back --target-dir="$TMP_RESTORE_DIR"

# Step 6: Set correct ownership and permissions on the MariaDB data directory
echo "Setting permissions on the MariaDB data directory..."
chown -R mysql:mysql "$DB_DATA_DIR"
chmod -R 700 "$DB_DATA_DIR"

# End of restore process
echo "Restore completed successfully from backup file: $BACKUP_FILE."
echo "Please start the MariaDB service manually when ready:"
echo "    systemctl start mariadb"

# Clean up the temporary restore directory
rm -rf "$TMP_RESTORE_DIR"
