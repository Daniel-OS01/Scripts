#!/bin/bash
#
# ==============================================================================
# Oracle Cloud: Configure Network Security
# ==============================================================================
#
# Description:
#   This script demonstrates configuring network security rules in OCI.
#   It simulates updating an OCI Network Security Group (NSG) with a new
#   security rule for allowing HTTPS traffic.
#
# Execution via Orchestrator:
#   Select option [1] from the main.sh menu.
#
# Direct Execution (requires environment variables to be set):
#   export DEFAULT_SL_OCI=your_oci_profile
#   export NETWORK_SECURITY_GROUP_ID=ocid1.nsg.xxxxx
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/Daniel-OS01/scripts/refs/heads/main/scripts/oracle/configure-network.sh)"
#
# Required Secrets:
#   - {{DEFAULT_SL_OCI}}: The OCI CLI profile name to use for authentication.
#   - {{NETWORK_SECURITY_GROUP_ID}}: The OCID of the Network Security Group to modify.
#
# Compatibility:
#   - An OCI instance with the OCI CLI installed and configured.
#
# ==============================================================================

echo "--- Oracle Cloud Network Configuration Simulation ---"

# This check ensures the script is not run without the secrets being processed.
# If the placeholder syntax is still present, it means substitution failed.
if [[ "{{DEFAULT_SL_OCI}}" == *"{{"* ]]; then
    echo "Error: Secrets have not been substituted. This script must be run via the orchestrator." >&2
    echo "Required environment variables: DEFAULT_SL_OCI, NETWORK_SECURITY_GROUP_ID" >&2
    exit 1
fi

echo "Authenticating with OCI profile: {{DEFAULT_SL_OCI}}"
echo "Targeting Network Security Group: {{NETWORK_SECURITY_GROUP_ID}}"
echo

echo "This is a DRY RUN. The following OCI CLI command would be executed:"
echo "-----------------------------------------------------------------"
echo "oci network nsg rules add \\"
echo "    --nsg-id {{NETWORK_SECURITY_GROUP_ID}} \\"
echo "    --direction INGRESS \\"
echo "    --protocol 6 \\"
echo "    --source '0.0.0.0/0' \\"
echo "    --description 'Allow HTTPS Ingress from Any' \\"
echo "    --tcp-options '{\"destinationPortRange\": {\"max\": 443, \"min\": 443}}' \\"
echo "    --profile {{DEFAULT_SL_OCI}}"
echo "-----------------------------------------------------------------"
echo
echo "--- Simulation Complete ---"
