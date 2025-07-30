# Centralized Automation Script System

This repository contains a centralized, menu-driven system for managing and executing complex automation scripts, primarily for Oracle Cloud Infrastructure (OCI), Docker, and Coolify platform operations.

The system is built around a main orchestrator script, `main.sh`, which provides a simple, interactive menu to select and run automation tasks safely and securely.

## Architecture

### Key Features:

*   **Menu-Driven Interface:** `main.sh` provides a user-friendly menu, so you don't have to memorize a long list of script names and paths.
*   **Centralized Script Repository:** All automation scripts are stored and version-controlled in this single GitHub repository, making them easy to update, manage, and audit.
*   **Secure Secret Management:** The system is designed to keep all sensitive credentials—like API keys, tokens, and passwords—out of the codebase by using a secure runtime substitution method.

### How Secrets Are Handled

A core design principle of this system is to **never hardcode credentials** in scripts. We use a secure template and substitution model.

*   **Template Syntax:** Within any given script, all sensitive data is represented by a placeholder, such as `{{DOCKER_REGISTRY_TOKEN}}`.
*   **Runtime Substitution:** When you select a script to run from the `main.sh` menu, the orchestrator securely substitutes these placeholders with values from **environment variables** that are set on your host machine.

> **Architectural Note:** The initial proposal to fetch secrets directly from the GitHub Secrets API is not technically feasible, as the GitHub API is designed to prevent this for security reasons. The adopted approach of using local environment variables is the industry standard for providing credentials to applications and scripts running in a secure server environment.

---

## How to Use

### Prerequisites

*   A Linux environment (e.g., Oracle Linux, Ubuntu) with `bash` and `curl` installed.
*   The necessary credentials and identifiers (API keys, OCIDs, etc.) for the cloud services you wish to automate.

### 1. Set Up Secrets on Your Host Machine

Before running the orchestrator, you must `export` the required secrets as environment variables. The variable name must **exactly match** the placeholder in the script, but without the `{{...}}`.

**Example Setup:**

```bash
# For Oracle Cloud Scripts
export DEFAULT_SL_OCI="your_oci_cli_profile_name"
export NETWORK_SECURITY_GROUP_ID="ocid1.nsg.oc1.iad.xxxxxxxxxxxxxxxxx"

# For Docker Private Registry Scripts
export DOCKER_REGISTRY_URL="your-registry.example.com"
export DOCKER_USERNAME="your-docker-username"
export DOCKER_REGISTRY_TOKEN="your_docker_access_token_or_password"

# For Coolify Scripts
export COOLIFY_API_KEY="your_coolify_api_bearer_token"
export COOLIFY_DEPLOYMENT_WEBHOOK="https://coolify.app.com/api/v1/applications/xyz/deployments"
```

**To make these variables persistent across reboots**, add the `export` commands to your shell's startup file (e.g., `~/.bashrc`, `~/.bash_profile`, or `~/.zshrc`) and then reload your shell with `source ~/.bashrc` or by logging out and back in.

### 2. Run the Orchestrator

Execute the following command in your terminal. It is recommended to run it with `sudo` if the underlying scripts are expected to perform system-level changes.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/Daniel-OS01/scripts/refs/heads/main/main.sh)"
```

This command downloads and runs the `main.sh` script, which will validate its dependencies and present you with the main menu.

---

## Available Scripts

The following scripts are currently available. The "Required Secrets" are the environment variables you must set before running the script.

| # | Script Name                        | Description                                          | Required Secrets                                                                                             |
|:-:|:-----------------------------------|:-----------------------------------------------------|:-------------------------------------------------------------------------------------------------------------|
| 1 | `configure-network.sh`             | Simulates adding an HTTPS ingress rule to an OCI NSG.  | `DEFAULT_SL_OCI`, `NETWORK_SECURITY_GROUP_ID`                                                                |
| 2 | `advanced-container-management.sh` | Simulates logging into a private registry and cleaning up Docker resources. | `DOCKER_REGISTRY_URL`, `DOCKER_USERNAME`, `DOCKER_REGISTRY_TOKEN`                                              |
| 3 | `deployment.sh`                    | Simulates triggering a deployment in Coolify via webhook. | `COOLIFY_API_KEY`, `COOLIFY_DEPLOYMENT_WEBHOOK`                                                              |

---

## How to Add New Scripts

To extend the system with a new script, follow these three steps:

1.  **Create the Script File:**
    *   Place your new `.sh` file in the appropriate subdirectory within `scripts/`.
    *   Follow the header and documentation format found in the existing scripts.
    *   Use the `{{VARIABLE_NAME}}` template syntax for any secrets or sensitive configuration values.

2.  **Update the Orchestrator Menu:**
    *   Open `main.sh` for editing.
    *   Add a new `echo` line to the `show_menu()` function to display your new script as a menu option.

3.  **Update the Orchestrator Logic:**
    *   In `main.sh`, find the `case` statement within the main execution loop.
    *   Add a new entry for your menu number that calls the `run_script` function with the path to your new script. For example:
        ```bash
        4)
            run_script "scripts/your-category/your-new-script.sh"
            ;;
        ```
