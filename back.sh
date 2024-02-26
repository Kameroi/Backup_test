#!/bin/bash

config_file="/etc/backup_script/backup_config.txt"

# Create log_message function
log_message() {
    local timestamp=$(date +'%Y/%m/%d %H:%M:%S')
    echo -e "$timestamp $1" >> "$log_file"
}

# Sends email which body is last line of log file.
# recipient is sourced from the config file.
send_email(){
    local subject="$1"
    local body=$(tail -n 1 "$log_file")

    echo "$body" | mail -s "$subject" "$recipient"
}

# Validate configuration file.
validate_config() {
    if [ -z "$log_file" ] || 
       [ -z "$local_dir" ] || 
       [ -z "$remote_dir" ] ||
       [ -z "$remote_dir" ] ||
       [ -z "$archive_dir" ] ||
       [ -z "$retention_days" ] ||
       [ -z "$recipient" ] || 
       [ -z "$remote_host" ]; then
        log_message "Error: Configuration validation failed."
        send_email "Backup script configuration failure"
        exit 1
    fi
}

initialize() {
    # Check if the configuration file exists
    if [ -f "$config_file" ]; then
        source "$config_file"
        log_message "Configuration file loaded."
    else
        log_message "Error: Configuration file not found."
        send_email "Backup script configuration failure"
        exit 1
    fi

    # Validate configuration file
    validate_config

    # Create the log file if it does not exist
    if [ ! -f "$log_file" ]; then
        touch "$log_file"
        log_message "Warning: Log file not found. Creating log file $log_file."
    fi
}

perform_backup() {
    # Check if local directory exists, if not, create it
    if [ ! -d "$local_dir" ]; then
        log_message "Warning: Backup directory not found. Creating backup directory."
        mkdir -p "$local_dir"
    fi

    # Check if remote server port 22 is open
    if ! nc -z -w5 "$remote_host" 22; then
        log_message "Error: Cannot connect to $remote_host on port 22"
        return 1
    fi

    # Check if remote directory exists
    if ! ssh "$remote_user@$remote_host" "test -d $remote_dir"; then
        log_message "Error: Remote directory $remote_dir does not exist"
        return 1
    fi

    # Perform the backup
    if ! rsync -avz --delete --log-file="$log_file" "$remote_user@$remote_host:$remote_dir" "$local_dir"; then
        log_message "Error: Backup failed"
        return 1
    fi

    log_message "Backup completed"
    send_email "Backup script finished"
}

# Create .tar.gz archive
archive_backup() {
    if [ ! -d "$archive_dir" ]; then
        log_message "Warning: Archive directory not found. Creating archive directory $archive_dir."
        mkdir -p "$archive_dir"
    fi

    # 2>&1 is used to include error messages.
    if ! tar -czf "$archive_dir/backup_$(date +"%Y-%m-%d-%H-%M-%S").tar.gz" -C "$local_dir" . >> $log_file 2>&1; then
        log_message "Archive creation failed"
        send_email "Archive script failed"
        return 1
    fi

    log_message "Archive creation finished"
}

# Delete archives older than retention days specified.
delete_old_archives() {
    log_message "Deleting archives older than $retention_days days."
    # -mtime - modification time
    find "$archive_dir" -maxdepth 1 -type f -mtime +$retention_days -exec \
    sh -c '{ echo "Deleting file: $1"; rm -f "$1" 2>&1; } >> logs.log' sh {} \;
}


initialize
perform_backup
if [ $? -ne 0 ]; then
    send_email "Backup script failed"
fi
