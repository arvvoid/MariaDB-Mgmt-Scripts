# MariaDB Management Toolkit

A collection of scripts to streamline the management of MariaDB databases, designed for automation and ease of use. These scripts focus on ensuring replication status, automating backups, and simplifying restores. Perfect for administrators managing small to medium-sized MariaDB databases who want automated and secure backup management.

## Table of Contents

- [Overview](#overview)
- [Target Database Sizes](#target-database-sizes)
- [Scripts](#scripts)
  - [Replication Status Checker](#replication-status-checker)
  - [Backup Script](#backup-script)
  - [Restore Script](#restore-script)
- [Setup](#setup)
  - [Dependencies](#dependencies)
  - [Cron Jobs](#cron-jobs)
- [Usage](#usage)

## Overview

This toolkit contains three primary scripts:

1. **Replication Status Checker**: Monitors the replication status on a MariaDB slave server and sends notifications via Discord when issues arise.
2. **Backup Script**: Creates a compressed, encrypted backup of the MariaDB database and uploads it to a Hetzner StorageBox.
3. **Restore Script**: Provides a straightforward way to restore MariaDB from a backup by specifying the local path to the backup file and entering a decryption key.

## Target Database Sizes

These scripts are best suited for **small to medium-sized databases**.

- **Small-Scale Databases**: Up to 5 GB. These databases are typically manageable on a single server with minimal resources, and backups/restores can be performed relatively quickly.
- **Medium-Sized Databases**: Between 5 GB and 50 GB. These databases may require more storage and processing resources, and backup/restores may take longer. Network transfer times are also a consideration.

For larger databases, additional tuning or alternative solutions might be necessary to handle backup frequency, storage, and restore times effectively.

## Scripts

### Replication Status Checker

- **Description**: Checks the replication status on a MariaDB slave. If replication issues are detected, it sends an alert message to a Discord channel.
- **Frequency**: This script is intended to be run as a cron job every 15 minutes to ensure prompt detection of replication failures.
- **Configuration**: Set up the Discord webhook URL in the script for notifications.

### Backup Script

- **Description**: Automates the process of creating a MariaDB backup, compressing, encrypting, and uploading it to a Hetzner StorageBox.
- **Backup Tool**: Uses `mariabackup` as the primary backup tool.
- **Storage**: Backups are uploaded to a Hetzner StorageBox for secure storage and easy retrieval.
- **Encryption**: Ensures backups are securely encrypted before uploading.

### Restore Script

- **Description**: A script to restore a MariaDB database from a specified local backup file.
- **Process**:
  - Expects a local path to the backup file as an argument.
  - Prompts for a decryption key during the restore process.
  - Decrypts, decompresses, and restores the backup to the specified MariaDB server.
- **Usage**:
  - Run the script and provide the path to the backup file as an argument.
  - When prompted, enter the decryption key to proceed with the restore.

## Setup

### Dependencies

To run these MariaDB backup and replication monitoring scripts, ensure the following dependencies are installed on your system:

1. **MariaDB** - Provides `mariabackup` utility for performing backups and restores.
   - **Installation** (Debian/Ubuntu): `sudo apt install mariadb-server mariadb-backup`

2. **OpenSSL** - Used for encryption and decryption of backup files.
   - **Installation** (Debian/Ubuntu): `sudo apt install openssl`

3. **tar** - For compressing and decompressing the backup files.
   - **Installation** (Debian/Ubuntu): `sudo apt install tar`

4. **gzip** - Required for compressing and decompressing `.tar.gz` backup files.
   - **Installation** (Debian/Ubuntu): `sudo apt install gzip`

5. **cURL** - Required for sending notifications to Discord via the Webhook.
   - **Installation** (Debian/Ubuntu): `sudo apt install curl`

6. **pv** - Used to monitor the progress of data through a pipeline, especially for large backup files.
   - **Installation** (Debian/Ubuntu): `sudo apt install pv`

7. **rsync** - Used to transfer the backup file to the Hetzner StorageBox via SSH.
   - **Installation** (Debian/Ubuntu): `sudo apt install rsync`

8. **SSH Key Setup** (for secure, passwordless uploads to Hetzner StorageBox) - Set up an SSH key for authentication:
   - Generate the SSH key:
     ```bash
     ssh-keygen -t ed25519 -f ~/.ssh/hetzner_storagebox_key -C "Hetzner StorageBox Key"
     ```
   - Add the public key (`~/.ssh/hetzner_storagebox_key.pub`) to the Hetzner StorageBox. For more details, refer to the Hetzner documentation: [Hetzner Storage Box SSH Keys Setup](https://docs.hetzner.com/storage/storage-box/backup-space-ssh-keys/).

9. **systemctl** - For stopping and starting the MariaDB service as needed during restoration.

This setup ensures the backup and replication monitoring scripts function securely and reliably. Adjust installation commands as needed for your operating system.

### Cron Jobs

To automate the scripts, set up cron jobs to run the scripts at regular intervals:

- **Replication Status Checker**: Run every 15 minutes for prompt replication monitoring:
  ```bash
  */15 * * * * /path/to/replication_status_checker.sh
