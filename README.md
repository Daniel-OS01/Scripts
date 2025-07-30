# Centralized Automation Script Orchestrator

Welcome to your centralized script distribution system. This repository contains a powerful, menu-driven framework for managing and executing complex automation scripts for your Oracle Cloud VPS, Docker, Coolify, and general system management needs.

## Architecture

This system is designed for use in a **private GitHub repository**. This simplifies the architecture significantly, allowing for a secure yet highly maintainable approach to configuration.

*   **Central Configuration:** All configuration, including credentials, API keys, and identifiers, is stored in a single file: `config.env`. This means you only need to update a variable in one place, and all scripts that use it will receive the update.
*   **Orchestrator Model:** The `main.sh` script acts as the single entry point. It provides a user-friendly menu that lists all available scripts, grouped by category, and handles their execution.
*   **Modular Scripts:** Each script in the subdirectories (`oracle-cloud/`, `docker-advanced/`, etc.) is designed to perform a specific, complex task. They are written to be robust, with clear output and error handling.

---

## Setup and Usage

### Step 1: Clone the Repository

Since this is a private repository, clone it to the machine where you intend to run the scripts (e.g., your main OCI instance or a dedicated management server).

```bash
git clone git@github.com:Daniel-OS01/scripts.git
cd scripts
```

### Step 2: Configure Your Credentials

Open the `config.env` file with a text editor (e.g., `nano config.env`).

This file contains all the settings and secrets the scripts will need. Fill in the placeholder values for each variable with your actual credentials.

**Example Snippet from `config.env`:**
```bash
# --- Oracle Cloud Infrastructure (OCI) ---
export OCI_USER_OCID="ocid1.user.oc1..xxxxxxxxxxxx"
export OCI_TENANCY_OCID="ocid1.tenancy.oc1..xxxxxxxxxxxx"
# ... and so on
```

### Step 3: Run the Orchestrator

Once the `config.env` file is populated, you can run the main orchestrator. First, make it executable:

```bash
chmod +x main.sh
```

Then run it:
```bash
./main.sh
```

This will display the main menu, from which you can select and run any of the available scripts. The orchestrator will prompt you for any arguments the selected script requires.

---

## Scripts Catalog

Here is a list of all the scripts currently available in the system.

| Category                 | Script                                    | Description                                                                 | Usage                                                                           |
| ------------------------ | ----------------------------------------- | --------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| **Oracle Cloud**         | `manage-nsg-rules.sh`                     | Add, remove, or list rules in an OCI Network Security Group.                | `./manage-nsg-rules.sh <nsg_ocid> <list\|add\|remove> [options]`              |
|                          | `manage-block-volumes.sh`                 | Create, attach, detach, list, and delete OCI block volumes.                 | `./manage-block-volumes.sh <action> [options]`                                  |
| **Docker Advanced**      | `selective-cleanup.sh`                    | Selectively clean up Docker images, volumes, and other resources.           | `./selective-cleanup.sh [--images\|--volumes\|--all] [options]`                   |
|                          | `inspect-resource-usage.sh`               | Show a sorted report of real-time container resource usage (CPU/Mem).       | `./inspect-resource-usage.sh [--sort-by <cpu\|mem>] [--top <n>]`                 |
| **Coolify Management**   | `manage-application.sh`                   | Restart, redeploy, or check the status of a Coolify application via API.    | `./manage-application.sh <app_uuid> <status\|restart\|redeploy>`                  |
| **Network Automation**   | `manage-dns-records.sh`                   | Manage Cloudflare DNS records (list, add, delete).                          | `./manage-dns-records.sh <list\|add\|delete> [options]`                           |
| **Security & Hardening** | `get-ssl-certificate.sh`                  | Obtain a Let's Encrypt SSL certificate using Certbot.                       | `sudo ./get-ssl-certificate.sh <domain.name>`                                   |
| **Backup & Recovery**    | `perform-s3-backup.sh`                    | Compresses, encrypts, and uploads a directory to S3-compatible storage.     | `./perform-s3-backup.sh <path_to_directory>`                                    |
| **Monitoring & Alerting**| `send-alert.sh`                           | Sends a formatted message to a Discord/Slack webhook.                       | `./send-alert.sh --title "..." --message "..." --level <INFO\|WARNING\|CRITICAL>` |
| **Maintenance**          | `system-update-and-health-check.sh`       | Updates system packages, cleans up, and sends a health report.              | `sudo ./system-update-and-health-check.sh`                                      |
