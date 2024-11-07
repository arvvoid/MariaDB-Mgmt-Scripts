#!/bin/bash

# Configuration
#
# DISCORD_WEBHOOK_URL: URL for sending notifications to a Discord webhook.
# This variable can be set here with a default value, or it can be set as an
# environment variable before running the script. If set as an environment
# variable, it will override this default.
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-YOUR_DISCORD_WEBHOOK_URL_HERE}"

NOTIFY_ALWAYS=false
NOTIFY_FLAG_FILE="/tmp/mysql_replication_notify.flag"
NOTIFY_TIMES="07:00,22:00"  # Specify times when notification should always be sent even if all ok
NOTIFICATION_TITLE="MariaDB Replication"  # Configurable title for notifications


# Parse command-line arguments
for arg in "$@"; do
  case $arg in
    --notify-always)
      NOTIFY_ALWAYS=true
      shift
      ;;
    *)
      ;;
  esac
done

# Function to check if the current time matches any of the configured notification times
check_notify_time() {
    local current_time=$(date +"%H:%M")
    IFS=',' read -r -a times <<< "$NOTIFY_TIMES"
    for time in "${times[@]}"; do
        if [[ "$current_time" == "$time" ]]; then
            return 0  # Match found
        fi
    done
    return 1  # No match
}

# Function to send success notification to Discord
send_discord_success_notification() {
    local message="{
        \"embeds\": [{
            \"title\": \"$NOTIFICATION_TITLE Status\",
            \"color\": 65280,
            \"description\": \"✅ Replication is working correctly.\",
            \"timestamp\": \"$(date -Iseconds)\"
        }]
    }"

    curl -H "Content-Type: application/json" -X POST -d "$message" "$DISCORD_WEBHOOK_URL" > /dev/null 2>&1
}

# Function to send failure notification to Discord
send_discord_failure_notification() {
    local io_running="$1"
    local sql_running="$2"
    local seconds_behind="$3"

    # Escape backslashes and double quotes
    io_running=$(echo "$io_running" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
    sql_running=$(echo "$sql_running" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
    seconds_behind=$(echo "$seconds_behind" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')

    local message="{
        \"embeds\": [{
            \"title\": \"$NOTIFICATION_TITLE Issue Detected\",
            \"color\": 16711680,
            \"fields\": [
                {\"name\": \"Slave_IO_Running\", \"value\": \"$io_running\", \"inline\": true},
                {\"name\": \"Slave_SQL_Running\", \"value\": \"$sql_running\", \"inline\": true},
                {\"name\": \"Seconds_Behind_Master\", \"value\": \"$seconds_behind\", \"inline\": true}
            ],
            \"timestamp\": \"$(date -Iseconds)\"
        }]
    }"

    curl -H "Content-Type: application/json" -X POST -d "$message" "$DISCORD_WEBHOOK_URL" > /dev/null 2>&1
}

# Check if the persistent notification flag file exists or if the current time matches the NOTIFY_TIMES
if [ -f "$NOTIFY_FLAG_FILE" ] || check_notify_time; then
    NOTIFY_AFTER_FAILURE=true
else
    NOTIFY_AFTER_FAILURE=false
fi

# Run the SHOW SLAVE STATUS command and store the output
SLAVE_STATUS=$(mysql -e "SHOW SLAVE STATUS\G" 2>/dev/null)

# Check if SLAVE_STATUS is empty (no replication setup or error)
if [ -z "$SLAVE_STATUS" ]; then
    echo "No replication status available. Replication may not be configured or an error occurred."
    # Send notification to Discord
    send_discord_failure_notification "N/A" "N/A" "N/A"
    # Set the flag file to enable notification on the next run
    touch "$NOTIFY_FLAG_FILE"
    exit 1
fi

# Check for Slave_IO_Running
SLAVE_IO_RUNNING=$(echo "$SLAVE_STATUS" | grep "Slave_IO_Running:" | awk '{print $2}')

# Check for Slave_SQL_Running
SLAVE_SQL_RUNNING=$(echo "$SLAVE_STATUS" | grep "Slave_SQL_Running:" | awk '{print $2}')

# Check for Seconds_Behind_Master
SECONDS_BEHIND_MASTER=$(echo "$SLAVE_STATUS" | grep "Seconds_Behind_Master:" | awk '{print $2}')

# Handle NULL values
if [ "$SECONDS_BEHIND_MASTER" == "NULL" ] || [ -z "$SECONDS_BEHIND_MASTER" ]; then
    SECONDS_BEHIND_MASTER="NULL"
fi

# Check replication status
if [[ "$SLAVE_IO_RUNNING" == "Yes" && "$SLAVE_SQL_RUNNING" == "Yes" && "$SECONDS_BEHIND_MASTER" == "0" ]]; then
    echo "Replication is working correctly."
    if [ "$NOTIFY_ALWAYS" = true ] || [ "$NOTIFY_AFTER_FAILURE" = true ]; then
        # Send success notification to Discord
        send_discord_success_notification
    fi
    # Remove the persistent failure notification flag file if it exists
    rm -f "$NOTIFY_FLAG_FILE"
else
    echo "$NOTIFICATION_TITLE issue detected!"
    echo "Slave_IO_Running: $SLAVE_IO_RUNNING"
    echo "Slave_SQL_Running: $SLAVE_SQL_RUNNING"
    echo "Seconds_Behind_Master: $SECONDS_BEHIND_MASTER"
    # Send failure notification to Discord
    send_discord_failure_notification "$SLAVE_IO_RUNNING" "$SLAVE_SQL_RUNNING" "$SECONDS_BEHIND_MASTER"
    # Set the flag file to enable notification on the next run
    touch "$NOTIFY_FLAG_FILE"
fi
