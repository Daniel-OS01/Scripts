#!/bin/bash
#
# ==============================================================================
# Coolify: Trigger Application Deployment
# ==============================================================================
#
# Description:
#   This script triggers a new deployment for a pre-configured application
#   in the Coolify platform. It works by sending a secure POST request to the
#   application's unique deployment webhook URL. This can be used to integrate
#   Coolify deployments into larger CI/CD pipelines or automation workflows.
#
# Execution via Orchestrator:
#   Select option [3] from the main.sh menu.
#
# Required Secrets:
#   - {{COOLIFY_API_KEY}}: The Bearer token for authenticating with the Coolify API.
#   - {{COOLIFY_DEPLOYMENT_WEBHOOK}}: The full, secret URL for the application's deployment webhook.
#
# Compatibility:
#   - Any system with 'curl' installed.
#   - A running Coolify v4 instance with a configured application that has a deployment webhook.
#
# ==============================================================================

echo "--- Coolify Application Deployment Simulation ---"

# Validate that secret substitution has occurred.
if [[ "{{COOLIFY_DEPLOYMENT_WEBHOOK}}" == *"{{"* ]]; then
    echo "Error: Secrets have not been substituted. This script must be run via the orchestrator." >&2
    echo "Required environment variables: COOLIFY_API_KEY, COOLIFY_DEPLOYMENT_WEBHOOK" >&2
    exit 1
fi

echo "Preparing to trigger deployment for the specified Coolify webhook."
echo
echo "This is a DRY RUN. The following command would be executed to trigger the deployment:"
echo "------------------------------------------------------------------------------------"
echo "curl --request POST \\"
echo "     --url \"{{COOLIFY_DEPLOYMENT_WEBHOOK}}\" \\"
echo "     --header \"Authorization: Bearer {{COOLIFY_API_KEY}}\" \\"
echo "     --header \"Content-Type: application/json\" \\"
echo "     --data '{\"force_rebuild\": true}'"
echo "------------------------------------------------------------------------------------"
echo
echo "Note: The 'force_rebuild' flag tells Coolify to clear the build cache before deploying."
echo
echo "--- Simulation Complete ---"
