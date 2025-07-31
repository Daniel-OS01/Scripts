# Remote-First Automation Script Orchestrator

Welcome to your centralized script distribution system. This repository contains a powerful, menu-driven framework for managing and executing complex automation scripts for your Oracle Cloud VPS, Docker, Coolify, and general system management needs.

The entire system is designed to be run remotely with a single command.

## Architecture: The "Injector" Model

This system uses a powerful "injector" model that allows for maximum flexibility and centralized management, designed for a **private GitHub repository**.

1.  **Remote Execution:** The main entry point, `main.sh`, is executed via a `curl` command. You do not need to clone this repository.
2.  **Central Configuration:** All configuration, including credentials and API keys, is stored in a single `config.env` file within this repository.
3.  **Runtime Injection:** When you select a script from the `main.sh` menu, the orchestrator performs two actions in the background:
    a. It fetches the content of `config.env` from the repository.
    b. It fetches the content of the selected script (e.g., `manage-nsg-rules.sh`).
    c. It dynamically prepends the configuration content to the script content and executes the combined result.

This means you only ever need to update your scripts or your `config.env` file in one place (this GitHub repository), and the changes are immediately live for execution on any of your servers.

---

## Setup and Usage

### Step 1: Populate the Configuration File

The **only setup step** is to edit the `config.env` file in this private GitHub repository.

Open `config.env` and fill in the placeholder values for each variable with your actual credentials.

**Example Snippet from `config.env`:**
```bash
# --- Oracle Cloud Infrastructure (OCI) ---
export OCI_USER_OCID="ocid1.user.oc1..xxxxxxxxxxxx"
export OCI_TENANCY_OCID="ocid1.tenancy.oc1..xxxxxxxxxxxx"
# ... and so on
```

### Step 2: Run the Orchestrator Remotely

From any of your servers, run the following command. This will download and execute the `main.sh` script, which will then give you access to all the other scripts.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/Daniel-OS01/Scripts/refs/heads/main/main.sh)"
```

The orchestrator menu will appear, and you can select a script to run. It will prompt you for any arguments the selected script requires.

---

## Scripts Catalog

Here is a list of all the scripts currently available in the system.

| Category                 | Script                                    | Description                                                                 |
| ------------------------ | ----------------------------------------- | --------------------------------------------------------------------------- |
| **Oracle Cloud**         | `manage-nsg-rules.sh`                     | Add, remove, or list rules in an OCI Network Security Group.                |
|                          | `manage-block-volumes.sh`                 | Create, attach, detach, list, and delete OCI block volumes.                 |
|                          | `oci-add-port.sh`                         | A wizard to add a port to both iptables and an OCI Security List.           |
|                          | `oci-manager2.sh`                         | An interactive menu to sync Docker/CasaOS ports to OCI and iptables.        |
|                          | `oci-manager2.5.sh`                       | A more advanced, robust version of the OCI port sync manager.               |
|                          | `dokploy-traefik-doctor.sh`               | Validates and auto-fixes common issues in Dokploy/Traefik stacks.           |
|                          | `VPS Comprehensive Diagnostics`           | Gathers an exhaustive diagnostics report for an ARM64 Ubuntu VPS.           |
| **Docker Advanced**      | `selective-cleanup.sh`                    | Selectively clean up Docker images, volumes, and other resources.           |
|                          | `inspect-resource-usage.sh`               | Show a sorted report of real-time container resource usage (CPU/Mem).       |
|                          | `Docker-Cleanup-Management.sh`            | A full menu-driven script for various Docker cleanup tasks.                 |
|                          | `cleanup.sh`                              | (Identical to above) A comprehensive Docker management script.              |
| **Coolify Management**   | `manage-application.sh`                   | Restart, redeploy, or check the status of a Coolify application via API.    |
| **Network Automation**   | `manage-dns-records.sh`                   | Manage Cloudflare DNS records (list, add, delete).                          |
| **Security & Hardening** | `get-ssl-certificate.sh`                  | Obtain a Let's Encrypt SSL certificate using Certbot.                       |
| **Backup & Recovery**    | `perform-s3-backup.sh`                    | Compresses, encrypts, and uploads a directory to S3-compatible storage.     |
| **Monitoring & Alerting**| `send-alert.sh`                           | Sends a formatted message to a Discord/Slack webhook.                       |
| **Maintenance**          | `system-update-and-health-check.sh`       | Updates system packages, cleans up, and provides a health report.           |
