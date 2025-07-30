#!/bin/bash

# This script provides a core function for securely processing script templates.
# It is intended to be sourced by the main orchestrator script.

# Function: process_script
#
# Description:
#   Takes script content as input, finds all `{{VARIABLE_NAME}}` placeholders,
#   validates that corresponding environment variables are set on the host machine,
#   and replaces the placeholders with the actual environment variable values.
#
# Arguments:
#   $1 - A string containing the script content to be processed.
#
# Returns:
#   - On success: echoes the processed script content to stdout and returns 0.
#   - On failure: echoes a descriptive error message to stderr and returns 1.
#     Failure occurs if a required environment variable is not set.
#
# Security:
#   - It validates variable presence before execution.
#   - It uses a different sed delimiter to prevent injection issues with paths.
#
# Usage:
#   source "scripts/lib/secrets.sh"
#   script_content=$(cat my_script_template.sh)
#   processed_script=$(process_script "$script_content")
#   if [[ $? -eq 0 ]]; then
#     bash -c "$processed_script"
#   else
#     echo "Halting execution due to missing secrets." >&2
#   fi
#
process_script() {
    local script_content="$1"

    # Step 1: Find all unique {{VARIABLE_NAME}} placeholders in the script content.
    # The regex matches {{...}} with uppercase letters, numbers, and underscores.
    local required_vars
    required_vars=$(echo "$script_content" | grep -o '{{[A-Z0-9_]\+}}' | sort -u | sed 's/[{}]//g')

    # If no variables are found, there's nothing to do. Return the original content.
    if [ -z "$required_vars" ]; then
        echo "$script_content"
        return 0
    fi

    # Step 2: Validate that all required environment variables are set.
    # Iterate through the list of unique variable names found in the template.
    for var in $required_vars; do
        # Use Bash's indirect variable expansion to check the value of the variable
        # whose name is stored in 'var'.
        if [ -z "${!var}" ]; then
            echo "Error: Required secret '{{$var}}' is not set as an environment variable." >&2
            return 1
        fi
    done

    # Step 3: If all variables are validated, substitute them in the script content.
    local processed_content="$script_content"
    for var in $required_vars; do
        local value="${!var}"
        # Use sed to replace all occurrences of the placeholder.
        # A pipe '|' is used as the sed delimiter to avoid conflicts if the
        # secret value contains slashes (e.g., URLs, file paths).
        processed_content=$(echo "$processed_content" | sed "s|{{$var}}|$value|g")
    done

    # Echo the final, processed script to be captured by the calling script.
    echo "$processed_content"
    return 0
}
