#!/bin/bash

# =============================================================================
# SYSTEM INFORMATION AND ACCESS LEVEL CHECKER SCRIPT
# For CloudLinux Shared Hosting Environments
# =============================================================================

# Set up log file location
LOG_DIR="$HOME/system_checks"
LOG_FILE="$LOG_DIR/system_info_$(date +%Y%m%d_%H%M%S).log"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Function to log and display output
log_output() {
    echo "$1" | tee -a "$LOG_FILE"
}

# Function to run command and log output
run_and_log() {
    local cmd="$1"
    local description="$2"

    log_output ""
    log_output "=== $description ==="
    log_output "Command: $cmd"
    log_output "Output:"

    if eval "$cmd" 2>/dev/null; then
        eval "$cmd" 2>&1 | tee -a "$LOG_FILE"
    else
        log_output "Command failed or not available"
    fi
    log_output ""
}

# Start logging
log_output "=============================================================================="
log_output "SYSTEM INFORMATION AND ACCESS LEVEL CHECK"
log_output "Generated on: $(date)"
log_output "=============================================================================="

# Basic System Information
log_output ""
log_output "################################"
log_output "# BASIC SYSTEM INFORMATION     #"
log_output "################################"

run_and_log "uname -a" "Kernel and System Information"
run_and_log "hostname" "Hostname"
run_and_log "whoami" "Current User"
run_and_log "pwd" "Current Directory"
run_and_log "echo \$SHELL" "Current Shell"
run_and_log "echo \$HOME" "Home Directory"

# Try to find OS release information
log_output ""
log_output "=== Operating System Release Information ==="
if [ -f /etc/.etc.version ]; then
    run_and_log "cat /etc/.etc.version" "System Version File"
fi

run_and_log "find /etc -name '*release*' -o -name '*version*' 2>/dev/null | head -10" "Available Release/Version Files"

# User Access and Permissions
log_output ""
log_output "################################"
log_output "# USER ACCESS AND PERMISSIONS  #"
log_output "################################"

run_and_log "id" "User ID and Groups"
run_and_log "groups" "User Groups"

# Check sudo availability
log_output ""
log_output "=== Sudo Access Check ==="
if command -v sudo >/dev/null 2>&1; then
    log_output "sudo command is available"
    run_and_log "sudo -v 2>&1" "Sudo Privilege Test"
    run_and_log "sudo -l 2>&1" "Sudo Permissions List"
else
    log_output "sudo command is NOT available (typical for shared hosting)"
fi

# Check for wheel/sudo group membership
run_and_log "groups \$USER | grep -E 'sudo|wheel' || echo 'Not in sudo/wheel group'" "Sudo/Wheel Group Membership"

# File System Permissions
log_output ""
log_output "################################"
log_output "# FILE SYSTEM INFORMATION      #"
log_output "################################"

run_and_log "ls -la ~/ | head -20" "Home Directory Contents"
run_and_log "ls -la / | head -15" "Root Directory Contents"
run_and_log "ls -la /usr/local/bin/ 2>/dev/null | head -10" "Local Binaries"

# Environment Information
log_output ""
log_output "################################"
log_output "# ENVIRONMENT INFORMATION      #"
log_output "################################"

run_and_log "env | grep -i path" "PATH-related Environment Variables"
run_and_log "echo \$PATH | tr ':' '\n'" "PATH Directories"

# Process Information
log_output ""
log_output "################################"
log_output "# PROCESS INFORMATION          #"
log_output "################################"

run_and_log "ps aux | head -10" "Running Processes (Top 10)"

# Hardware Information (using /proc)
log_output ""
log_output "################################"
log_output "# HARDWARE INFORMATION         #"
log_output "################################"

run_and_log "cat /proc/cpuinfo | head -20" "CPU Information"
run_and_log "cat /proc/meminfo | head -10" "Memory Information"
run_and_log "cat /proc/mounts | head -10" "Mounted File Systems"

# Available Commands Check
log_output ""
log_output "################################"
log_output "# AVAILABLE COMMANDS           #"
log_output "################################"

run_and_log "ls /bin/ | head -20" "Available System Commands (/bin)"
run_and_log "ls /usr/bin/ | head -20" "Available User Commands (/usr/bin)"

# Check for common utilities
log_output ""
log_output "=== Common Utility Availability ==="
utilities=("git" "python" "python3" "php" "mysql" "wget" "curl" "tar" "zip" "unzip")
for util in "${utilities[@]}"; do
    if command -v "$util" >/dev/null 2>&1; then
        run_and_log "which $util && $util --version 2>/dev/null | head -1" "$util availability and version"
    else
        log_output "$util: NOT AVAILABLE"
    fi
done

# Homebrew Check
log_output ""
log_output "################################"
log_output "# HOMEBREW INFORMATION         #"
log_output "################################"

if [ -d "$HOME/homebrew" ]; then
    log_output "Homebrew directory found in home"
    run_and_log "ls -la ~/homebrew/ | head -10" "Homebrew Directory Contents"

    # Try to set up homebrew path
    export PATH="$HOME/homebrew/bin:$PATH"
    if command -v brew >/dev/null 2>&1; then
        run_and_log "which brew" "Homebrew Binary Location"
        run_and_log "brew --version 2>/dev/null" "Homebrew Version"
    else
        log_output "Homebrew binary not found or not executable"
    fi
else
    log_output "Homebrew directory not found in home"
fi

# Disk Usage
log_output ""
log_output "################################"
log_output "# DISK USAGE INFORMATION       #"
log_output "################################"

run_and_log "du -sh ~/* 2>/dev/null | sort -hr | head -10" "Home Directory Usage (Top 10)"

# Network Information (if available)
log_output ""
log_output "################################"
log_output "# NETWORK INFORMATION          #"
log_output "################################"

run_and_log "hostname -f 2>/dev/null || hostname" "Fully Qualified Domain Name"

# CloudLinux Specific Information
log_output ""
log_output "################################"
log_output "# CLOUDLINUX SPECIFIC INFO     #"
log_output "################################"

if [ -d "$HOME/.cagefs" ]; then
    log_output "CageFS detected (CloudLinux feature)"
    run_and_log "ls -la ~/.cagefs/" "CageFS Directory"
fi

if [ -d "/etc/cl.selector" ]; then
    log_output "CloudLinux Selector detected"
fi

# Final Summary
log_output ""
log_output "=============================================================================="
log_output "SUMMARY"
log_output "=============================================================================="
log_output "System Type: CloudLinux Shared Hosting Environment"
log_output "User: $(whoami)"
log_output "Sudo Access: $(if command -v sudo >/dev/null 2>&1; then echo 'Available'; else echo 'Not Available'; fi)"
log_output "Homebrew: $(if [ -d ~/homebrew ]; then echo 'Installed'; else echo 'Not Found'; fi)"
log_output "Environment: Highly Restricted (CageFS enabled)"
log_output "=============================================================================="

# Script completion
log_output ""
log_output "System check completed on: $(date)"
log_output "Log file location: $LOG_FILE"
log_output "=============================================================================="

# Display log file information
echo ""
echo "============================================="
echo "SYSTEM CHECK COMPLETED"
echo "============================================="
echo "Log file created at: $LOG_FILE"
echo ""
echo "To view the log file, use any of these commands:"
echo "  cat '$LOG_FILE'"
echo "  less '$LOG_FILE'"
echo "  more '$LOG_FILE'"
echo "  nano '$LOG_FILE'"
echo "  vi '$LOG_FILE'"
echo ""
echo "To view the last 50 lines:"
echo "  tail -50 '$LOG_FILE'"
echo ""
echo "To search within the log:"
echo "  grep 'search_term' '$LOG_FILE'"
echo ""
echo "Log directory: $LOG_DIR"
echo "============================================="
